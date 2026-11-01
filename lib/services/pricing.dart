import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
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

  static Future<Pricing> load() async {
    final r = await Future.wait<Object>([DBHelper.instance.getFinanceSettings(), PriceRules.load()]);
    return Pricing(FinanceSettings.fromMap(r[0] as Map<String, dynamic>));
  }

  /// ₹1 steps under ₹100, ₹5 steps from ₹100, always rounding UP.
  static double round(double v) {
    if (v <= 0) return 0;
    if (v < 100) return v.ceilToDouble();
    return (v / 5).ceil() * 5.0;
  }

  double target(String category) => s.targetFor(category);

  static double margin(double price, double cost) => price <= 0 ? 0.0 : (price - cost) / price * 100;

  /// Suggested prices follow the owner's price rules (see [PriceRules]).
  double suggestShop(double cost, String category) => PriceRules.cached.shopPrice(cost, category);

  /// Pack-cost share for one selling unit (kg for loose items).
  double packShare(bool perKg) => perKg ? s.onlinePackCost / math.max(s.onlineTypicalKg, 0.1) : s.onlinePackCost;

  double suggestOnline(double cost, String category, {bool perKg = true}) =>
      PriceRules.cached.onlinePrice(cost, category, perKg);

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

/// The owner's agreed price rules (October 2026), kept in
/// app_settings/price_rules so they can be changed without a new app.
///
///   Bills share  = monthly bills ÷ target revenue + credit delay (10.5%)
///   Shop price   = cost ÷ (1 − bills − shop profit)          (cost ÷ 0.775)
///   Online price = (cost + packing) ÷ (1 − bills − pay & returns
///                   − partner commission − profit), profit 12–15%
///   Cost and expenses are fixed. To meet a lower market price, partner
///   commission and profit are cut in the same proportion, never below
///   [keepPct] % of their normal size.
///   Delivery is charged separately at checkout, never inside the price.
class PriceRules {
  final double monthlyBills; // ₹ per month (rent, wages, power...)
  final double targetRevenue; // ₹ sales per month the bills are spread over
  final double creditPct; // cost of waiting for credit customers
  final double packCost; // ₹ per online pack (per-kg items)
  final double bagPackCost; // ₹ per online bag / unit item
  final double payPct; // payment fee + returns, online only
  final double commissionPct; // partner commission: millets, flour, grams & nuts
  final double riceCommissionPct; // partner commission on rice
  final double bagCommission; // ₹ per bag: cattle feed and wholesale bags
  final double shopProfit; // shop profit %
  final double onlineProfitMin, onlineProfitMax;
  final double keepPct; // competitive: keep at least this % of commission & profit
  final Map<String, double> catShopProfit; // category (lower case) -> shop profit %
  final Map<String, double> catOnlineProfit; // category (lower case) -> lowest online profit %

  const PriceRules({
    this.monthlyBills = 25000,
    this.targetRevenue = 250000,
    this.creditPct = 0.5,
    this.packCost = 7,
    this.bagPackCost = 10,
    this.payPct = 3,
    this.commissionPct = 7.5,
    this.riceCommissionPct = 2,
    this.bagCommission = 15,
    this.shopProfit = 12,
    this.onlineProfitMin = 12,
    this.onlineProfitMax = 15,
    this.keepPct = 50,
    this.catShopProfit = const {},
    this.catOnlineProfit = const {},
  });

  static double _d(Object? v, double def) => v is num ? v.toDouble() : def;
  static Map<String, double> _m(Object? v) =>
      v is Map ? {for (final e in v.entries) if (e.value is num) e.key.toString().toLowerCase(): (e.value as num).toDouble()} : {};

  factory PriceRules.fromMap(Map<String, dynamic> m) => PriceRules(
        monthlyBills: _d(m['monthly_bills'], 25000),
        targetRevenue: _d(m['target_revenue'], 250000),
        creditPct: _d(m['credit_pct'], 0.5),
        packCost: _d(m['pack_cost'], 7),
        bagPackCost: _d(m['bag_pack_cost'], 10),
        payPct: _d(m['pay_pct'], 3),
        commissionPct: _d(m['commission_pct'], 7.5),
        riceCommissionPct: _d(m['rice_commission_pct'], 2),
        bagCommission: _d(m['bag_commission'], 15),
        shopProfit: _d(m['shop_profit'], 12),
        onlineProfitMin: _d(m['online_profit_min'], 12),
        onlineProfitMax: _d(m['online_profit_max'], 15),
        keepPct: _d(m['keep_pct'], 50).clamp(0, 100).toDouble(),
        catShopProfit: _m(m['cat_shop_profit']),
        catOnlineProfit: _m(m['cat_online_profit']),
      );

  Map<String, dynamic> toMap() => {
        'monthly_bills': monthlyBills,
        'target_revenue': targetRevenue,
        'credit_pct': creditPct,
        'pack_cost': packCost,
        'bag_pack_cost': bagPackCost,
        'pay_pct': payPct,
        'commission_pct': commissionPct,
        'rice_commission_pct': riceCommissionPct,
        'bag_commission': bagCommission,
        'shop_profit': shopProfit,
        'online_profit_min': onlineProfitMin,
        'online_profit_max': onlineProfitMax,
        'keep_pct': keepPct,
        'cat_shop_profit': catShopProfit,
        'cat_online_profit': catOnlineProfit,
      };

  /// Same rules with one category's profit changed (null = back to normal).
  PriceRules withCategoryProfit(String category, {double? shop, double? online}) {
    final c = category.trim().toLowerCase();
    final s = {...catShopProfit}..remove(c);
    final o = {...catOnlineProfit}..remove(c);
    if (shop != null) s[c] = shop;
    if (online != null) o[c] = online;
    return PriceRules.fromMap({...toMap(), 'cat_shop_profit': s, 'cat_online_profit': o});
  }

  static PriceRules? _cache;
  static PriceRules get cached => _cache ?? const PriceRules();

  static DocumentReference get _doc => FirebaseFirestore.instance.collection('app_settings').doc('price_rules');

  /// Works offline: falls back to the last rules seen, then the defaults.
  static Future<PriceRules> load() async {
    try {
      final snap = await _doc.get().timeout(const Duration(seconds: 4));
      _cache = PriceRules.fromMap((snap.data() as Map<String, dynamic>?) ?? {});
    } catch (_) {
      _cache ??= const PriceRules();
    }
    return _cache!;
  }

  static Future<void> save(PriceRules r) async {
    _cache = r;
    final op = _doc.set(r.toMap());
    try {
      await op.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      op.catchError((Object _) {}); // offline: saved on the phone, syncs later
    }
  }

  /// Bills share of every sale, %.
  double get billsPct => (targetRevenue <= 0 ? 0 : monthlyBills / targetRevenue * 100) + creditPct;

  static bool _has(String c, List<String> w) => w.any(c.contains);
  static bool isRice(String category) => _has(category.toLowerCase(), ['rice', 'arisi', 'அரிசி']);
  static bool isBagCategory(String category) =>
      _has(category.toLowerCase(), ['cattle', 'feed', 'bran', 'thavidu', 'punnaku', 'தீவன']);

  double shopProfitFor(String category) => catShopProfit[category.trim().toLowerCase()] ?? shopProfit;
  double onlineMinFor(String category) => catOnlineProfit[category.trim().toLowerCase()] ?? onlineProfitMin;
  double onlineMaxFor(String category) => onlineMinFor(category) + math.max(0, onlineProfitMax - onlineProfitMin);
  bool hasCategoryProfit(String category) {
    final c = category.trim().toLowerCase();
    return catShopProfit.containsKey(c) || catOnlineProfit.containsKey(c);
  }

  /// Normal partner commission % of the price for a category (bags: ₹ per bag).
  double commissionFor(String category) {
    if (isBagCategory(category)) return 0;
    if (isRice(category)) return riceCommissionPct;
    return commissionPct;
  }

  /// Partner commission in ₹ for one sold line. [productPct] is the
  /// product's own (cut) commission when its price was set to meet the
  /// market. Cattle feed earns ₹ per bag (nothing on loose feed by the kg).
  double lineCommission(String category, double qty, double lineAmount, {bool byKg = false, double? productPct}) {
    if (isBagCategory(category)) return byKg ? 0 : bagCommission * qty;
    return lineAmount * (productPct ?? commissionFor(category)) / 100;
  }

  double packFor(bool perKg) => perKg ? packCost : bagPackCost;

  static double up(double v) => v <= 0 ? 0 : (v - 0.0001).ceilToDouble();

  double shopPrice(double cost, [String category = '']) {
    if (cost <= 0) return 0;
    final k = 1 - (billsPct + shopProfitFor(category)) / 100;
    return up(cost / math.max(k, 0.05));
  }

  double _onlineAt(double cost, bool perKg, double commission, double profit) {
    if (cost <= 0) return 0;
    final k = 1 - (billsPct + payPct + commission + profit) / 100;
    return up((cost + packFor(perKg)) / math.max(k, 0.05));
  }

  double onlineFloor(double cost, String category, bool perKg) =>
      _onlineAt(cost, perKg, commissionFor(category), onlineMinFor(category));
  double onlineCeiling(double cost, String category, bool perKg) =>
      _onlineAt(cost, perKg, commissionFor(category), onlineMaxFor(category));

  /// The online price the rules give, and the commission it carries:
  /// - no market price → floor (lowest normal profit)
  /// - market above the ceiling → ceiling
  /// - market between → match the market
  /// - market below the floor → match it by cutting commission and profit
  ///   in the same proportion, but keep at least [keepPct] % of both
  ///   (then the price stays above market — shown red).
  OnlinePlan onlinePlan(double cost, String category, bool perKg, {double market = 0}) {
    final c = commissionFor(category);
    final pMin = onlineMinFor(category);
    if (cost <= 0) return OnlinePlan(0, c, pMin, PlanKind.rule);
    final lo = onlineFloor(cost, category, perKg), hi = onlineCeiling(cost, category, perKg);
    if (market <= 0) return OnlinePlan(lo, c, pMin, PlanKind.noMarket);
    if (market >= hi) return OnlinePlan(hi, c, onlineMaxFor(category), PlanKind.belowMarket);
    final p = market.floorToDouble();
    if (p >= lo) {
      final left = (p * (1 - (billsPct + payPct + c) / 100) - cost - packFor(perKg)) / p * 100;
      return OnlinePlan(p, c, left, PlanKind.atMarket);
    }
    // Share of the price left for commission + profit at the market price.
    final avail = (p * (1 - (billsPct + payPct) / 100) - cost - packFor(perKg)) / p * 100;
    final need = c + pMin;
    final s = need <= 0 ? 0.0 : avail / need;
    final keep = keepPct / 100;
    if (s >= keep) return OnlinePlan(p, c * s, pMin * s, PlanKind.cut);
    final pk = _onlineAt(cost, perKg, c * keep, pMin * keep);
    return OnlinePlan(pk, c * keep, pMin * keep, PlanKind.aboveMarket);
  }

  /// Partner commission % at an online price the owner typed: the normal
  /// rate at or above the floor; below it, cut in proportion with profit.
  double commissionAt(double price, double cost, String category, bool perKg) {
    final c = commissionFor(category);
    if (price <= 0 || cost <= 0 || c <= 0 || price >= onlineFloor(cost, category, perKg)) return c;
    final avail = (price * (1 - (billsPct + payPct) / 100) - cost - packFor(perKg)) / price * 100;
    final need = c + onlineMinFor(category);
    return (c * avail / need).clamp(0.0, c).toDouble();
  }

  double onlinePrice(double cost, String category, bool perKg, {double market = 0}) =>
      onlinePlan(cost, category, perKg, market: market).price;

  /// Cost, expenses, commission and net profit of one sale at [price].
  PriceBreak shopBreak(double price, double cost) => PriceBreak(
        price: price,
        cost: cost,
        expenses: price * billsPct / 100,
        commission: 0,
      );

  PriceBreak onlineBreak(double price, double cost, String category, bool perKg, {double? productPct}) => PriceBreak(
        price: price,
        cost: cost,
        expenses: packFor(perKg) + price * (billsPct + payPct) / 100,
        commission: isBagCategory(category) ? bagCommission : price * (productPct ?? commissionFor(category)) / 100,
      );
}

enum PlanKind { rule, noMarket, belowMarket, atMarket, cut, aboveMarket }

/// An online price from the rules, with the partner commission it carries.
class OnlinePlan {
  final double price, commissionPct, profitPct;
  final PlanKind kind;
  const OnlinePlan(this.price, this.commissionPct, this.profitPct, this.kind);
  bool get commissionCut => kind == PlanKind.cut || kind == PlanKind.aboveMarket;
}

/// One sale split into the four parts the owner looks at.
class PriceBreak {
  final double price, cost, expenses, commission;
  const PriceBreak({required this.price, required this.cost, required this.expenses, required this.commission});
  double get profit => price - cost - expenses - commission;
  double pctOf(double v) => price <= 0 ? 0 : v / price * 100;
  double get costPct => pctOf(cost);
  double get expensesPct => pctOf(expenses);
  double get commissionPct => pctOf(commission);
  double get profitPct => pctOf(profit);
}
