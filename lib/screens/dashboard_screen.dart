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
