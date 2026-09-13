import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../db/db_helper.dart';
import '../utils/formatters.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final _db = DBHelper.instance;
  String _period = 'Week'; // Week or Month
  bool _loading = true;
  String? _error;

  double _revenue = 0;
  double _cost = 0;
  double _profit = 0;
  int _salesCount = 0;
  List<Map<String, dynamic>> _trend = [];
  List<Map<String, dynamic>> _paymentMix = [];
  List<Map<String, dynamic>> _topProducts = [];
  List<Map<String, dynamic>> _byCategory = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  (String, String, int) _rangeAndDays() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (_period == 'Month') {
      final start = DateTime(now.year, now.month, 1);
      final endExclusive = DateTime(now.year, now.month + 1, 1);
      return (start.toIso8601String(), endExclusive.toIso8601String(), now.day);
    }
    final start = today.subtract(const Duration(days: 6));
    final endExclusive = today.add(const Duration(days: 1));
    return (start.toIso8601String(), endExclusive.toIso8601String(), 7);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final (start, end, days) = _rangeAndDays();
      final results = await Future.wait([
        _db.getRevenueCostProfit(startIso: start, endIsoExclusive: end),
        _db.getSalesSummaryByDay(days: days),
        _db.getPaymentTypeWiseSales(startIso: start, endIsoExclusive: end),
        _db.getProductWiseSales(startIso: start, endIsoExclusive: end),
        _db.getCategoryWiseSales(startIso: start, endIsoExclusive: end),
      ]);
      final summary = results[0] as Map<String, dynamic>;
      setState(() {
        _revenue = (summary['revenue'] as num?)?.toDouble() ?? 0;
        _cost = (summary['cost'] as num?)?.toDouble() ?? 0;
        _profit = (summary['profit'] as num?)?.toDouble() ?? 0;
        _salesCount = (summary['count'] as int?) ?? 0;
        _trend = (results[1] as List<Map<String, dynamic>>).reversed.toList();
        _paymentMix = results[2] as List<Map<String, dynamic>>;
        _topProducts = (results[3] as List<Map<String, dynamic>>).take(5).toList();
        _byCategory = results[4] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Could not load reports: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final (start, end, _) = _rangeAndDays();
    return Scaffold(
      appBar: AppBar(title: const Text('Reports & Trends')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
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
                      Text(
                        '${formatDay(start)} → ${formatDay(DateTime.parse(end).subtract(const Duration(days: 1)).toIso8601String())}  ·  $_salesCount sales',
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'Week', label: Text('Week')),
                          ButtonSegment(value: 'Month', label: Text('Month')),
                        ],
                        selected: {_period},
                        onSelectionChanged: (s) {
                          setState(() => _period = s.first);
                          _load();
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: _metricCard('Revenue', formatCurrency(_revenue), Colors.blue)),
                          const SizedBox(width: 12),
                          Expanded(child: _metricCard('Cost', formatCurrency(_cost), Colors.orange)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                              child: _metricCard('Gross Profit', formatCurrency(_profit), Colors.green)),
                          const SizedBox(width: 12),
                          Expanded(
                              child: _metricCard('Sales Count', '$_salesCount', Colors.brown)),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text('Revenue over period', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      SizedBox(height: 160, child: _TrendChart(data: _trend)),
                      const SizedBox(height: 24),
                      Text('Payment Mix', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      SizedBox(height: 160, child: _PaymentMixChart(data: _paymentMix)),
                      const SizedBox(height: 24),
                      Text('Top Products', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      if (_topProducts.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('No sales in this period.'),
                        )
                      else
                        _RankedList(
                          items: _topProducts
                              .map((p) => _RankedItem(p['name'] as String, (p['total'] as num).toDouble()))
                              .toList(),
                        ),
                      const SizedBox(height: 24),
                      Text('By Category', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      if (_byCategory.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('No sales in this period.'),
                        )
                      else
                        _RankedList(
                          items: _byCategory
                              .map((c) => _RankedItem(c['category'] as String, (c['total'] as num).toDouble()))
                              .toList(),
                          barColor: Colors.green,
                        ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
    );
  }

  Widget _metricCard(String label, String value, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
            const SizedBox(height: 6),
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}

class _RankedItem {
  final String label;
  final double value;
  _RankedItem(this.label, this.value);
}

class _RankedList extends StatelessWidget {
  final List<_RankedItem> items;
  final Color barColor;
  const _RankedList({required this.items, this.barColor = Colors.deepOrange});

  @override
  Widget build(BuildContext context) {
    final maxValue = items.fold<double>(0, (m, i) => i.value > m ? i.value : m);
    return Column(
      children: items.map((item) {
        final fraction = maxValue > 0 ? (item.value / maxValue).clamp(0.0, 1.0) : 0.0;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text(item.label, overflow: TextOverflow.ellipsis)),
                  Text(formatCurrency(item.value), style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: fraction,
                  minHeight: 8,
                  backgroundColor: barColor.withOpacity(0.15),
                  valueColor: AlwaysStoppedAnimation(barColor),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _TrendChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  const _TrendChart({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const Center(child: Text('No sales in this period.'));
    final spots = <FlSpot>[];
    for (var i = 0; i < data.length; i++) {
      spots.add(FlSpot(i.toDouble(), (data[i]['total'] as num?)?.toDouble() ?? 0));
    }
    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: (data.length / 6).clamp(1, data.length).toDouble(),
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
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: Theme.of(context).colorScheme.primary,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentMixChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  const _PaymentMixChart({required this.data});

  static const _labels = {'CASH': 'Cash', 'CREDIT': 'Full Credit', 'PARTIAL': 'Partial Credit'};
  static const _order = ['CASH', 'PARTIAL', 'CREDIT'];

  @override
  Widget build(BuildContext context) {
    final totalsByType = {for (final d in data) d['payment_type'] as String: (d['total'] as num).toDouble()};
    if (totalsByType.values.every((v) => v == 0) || totalsByType.isEmpty) {
      return const Center(child: Text('No sales in this period.'));
    }
    final maxValue = totalsByType.values.fold<double>(0, (m, v) => v > m ? v : m);
    final bars = <BarChartGroupData>[];
    for (var i = 0; i < _order.length; i++) {
      final value = totalsByType[_order[i]] ?? 0;
      bars.add(BarChartGroupData(x: i, barRods: [
        BarChartRodData(toY: value, color: Theme.of(context).colorScheme.primary, width: 28),
      ]));
    }
    return BarChart(
      BarChartData(
        maxY: maxValue == 0 ? 1 : maxValue * 1.2,
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
                if (i < 0 || i >= _order.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_labels[_order[i]] ?? '', style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
