import 'package:cloud_firestore/cloud_firestore.dart';
import 'pricing.dart';

/// One category's (or all categories') sales for a month, split into the
/// same four parts as a price: cost, expenses, commission, net profit.
/// Cost and commission are the real figures saved on each sold item;
/// expenses are worked out with the price rules (bills share for every
/// sale, plus packing and payment & returns for online sales).
class SalesParts {
  double revenue = 0, cost = 0, expenses = 0, commission = 0;
  int bills = 0;
  final Set<String> _sales = {};
  double get profit => revenue - cost - expenses - commission;
  PriceBreak get asBreak => PriceBreak(price: revenue, cost: cost, expenses: expenses, commission: commission);
}

class CategorySales {
  final SalesParts shop = SalesParts(), online = SalesParts();
  SalesParts get total {
    final t = SalesParts();
    for (final x in [shop, online]) {
      t.revenue += x.revenue;
      t.cost += x.cost;
      t.expenses += x.expenses;
      t.commission += x.commission;
      t.bills += x.bills;
    }
    return t;
  }

  static double _n(Object? v) => v is num ? v.toDouble() : 0.0;

  /// Sales from [start] (inclusive) to [end] (exclusive), keyed by
  /// category in lower case ('' = no category).
  static Future<Map<String, CategorySales>> load(DateTime start, DateTime end, PriceRules rules) async {
    final fs = FirebaseFirestore.instance;
    final a = start.toIso8601String(), b = end.toIso8601String();
    final r = await Future.wait([
      fs.collection('sales').where('date', isGreaterThanOrEqualTo: a).where('date', isLessThan: b).get(),
      fs.collection('sale_items').where('sale_date', isGreaterThanOrEqualTo: a).where('sale_date', isLessThan: b).get(),
    ]);
    final sales = <String, Map<String, dynamic>>{for (final d in r[0].docs) d.id: d.data()};
    final out = <String, CategorySales>{};
    for (final d in r[1].docs) {
      final it = d.data();
      if (it['status'] == 'cancelled') continue;
      final sale = sales[(it['sale_id'] ?? '').toString()];
      if (sale == null || sale['status'] == 'cancelled') continue;
      final sub = _n(sale['subtotal']);
      final factor = sub > 0 ? ((sub - _n(sale['discount'])) / sub).clamp(0.0, 1.0).toDouble() : 1.0;
      final online = (sale['notes'] ?? '').toString().startsWith('Web order');
      final qty = _n(it['quantity']);
      final revenue = _n(it['subtotal']) * factor;
      final cat = (it['category'] ?? '').toString().trim().toLowerCase();
      final g = out.putIfAbsent(cat, () => CategorySales());
      final x = online ? g.online : g.shop;
      x.revenue += revenue;
      x.cost += _n(it['unit_cost']) * qty;
      x.expenses += revenue * rules.billsPct / 100 + (online ? revenue * rules.payPct / 100 + rules.packCost * qty : 0);
      x.commission += _n(it['partner_commission']);
      if (x._sales.add(it['sale_id'].toString())) x.bills++;
    }
    return out;
  }

  /// All categories added together.
  static CategorySales sum(Iterable<CategorySales> list) {
    final t = CategorySales();
    for (final c in list) {
      for (final pair in [(c.shop, t.shop), (c.online, t.online)]) {
        pair.$2.revenue += pair.$1.revenue;
        pair.$2.cost += pair.$1.cost;
        pair.$2.expenses += pair.$1.expenses;
        pair.$2.commission += pair.$1.commission;
        pair.$2._sales.addAll(pair.$1._sales);
        pair.$2.bills = pair.$2._sales.length;
      }
    }
    return t;
  }
}
