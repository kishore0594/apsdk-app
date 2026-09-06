import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../db/db_helper.dart';
import '../utils/formatters.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _db = DBHelper.instance;

  double _todaysSales = 0;
  double _todaysCollections = 0;
  double _outstandingCredit = 0;
  List<Map<String, dynamic>> _lowStock = [];
  List<Map<String, dynamic>> _weeklySales = [];
  bool _loading = true;

  // Sales breakdown (pie charts) state
  String _period = 'Daily'; // Daily, Weekly, Monthly, Custom
  DateTime _customStart = DateTime.now();
  DateTime _customEnd = DateTime.now();
  List<Map<String, dynamic>> _productWiseData = [];
  List<Map<String, dynamic>> _paymentWiseData = [];
  bool _breakdownLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final sales = await _db.getTodaysSalesTotal();
    final collections = await _db.getTodaysCollections();
    final collectionsTotal = collections.fold<double>(
        0, (sum, c) => sum + (c['amount'] as num).toDouble());
    final outstanding = await _db.getTotalOutstandingCredit();
    final lowStock = await _db.getLowStockProducts();
    final weekly = await _db.getSalesSummaryByDay(days: 7);

    setState(() {
      _todaysSales = sales;
      _todaysCollections = collectionsTotal;
      _outstandingCredit = outstanding;
      _lowStock = lowStock;
      _weeklySales = weekly.reversed.toList();
      _loading = false;
    });

    await _loadBreakdown();
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

  Future<void> _loadBreakdown() async {
    setState(() => _breakdownLoading = true);
    final (start, end) = _periodRange();
    final products = await _db.getProductWiseSales(startIso: start, endIsoExclusive: end);
    final payments = await _db.getPaymentTypeWiseSales(startIso: start, endIsoExclusive: end);
    setState(() {
      _productWiseData = products;
      _paymentWiseData = payments;
      _breakdownLoading = false;
    });
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
      appBar: AppBar(title: const Text('APSDK — Store Overview')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          label: "Today's Sales",
                          value: formatCurrency(_todaysSales),
                          icon: Icons.point_of_sale,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          label: "Today's Collections",
                          value: formatCurrency(_todaysCollections),
                          icon: Icons.payments,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _StatCard(
                    label: 'Total Outstanding Credit',
                    value: formatCurrency(_outstandingCredit),
                    icon: Icons.receipt_long,
                    color: Colors.orange,
                    wide: true,
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
                      Text('Low Stock Alerts', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(width: 8),
                      if (_lowStock.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text('${_lowStock.length}',
                              style: const TextStyle(color: Colors.white, fontSize: 12)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_lowStock.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('All products are above reorder level.'),
                    )
                  else
                    ..._lowStock.map((p) => Card(
                          child: ListTile(
                            leading: const Icon(Icons.warning_amber, color: Colors.red),
                            title: Text(p['name'] as String),
                            subtitle: Text(
                                'In stock: ${p['quantity']} ${p['unit']}  •  Reorder level: ${p['reorder_level']}'),
                          ),
                        )),
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

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color.withOpacity(0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontSize: wide ? 22 : 18, fontWeight: FontWeight.bold, color: color)),
          ],
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
