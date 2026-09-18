import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import '../db/db_helper.dart';
import '../utils/formatters.dart';
import '../utils/app_logo.dart';
import '../utils/app_theme.dart';
import '../utils/locale_controller.dart';
import '../utils/app_strings.dart';
import 'sales_screen.dart';
import 'vendors_screen.dart';
import 'vendor_insights_screen.dart';
import 'todays_collections_screen.dart';
import 'data_sync_screen.dart';
import 'suppliers_screen.dart';
import 'reports_screen.dart';
import 'inventory_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _db = DBHelper.instance;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  double _todaysSales = 0;
  double _todaysCollections = 0;
  double _outstandingCredit = 0;
  double _supplierDues = 0;
  double _todaysGrossProfit = 0;
  List<Map<String, dynamic>> _lowStock = [];
  List<Map<String, dynamic>> _agingVendors = [];
  List<Map<String, dynamic>> _weeklySales = [];
  bool _loading = true;
  String? _error;

  // Sales breakdown (pie charts) state
  String _period = 'Daily'; // Daily, Weekly, Monthly, Custom
  DateTime _customStart = DateTime.now();
  DateTime _customEnd = DateTime.now();
  List<Map<String, dynamic>> _productWiseData = [];
  List<Map<String, dynamic>> _paymentWiseData = [];
  bool _breakdownLoading = true;

  StreamSubscription? _salesChangeSub;
  StreamSubscription? _creditChangeSub;

  @override
  void initState() {
    super.initState();
    _load();
    // Auto-refresh the whole dashboard the instant a sale or a credit/
    // payment entry changes — on this phone, or synced in from the other
    // one. .skip(1) drops the initial snapshot each stream fires
    // immediately on subscribing, since _load() above already covers that.
    _salesChangeSub = _db.watchSalesRaw().skip(1).listen((_) => _load());
    _creditChangeSub = _db.watchCreditTransactionsRaw().skip(1).listen((_) => _load());
  }

  @override
  void dispose() {
    _salesChangeSub?.cancel();
    _creditChangeSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day).toIso8601String();
      final todayEnd = DateTime(now.year, now.month, now.day).add(const Duration(days: 1)).toIso8601String();

      // Run every independent query at once instead of one after another —
      // this is what made the Dashboard feel slow, since these used to
      // wait on each other in sequence.
      final results = await Future.wait([
        _db.getTodaysSalesTotal(),
        _db.getTodaysCollections(),
        _db.getTotalOutstandingCredit(),
        _db.getLowStockProducts(),
        _db.getAgingVendors(minDays: 60),
        _db.getSalesSummaryByDay(days: 7),
        _db.getTotalSupplierDues(),
        _db.getRevenueCostProfit(startIso: todayStart, endIsoExclusive: todayEnd),
      ]).timeout(
        const Duration(seconds: 20),
        // A timeout throws by default, which the catch block below already
        // turns into a proper error screen with Retry — this just
        // guarantees that happens within a bounded time instead of the
        // spinner running indefinitely if a query is ever stuck (flaky
        // connection, etc.).
      );
      final collections = results[1] as List<Map<String, dynamic>>;
      final collectionsTotal =
          collections.fold<double>(0, (sum, c) => sum + (c['amount'] as num).toDouble());
      final profitData = results[7] as Map<String, dynamic>;

      setState(() {
        _todaysSales = results[0] as double;
        _todaysCollections = collectionsTotal;
        _outstandingCredit = results[2] as double;
        _lowStock = results[3] as List<Map<String, dynamic>>;
        _agingVendors = results[4] as List<Map<String, dynamic>>;
        _weeklySales = (results[5] as List<Map<String, dynamic>>).reversed.toList();
        _supplierDues = results[6] as double;
        _todaysGrossProfit = (profitData['profit'] as num?)?.toDouble() ?? 0;
        _loading = false;
      });

      await _loadBreakdown();
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Could not load dashboard: $e';
      });
    }
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

  Future<void> _loadBreakdown() async {
    setState(() => _breakdownLoading = true);
    try {
      final (start, end) = _periodRange();
      final results = await Future.wait([
        _db.getProductWiseSales(startIso: start, endIsoExclusive: end),
        _db.getPaymentTypeWiseSales(startIso: start, endIsoExclusive: end),
      ]).timeout(const Duration(seconds: 20));
      setState(() {
        _productWiseData = results[0];
        _paymentWiseData = results[1];
        _breakdownLoading = false;
      });
    } catch (e) {
      setState(() => _breakdownLoading = false);
    }
  }

  Future<void> _pickCustomRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _customStart, end: _customEnd),
    );
    if (range != null) {
      setState(() {
        _customStart = range.start;
        _customEnd = range.end;
        _period = 'Custom';
      });
      _loadBreakdown();
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
                await FirebaseAuth.instance.signOut();
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
                : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 40),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
              onRefresh: _load,
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
                        _loadBreakdown();
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
                  if (_breakdownLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else ...[
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
                  ],
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
                          title: '${(sorted[i].value / total * 100).toStringAsFixed(0)}%',
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
