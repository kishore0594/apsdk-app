import 'dart:math' as math;
import 'package:intl/intl.dart';
import '../db/db_helper.dart';
import '../utils/user_role.dart';
import 'pricing.dart';

/// Financial statements for the shop: Profit & Loss, cash flow, balance
/// sheet and the monthly KPIs, for any month, quarter or financial year
/// (April–March). Every record is read once; each period is worked out
/// on the phone. The core aim: find the real low-profit culprits — every
/// KPI can list the items, categories, expense heads or customers behind
/// it, worst first.

enum FinScale { month, quarter, year }

const finScaleNames = {FinScale.month: 'Month', FinScale.quarter: 'Quarter', FinScale.year: 'Year'};

class FinPeriod {
  final FinScale scale;
  final DateTime start; // first day
  final DateTime end; // day after the last day
  const FinPeriod(this.scale, this.start, this.end);

  factory FinPeriod.of(FinScale s, DateTime d) {
    final q = (d.month - 1) ~/ 3;
    final y = d.month >= 4 ? d.year : d.year - 1; // Indian financial year (April–March)
    return switch (s) {
      FinScale.month => FinPeriod(s, DateTime(d.year, d.month), DateTime(d.year, d.month + 1)),
      FinScale.quarter => FinPeriod(s, DateTime(d.year, q * 3 + 1), DateTime(d.year, q * 3 + 4)),
      FinScale.year => FinPeriod(s, DateTime(y, 4), DateTime(y + 1, 4)),
    };
  }

  FinPeriod get prev => FinPeriod.of(scale, start.subtract(const Duration(days: 1)));
  FinPeriod get next => FinPeriod.of(scale, end);
  FinPeriod get lastYear => FinPeriod.of(scale, DateTime(start.year - 1, start.month, 1));

  bool get isCurrent {
    final now = DateTime.now();
    return !now.isBefore(start) && now.isBefore(end);
  }

  bool get isFuture => start.isAfter(DateTime.now());

  int get totalDays => end.difference(start).inDays;

  int get elapsedDays {
    if (!isCurrent) return totalDays;
    final now = DateTime.now();
    return math.max(1, DateTime(now.year, now.month, now.day).difference(start).inDays + 1);
  }

  int get months => (end.year - start.year) * 12 + end.month - start.month;

  /// Last day shown in labels.
  DateTime get lastDay => end.subtract(const Duration(days: 1));

  String get label => switch (scale) {
        FinScale.month => DateFormat('MMMM yyyy').format(start),
        FinScale.quarter => '$fyQuarter · ${DateFormat('MMM').format(start)}–${DateFormat('MMM yyyy').format(lastDay)}',
        FinScale.year => 'FY ${start.year}-${(start.year + 1) % 100}  (Apr–Mar)',
      };

  /// Short label for charts.
  String get short => switch (scale) {
        FinScale.month => DateFormat('MMM').format(start),
        FinScale.quarter => "$fyQuarter'${(start.month >= 4 ? start.year + 1 : start.year) % 100}",
        FinScale.year => 'FY${(start.year + 1) % 100}',
      };

  /// Financial-year quarter: Apr–Jun = Q1 … Jan–Mar = Q4.
  String get fyQuarter => 'Q${((start.month - 4 + 12) % 12) ~/ 3 + 1}';

  String get prevWord => switch (scale) {
        FinScale.month => 'last month',
        FinScale.quarter => 'last quarter',
        FinScale.year => 'last year',
      };

  /// This period and the ones before it, oldest first.
  List<FinPeriod> trail(int n) {
    final list = <FinPeriod>[this];
    while (list.length < n) {
      list.insert(0, list.first.prev);
    }
    return list;
  }

  @override
  bool operator ==(Object other) =>
      other is FinPeriod && other.scale == scale && other.start == start;

  @override
  int get hashCode => Object.hash(scale, start);
}

/// Owner's targets and fixed costs (app_settings/finance).
class FinanceSettings {
  double targetNet; // % of sales after all expenses
  double targetGross;
  double maxExpense;
  double minCollection;
  double maxCreditDays;
  double maxStockDays;
  double officialInflation;
  double realInflation;
  Map<String, double> fixed; // expense head -> ₹ per month
  bool autoFixed;
  String fixedFrom; // yyyy-MM: first month the fixed expenses are added
  double? startCash;
  String startCashDate; // yyyy-MM-dd
  bool startCashEstimate; // true while it's the "this month's sales" guess
  double creditDelayDays; // how long customers take to pay (owner's figure)
  double defaultTarget; // shop margin target when a category has none
  Map<String, double> catTargets; // category (lower case) -> shop margin target %
  double onlineFeePct; // payment gateway etc. (% of online price)
  double onlineRiskPct; // returns, damage, risk (% of online price)
  double onlinePackCost; // ₹ packing & handling per online pack
  double onlineTypicalKg; // usual online pack size for per-kg items
  double billMinMargin; // warn when a bill / offer goes below this margin

  FinanceSettings({
    this.targetNet = 12,
    this.targetGross = 20,
    this.maxExpense = 10,
    this.minCollection = 95,
    this.maxCreditDays = 30,
    this.maxStockDays = 45,
    this.officialInflation = 6.8,
    this.realInflation = 10,
    Map<String, double>? fixed,
    this.autoFixed = true,
    String? fixedFrom,
    this.startCash,
    this.startCashDate = '',
    this.startCashEstimate = false,
    this.creditDelayDays = 50,
    this.defaultTarget = 20,
    Map<String, double>? catTargets,
    this.onlineFeePct = 2,
    this.onlineRiskPct = 3,
    this.onlinePackCost = 12,
    this.onlineTypicalKg = 1,
    this.billMinMargin = 10,
  })  : catTargets = catTargets ?? {},
        fixed = fixed ??
            {'Rent': 5000, 'Electricity': 1000, 'Wages': 15000, 'Transport': 2500, 'Other': 1500},
        fixedFrom = fixedFrom ?? _ym(DateTime(DateTime.now().year, DateTime.now().month - 1));

  static String _ym(DateTime d) => DateFormat('yyyy-MM').format(d);

  double get fixedTotal => fixed.values.fold(0.0, (a, b) => a + b);

  static double _d(Object? v, double def) => v is num ? v.toDouble() : def;

  /// Shop margin target for a category: the owner's figure, else a
  /// sensible one from the category name, else the default.
  double targetFor(String category) {
    final c = category.trim().toLowerCase();
    final own = catTargets[c];
    if (own != null) return own;
    return guessTarget(c) ?? defaultTarget;
  }

  static double? guessTarget(String c) {
    bool has(List<String> w) => w.any(c.contains);
    if (has(['feed', 'cattle', 'bran', 'cake', 'thavidu', 'punnaku', 'தீவன'])) return 9;
    if (has(['flour', 'maavu', 'mavu', 'mix', 'மாவு'])) return 36;
    if (has(['millet', 'gram', 'pulse', 'dal', 'siru', 'traditional', 'சிறுதானி', 'பயறு'])) return 26;
    if (has(['rice', 'arisi', 'அரிசி'])) return 14;
    return null;
  }

  /// Online target = shop target; fees, risk and packing are added on top
  /// by the price formula.
  double get onlineCostPct => onlineFeePct + onlineRiskPct;

  factory FinanceSettings.fromMap(Map<String, dynamic> m) {
    final f = m['fixed'];
    final ct = m['cat_targets'];
    return FinanceSettings(
      targetNet: _d(m['target_net'], 12),
      targetGross: _d(m['target_gross'], 20),
      maxExpense: _d(m['max_expense'], 10),
      minCollection: _d(m['min_collection'], 95),
      maxCreditDays: _d(m['max_credit_days'], 30),
      maxStockDays: _d(m['max_stock_days'], 45),
      officialInflation: _d(m['official_inflation'], 6.8),
      realInflation: _d(m['real_inflation'], 10),
      fixed: f is Map ? {for (final e in f.entries) e.key.toString(): _d(e.value, 0)} : null,
      autoFixed: m['auto_fixed'] != false,
      fixedFrom: (m['fixed_from'] as String?)?.isNotEmpty == true ? m['fixed_from'] as String : null,
      startCash: m['start_cash'] is num ? (m['start_cash'] as num).toDouble() : null,
      startCashDate: (m['start_cash_date'] as String?) ?? '',
      startCashEstimate: m['start_cash_estimate'] == true,
      creditDelayDays: _d(m['credit_delay_days'], 50),
      defaultTarget: _d(m['default_target'], 20),
      catTargets: ct is Map ? {for (final e in ct.entries) e.key.toString().toLowerCase(): _d(e.value, 20)} : null,
      onlineFeePct: _d(m['online_fee_pct'], 2),
      onlineRiskPct: _d(m['online_risk_pct'], 3),
      onlinePackCost: _d(m['online_pack_cost'], 12),
      onlineTypicalKg: _d(m['online_typical_kg'], 1),
      billMinMargin: _d(m['bill_min_margin'], 10),
    );
  }

  Map<String, dynamic> toMap() => {
        'target_net': targetNet,
        'target_gross': targetGross,
        'max_expense': maxExpense,
        'min_collection': minCollection,
        'max_credit_days': maxCreditDays,
        'max_stock_days': maxStockDays,
        'official_inflation': officialInflation,
        'real_inflation': realInflation,
        'fixed': fixed,
        'auto_fixed': autoFixed,
        'fixed_from': fixedFrom,
        if (startCash != null) 'start_cash': startCash,
        'start_cash_date': startCashDate,
        'start_cash_estimate': startCashEstimate,
        'credit_delay_days': creditDelayDays,
        'default_target': defaultTarget,
        'cat_targets': catTargets,
        'online_fee_pct': onlineFeePct,
        'online_risk_pct': onlineRiskPct,
        'online_pack_cost': onlinePackCost,
        'online_typical_kg': onlineTypicalKg,
        'bill_min_margin': billMinMargin,
      };
}

/// Everything one period's statements show.
class FinFigures {
  final FinPeriod period;
  double grossSales = 0; // before bill discounts
  double discounts = 0;
  double delivery = 0; // delivery charges received
  double cogs = 0;
  double costMissingSales = 0; // sold items with no purchase cost
  int costMissingLines = 0;
  final Map<String, double> expenses = {};
  double stockAdjust = 0; // stock loss (+) or gain (−) from adjustments, at cost
  int bills = 0;
  double cashSales = 0; // paid at the counter
  double creditGiven = 0;
  double creditCollected = 0;
  double purchases = 0;
  double supplierPaid = 0;
  double receivables = 0; // customers owe (period end)
  double payables = 0; // owed to suppliers (period end)
  double stockValue = 0; // at cost (period end)
  double cashStart = 0;
  double cashEnd = 0;
  double fixedPerMonth = 0;
  double badDebts = 0; // credit written off as never coming
  double creditDelay = 0; // value lost while customers take time to pay
  double delayDays = 0;
  double delayRate = 0;
  FinFigures(this.period);

  double get netSales => grossSales - discounts;
  double get revenue => netSales + delivery;
  double get grossProfit => netSales - cogs;
  double get expenseTotal => expenses.values.fold(0.0, (a, b) => a + b);
  double get operatingProfit => grossProfit + delivery - expenseTotal;
  /// Profit in the books: after expenses, stock loss and bad debts.
  double get bookProfit => operatingProfit - stockAdjust - badDebts;

  /// REAL profit: also after the value lost while customers take time to pay.
  double get netProfit => bookProfit - creditDelay;
  double get losses => stockAdjust + badDebts + creditDelay;
  int get days => period.elapsedDays;

  double _pct(double a, double b) => b.abs() < 0.01 ? 0.0 : a / b * 100;
  double get grossMargin => _pct(grossProfit, netSales);
  double get netMargin => _pct(netProfit, netSales);
  double get expenseRatio => _pct(expenseTotal, netSales);
  double get collectionRatio => _pct(cashSales + creditCollected, revenue);
  double get avgBill => bills == 0 ? 0.0 : revenue / bills;
  double? get creditDays => revenue <= 0 ? null : receivables / (revenue / days);
  double? get stockDays => cogs <= 0 ? null : stockValue / (cogs / days);

  /// Expenses expected for the whole period (fixed costs count in full).
  double get expectedExpenses => math.max(expenseTotal, fixedPerMonth * period.months);

  /// Sales needed for gross profit to pay all expenses.
  double? get breakEven => grossMargin <= 0 ? null : expectedExpenses / (grossMargin / 100);

  /// Sales needed to reach the profit target.
  double? targetSales(double targetNet) =>
      grossMargin - targetNet <= 0 ? null : expectedExpenses / ((grossMargin - targetNet) / 100);

  double get _pace => period.isCurrent ? period.totalDays / period.elapsedDays : 1;
  double get projectedSales => netSales * _pace;
  double get projectedNet =>
      projectedSales * grossMargin / 100 + delivery * _pace - expectedExpenses - losses * _pace;
  double get projectedNetMargin => _pct(projectedNet, projectedSales);

  /// Expense share of sales used to judge items: for the running period,
  /// full expected expenses against projected sales (so a month isn't
  /// judged on 5 days of sales against a full month's rent).
  /// Includes credit delay, bad debts and stock loss.
  double get itemExpenseRatio => _pct(expectedExpenses + losses * _pace, projectedSales);
}

/// One item / category / expense head / customer in a culprit list.
class FinRow {
  final String key;
  final String name;
  String group = '';
  double qty = 0;
  double sales = 0;
  double cost = 0;
  double prevSales = 0;
  double prevCost = 0;
  bool costMissing = false;
  // stock
  double stockQty = 0;
  double stockValue = 0;
  double? daysCover;
  double excessStock = 0;
  // customers / suppliers / expenses
  double amount = 0;
  double prevAmount = 0;
  int? ageDays;
  FinRow(this.key, this.name);

  double get gp => sales - cost;
  double get margin => sales.abs() < 0.01 ? 0.0 : gp / sales * 100;
  double get prevMargin => prevSales.abs() < 0.01 ? 0.0 : (prevSales - prevCost) / prevSales * 100;
  double profitAfter(double expRatio) => gp - sales * expRatio / 100;
  double profitAfterPct(double expRatio) => margin - expRatio;
  double gap(double expRatio, double target) => sales * target / 100 - profitAfter(expRatio);
}

enum Kpi { netProfit, grossMargin, netSales, expenseRatio, breakEven, collection, credit, stock, supplier, avgBill }

const kpiNames = {
  Kpi.netProfit: 'Net profit',
  Kpi.grossMargin: 'Gross margin',
  Kpi.netSales: 'Net sales',
  Kpi.expenseRatio: 'Expense ratio',
  Kpi.breakEven: 'Break-even sales',
  Kpi.collection: 'Collection ratio',
  Kpi.credit: 'Customer credit',
  Kpi.stock: 'Stock days',
  Kpi.supplier: 'Supplier dues',
  Kpi.avgBill: 'Average bill',
};

enum Light { green, orange, red, none }

class FinanceService {
  FinanceService(this.raw, this.settings) {
    _prepare();
  }

  final Map<String, List<Map<String, dynamic>>> raw;
  final FinanceSettings settings;

  static Future<FinanceService> load() async {
    final db = DBHelper.instance;
    final results = await Future.wait([db.getFinanceRaw(), db.getFinanceSettings()]);
    final raw = results[0] as Map<String, List<Map<String, dynamic>>>;
    final settings = FinanceSettings.fromMap(results[1] as Map<String, dynamic>);
    final svc = FinanceService(raw, settings);
    await svc._postFixedExpenses();
    await svc._initStartCash();
    return svc;
  }

  // ---------------- preparation ----------------

  late List<_Sale> _sales;
  late List<_Item> _items;
  late List<_Dated> _expenses;
  late List<_Dated> _credit;
  late List<_Dated> _supplierTx;
  late List<_Dated> _moves;
  final Map<String, Map<String, dynamic>> _products = {};
  final Map<String, double> _costNow = {};
  final Map<String, String> _groupOf = {};

  static DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;
  static double _n(Object? v) => v is num ? v.toDouble() : 0.0;

  static String tidy(String? v) {
    final t = (v ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.isEmpty) return '';
    return t[0].toUpperCase() + t.substring(1);
  }

  void _prepare() {
    for (final p in raw['products'] ?? const <Map<String, dynamic>>[]) {
      final id = p['id'] as String;
      _products[id] = p;
      _costNow[id] = _n(p['cost_price']);
      _groupOf[id] = tidy(p['category'] as String?);
    }
    _sales = [];
    for (final s in raw['sales'] ?? const <Map<String, dynamic>>[]) {
      if (s['status'] == 'cancelled') continue;
      final d = _date(s['date']);
      if (d == null) continue;
      final subtotal = _n(s['subtotal']);
      final discount = _n(s['discount']);
      _sales.add(_Sale(
        id: s['id'] as String,
        date: d,
        subtotal: subtotal,
        discount: discount,
        delivery: _n(s['delivery_charge']),
        total: _n(s['total_amount']),
        paid: (s['payment_type'] == 'CASH' || s['payment_type'] == 'PARTIAL') ? _n(s['paid_amount']) : 0.0,
      ));
    }
    final factor = {for (final s in _sales) s.id: s.subtotal > 0 ? (s.subtotal - s.discount) / s.subtotal : 1.0};
    _items = [];
    for (final i in raw['items'] ?? const <Map<String, dynamic>>[]) {
      if (i['status'] == 'cancelled') continue;
      final d = _date(i['sale_date']);
      final f = factor[i['sale_id']];
      if (d == null || f == null) continue;
      final pid = (i['product_id'] as String?) ?? '';
      final name = (i['product_name'] as String?)?.trim() ?? '—';
      var group = tidy(i['category'] as String?);
      if (group.isEmpty) group = _groupOf[pid] ?? '';
      final qty = _n(i['quantity']);
      final unitCost = _n(i['unit_cost']);
      _items.add(_Item(
        date: d,
        key: pid.isEmpty ? 'name:${name.toLowerCase()}' : pid,
        name: name,
        group: group.isEmpty ? 'Uncategorised' : group,
        qty: qty,
        sales: _n(i['subtotal']) * f,
        cost: qty * unitCost,
        costMissing: unitCost <= 0,
      ));
    }
    List<_Dated> dated(String key) => [
          for (final m in raw[key] ?? const <Map<String, dynamic>>[])
            if (_date(m['date']) != null) _Dated(_date(m['date'])!, m),
        ];
    _expenses = dated('expenses');
    _credit = dated('credit');
    _supplierTx = dated('supplier_txns');
    _moves = dated('movements');
  }

  bool _in(DateTime d, FinPeriod p) => !d.isBefore(p.start) && d.isBefore(p.end);

  /// End point used for "as of" balances: the period end, or now.
  DateTime _asOf(FinPeriod p) {
    final now = DateTime.now();
    return p.end.isAfter(now) ? now : p.end;
  }

  // ---------------- fixed monthly expenses ----------------

  static String _slug(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');

  /// Adds rent, salary and the other fixed costs on the 1st of every month
  /// from [FinanceSettings.fixedFrom], once (fixed ids, so never twice).
  Future<void> _postFixedExpenses() async {
    if (!settings.autoFixed || !UserRole.instance.isAdmin) return;
    final from = DateTime.tryParse('${settings.fixedFrom}-01');
    if (from == null) return;
    final have = {for (final e in raw['expenses'] ?? const <Map<String, dynamic>>[]) e['id'] as String};
    final now = DateTime.now();
    var m = DateTime(from.year, from.month);
    var guard = 0;
    while (!m.isAfter(DateTime(now.year, now.month)) && guard++ < 36) {
      for (final e in settings.fixed.entries) {
        if (e.value <= 0) continue;
        final id = 'fixed_${_slug(e.key)}_${DateFormat('yyyy-MM').format(m)}';
        if (have.contains(id)) continue;
        final data = {
          'category': e.key,
          'amount': e.value,
          'notes': 'Fixed monthly expense (added automatically)',
          'date': m.toIso8601String(),
          'created_at': now.toIso8601String(),
          'fixed': true,
        };
        await DBHelper.instance.setFixedExpense(id, data);
        _expenses.add(_Dated(m, {...data, 'id': id}));
        have.add(id);
      }
      m = DateTime(m.year, m.month + 1);
    }
  }

  /// Changing a fixed amount updates this month's entry too.
  static Future<void> refreshThisMonthFixed(FinanceSettings s) async {
    if (!UserRole.instance.isAdmin || !s.autoFixed) return;
    final m = DateTime(DateTime.now().year, DateTime.now().month);
    for (final e in s.fixed.entries) {
      await DBHelper.instance.setFixedExpense('fixed_${_slug(e.key)}_${DateFormat('yyyy-MM').format(m)}', {
        'category': e.key,
        'amount': e.value,
        'notes': 'Fixed monthly expense (added automatically)',
        'date': m.toIso8601String(),
        'created_at': DateTime.now().toIso8601String(),
        'fixed': true,
      });
    }
  }

  /// Starting cash: the owner's figure, or (first time) this month's sales.
  bool startCashIsEstimate = false;
  DateTime _startCashDate = DateTime.now();
  double _startCash = 0;

  Future<void> _initStartCash() async {
    final d = DateTime.tryParse(settings.startCashDate);
    if (settings.startCash != null && d != null) {
      _startCash = settings.startCash!;
      _startCashDate = d;
      startCashIsEstimate = settings.startCashEstimate;
      return;
    }
    final now = DateTime.now();
    final month = FinPeriod.of(FinScale.month, now);
    _startCash = figures(month, withCash: false).revenue;
    _startCashDate = DateTime(now.year, now.month, now.day);
    startCashIsEstimate = true;
    settings.startCash = _startCash;
    settings.startCashDate = DateFormat('yyyy-MM-dd').format(_startCashDate);
    settings.startCashEstimate = true;
    if (UserRole.instance.isAdmin) {
      await DBHelper.instance.saveFinanceSettings({
        'start_cash': _startCash,
        'start_cash_date': settings.startCashDate,
        'start_cash_estimate': true,
      });
    }
  }

  double get startCash => _startCash;
  DateTime get startCashDate => _startCashDate;

  /// Money in − money out between two dates.
  double _cashFlow(DateTime a, DateTime b) {
    if (!b.isAfter(a)) return 0;
    bool inside(DateTime d) => !d.isBefore(a) && d.isBefore(b);
    double flow = 0;
    for (final s in _sales) {
      if (inside(s.date)) flow += s.paid;
    }
    for (final c in _credit) {
      if (inside(c.date) && c.m['type'] == 'PAYMENT') flow += _n(c.m['amount']);
    }
    for (final t in _supplierTx) {
      if (inside(t.date) && t.m['type'] == 'PAYMENT') flow -= _n(t.m['amount']);
    }
    for (final e in _expenses) {
      if (inside(e.date)) flow -= _n(e.m['amount']);
    }
    return flow;
  }

  double cashAt(DateTime d) =>
      d.isBefore(_startCashDate) ? _startCash - _cashFlow(d, _startCashDate) : _startCash + _cashFlow(_startCashDate, d);

  // ---------------- one period ----------------

  final Map<FinPeriod, FinFigures> _cache = {};

  FinFigures figures(FinPeriod p, {bool withCash = true}) {
    final hit = _cache[p];
    if (hit != null && withCash) return hit;
    final f = FinFigures(p)..fixedPerMonth = settings.fixedTotal;
    for (final s in _sales) {
      if (!_in(s.date, p)) continue;
      f.grossSales += s.subtotal;
      f.discounts += s.discount;
      f.delivery += s.delivery;
      f.cashSales += s.paid;
      f.bills++;
    }
    for (final i in _items) {
      if (!_in(i.date, p)) continue;
      f.cogs += i.cost;
      if (i.costMissing) {
        f.costMissingSales += i.sales;
        f.costMissingLines++;
      }
    }
    for (final e in _expenses) {
      if (!_in(e.date, p)) continue;
      final head = tidy(e.m['category'] as String?);
      final k = head.isEmpty ? 'Other' : head;
      f.expenses[k] = (f.expenses[k] ?? 0) + _n(e.m['amount']);
    }
    for (final mv in _moves) {
      if (!_in(mv.date, p) || mv.m['reason'] != 'ADJUSTMENT') continue;
      final v = _n(mv.m['quantity']) * (_costNow[mv.m['product_id']] ?? 0);
      f.stockAdjust += mv.m['type'] == 'OUT' ? v : -v;
    }
    for (final c in _credit) {
      if (!_in(c.date, p)) continue;
      if (c.m['type'] == 'CREDIT') f.creditGiven += _n(c.m['amount']);
      if (c.m['type'] == 'PAYMENT') f.creditCollected += _n(c.m['amount']);
      if (c.m['type'] == 'ADJUSTMENT' && c.m['bad_debt'] == true) f.badDebts += _n(c.m['amount']);
    }
    for (final t in _supplierTx) {
      if (!_in(t.date, p)) continue;
      if (t.m['type'] == 'PURCHASE') f.purchases += _n(t.m['amount']);
      if (t.m['type'] == 'PAYMENT') f.supplierPaid += _n(t.m['amount']);
    }
    f.delayDays = settings.creditDelayDays;
    f.delayRate = settings.realInflation;
    f.creditDelay = f.creditGiven * settings.realInflation / 100 * settings.creditDelayDays / 365;
    final asOf = _asOf(p);
    f.receivables = receivablesAt(asOf);
    f.payables = payablesAt(asOf);
    f.stockValue = stockRows(p).fold(0.0, (a, r) => a + r.stockValue);
    if (withCash) {
      f.cashStart = cashAt(p.start);
      f.cashEnd = cashAt(asOf);
      _cache[p] = f;
    }
    return f;
  }

  double receivablesAt(DateTime at) {
    double v = 0;
    for (final c in raw['vendors'] ?? const <Map<String, dynamic>>[]) {
      v += _n(c['opening_balance']);
    }
    for (final c in _credit) {
      if (!c.date.isBefore(at)) continue;
      v += c.m['type'] == 'CREDIT' ? _n(c.m['amount']) : -_n(c.m['amount']);
    }
    return v;
  }

  double payablesAt(DateTime at) {
    double v = 0;
    for (final s in raw['suppliers'] ?? const <Map<String, dynamic>>[]) {
      v += _n(s['opening_balance']);
    }
    for (final t in _supplierTx) {
      if (!t.date.isBefore(at)) continue;
      v += t.m['type'] == 'PURCHASE' ? _n(t.m['amount']) : -_n(t.m['amount']);
    }
    return v;
  }

  // ---------------- culprit lists ----------------

  /// Items (or categories) with sales, cost and profit — this period and
  /// the one before.
  List<FinRow> salesRows(FinPeriod p, {bool byCategory = false}) {
    final rows = <String, FinRow>{};
    final prev = p.prev;
    for (final i in _items) {
      final now = _in(i.date, p);
      final before = _in(i.date, prev);
      if (!now && !before) continue;
      final key = byCategory ? i.group.toLowerCase() : i.key;
      final r = rows.putIfAbsent(key, () => FinRow(key, byCategory ? i.group : i.name)..group = i.group);
      if (now) {
        r.qty += i.qty;
        r.sales += i.sales;
        r.cost += i.cost;
        if (i.costMissing) r.costMissing = true;
      } else {
        r.prevSales += i.sales;
        r.prevCost += i.cost;
      }
    }
    return rows.values.toList();
  }

  /// Worst first: the ₹ each item is short of the profit target after its
  /// share of expenses. Items with no cost entered go last (can't judge).
  List<FinRow> profitCulprits(FinPeriod p, {bool byCategory = false}) {
    final f = figures(p);
    final r = f.itemExpenseRatio;
    final t = settings.targetNet;
    final list = salesRows(p, byCategory: byCategory).where((x) => x.sales > 0).toList()
      ..sort((a, b) {
        if (a.costMissing != b.costMissing) return a.costMissing ? 1 : -1;
        return b.gap(r, t).compareTo(a.gap(r, t));
      });
    return list;
  }

  /// Worst first: lowest gross margin, weighted by sales.
  List<FinRow> marginCulprits(FinPeriod p, {bool byCategory = false}) {
    final t = settings.targetGross;
    double short(FinRow x) => x.sales * t / 100 - x.gp;
    return salesRows(p, byCategory: byCategory).where((x) => x.sales > 0).toList()
      ..sort((a, b) {
        if (a.costMissing != b.costMissing) return a.costMissing ? 1 : -1;
        return short(b).compareTo(short(a));
      });
  }

  /// Worst first: biggest fall in sales against the period before.
  List<FinRow> salesDropCulprits(FinPeriod p, {bool byCategory = false}) {
    final f = figures(p);
    final pace = f.period.isCurrent ? f.period.totalDays / f.period.elapsedDays : 1.0;
    final list = salesRows(p, byCategory: byCategory);
    for (final r in list) {
      r.amount = r.sales * pace - r.prevSales; // change (running period projected)
    }
    list.sort((a, b) => a.amount.compareTo(b.amount));
    return list;
  }

  List<FinRow> expenseRows(FinPeriod p) {
    final now = figures(p).expenses;
    final before = figures(p.prev).expenses;
    final keys = {...now.keys, ...before.keys};
    return [
      for (final k in keys)
        FinRow(k, k)
          ..amount = now[k] ?? 0
          ..prevAmount = before[k] ?? 0,
    ]..sort((a, b) => b.amount.compareTo(a.amount));
  }

  /// Customers who owe, worst first: overdue amount, then amount.
  List<FinRow> creditRows(FinPeriod p) {
    final at = _asOf(p);
    final byVendor = <String, List<Map<String, dynamic>>>{};
    for (final c in _credit) {
      if (!c.date.isBefore(at)) continue;
      final id = c.m['vendor_id'] as String?;
      if (id == null) continue;
      byVendor.putIfAbsent(id, () => []).add(c.m);
    }
    final rows = <FinRow>[];
    for (final v in raw['vendors'] ?? const <Map<String, dynamic>>[]) {
      final id = v['id'] as String;
      final txns = byVendor[id] ?? const <Map<String, dynamic>>[];
      double bal = _n(v['opening_balance']);
      for (final t in txns) {
        bal += t['type'] == 'CREDIT' ? _n(t['amount']) : -_n(t['amount']);
      }
      if (bal < 1) continue;
      final since = oldestUnpaidCreditSince(txns);
      rows.add(FinRow(id, (v['name'] as String?) ?? '—')
        ..amount = bal
        ..ageDays = since == null ? null : at.difference(since).inDays);
    }
    final limit = settings.maxCreditDays;
    double overdue(FinRow r) => (r.ageDays ?? 0) > limit ? r.amount : 0.0;
    rows.sort((a, b) {
      final c = overdue(b).compareTo(overdue(a));
      return c != 0 ? c : b.amount.compareTo(a.amount);
    });
    return rows;
  }

  List<FinRow> supplierRows(FinPeriod p) {
    final at = _asOf(p);
    final bal = <String, double>{};
    for (final s in raw['suppliers'] ?? const <Map<String, dynamic>>[]) {
      bal[s['id'] as String] = _n(s['opening_balance']);
    }
    for (final t in _supplierTx) {
      if (!t.date.isBefore(at)) continue;
      final id = t.m['supplier_id'] as String?;
      if (id == null) continue;
      bal[id] = (bal[id] ?? 0) + (t.m['type'] == 'PURCHASE' ? _n(t.m['amount']) : -_n(t.m['amount']));
    }
    return [
      for (final s in raw['suppliers'] ?? const <Map<String, dynamic>>[])
        if ((bal[s['id']] ?? 0) >= 1) FinRow(s['id'] as String, (s['name'] as String?) ?? '—')..amount = bal[s['id']]!,
    ]..sort((a, b) => b.amount.compareTo(a.amount));
  }

  /// Stock at cost on the period end, with days of cover. Worst first:
  /// money stuck beyond the stock-days target (unsold items first).
  List<FinRow> stockRows(FinPeriod p) {
    final at = _asOf(p);
    final later = <String, double>{};
    for (final mv in _moves) {
      if (mv.date.isBefore(at)) continue;
      final id = mv.m['product_id'] as String?;
      if (id == null) continue;
      final q = _n(mv.m['quantity']);
      later[id] = (later[id] ?? 0) + (mv.m['type'] == 'IN' ? q : -q);
    }
    final sold = <String, double>{};
    for (final i in _items) {
      if (_in(i.date, p)) sold[i.key] = (sold[i.key] ?? 0) + i.qty;
    }
    final days = p.elapsedDays;
    final limit = settings.maxStockDays;
    final rows = <FinRow>[];
    for (final e in _products.entries) {
      final qtyNow = _n(e.value['quantity']);
      final qty = qtyNow - (later[e.key] ?? 0);
      if (qty <= 0) continue;
      final value = qty * (_costNow[e.key] ?? 0);
      final perDay = (sold[e.key] ?? 0) / days;
      final r = FinRow(e.key, (e.value['name'] as String?) ?? '—')
        ..group = _groupOf[e.key] ?? ''
        ..stockQty = qty
        ..stockValue = value
        ..daysCover = perDay > 0 ? qty / perDay : null;
      final cover = r.daysCover;
      r.excessStock = cover == null ? value : (cover > limit ? value * (1 - limit / cover) : 0.0);
      rows.add(r);
    }
    rows.sort((a, b) {
      final c = b.excessStock.compareTo(a.excessStock);
      return c != 0 ? c : b.stockValue.compareTo(a.stockValue);
    });
    return rows;
  }

  // ---------------- pricing check ----------------

  static bool perKgUnit(Map<String, dynamic> p) {
    if (p['web_weight'] is bool) return p['web_weight'] as bool;
    return RegExp(r'^\s*(kg|kgs|kilo|kilos|kilogram|kilograms)\s*\.?$', caseSensitive: false)
        .hasMatch((p['unit'] ?? '').toString());
  }

  int? _below;

  /// Products whose shop or online price is under the margin target.
  int belowTargetCount() {
    final cached = _below;
    if (cached != null) return cached;
    final pr = Pricing(settings);
    var n = 0;
    for (final p in _products.values) {
      final cost = _n(p['cost_price']);
      if (cost <= 0) continue;
      final t = pr.target(tidy(p['category'] as String?)) - 0.5;
      final shop = _n(p['selling_price']);
      final web = _n(p['web_price']) > 0 ? _n(p['web_price']) : shop;
      final online = p['web_visible'] != false && web > 0;
      if ((shop > 0 && Pricing.margin(shop, cost) < t) ||
          (online && pr.onlineMargin(web, cost, perKg: perKgUnit(p)) < t)) {
        n++;
      }
    }
    return _below = n;
  }

  // ---------------- debts ----------------

  /// Customer dues by age (oldest unpaid first, FIFO), doubtful-debt
  /// provision and the measured time customers take to pay.
  DebtView debts(FinPeriod p) {
    final at = _asOf(p);
    final byVendor = <String, List<_Dated>>{};
    for (final c in _credit) {
      if (!c.date.isBefore(at)) continue;
      final id = c.m['vendor_id'] as String?;
      if (id == null) continue;
      byVendor.putIfAbsent(id, () => []).add(c);
    }
    final view = DebtView();
    double paidWeighted = 0, paidTotal = 0;
    for (final v in raw['vendors'] ?? const <Map<String, dynamic>>[]) {
      final id = v['id'] as String;
      final txns = (byVendor[id] ?? <_Dated>[])..sort((a, b) => a.date.compareTo(b.date));
      final lots = <List<Object>>[]; // [DateTime, double remaining]
      final opening = _n(v['opening_balance']);
      if (opening > 0.005) lots.add([_date(v['created_at']) ?? DateTime(2020), opening]);
      double advance = opening < 0 ? -opening : 0.0;
      for (final t in txns) {
        final amount = _n(t.m['amount']);
        if (amount <= 0) continue;
        if (t.m['type'] == 'CREDIT') {
          var rem = amount;
          if (advance > 0) {
            final used = math.min(advance, rem);
            rem -= used;
            advance -= used;
          }
          if (rem > 0.005) lots.add([t.date, rem]);
        } else {
          var pay = amount;
          final isPay = t.m['type'] == 'PAYMENT';
          final recent = at.difference(t.date).inDays <= 365;
          while (pay > 0.005 && lots.isNotEmpty) {
            final lot = lots.first;
            final rem = lot[1] as double;
            final used = math.min(rem, pay);
            if (isPay && recent) {
              paidWeighted += used * t.date.difference(lot[0] as DateTime).inDays;
              paidTotal += used;
            }
            pay -= used;
            if (rem - used <= 0.005) {
              lots.removeAt(0);
            } else {
              lot[1] = rem - used;
            }
          }
          if (pay > 0.005) advance += pay;
        }
      }
      if (lots.isEmpty) continue;
      final row = DebtRow(id, (v['name'] as String?) ?? '—', (v['phone'] as String?) ?? '');
      for (final lot in lots) {
        final days = at.difference(lot[0] as DateTime).inDays;
        final amt = lot[1] as double;
        final b = days <= 30 ? 0 : (days <= 60 ? 1 : (days <= 90 ? 2 : (days <= 180 ? 3 : 4)));
        row.buckets[b] += amt;
        row.total += amt;
        row.oldestDays = math.max(row.oldestDays ?? 0, days);
      }
      if (row.total < 1) continue;
      view.rows.add(row);
      for (var i = 0; i < 5; i++) {
        view.buckets[i] += row.buckets[i];
      }
      view.total += row.total;
    }
    view.rows.sort((a, b) {
      final c = b.risk.compareTo(a.risk);
      return c != 0 ? c : b.total.compareTo(a.total);
    });
    view.measuredDays = paidTotal > 0 ? paidWeighted / paidTotal : null;
    view.delayCostPerYear = view.total * settings.realInflation / 100;
    return view;
  }

  // ---------------- KPIs ----------------

  double? kpiValue(Kpi k, FinFigures f) => switch (k) {
        Kpi.netProfit => f.netSales > 0 ? f.netMargin : null,
        Kpi.grossMargin => f.netSales > 0 ? f.grossMargin : null,
        Kpi.netSales => f.netSales,
        Kpi.expenseRatio => f.netSales > 0 ? f.expenseRatio : null,
        Kpi.breakEven => f.breakEven,
        Kpi.collection => f.revenue > 0 ? f.collectionRatio : null,
        Kpi.credit => f.creditDays,
        Kpi.stock => f.stockDays,
        Kpi.supplier => f.payables,
        Kpi.avgBill => f.avgBill,
      };

  /// Target line on the trend chart (null = no fixed target).
  double? kpiTarget(Kpi k) => switch (k) {
        Kpi.netProfit => settings.targetNet,
        Kpi.grossMargin => settings.targetGross,
        Kpi.expenseRatio => settings.maxExpense,
        Kpi.collection => settings.minCollection,
        Kpi.credit => settings.maxCreditDays,
        Kpi.stock => settings.maxStockDays,
        _ => null,
      };

  bool kpiIsPercent(Kpi k) =>
      k == Kpi.netProfit || k == Kpi.grossMargin || k == Kpi.expenseRatio || k == Kpi.collection;
  bool kpiIsDays(Kpi k) => k == Kpi.credit || k == Kpi.stock;

  Light light(Kpi k, FinFigures f) {
    final v = kpiValue(k, f);
    if (v == null) return Light.none;
    final s = settings;
    switch (k) {
      case Kpi.netProfit:
        final pv = f.period.isCurrent ? f.projectedNetMargin : v;
        return pv < 0 ? Light.red : (pv < s.targetNet ? Light.orange : Light.green);
      case Kpi.grossMargin:
        return v < s.targetGross - 5 ? Light.red : (v < s.targetGross ? Light.orange : Light.green);
      case Kpi.expenseRatio:
        final ev = f.period.isCurrent ? f.itemExpenseRatio : v;
        return ev > s.maxExpense + 5 ? Light.red : (ev > s.maxExpense ? Light.orange : Light.green);
      case Kpi.collection:
        return v < s.minCollection - 10 ? Light.red : (v < s.minCollection ? Light.orange : Light.green);
      case Kpi.credit:
        return v > s.maxCreditDays * 2 ? Light.red : (v > s.maxCreditDays ? Light.orange : Light.green);
      case Kpi.stock:
        return v > s.maxStockDays * 2 ? Light.red : (v > s.maxStockDays ? Light.orange : Light.green);
      case Kpi.netSales:
        final prev = figures(f.period.prev).netSales;
        if (prev <= 0) return Light.none;
        final change = (f.projectedSales - prev) / prev * 100;
        return change < -10 ? Light.red : (change < 0 ? Light.orange : Light.green);
      case Kpi.breakEven:
        final need = f.breakEven;
        if (need == null) return Light.red;
        final sales = f.period.isCurrent ? f.projectedSales : f.netSales;
        return sales < need ? Light.red : (sales < (f.targetSales(s.targetNet) ?? double.infinity) ? Light.orange : Light.green);
      case Kpi.avgBill:
        final prevBill = figures(f.period.prev).avgBill;
        if (prevBill <= 0) return Light.none;
        return v < prevBill * 0.9 ? Light.red : (v < prevBill ? Light.orange : Light.green);
      case Kpi.supplier:
        return Light.none;
    }
    // ignore: dead_code
    return Light.none;
  }
}

const debtBucketNames = ['0–30 days', '31–60 days', '61–90 days', '91–180 days', 'Over 180 days'];

class DebtRow {
  final String id, name, phone;
  double total = 0;
  final List<double> buckets = List<double>.filled(5, 0);
  int? oldestDays;
  DebtRow(this.id, this.name, this.phone);

  /// Doubtful part: half of 91–180 days, all of over 180 days.
  double get provision => buckets[3] * 0.5 + buckets[4];

  /// Sort key: older money first.
  double get risk => buckets[4] * 4 + buckets[3] * 3 + buckets[2] * 2 + buckets[1];
}

class DebtView {
  final List<DebtRow> rows = [];
  final List<double> buckets = List<double>.filled(5, 0);
  double total = 0;
  double? measuredDays;
  double delayCostPerYear = 0;
  double get provision => buckets[3] * 0.5 + buckets[4];
}

class _Sale {
  final String id;
  final DateTime date;
  final double subtotal, discount, delivery, total, paid;
  _Sale({
    required this.id,
    required this.date,
    required this.subtotal,
    required this.discount,
    required this.delivery,
    required this.total,
    required this.paid,
  });
}

class _Item {
  final DateTime date;
  final String key, name, group;
  final double qty, sales, cost;
  final bool costMissing;
  _Item({
    required this.date,
    required this.key,
    required this.name,
    required this.group,
    required this.qty,
    required this.sales,
    required this.cost,
    required this.costMissing,
  });
}

class _Dated {
  final DateTime date;
  final Map<String, dynamic> m;
  _Dated(this.date, this.m);
}
