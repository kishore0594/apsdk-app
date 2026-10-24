import 'dart:math' as math;
import '../db/db_helper.dart';
import 'finance_service.dart';

/// Shop (offline) and online prices from the owner's margin targets.
///
/// Shop price  = cost ÷ (1 − target).
/// Online price covers the same target PLUS online costs: payment fee and
/// risk/returns (% of price) and packing & handling (₹ per pack, spread
/// over the usual pack size for per-kg items):
///   online price = (cost + pack cost ÷ usual kg) ÷ (1 − target − fee − risk)
class Pricing {
  final FinanceSettings s;
  const Pricing(this.s);

  static Future<Pricing> load() async =>
      Pricing(FinanceSettings.fromMap(await DBHelper.instance.getFinanceSettings()));

  /// ₹1 steps under ₹100, ₹5 steps from ₹100, always rounding UP.
  static double round(double v) {
    if (v <= 0) return 0;
    if (v < 100) return v.ceilToDouble();
    return (v / 5).ceil() * 5.0;
  }

  double target(String category) => s.targetFor(category);

  static double margin(double price, double cost) => price <= 0 ? 0.0 : (price - cost) / price * 100;

  double suggestShop(double cost, String category) {
    if (cost <= 0) return 0;
    final k = 1 - target(category) / 100;
    return round(cost / math.max(k, 0.05));
  }

  /// Pack-cost share for one selling unit (kg for loose items).
  double packShare(bool perKg) => perKg ? s.onlinePackCost / math.max(s.onlineTypicalKg, 0.1) : s.onlinePackCost;

  double suggestOnline(double cost, String category, {bool perKg = true}) {
    if (cost <= 0) return 0;
    final k = 1 - (target(category) + s.onlineCostPct) / 100;
    return round((cost + packShare(perKg)) / math.max(k, 0.05));
  }

  /// Margin left on an online sale after fees, risk and packing.
  double onlineMargin(double price, double cost, {bool perKg = true}) {
    if (price <= 0) return 0;
    final left = price * (1 - s.onlineCostPct / 100) - cost - packShare(perKg);
    return left / price * 100;
  }

  /// Margin of a web pack of [kg] at [perKgPrice] (per-kg items).
  double packMargin(double perKgPrice, double costPerKg, double kg) {
    final price = (perKgPrice * kg).roundToDouble();
    if (price <= 0) return 0;
    final left = price * (1 - s.onlineCostPct / 100) - costPerKg * kg - s.onlinePackCost;
    return left / price * 100;
  }

  /// green / orange / red against a target.
  static Light light(double margin, double target, double floor) =>
      margin >= target ? Light.green : (margin >= floor ? Light.orange : Light.red);
}
