import 'dart:math' as math;

/// Buying pattern of every named customer (vendor) from their bills:
/// how often they come, when they are due next, what they usually buy,
/// whether spending is dropping, how they pay and what they earn us.
/// Pure Dart over raw Firestore maps, so the Today screen (live streams)
/// and Vendor Insights (one-time load) share the same numbers.

enum CustGroup { late, due, dropping, lost, top, regular, newbie }

const custGroupNames = {
  CustGroup.late: 'Late',
  CustGroup.due: 'Due this week',
  CustGroup.dropping: 'Dropping',
  CustGroup.lost: 'Lost',
  CustGroup.top: 'Top 20%',
  CustGroup.regular: 'Regulars',
  CustGroup.newbie: 'New',
};

const custGroupHelp = {
  CustGroup.late: 'Waited more than 1½ times their usual gap — call or remind them first. Most money at risk on top.',
  CustGroup.due: 'Their usual visit falls in the next 7 days — keep their items ready. Soonest first.',
  CustGroup.dropping: 'Last 30 days spend is 30% or more below their 3-month average. Biggest fall first.',
  CustGroup.lost: 'No bill for more than 3 times their usual gap (or 90 days). Send a win-back offer. Biggest past buyers first.',
  CustGroup.top: 'The top 20% of customers by spend in the last 6 months — protect them. Highest first.',
  CustGroup.regular: '4 or more visits in the last 60 days. Most visits first.',
  CustGroup.newbie: 'First bill in the last 30 days — make them regulars. Newest first.',
};

class CustItem {
  final String key, name, category, unit;
  double qty = 0, spend = 0;
  final List<double> qtys = [];
  final Set<DateTime> days = {};
  CustItem(this.key, this.name, this.category, this.unit);

  int? get cycleDays => CustomerPatterns.medianGap(days.toList()..sort());
  double get usualQty => CustomerPatterns.median(qtys);
  DateTime? get last => days.isEmpty ? null : days.reduce((a, b) => a.isAfter(b) ? a : b);
  DateTime? get nextDue => (last == null || cycleDays == null) ? null : last!.add(Duration(days: cycleDays!));
}

class CustPattern {
  final Map<String, dynamic> vendor;
  CustPattern(this.vendor);

  String get id => vendor['id'] as String;
  String get name => (vendor['name'] ?? '').toString();
  String get phone => (vendor['phone'] ?? '').toString();
  String get place => (vendor['address'] ?? '').toString().trim();
  double get balance => (vendor['balance'] as num?)?.toDouble() ?? 0.0;

  final List<DateTime> visitDays = []; // distinct days, oldest first
  int bills = 0;
  DateTime? first, last;
  int? usualGap; // days
  int daysSince = 0;
  double spendAll = 0, spend30 = 0, spendPrev90 = 0, spend180 = 0;
  double cashSales = 0, creditSales = 0;
  double profit = 0, itemSales = 0;
  double? avgDaysToPay;
  int visits60 = 0;
  final List<double> months = List.filled(6, 0.0); // oldest → this month
  final List<int> weekdays = List.filled(7, 0); // Mon..Sun
  final Map<String, CustItem> items = {};
  final Map<String, double> catSpend = {};
  final Set<CustGroup> groups = {};
  List<String> missingCats = const [];

  double get avgPrev30 => spendPrev90 / 3;
  double? get changePct => avgPrev30 > 0 ? (spend30 - avgPrev30) / avgPrev30 * 100 : null;
  double get perVisit => visitDays.isEmpty ? 0.0 : spendAll / visitDays.length;
  DateTime? get nextDue => (last == null || usualGap == null) ? null : last!.add(Duration(days: usualGap!));
  int? get lateDays => usualGap == null ? null : daysSince - usualGap!;
  double get margin => itemSales > 0 ? profit / itemSales * 100 : 0.0;
  double get creditShare => (cashSales + creditSales) > 0 ? creditSales / (cashSales + creditSales) * 100 : 0.0;
  int? get favWeekday {
    if (visitDays.length < 3) return null;
    var best = 0;
    for (var i = 1; i < 7; i++) {
      if (weekdays[i] > weekdays[best]) best = i;
    }
    return weekdays[best] * 3 >= visitDays.length ? best : null; // only if clearly favourite
  }

  /// Items they buy most often (by number of visits), optionally in one category.
  List<CustItem> usualItems({String category = '', int max = 3}) {
    final l = items.values.where((i) => category.isEmpty || i.category.toLowerCase() == category).toList()
      ..sort((a, b) {
        final c = b.days.length.compareTo(a.days.length);
        return c != 0 ? c : b.spend.compareTo(a.spend);
      });
    return l.take(max).toList();
  }

  bool boughtCategory(String c) => catSpend.keys.any((k) => k.toLowerCase() == c);

  /// Money at risk for a late customer: what one visit is worth × how late.
  double get riskScore => perVisit * math.max(1, lateDays ?? 0);
}

class PatternSummary {
  int active = 0, repeatBase = 0, repeaters = 0, due = 0, late = 0, newbies = 0, lost = 0;
  double topShare = 0;
  double get repeatRate => repeatBase > 0 ? repeaters / repeatBase * 100 : 0.0;
}

class CustomerPatterns {
  final List<CustPattern> all;
  final PatternSummary summary;
  final List<String> categories; // store categories, biggest sales first
  CustomerPatterns(this.all, this.summary, this.categories);

  static DateTime? _date(Object? v) {
    if (v is String && v.length >= 10) return DateTime.tryParse(v);
    try {
      // Firestore Timestamp without importing cloud_firestore
      final d = (v as dynamic)?.toDate();
      if (d is DateTime) return d;
    } catch (_) {}
    return null;
  }

  static double _n(Object? v) => v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0.0);
  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static double median(List<double> v) {
    if (v.isEmpty) return 0;
    final s = [...v]..sort();
    final m = s.length ~/ 2;
    return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
  }

  /// Median gap in days between consecutive days (last 12 gaps), null if < 2 days.
  static int? medianGap(List<DateTime> days) {
    if (days.length < 2) return null;
    final gaps = <double>[];
    for (var i = 1; i < days.length; i++) {
      gaps.add(days[i].difference(days[i - 1]).inDays.toDouble());
    }
    final recent = gaps.length > 12 ? gaps.sublist(gaps.length - 12) : gaps;
    return math.max(1, median(recent).round());
  }

  static CustomerPatterns build({
    required List<Map<String, dynamic>> vendors,
    required List<Map<String, dynamic>> sales,
    required List<Map<String, dynamic>> items,
    required List<Map<String, dynamic>> credit,
    List<Map<String, dynamic>> products = const [],
    DateTime? now,
  }) {
    final today = _day(now ?? DateTime.now());
    final byId = <String, CustPattern>{for (final v in vendors) if (v['id'] is String) v['id'] as String: CustPattern(v)};
    final unitOf = {for (final p in products) if (p['id'] is String) p['id'] as String: (p['unit'] ?? '').toString()};
    final catOfProduct = {for (final p in products) if (p['id'] is String) p['id'] as String: (p['category'] ?? '').toString().trim()};

    // bills
    final saleCust = <String, CustPattern>{};
    final saleDay = <String, DateTime>{};
    final saleFactor = <String, double>{};
    final dayKeys = <String, Set<DateTime>>{};
    final storeCat = <String, double>{};
    for (final s in sales) {
      if (s['status'] == 'cancelled') continue;
      final vid = s['vendor_id'];
      final d0 = _date(s['date']);
      if (vid is! String || d0 == null) continue;
      final c = byId[vid];
      if (c == null) continue;
      final d = _day(d0);
      final sid = (s['id'] ?? '').toString();
      saleCust[sid] = c;
      saleDay[sid] = d;
      final sub = _n(s['subtotal']);
      saleFactor[sid] = sub > 0 ? (sub - _n(s['discount'])) / sub : 1.0;
      final total = _n(s['total_amount']);
      c.bills++;
      c.spendAll += total;
      final age = today.difference(d).inDays;
      if (age < 30) c.spend30 += total;
      if (age >= 30 && age < 120) c.spendPrev90 += total;
      if (age < 180) c.spend180 += total;
      final mi = (today.year - d.year) * 12 + today.month - d.month;
      if (mi >= 0 && mi < 6) c.months[5 - mi] += total;
      if (s['payment_type'] == 'CREDIT' || s['payment_type'] == 'PARTIAL') {
        final paid = s['payment_type'] == 'PARTIAL' ? _n(s['paid_amount']) : 0.0;
        c.creditSales += total - paid;
        c.cashSales += paid;
      } else {
        c.cashSales += total;
      }
      dayKeys.putIfAbsent(c.id, () => {}).add(d);
    }
    for (final e in dayKeys.entries) {
      final c = byId[e.key]!;
      final days = e.value.toList()..sort();
      c.visitDays.addAll(days);
      c.first = days.first;
      c.last = days.last;
      c.daysSince = today.difference(days.last).inDays;
      c.usualGap = medianGap(days);
      for (final d in days) {
        c.weekdays[d.weekday - 1]++;
        if (today.difference(d).inDays < 60) c.visits60++;
      }
    }

    // items
    for (final i in items) {
      if (i['status'] == 'cancelled') continue;
      final sid = (i['sale_id'] ?? '').toString();
      final c = saleCust[sid];
      final f = saleFactor[sid] ?? 1.0;
      final pid = (i['product_id'] ?? '').toString();
      var cat = (i['category'] ?? '').toString().trim();
      if (cat.isEmpty) cat = catOfProduct[pid] ?? '';
      if (cat.isEmpty) cat = 'Uncategorised';
      final sale = _n(i['subtotal']) * f;
      storeCat[cat] = (storeCat[cat] ?? 0) + sale; // every named-customer bill
      if (c == null) continue;
      final name = (i['product_name'] ?? '—').toString().trim();
      final key = pid.isEmpty ? 'name:${name.toLowerCase()}' : pid;
      final qty = _n(i['quantity']);
      final it = c.items.putIfAbsent(key, () => CustItem(key, name, cat, unitOf[pid] ?? ''));
      it.qty += qty;
      it.qtys.add(qty);
      it.spend += sale;
      final d = saleDay[sid];
      if (d != null) it.days.add(d);
      c.catSpend[cat] = (c.catSpend[cat] ?? 0) + sale;
      final unitCost = _n(i['unit_cost']);
      if (unitCost > 0) {
        c.itemSales += sale;
        c.profit += sale - qty * unitCost;
      }
    }

    // average days to pay (oldest credit paid first)
    final txByCust = <String, List<Map<String, dynamic>>>{};
    for (final t in credit) {
      final vid = t['vendor_id'];
      if (vid is String && byId.containsKey(vid)) txByCust.putIfAbsent(vid, () => []).add(t);
    }
    for (final e in txByCust.entries) {
      final tx = e.value.where((t) => _date(t['date']) != null).toList()
        ..sort((a, b) => _date(a['date'])!.compareTo(_date(b['date'])!));
      final lots = <List<Object>>[]; // [DateTime, remaining]
      double w = 0, amt = 0;
      for (final t in tx) {
        final d = _date(t['date'])!;
        final a = _n(t['amount']);
        if (t['type'] == 'CREDIT') {
          lots.add([d, a]);
        } else if (t['type'] == 'PAYMENT') {
          var left = a;
          while (left > 0.01 && lots.isNotEmpty) {
            final lot = lots.first;
            final rem = lot[1] as double;
            final use = math.min(rem, left);
            w += use * d.difference(lot[0] as DateTime).inDays;
            amt += use;
            left -= use;
            if (rem - use <= 0.01) {
              lots.removeAt(0);
            } else {
              lot[1] = rem - use;
            }
          }
        }
      }
      if (amt > 0) byId[e.key]!.avgDaysToPay = w / amt;
    }

    final cats = storeCat.keys.toList()..sort((a, b) => storeCat[b]!.compareTo(storeCat[a]!));
    final topCats = cats.where((c) => c != 'Uncategorised').take(4).toList();

    // groups
    final buyers = byId.values.where((c) => c.visitDays.isNotEmpty).toList();
    final s = PatternSummary();
    for (final c in buyers) {
      final g = c.usualGap;
      final lostLimit = g == null ? 90 : math.max(90, 3 * g);
      final lost = c.daysSince > lostLimit;
      if (lost) {
        c.groups.add(CustGroup.lost);
      } else if (g != null) {
        if (c.daysSince > g * 1.5 && c.daysSince - g >= 2) {
          c.groups.add(CustGroup.late);
        } else if (c.nextDue != null && !c.nextDue!.isAfter(today.add(const Duration(days: 7)))) {
          c.groups.add(CustGroup.due);
        }
      }
      final ch = c.changePct;
      if (!lost && ch != null && ch <= -30 && c.spendPrev90 > 0) c.groups.add(CustGroup.dropping);
      if (c.visits60 >= 4) c.groups.add(CustGroup.regular);
      if (c.first != null && today.difference(c.first!).inDays < 30) c.groups.add(CustGroup.newbie);
      c.missingCats = [for (final t in topCats) if (!c.boughtCategory(t.toLowerCase())) t].take(2).toList();

      if (c.last != null && c.last!.year == today.year && c.last!.month == today.month) s.active++;
      if (today.difference(c.last!).inDays < 90) {
        s.repeatBase++;
        if (c.visitDays.where((d) => today.difference(d).inDays < 90).length >= 2) s.repeaters++;
      }
    }
    final ranked = buyers.where((c) => c.spend180 > 0).toList()..sort((a, b) => b.spend180.compareTo(a.spend180));
    final topN = (ranked.length * 0.2).ceil();
    final total180 = ranked.fold<double>(0, (a, c) => a + c.spend180);
    double topSum = 0;
    for (var i = 0; i < topN && i < ranked.length; i++) {
      ranked[i].groups.add(CustGroup.top);
      topSum += ranked[i].spend180;
    }
    s.topShare = total180 > 0 ? topSum / total180 * 100 : 0.0;
    for (final c in buyers) {
      if (c.groups.contains(CustGroup.due)) s.due++;
      if (c.groups.contains(CustGroup.late)) s.late++;
      if (c.groups.contains(CustGroup.newbie)) s.newbies++;
      if (c.groups.contains(CustGroup.lost)) s.lost++;
    }
    return CustomerPatterns(buyers, s, cats);
  }

  /// Customers in [g] (null = everyone who has bought), in priority order.
  List<CustPattern> list(CustGroup? g, {String category = ''}) {
    var l = all.where((c) => g == null || c.groups.contains(g)).toList();
    if (category.isNotEmpty) l = l.where((c) => c.boughtCategory(category)).toList();
    int cmp(CustPattern a, CustPattern b) {
      switch (g) {
        case CustGroup.late:
          return b.riskScore.compareTo(a.riskScore);
        case CustGroup.due:
          return (a.nextDue ?? DateTime(2100)).compareTo(b.nextDue ?? DateTime(2100));
        case CustGroup.dropping:
          return (b.avgPrev30 - b.spend30).compareTo(a.avgPrev30 - a.spend30);
        case CustGroup.lost:
          return b.spendAll.compareTo(a.spendAll);
        case CustGroup.regular:
          return b.visits60.compareTo(a.visits60);
        case CustGroup.newbie:
          return (b.first ?? DateTime(2000)).compareTo(a.first ?? DateTime(2000));
        case CustGroup.top:
        case null:
          return b.spend180.compareTo(a.spend180);
      }
      // ignore: dead_code
      return 0;
    }

    l.sort(cmp);
    return l;
  }

  int count(CustGroup g, {String category = ''}) =>
      all.where((c) => c.groups.contains(g) && (category.isEmpty || c.boughtCategory(category))).length;
}
