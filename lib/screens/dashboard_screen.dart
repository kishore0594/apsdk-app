import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import '../db/db_helper.dart';
import '../utils/formatters.dart';
import '../utils/app_logo.dart';
import '../utils/app_theme.dart';
import '../utils/locale_controller.dart';
import '../utils/user_role.dart';
import '../utils/session_lock.dart';
import '../utils/app_strings.dart';
import 'sales_screen.dart';
import 'vendors_screen.dart';
import 'vendor_insights_screen.dart';
import 'product_margins_screen.dart';
import 'todays_collections_screen.dart';
import 'data_sync_screen.dart';
import 'suppliers_screen.dart';
import 'reports_screen.dart';
import 'inventory_screen.dart';
import 'expenses_screen.dart';
import 'change_password_screen.dart';
import 'promotions_screen.dart';
import 'manage_users_screen.dart';
import '../utils/chart_style.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _db = DBHelper.instance;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  // Raw data, kept live via Firestore listeners (see initState) — every
  // number on this screen is computed from these six lists in
  // _recompute(), never from a separate one-time fetch. A listener
  // always emits whatever's in the local cache the instant it's
  // subscribed to, then updates automatically as fresher data arrives —
  // so the Dashboard shows *something* immediately on open regardless of
  // connection quality, without the hang-or-show-stale-data tradeoff a
  // one-time fetch forced us into (see db_helper.dart's history of this
  // for why that approach was tried and reverted twice).
  List<Map<String, dynamic>> _rawSales = [];
  List<Map<String, dynamic>> _rawSaleItems = [];
  List<Map<String, dynamic>> _rawCreditTxns = [];
  List<Map<String, dynamic>> _rawVendors = [];
  List<Map<String, dynamic>> _rawProducts = [];
  List<Map<String, dynamic>> _rawSuppliers = [];

  // Which of the six streams above have emitted at least once — the
  // loading spinner clears the moment every stream has reported
  // *something* (even an empty cache), rather than waiting on
  // whichever one happens to be slowest to sync.
  final Set<String> _streamsReady = {};
  bool get _loading => _streamsReady.length < 6;
  String? _streamError;

  double _todaysSales = 0;
  double _todaysCollections = 0;
  double _outstandingCredit = 0;
  double _supplierDues = 0;
  double _todaysGrossProfit = 0;
  List<Map<String, dynamic>> _lowStock = [];
  List<Map<String, dynamic>> _agingVendors = [];
  List<Map<String, dynamic>> _weeklySales = [];

  // Sales breakdown (pie charts) state
  String _period = 'Daily'; // Daily, Weekly, Monthly, Custom
  DateTime _customStart = DateTime.now();
  DateTime _customEnd = DateTime.now();
  List<Map<String, dynamic>> _productWiseData = [];
  List<Map<String, dynamic>> _paymentWiseData = [];

  // --- Dashboard resilience: every known failure mode this screen has
  // hit, addressed as one coherent design:
  //
  // 1. STALE DATA — listens to every collection the Dashboard's figures
  //    depend on (sales, sale_items, credit, vendors, products,
  //    suppliers), so any change relevant to a number shown here
  //    updates it.
  // 2. HANGING OR SHOWING STALE DATA ON A FLAKY CONNECTION — this used
  //    to be one-time fetches, which forced a choice between "wait out
  //    a slow server round-trip" and "trust the local cache", and the
  //    cache-trusting version turned out unreliable for filtered
  //    queries (tried and reverted twice — see db_helper.dart). Live
  //    listeners don't have that tradeoff: they emit whatever's cached
  //    immediately on subscribing, then update automatically and
  //    correctly as real data arrives, which is exactly the reliable
  //    behavior that was being approximated badly before.
  // 3. RACING RECOMPUTES — a single credit or partial sale writes to two
  //    collections at once, which can fire multiple listeners within
  //    the same instant. All of them funnel through a debounce, so
  //    near-simultaneous triggers coalesce into one recompute.
  // 4. UPDATING A DISPOSED SCREEN — _recompute() checks `mounted` before
  //    touching state, same reasoning as every other guard in this app.
  StreamSubscription? _salesSub;
  StreamSubscription? _saleItemsSub;
  StreamSubscription? _creditTxnsSub;
  StreamSubscription? _vendorsSub;
  StreamSubscription? _productsSub;
  StreamSubscription? _suppliersSub;
  Timer? _recomputeDebounce;

  @override
  void initState() {
    super.initState();
    _salesSub = _db.watchSalesRaw().listen(
      (snap) {
        _rawSales = _snapToList(snap);
        _streamsReady.add('sales');
        _scheduleRecompute();
      },
      onError: (e) => _handleStreamError('sales', e),
    );
    _saleItemsSub = _db.watchSaleItemsRaw().listen(
      (snap) {
        _rawSaleItems = _snapToList(snap);
        _streamsReady.add('sale_items');
        _scheduleRecompute();
      },
      onError: (e) => _handleStreamError('sale items', e),
    );
    _creditTxnsSub = _db.watchCreditTransactionsRaw().listen(
      (snap) {
        _rawCreditTxns = _snapToList(snap);
        _streamsReady.add('credit_transactions');
        _scheduleRecompute();
      },
      onError: (e) => _handleStreamError('credit transactions', e),
    );
    _vendorsSub = _db.watchVendorsRaw().listen(
      (snap) {
        _rawVendors = _snapToList(snap);
        _streamsReady.add('vendors');
        _scheduleRecompute();
      },
      onError: (e) => _handleStreamError('vendors', e),
    );
    _productsSub = _db.watchProductsRaw().listen(
      (snap) {
        _rawProducts = _snapToList(snap);
        _streamsReady.add('products');
        _scheduleRecompute();
      },
      onError: (e) => _handleStreamError('products', e),
    );
    _suppliersSub = _db.watchSuppliersRaw().listen(
      (snap) {
        _rawSuppliers = _snapToList(snap);
        _streamsReady.add('suppliers');
        _scheduleRecompute();
      },
      onError: (e) => _handleStreamError('suppliers', e),
    );
  }

  List<Map<String, dynamic>> _snapToList(QuerySnapshot snap) {
    return snap.docs.map((d) {
      final data = (d.data() as Map<String, dynamic>?) ?? {};
      return {...data, 'id': d.id};
    }).toList();
  }

  void _handleStreamError(String which, Object e) {
    if (mounted) setState(() => _streamError = 'Could not sync $which: $e');
  }

  void _scheduleRecompute() {
    // Coalesces near-simultaneous emissions into a single recompute —
    // this is now pure, synchronous Dart over data already held in
    // memory, not a fresh set of Firestore queries, so there's nothing
    // left to race, hang, or go stale waiting on.
    _recomputeDebounce?.cancel();
    _recomputeDebounce = Timer(const Duration(milliseconds: 150), _recompute);
  }

  @override
  void dispose() {
    _recomputeDebounce?.cancel();
    _salesSub?.cancel();
    _saleItemsSub?.cancel();
    _creditTxnsSub?.cancel();
    _vendorsSub?.cancel();
    _productsSub?.cancel();
    _suppliersSub?.cancel();
    super.dispose();
  }

  void _recompute() {
    if (!mounted) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayPrefix = today.toIso8601String().substring(0, 10);
    final weekAgoPrefix = today.subtract(const Duration(days: 6)).toIso8601String();

    double todaysSales = 0;
    final byDay = <String, double>{};
    for (final s in _rawSales) {
      if (s['status'] == 'cancelled') continue;
      final date = s['date'] as String? ?? '';
      final amount = (s['total_amount'] as num?)?.toDouble() ?? 0;
      if (date.startsWith(todayPrefix)) todaysSales += amount;
      if (date.compareTo(weekAgoPrefix) >= 0) {
        final day = date.length >= 10 ? date.substring(0, 10) : date;
        byDay[day] = (byDay[day] ?? 0) + amount;
      }
    }
    final weeklySales = byDay.entries.map((e) => {'day': e.key, 'total': e.value}).toList()
      ..sort((a, b) => (b['day'] as String).compareTo(a['day'] as String));

    double todaysCost = 0;
    for (final item in _rawSaleItems) {
      if (item['status'] == 'cancelled') continue;
      final saleDate = item['sale_date'] as String? ?? '';
      if (!saleDate.startsWith(todayPrefix)) continue;
      final qty = (item['quantity'] as num?)?.toDouble() ?? 0;
      final unitCost = (item['unit_cost'] as num?)?.toDouble() ?? 0;
      todaysCost += qty * unitCost;
    }

    double todaysCollections = 0;
    for (final t in _rawCreditTxns) {
      if (t['type'] != 'PAYMENT') continue;
      final date = t['date'] as String? ?? '';
      if (date.startsWith(todayPrefix)) todaysCollections += (t['amount'] as num?)?.toDouble() ?? 0;
    }

    double outstandingCredit = 0;
    for (final v in _rawVendors) {
      outstandingCredit += (v['balance'] as num?)?.toDouble() ?? 0;
    }

    // Same days-outstanding algorithm as getVendorOutstandingDays in
    // db_helper.dart, computed per vendor from the in-memory
    // credit_transactions list instead of a fresh per-vendor query.
    final txnsByVendor = <String, List<Map<String, dynamic>>>{};
    for (final t in _rawCreditTxns) {
      final vendorId = t['vendor_id'] as String?;
      if (vendorId == null) continue;
      txnsByVendor.putIfAbsent(vendorId, () => []).add(t);
    }
    final agingVendors = <Map<String, dynamic>>[];
    for (final v in _rawVendors) {
      final balance = (v['balance'] as num?)?.toDouble() ?? 0;
      if (balance <= 0) continue;
      final vendorId = v['id'] as String;
      final txns = <Map<String, dynamic>>[...(txnsByVendor[vendorId] ?? const <Map<String, dynamic>>[])]
        ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
      final since = oldestUnpaidCreditSince(txns);
      if (since == null) continue;
      final days = now.difference(since).inDays;
      if (days >= 60) {
        agingVendors.add({...v, 'balance': balance, 'days_outstanding': days});
      }
    }
    agingVendors.sort((a, b) => (b['days_outstanding'] as int).compareTo(a['days_outstanding'] as int));

    final lowStock = _rawProducts.where((p) {
      final qty = (p['quantity'] as num?)?.toDouble() ?? 0;
      final reorder = (p['reorder_level'] as num?)?.toDouble() ?? 0;
      return qty <= reorder;
    }).toList()
      ..sort((a, b) => ((a['quantity'] as num?) ?? 0).compareTo((b['quantity'] as num?) ?? 0));

    double supplierDues = 0;
    for (final s in _rawSuppliers) {
      supplierDues += (s['balance'] as num?)?.toDouble() ?? 0;
    }

    // Breakdown (product-wise / payment-type-wise) for whichever period
    // is currently selected — recomputed here too rather than via a
    // separate fetch, so switching Daily/Weekly/Monthly/Custom is
    // instant.
    final (periodStart, periodEnd) = _periodRange();
    final productTotals = <String, double>{};
    final paymentTotals = <String, double>{};
    // Share of each bill actually charged after its discount, so the
    // product pie adds up to real revenue (item prices are pre-discount).
    final saleFactor = <String, double>{};
    for (final s in _rawSales) {
      final total = (s['total_amount'] as num?)?.toDouble() ?? 0;
      final discount = (s['discount'] as num?)?.toDouble() ?? 0;
      saleFactor[s['id'] as String] = (total + discount) > 0 ? total / (total + discount) : 1;
    }
    for (final item in _rawSaleItems) {
      if (item['status'] == 'cancelled') continue;
      final saleDate = item['sale_date'] as String? ?? '';
      if (saleDate.compareTo(periodStart) < 0 || saleDate.compareTo(periodEnd) >= 0) continue;
      final name = item['product_name'] as String? ?? '';
      productTotals[name] = (productTotals[name] ?? 0) +
          ((item['subtotal'] as num?)?.toDouble() ?? 0) * (saleFactor[item['sale_id']] ?? 1);
    }
    for (final s in _rawSales) {
      if (s['status'] == 'cancelled') continue;
      final date = s['date'] as String? ?? '';
      if (date.compareTo(periodStart) < 0 || date.compareTo(periodEnd) >= 0) continue;
      final type = s['payment_type'] as String? ?? '';
      paymentTotals[type] = (paymentTotals[type] ?? 0) + ((s['total_amount'] as num?)?.toDouble() ?? 0);
    }
    final productWiseData = productTotals.entries.map((e) => {'name': e.key, 'total': e.value}).toList()
      ..sort((a, b) => (b['total'] as double).compareTo(a['total'] as double));
    final paymentWiseData =
        paymentTotals.entries.map((e) => {'payment_type': e.key, 'total': e.value}).toList();

    setState(() {
      _todaysSales = todaysSales;
      _todaysCollections = todaysCollections;
      _outstandingCredit = outstandingCredit;
      _lowStock = lowStock;
      _agingVendors = agingVendors;
      _weeklySales = weeklySales.reversed.toList();
      _supplierDues = supplierDues;
      _todaysGrossProfit = todaysSales - todaysCost;
      _productWiseData = productWiseData;
      _paymentWiseData = paymentWiseData;
      _streamError = null;
    });
  }

  /// Returns the start/endExclusive ISO8601 range for the current
  /// period selection.
  (String, String) _periodRange() {
    final now = DateTime.now();
    DateTime start;
    DateTime endExclusive;
    switch (_period) {
      case 'Weekly':
        final today = DateTime(now.year, now.month, now.day);
        start = today.subtract(const Duration(days: 6));
        endExclusive = today.add(const Duration(days: 1));
        break;
      case 'Monthly':
        start = DateTime(now.year, now.month, 1);
        endExclusive = DateTime(now.year, now.month + 1, 1);
        break;
      case 'Custom':
        start = DateTime(_customStart.year, _customStart.month, _customStart.day);
        endExclusive = DateTime(_customEnd.year, _customEnd.month, _customEnd.day)
            .add(const Duration(days: 1));
        break;
      case 'Daily':
      default:
        start = DateTime(now.year, now.month, now.day);
        endExclusive = start.add(const Duration(days: 1));
    }
    return (start.toIso8601String(), endExclusive.toIso8601String());
  }

  Future<void> _pickLanguage() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppStrings.t('select_language')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(AppStrings.t('english')),
              trailing: LocaleController.instance.language == 'en'
                  ? const Icon(Icons.check, color: AppTheme.primary)
                  : null,
              onTap: () => Navigator.pop(context, 'en'),
            ),
            ListTile(
              title: Text(AppStrings.t('tamil')),
              trailing: LocaleController.instance.language == 'ta'
                  ? const Icon(Icons.check, color: AppTheme.primary)
                  : null,
              onTap: () => Navigator.pop(context, 'ta'),
            ),
          ],
        ),
      ),
    );
    if (choice != null) {
      await LocaleController.instance.setLanguage(choice);
    }
  }

  Future<void> _pickCustomRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _customStart, end: _customEnd),
    );
    if (range != null && mounted) {
      setState(() {
        _customStart = range.start;
        _customEnd = range.end;
        _period = 'Custom';
      });
      _recompute();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      endDrawerEnableOpenDragGesture: true,
      endDrawer: _buildQuickAccessDrawer(context),
      appBar: AppBar(
        title: Row(
          children: [
            const AppLogo(size: 32, withBackground: false),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(AppStrings.t('app_name'),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.1)),
                  Text(AppStrings.t('store_overview'),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w400, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (UserRole.instance.isViewer)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Chip(
                label: const Text('View Only', style: TextStyle(fontSize: 11, color: Colors.white)),
                backgroundColor: Colors.white.withOpacity(0.2),
                visualDensity: VisualDensity.compact,
                side: BorderSide.none,
              ),
            ),
          IconButton(
            tooltip: AppStrings.t('language'),
            icon: const Icon(Icons.language),
            onPressed: _pickLanguage,
          ),
          IconButton(
            tooltip: AppStrings.t('sign_out'),
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: Text(AppStrings.t('sign_out_confirm')),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false), child: Text(AppStrings.t('cancel'))),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true), child: Text(AppStrings.t('sign_out'))),
                  ],
                ),
              );
              if (confirm == true) {
                // Locks the app on this device instead of destroying the
                // Firebase session — so signing back in works offline
                // (see SessionLock). The session and any unsynced sales
                // stay safe underneath.
                UserRole.instance.reset();
                await SessionLock.instance.lock();
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _streamError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 40),
                        const SizedBox(height: 12),
                        Text(_streamError!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => setState(() => _streamError = null),
                          child: const Text('Dismiss'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
              // There's no separate fetch to trigger anymore — every
              // figure is already live — but pulling to refresh is a
              // familiar gesture people expect to do *something*, so
              // this just re-runs the same synchronous computation
              // against whatever's currently held in memory. Near-
              // instant, and harmless to call whenever.
              onRefresh: () async => _recompute(),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          label: AppStrings.t('todays_sales'),
                          value: formatCurrency(_todaysSales),
                          icon: Icons.point_of_sale,
                          color: Colors.green,
                          onTap: () => Navigator.push(
                              context, MaterialPageRoute(builder: (_) => const SalesScreen())),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          label: AppStrings.t('todays_collections'),
                          value: formatCurrency(_todaysCollections),
                          icon: Icons.payments,
                          color: Colors.blue,
                          onTap: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const TodaysCollectionsScreen())),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _StatCard(
                    label: AppStrings.t('total_outstanding_credit'),
                    value: formatCurrency(_outstandingCredit),
                    icon: Icons.receipt_long,
                    color: Colors.orange,
                    wide: true,
                    onTap: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => const VendorsScreen())),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          label: AppStrings.t('todays_gross_profit'),
                          value: formatCurrency(_todaysGrossProfit),
                          icon: Icons.trending_up,
                          color: Colors.teal,
                          onTap: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const ReportsScreen())),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          label: AppStrings.t('supplier_dues'),
                          value: formatCurrency(_supplierDues),
                          icon: Icons.local_shipping,
                          color: Colors.brown,
                          onTap: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const SuppliersScreen())),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text('Sales — last 7 days', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  SizedBox(height: 180, child: _WeeklyChart(data: _weeklySales)),
                  const SizedBox(height: 28),
                  Text('Sales Breakdown', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'Daily', label: Text('Daily')),
                      ButtonSegment(value: 'Weekly', label: Text('Weekly')),
                      ButtonSegment(value: 'Monthly', label: Text('Monthly')),
                      ButtonSegment(value: 'Custom', label: Text('Custom')),
                    ],
                    selected: {_period},
                    onSelectionChanged: (s) {
                      final choice = s.first;
                      if (choice == 'Custom') {
                        _pickCustomRange();
                      } else {
                        setState(() => _period = choice);
                        _recompute();
                      }
                    },
                  ),
                  if (_period == 'Custom')
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '${dayFormat.format(_customStart)} — ${dayFormat.format(_customEnd)}',
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ),
                  const SizedBox(height: 12),
                  _PieChartCard(
                    title: 'Sales by Product',
                    data: _productWiseData
                        .map((d) => _PieSlice(label: d['name'] as String, value: (d['total'] as num).toDouble()))
                        .toList(),
                  ),
                  const SizedBox(height: 20),
                  _PieChartCard(
                    title: 'Cash vs Credit',
                    data: _paymentWiseData
                        .map((d) => _PieSlice(
                            label: d['payment_type'] as String, value: (d['total'] as num).toDouble()))
                        .toList(),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Text(AppStrings.t('outstanding_vendors'), style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(width: 8),
                      if (_agingVendors.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text('${_agingVendors.length}',
                              style: const TextStyle(color: Colors.white, fontSize: 12)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_agingVendors.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('No vendor has had an unpaid balance for 60+ days.'),
                    )
                  else
                    ..._agingVendors.map((v) => Card(
                          child: ListTile(
                            leading: const Icon(Icons.warning_amber, color: Colors.red),
                            title: Text(v['name'] as String),
                            subtitle: Text('Outstanding ${v['days_outstanding']} days'),
                            trailing: Text(
                              formatCurrency(v['balance']),
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                            ),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => VendorDetailScreen(vendor: v)),
                            ),
                          ),
                        )),
                ],
              ),
            ),
          ),
          _buildPullTab(context),
        ],
      ),
    );
  }

  /// A persistently visible tab on the right edge — tap (or swipe from
  /// the edge) to open the "More" panel. Shows a small red dot when
  /// there's a low-stock alert, so it hints something needs attention
  /// even before it's opened.
  Widget _buildPullTab(BuildContext context) {
    return Positioned(
      right: 0,
      top: MediaQuery.of(context).size.height * 0.38,
      child: GestureDetector(
        onTap: () => _scaffoldKey.currentState?.openEndDrawer(),
        child: Container(
          width: 26,
          height: 72,
          decoration: BoxDecoration(
            color: AppTheme.primary,
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 6, offset: const Offset(-1, 2)),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Icon(Icons.chevron_left, color: Colors.white, size: 20),
              if (_lowStock.isNotEmpty)
                const Positioned(
                  top: 8,
                  child: CircleAvatar(radius: 4, backgroundColor: Colors.redAccent),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The panel the pull tab opens — houses everything moved off the
  /// Dashboard's app bar and body (Vendor Insights, Reports, Import/
  /// Export, and the Low Stock list) so the Dashboard itself stays to
  /// just its core at-a-glance numbers.
  Widget _buildQuickAccessDrawer(BuildContext context) {
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.7,
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Text('More',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primary)),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const IconBadge(icon: Icons.insights_outlined, color: AppTheme.accent, size: 18),
              title: const Text('Vendor Insights'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const VendorInsightsScreen()));
              },
            ),
            ListTile(
              leading: const IconBadge(icon: Icons.percent, color: AppTheme.profit, size: 18),
              title: const Text('Profit Margins'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductMarginsScreen()));
              },
            ),
            ListTile(
              leading: const IconBadge(icon: Icons.bar_chart, color: AppTheme.revenue, size: 18),
              title: Text(AppStrings.t('reports_trends')),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsScreen()));
              },
            ),
            ListTile(
              leading: const IconBadge(icon: Icons.sync_alt, color: AppTheme.profit, size: 18),
              title: Text(AppStrings.t('data_export_import')),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const DataSyncScreen()));
              },
            ),
            ListTile(
              leading: IconBadge(
                icon: Icons.warning_amber_rounded,
                color: _lowStock.isNotEmpty ? AppTheme.danger : AppTheme.success,
                size: 18,
              ),
              title: Text(AppStrings.t('low_stock_alerts')),
              trailing: _lowStock.isNotEmpty
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: AppTheme.danger, borderRadius: BorderRadius.circular(12)),
                      child: Text('${_lowStock.length}', style: const TextStyle(color: Colors.white, fontSize: 11)),
                    )
                  : null,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const InventoryScreen(initialCategoryFilter: 'Low Stock')),
                );
              },
            ),
            ListTile(
              leading: const IconBadge(icon: Icons.receipt_long_outlined, color: AppTheme.cost, size: 18),
              title: const Text('Operating Expenses'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ExpensesScreen()));
              },
            ),
            ListTile(
              leading: const IconBadge(icon: Icons.lock_reset, color: AppTheme.primary, size: 18),
              title: const Text('Change Password'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ChangePasswordScreen()));
              },
            ),
            if (UserRole.instance.isAdmin) ...[
              ListTile(
                leading: const IconBadge(icon: Icons.campaign_outlined, color: AppTheme.accent, size: 18),
                title: const Text('Promotions'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const PromotionsScreen()));
                },
              ),
              ListTile(
                leading: const IconBadge(icon: Icons.manage_accounts_outlined, color: AppTheme.primary, size: 18),
                title: const Text('Manage Users'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageUsersScreen()));
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool wide;
  final VoidCallback? onTap;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.wide = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color.withOpacity(0.08),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icon, color: color),
                  if (onTap != null) Icon(Icons.chevron_right, color: color.withOpacity(0.6), size: 18),
                ],
              ),
              const SizedBox(height: 8),
              Text(label, style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
              const SizedBox(height: 4),
              Text(value,
                  style: TextStyle(
                      fontSize: wide ? 22 : 18, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeeklyChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  const _WeeklyChart({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Center(child: Text('No sales recorded yet.'));
    }
    final bars = <BarChartGroupData>[];
    for (var i = 0; i < data.length; i++) {
      final total = (data[i]['total'] as num?)?.toDouble() ?? 0;
      bars.add(BarChartGroupData(x: i, barRods: [
        BarChartRodData(toY: total, color: Theme.of(context).colorScheme.primary, width: 16),
      ]));
    }
    return BarChart(
      BarChartData(
        barTouchData: ChartStyle.barTouch([for (final d in data) d['day'] as String? ?? '']),
        barGroups: bars,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= data.length) return const SizedBox.shrink();
                final day = data[i]['day'] as String? ?? '';
                final label = day.length >= 10 ? day.substring(8, 10) : day;
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(label, style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// One slice of data for a pie chart (a product name + its total, or a
/// payment type + its total).
class _PieSlice {
  final String label;
  final double value;
  _PieSlice({required this.label, required this.value});
}

const _pieColors = [
  Color(0xFF1E6F5C),
  Color(0xFFE07A5F),
  Color(0xFF3D5A80),
  Color(0xFFF2CC8F),
  Color(0xFF81B29A),
  Color(0xFF9B5DE5),
  Color(0xFFEE6C4D),
  Color(0xFF457B9D),
  Color(0xFFBC6C25),
  Color(0xFF6D6875),
];

class _PieChartCard extends StatelessWidget {
  final String title;
  final List<_PieSlice> data;
  const _PieChartCard({required this.title, required this.data});

  @override
  Widget build(BuildContext context) {
    final total = data.fold<double>(0, (sum, d) => sum + d.value);
    final sorted = [...data]..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            if (total == 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No sales in this period.')),
              )
            else ...[
              SizedBox(
                height: 160,
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 32,
                    sections: [
                      for (var i = 0; i < sorted.length; i++)
                        PieChartSectionData(
                          value: sorted[i].value,
                          color: _pieColors[i % _pieColors.length],
                          // Slices under 6% are too thin for a readable
                          // label — their % is shown in the legend below.
                          title: sorted[i].value / total >= 0.06
                              ? '${(sorted[i].value / total * 100).toStringAsFixed(0)}%'
                              : '',
                          radius: 55,
                          titleStyle: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < sorted.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: _pieColors[i % _pieColors.length],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(sorted[i].label,
                              overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5))),
                      Text('${(sorted[i].value / total * 100).toStringAsFixed(0)}%  ',
                          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                      Text(formatCurrency(sorted[i].value),
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
