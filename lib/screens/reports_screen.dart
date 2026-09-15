import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../db/db_helper.dart';
import '../utils/formatters.dart';
import '../utils/app_logo.dart';
import '../utils/app_info.dart';
import '../utils/app_strings.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final _db = DBHelper.instance;
  String _period = 'Week'; // Week, Month, Custom
  DateTime _customStart = DateTime.now().subtract(const Duration(days: 6));
  DateTime _customEnd = DateTime.now();
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
  List<Map<String, dynamic>> _bySubcategory = [];

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
    if (_period == 'Custom') {
      final start = DateTime(_customStart.year, _customStart.month, _customStart.day);
      final endExclusive =
          DateTime(_customEnd.year, _customEnd.month, _customEnd.day).add(const Duration(days: 1));
      final days = endExclusive.difference(start).inDays;
      return (start.toIso8601String(), endExclusive.toIso8601String(), days.clamp(1, 366));
    }
    final start = today.subtract(const Duration(days: 6));
    final endExclusive = today.add(const Duration(days: 1));
    return (start.toIso8601String(), endExclusive.toIso8601String(), 7);
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
      _load();
    }
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
        _db.getSubcategoryWiseSales(startIso: start, endIsoExclusive: end),
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
        _bySubcategory = results[5] as List<Map<String, dynamic>>;
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
      backgroundColor: const Color(0xFFF7F8F7),
      appBar: AppBar(title: Text(AppStrings.t('reports_trends'))),
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
                        FilledButton(onPressed: _load, child: Text(AppStrings.t('retry'))),
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
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _PeriodPill(
                              label: AppStrings.t('week'),
                              selected: _period == 'Week',
                              onTap: () {
                                setState(() => _period = 'Week');
                                _load();
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _PeriodPill(
                              label: AppStrings.t('month'),
                              selected: _period == 'Month',
                              onTap: () {
                                setState(() => _period = 'Month');
                                _load();
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _PeriodPill(
                              label: AppStrings.t('custom'),
                              selected: _period == 'Custom',
                              icon: Icons.calendar_month,
                              onTap: _pickCustomRange,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1.55,
                        children: [
                          _MetricCard(
                              label: AppStrings.t('revenue'),
                              value: formatCurrency(_revenue),
                              icon: Icons.trending_up,
                              color: const Color(0xFF2563EB)),
                          _MetricCard(
                              label: AppStrings.t('cost'),
                              value: formatCurrency(_cost),
                              icon: Icons.shopping_bag_outlined,
                              color: const Color(0xFFEA580C)),
                          _MetricCard(
                              label: AppStrings.t('gross_profit'),
                              value: formatCurrency(_profit),
                              icon: Icons.savings_outlined,
                              color: const Color(0xFF1E6F5C)),
                          _MetricCard(
                              label: AppStrings.t('sales_count'),
                              value: '$_salesCount',
                              icon: Icons.receipt_long_outlined,
                              color: const Color(0xFF7C3AED)),
                        ],
                      ),
                      const SizedBox(height: 28),
                      _SectionHeader(AppStrings.t('revenue_over_period')),
                      const SizedBox(height: 12),
                      _ChartCard(child: SizedBox(height: 170, child: _TrendChart(data: _trend))),
                      const SizedBox(height: 28),
                      _SectionHeader(AppStrings.t('payment_mix')),
                      const SizedBox(height: 12),
                      _ChartCard(child: SizedBox(height: 180, child: _PaymentMixChart(data: _paymentMix))),
                      const SizedBox(height: 28),
                      _SectionHeader(AppStrings.t('top_products')),
                      const SizedBox(height: 12),
                      _ChartCard(
                        child: _topProducts.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Text(AppStrings.t('no_sales_in_period')),
                              )
                            : _RankedList(
                                items: _topProducts
                                    .map((p) =>
                                        _RankedItem(p['name'] as String, (p['total'] as num).toDouble()))
                                    .toList(),
                                barColor: const Color(0xFF1E6F5C),
                              ),
                      ),
                      const SizedBox(height: 28),
                      _SectionHeader(AppStrings.t('by_category')),
                      const SizedBox(height: 12),
                      _ChartCard(
                        child: _byCategory.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Text(AppStrings.t('no_sales_in_period')),
                              )
                            : _RankedList(
                                items: _byCategory
                                    .map((c) => _RankedItem(
                                        c['category'] as String, (c['total'] as num).toDouble()))
                                    .toList(),
                                barColor: const Color(0xFF7C3AED),
                              ),
                      ),
                      const SizedBox(height: 28),
                      _SectionHeader(AppStrings.t('by_subcategory')),
                      const SizedBox(height: 12),
                      _ChartCard(
                        child: _bySubcategory.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Text(AppStrings.t('no_sales_in_period')),
                              )
                            : _RankedList(
                                items: _bySubcategory
                                    .map((c) => _RankedItem(
                                        c['subcategory'] as String, (c['total'] as num).toDouble()))
                                    .toList(),
                                barColor: const Color(0xFFD97706),
                              ),
                      ),
                      const SizedBox(height: 28),
                      // Version footer — makes it unambiguous which build
                      // is installed when reporting an issue.
                      Center(
                        child: Column(
                          children: [
                            const AppLogo(size: 34),
                            const SizedBox(height: 8),
                            Text(
                              AppInfo.appName,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade600),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              AppInfo.versionLine,
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }
}

class _PeriodPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  const _PeriodPill({required this.label, required this.selected, required this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF1E6F5C);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? primary : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? primary : Colors.grey.shade300),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: selected ? Colors.white : Colors.black54),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.black87,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold));
  }
}

class _ChartCard extends StatelessWidget {
  final Widget child;
  const _ChartCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: child,
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _MetricCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: color),
          ),
          const Spacer(),
          Text(label, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: color),
            overflow: TextOverflow.ellipsis,
          ),
        ],
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
  const _RankedList({required this.items, this.barColor = const Color(0xFF1E6F5C)});

  @override
  Widget build(BuildContext context) {
    final maxValue = items.fold<double>(0, (m, i) => i.value > m ? i.value : m);
    return Column(
      children: [
        for (var idx = 0; idx < items.length; idx++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  margin: const EdgeInsets.only(top: 1, right: 10),
                  decoration: BoxDecoration(
                    color: barColor.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text('${idx + 1}',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: barColor)),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                              child: Text(items[idx].label,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))),
                          Text(formatCurrency(items[idx].value),
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: maxValue > 0 ? (items[idx].value / maxValue).clamp(0.0, 1.0) : 0.0,
                          minHeight: 7,
                          backgroundColor: barColor.withOpacity(0.10),
                          valueColor: AlwaysStoppedAnimation(barColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TrendChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  const _TrendChart({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return Center(child: Text(AppStrings.t('no_sales_in_period')));
    const lineColor = Color(0xFF1E6F5C);
    final spots = <FlSpot>[];
    for (var i = 0; i < data.length; i++) {
      spots.add(FlSpot(i.toDouble(), (data[i]['total'] as num?)?.toDouble() ?? 0));
    }
    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: null,
          getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey.shade200, strokeWidth: 1),
        ),
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
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.25,
            color: lineColor,
            barWidth: 3,
            dotData: FlDotData(
              show: spots.length <= 14,
              getDotPainter: (spot, percent, bar, index) =>
                  FlDotCirclePainter(radius: 3, color: lineColor, strokeWidth: 2, strokeColor: Colors.white),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [lineColor.withOpacity(0.22), lineColor.withOpacity(0.0)],
              ),
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

  static Map<String, String> get _labels =>
      {'CASH': AppStrings.t('cash'), 'CREDIT': AppStrings.t('full_credit'), 'PARTIAL': AppStrings.t('partial_credit')};
  static const _order = ['CASH', 'PARTIAL', 'CREDIT'];
  static const _colors = {
    'CASH': Color(0xFF16A34A),
    'PARTIAL': Color(0xFFD97706),
    'CREDIT': Color(0xFFDC2626),
  };

  @override
  Widget build(BuildContext context) {
    final totalsByType = {for (final d in data) d['payment_type'] as String: (d['total'] as num).toDouble()};
    if (totalsByType.values.every((v) => v == 0) || totalsByType.isEmpty) {
      return Center(child: Text(AppStrings.t('no_sales_in_period')));
    }
    final maxValue = totalsByType.values.fold<double>(0, (m, v) => v > m ? v : m);
    final bars = <BarChartGroupData>[];
    for (var i = 0; i < _order.length; i++) {
      final value = totalsByType[_order[i]] ?? 0;
      bars.add(BarChartGroupData(x: i, barRods: [
        BarChartRodData(
          toY: value,
          color: _colors[_order[i]],
          width: 32,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
        ),
      ]));
    }
    return Column(
      children: [
        Expanded(
          child: BarChart(
            BarChartData(
              maxY: maxValue == 0 ? 1 : maxValue * 1.25,
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
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(_labels[_order[i]] ?? '',
                            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 14,
          children: _order.map((key) {
            final value = totalsByType[key] ?? 0;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 9, height: 9, decoration: BoxDecoration(color: _colors[key], shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Text(formatCurrency(value), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }
}
