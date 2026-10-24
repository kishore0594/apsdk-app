import 'dart:io';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../db/db_helper.dart';
import '../services/finance_service.dart';
import '../services/pricing.dart';
import '../utils/app_theme.dart';
import '../utils/user_role.dart';
import 'expenses_screen.dart';
import 'finance_explain.dart';
import 'finance_settings_screen.dart';
import 'product_margins_screen.dart';
import 'reports_screen.dart';

/// Reports & Trends as company-style financial statements: KPI overview,
/// Profit & Loss, low-profit culprits, cash flow and balance sheet — for a
/// month, a quarter or a financial year. Every KPI opens its trend and
/// the items / categories / expenses / customers behind it, worst first.
class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key});

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

final _rs0 = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
String rs(double v) => _rs0.format(v.round());
String pct(double v) => '${v.toStringAsFixed(1)}%';
String daysTxt(double? v) => v == null ? '—' : '${v.round()} days';

Color lightColor(Light l) => switch (l) {
      Light.green => const Color(0xFF16A34A),
      Light.orange => const Color(0xFFD97706),
      Light.red => const Color(0xFFDC2626),
      Light.none => Colors.blueGrey,
    };

Color profitColor(double profitPct, double target) =>
    profitPct < 0 ? lightColor(Light.red) : (profitPct < target ? lightColor(Light.orange) : lightColor(Light.green));

/// "4.7%" / "₹1,59,270" / "38 days" for a KPI value.
String kpiText(FinanceService s, Kpi k, double? v) {
  if (v == null) return '—';
  if (s.kpiIsPercent(k)) return pct(v);
  if (s.kpiIsDays(k)) return daysTxt(v);
  return rs(v);
}

class _FinanceScreenState extends State<FinanceScreen> {
  FinanceService? _svc;
  String? _error;
  FinScale _scale = FinScale.month;
  late FinPeriod _period = FinPeriod.of(FinScale.month, DateTime.now());

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _svc = null;
        _error = null;
      });
    }
    try {
      final s = await FinanceService.load().timeout(const Duration(seconds: 40));
      if (mounted) setState(() => _svc = s);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load the accounts: $e');
    }
  }

  void _setScale(FinScale s) => setState(() {
        _scale = s;
        _period = FinPeriod.of(s, DateTime.now());
      });

  Future<void> _openSettings() async {
    final s = _svc;
    if (s == null) return;
    final changed = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => FinanceSettingsScreen(settings: s.settings)));
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = _svc;
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        backgroundColor: AppTheme.scaffold,
        appBar: AppBar(
          title: const Text('Reports & Trends'),
          actions: [
            IconButton(
              tooltip: 'Sales details',
              icon: const Icon(Icons.receipt_long_outlined),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsScreen())),
            ),
            IconButton(
              tooltip: 'Expenses',
              icon: const Icon(Icons.payments_outlined),
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const ExpensesScreen()));
                _load();
              },
            ),
            if (s != null)
              IconButton(
                tooltip: 'Share statement (for your CA)',
                icon: const Icon(Icons.ios_share),
                onPressed: () => shareStatement(context, s, _period),
              ),
            if (UserRole.instance.isAdmin)
              IconButton(tooltip: 'Targets & fixed costs', icon: const Icon(Icons.tune), onPressed: _openSettings),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Profit & Loss'),
              Tab(text: 'Low-profit culprits'),
              Tab(text: 'Cash flow'),
              Tab(text: 'Debts'),
              Tab(text: 'Balance sheet'),
            ],
          ),
        ),
        body: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _load, child: const Text('Try again')),
                  ]),
                ),
              )
            : s == null
                ? const Center(child: CircularProgressIndicator())
                : Column(children: [
                    PeriodBar(
                      scale: _scale,
                      period: _period,
                      onScale: _setScale,
                      onPeriod: (p) => setState(() => _period = p),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: () => _load(quiet: true),
                        child: TabBarView(children: [
                          _Overview(svc: s, period: _period),
                          _ProfitLoss(svc: s, period: _period),
                          ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 32), children: [
                            CulpritList(svc: s, kpi: Kpi.netProfit, period: _period, limit: 60),
                          ]),
                          _CashFlow(svc: s, period: _period, onSettings: _openSettings),
                          _Debts(svc: s, period: _period, onChanged: () => _load(quiet: true)),
                          _BalanceSheet(svc: s, period: _period),
                        ]),
                      ),
                    ),
                  ]),
      ),
    );
  }
}

/// Month / Quarter / Year and ◂ period ▸.
class PeriodBar extends StatelessWidget {
  final FinScale scale;
  final FinPeriod period;
  final ValueChanged<FinScale> onScale;
  final ValueChanged<FinPeriod> onPeriod;
  const PeriodBar({super.key, required this.scale, required this.period, required this.onScale, required this.onPeriod});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(children: [
        SegmentedButton<FinScale>(
          showSelectedIcon: false,
          segments: [
            for (final e in finScaleNames.entries) ButtonSegment(value: e.key, label: Text(e.value)),
          ],
          selected: {scale},
          onSelectionChanged: (x) => onScale(x.first),
        ),
        Row(children: [
          IconButton(onPressed: () => onPeriod(period.prev), icon: const Icon(Icons.chevron_left)),
          Expanded(
            child: Text(
              period.isCurrent ? '${period.label}  ·  so far (${period.elapsedDays} of ${period.totalDays} days)' : period.label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
            ),
          ),
          IconButton(
            onPressed: period.next.isFuture ? null : () => onPeriod(period.next),
            icon: const Icon(Icons.chevron_right),
          ),
        ]),
      ]),
    );
  }
}

// ---------------- Overview ----------------

class _Overview extends StatelessWidget {
  final FinanceService svc;
  final FinPeriod period;
  const _Overview({required this.svc, required this.period});

  @override
  Widget build(BuildContext context) {
    final f = svc.figures(period);
    final t = svc.settings.targetNet;
    final net = period.isCurrent ? f.projectedNetMargin : f.netMargin;
    final gapRs = (period.isCurrent ? f.projectedSales : f.netSales) * t / 100 -
        (period.isCurrent ? f.projectedNet : f.netProfit);
    final kpis = [
      Kpi.netProfit,
      Kpi.grossMargin,
      Kpi.netSales,
      Kpi.expenseRatio,
      Kpi.breakEven,
      Kpi.collection,
      Kpi.credit,
      Kpi.stock,
      Kpi.supplier,
      Kpi.avgBill,
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 32),
      children: [
        Card(
          color: profitColor(net, t).withOpacity(0.08),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(period.isCurrent ? 'Net profit (this ${finScaleNames[period.scale]!.toLowerCase()} so far)' : 'Net profit',
                  style: const TextStyle(fontSize: 13, color: Colors.black54)),
              const SizedBox(height: 2),
              Text('${rs(f.netProfit)}  ·  ${pct(f.netMargin)} of sales',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: profitColor(f.netMargin, t))),
              if (period.isCurrent && f.netSales > 0)
                Text(
                    'At this pace: sales ${rs(f.projectedSales)}, net profit ${rs(f.projectedNet)} (${pct(f.projectedNetMargin)})',
                    style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 6),
              Text(
                net >= t
                    ? 'On target (${pct(t)} after all expenses).'
                    : 'Target ${pct(t)} after all expenses — short by ${rs(gapRs)}${period.isCurrent ? ' at this pace' : ''}. '
                        'See "Low-profit culprits" for what pulls it down.',
                style: const TextStyle(fontSize: 13, height: 1.3),
              ),
            ]),
          ),
        ),
        ..._warnings(f),
        const SizedBox(height: 6),
        LayoutBuilder(builder: (context, c) {
          final w = (c.maxWidth - 8) / 2;
          return Wrap(spacing: 8, runSpacing: 8, children: [
            for (final k in kpis) SizedBox(width: w, child: KpiTile(svc: svc, kpi: k, period: period)),
          ]);
        }),
        const SizedBox(height: 16),
        Text('Sales and net profit — last ${_n(period.scale)} ${finScaleNames[period.scale]!.toLowerCase()}s',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 4),
        const Row(children: [
          _Dot(Color(0xFF2563EB)),
          Text(' Net sales   ', style: TextStyle(fontSize: 12)),
          _Dot(Color(0xFF16A34A)),
          Text(' Net profit (red = loss)', style: TextStyle(fontSize: 12)),
        ]),
        const SizedBox(height: 8),
        SizedBox(height: 210, child: _SalesProfitChart(svc: svc, periods: period.trail(_n(period.scale)))),
        const SizedBox(height: 8),
        const Text('Tap any box for its trend, the reason for its target, and what is behind it — worst first.',
            style: TextStyle(fontSize: 12, color: Colors.black54)),
      ],
    );
  }

  static int _n(FinScale s) => switch (s) { FinScale.month => 12, FinScale.quarter => 8, FinScale.year => 5 };

  List<Widget> _warnings(FinFigures f) => [
        if (period.isCurrent && svc.belowTargetCount() > 0)
          Builder(
            builder: (context) => InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductMarginsScreen())),
              child: _Warn('${svc.belowTargetCount()} products are priced below their margin target (shop or online). '
                  'Tap to open Pricing and apply the suggested prices.'),
            ),
          ),
        if (f.costMissingLines > 0)
          _Warn('${f.costMissingLines} sold item lines (${rs(f.costMissingSales)}) have no purchase cost, so profit '
              'looks higher than it is. Add the cost price in Inventory.'),
        if (f.expenseTotal == 0 && f.netSales > 0)
          const _Warn('No expenses entered for this period, so net profit is too high. Set fixed monthly costs '
              '(⚙ at the top) or add expenses.'),
      ];
}

class _Warn extends StatelessWidget {
  final String text;
  const _Warn(this.text);
  @override
  Widget build(BuildContext context) => Card(
        color: const Color(0xFFFFF4E5),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5, height: 1.3))),
          ]),
        ),
      );
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot(this.color);
  @override
  Widget build(BuildContext context) =>
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

class KpiTile extends StatelessWidget {
  final FinanceService svc;
  final Kpi kpi;
  final FinPeriod period;
  const KpiTile({super.key, required this.svc, required this.kpi, required this.period});

  @override
  Widget build(BuildContext context) {
    final f = svc.figures(period);
    final v = svc.kpiValue(kpi, f);
    final l = svc.light(kpi, f);
    final sub = kpiSubtitle(svc, kpi, f);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => KpiDetailScreen(svc: svc, kpi: kpi, period: period))),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: lightColor(l), width: 4)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text(kpiNames[kpi]!,
                      style: const TextStyle(fontSize: 12.5, color: Colors.black54, fontWeight: FontWeight.w600))),
              InkWell(
                onTap: () => showExplain(context, svc, kpi, f),
                child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.info_outline, size: 17)),
              ),
            ]),
            Text(kpiText(svc, kpi, v),
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: l == Light.none ? null : lightColor(l))),
            const SizedBox(height: 2),
            Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, height: 1.25)),
          ]),
        ),
      ),
    );
  }
}

/// Second line on a KPI tile: target and comparison.
String kpiSubtitle(FinanceService svc, Kpi k, FinFigures f) {
  final s = svc.settings;
  final prev = svc.figures(f.period.prev);
  String vs(double a, double b) {
    if (b.abs() < 0.01) return '';
    final ch = (a - b) / b.abs() * 100;
    return '${ch >= 0 ? '▲' : '▼'} ${ch.abs().toStringAsFixed(0)}% vs ${f.period.prevWord}';
  }

  switch (k) {
    case Kpi.netProfit:
      return 'Target ${pct(s.targetNet)} · ${rs(f.netProfit)}';
    case Kpi.grossMargin:
      return 'Target ${pct(s.targetGross)} · ${f.period.prevWord} ${pct(prev.grossMargin)}';
    case Kpi.netSales:
      return f.period.isCurrent
          ? 'Pace ${rs(f.projectedSales)} · ${vs(f.projectedSales, prev.netSales)}'
          : vs(f.netSales, prev.netSales);
    case Kpi.expenseRatio:
      return 'Max ${pct(s.maxExpense)} · ${rs(f.expectedExpenses)} expenses';
    case Kpi.breakEven:
      final ts = f.targetSales(s.targetNet);
      return 'For ${pct(s.targetNet)} profit: ${ts == null ? 'raise margin first' : rs(ts)}';
    case Kpi.collection:
      return 'Target ${pct(s.minCollection)} · collected ${rs(f.cashSales + f.creditCollected)}';
    case Kpi.credit:
      return 'Max ${s.maxCreditDays.round()} days · owed ${rs(f.receivables)}';
    case Kpi.stock:
      return 'Max ${s.maxStockDays.round()} days · stock ${rs(f.stockValue)}';
    case Kpi.supplier:
      return 'To pay suppliers · paid ${rs(f.supplierPaid)} this period';
    case Kpi.avgBill:
      return '${f.bills} bills · ${vs(f.avgBill, prev.avgBill)}';
  }
  // ignore: dead_code
  return '';
}

class _SalesProfitChart extends StatelessWidget {
  final FinanceService svc;
  final List<FinPeriod> periods;
  const _SalesProfitChart({required this.svc, required this.periods});

  @override
  Widget build(BuildContext context) {
    final figs = [for (final p in periods) svc.figures(p)];
    return BarChart(BarChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey.shade200, strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          getTooltipColor: (_) => const Color(0xFF263238),
          fitInsideHorizontally: true,
          fitInsideVertically: true,
          getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
            '${ri == 0 ? 'Sales' : 'Net profit'} ${rs(rod.toY)}\n${periods[group.x].short}',
            const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 44,
            getTitlesWidget: (v, meta) => Text(_short(v), style: const TextStyle(fontSize: 10, color: Colors.black54)),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (v, meta) {
              final i = v.toInt();
              if (i < 0 || i >= periods.length) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(periods[i].short, style: const TextStyle(fontSize: 10, color: Colors.black54)),
              );
            },
          ),
        ),
      ),
      barGroups: [
        for (var i = 0; i < figs.length; i++)
          BarChartGroupData(x: i, barsSpace: 2, barRods: [
            BarChartRodData(toY: figs[i].netSales, color: const Color(0xFF2563EB), width: 7),
            BarChartRodData(
                toY: figs[i].netProfit,
                color: figs[i].netProfit >= 0 ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                width: 7),
          ]),
      ],
    ));
  }

  static String _short(double v) {
    final a = v.abs();
    if (a >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (a >= 1000) return '${(v / 1000).toStringAsFixed(0)}k';
    return v.toStringAsFixed(0);
  }
}

// ---------------- KPI detail ----------------

class KpiDetailScreen extends StatefulWidget {
  final FinanceService svc;
  final Kpi kpi;
  final FinPeriod period;
  const KpiDetailScreen({super.key, required this.svc, required this.kpi, required this.period});

  @override
  State<KpiDetailScreen> createState() => _KpiDetailScreenState();
}

class _KpiDetailScreenState extends State<KpiDetailScreen> {
  late FinPeriod _period = widget.period;

  @override
  Widget build(BuildContext context) {
    final svc = widget.svc;
    final k = widget.kpi;
    final f = svc.figures(_period);
    final l = svc.light(k, f);
    final ex = explainKpi(svc, k, f);
    final n = switch (_period.scale) { FinScale.month => 12, FinScale.quarter => 8, FinScale.year => 5 };
    final trail = _period.trail(n);
    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      appBar: AppBar(title: Text(kpiNames[k]!)),
      body: Column(children: [
        PeriodBar(
          scale: _period.scale,
          period: _period,
          onScale: (s) => setState(() => _period = FinPeriod.of(s, DateTime.now())),
          onPeriod: (p) => setState(() => _period = p),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(12, 10, 12, 32), children: [
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(kpiText(svc, k, svc.kpiValue(k, f)),
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: l == Light.none ? null : lightColor(l))),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(kpiSubtitle(svc, k, f), style: const TextStyle(fontSize: 12.5)),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            ExplainCard(ex: ex),
            const SizedBox(height: 14),
            Text('Trend — last $n ${finScaleNames[_period.scale]!.toLowerCase()}s',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              child: TrendLine(
                labels: [for (final p in trail) p.short],
                values: [for (final p in trail) svc.kpiValue(k, svc.figures(p))],
                target: svc.kpiTarget(k),
                format: (v) => kpiText(svc, k, v),
                lowerBetter: k == Kpi.expenseRatio || k == Kpi.credit || k == Kpi.stock,
              ),
            ),
            const SizedBox(height: 16),
            CulpritList(svc: svc, kpi: k, period: _period),
          ]),
        ),
      ]),
    );
  }
}

class TrendLine extends StatelessWidget {
  final List<String> labels;
  final List<double?> values;
  final double? target;
  final String Function(double) format;
  final bool lowerBetter; // expense ratio, credit days, stock days
  const TrendLine(
      {super.key,
      required this.labels,
      required this.values,
      required this.target,
      required this.format,
      this.lowerBetter = false});

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[
      for (var i = 0; i < values.length; i++) values[i] == null ? FlSpot.nullSpot : FlSpot(i.toDouble(), values[i]!),
    ];
    if (spots.every((s) => s.isNull())) {
      return const Center(child: Text('No data yet for this period range.'));
    }
    const line = Color(0xFF1E6F5C);
    return LineChart(LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey.shade200, strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      extraLinesData: ExtraLinesData(horizontalLines: [
        if (target != null)
          HorizontalLine(
            y: target!,
            color: const Color(0xFFD97706),
            strokeWidth: 1.5,
            dashArray: [6, 4],
            label: HorizontalLineLabel(
              show: true,
              alignment: Alignment.topRight,
              style: const TextStyle(fontSize: 10.5, color: Color(0xFFD97706), fontWeight: FontWeight.w700),
              labelResolver: (_) => 'Target ${format(target!)}',
            ),
          ),
      ]),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => const Color(0xFF263238),
          fitInsideHorizontally: true,
          fitInsideVertically: true,
          getTooltipItems: (ts) => [
            for (final s in ts)
              LineTooltipItem('${format(s.y)}\n${labels[s.x.toInt()]}',
                  const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 1,
            getTitlesWidget: (v, meta) {
              final i = v.toInt();
              if (i < 0 || i >= labels.length || v != i.toDouble()) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(labels[i], style: const TextStyle(fontSize: 9.5, color: Colors.black54)),
              );
            },
          ),
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          color: line,
          barWidth: 3,
          isCurved: false,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
              radius: 3.5,
              color: target == null
                  ? line
                  : ((spot.y <= target!) == lowerBetter ? lightColor(Light.green) : lightColor(Light.red)),
              strokeWidth: 1.5,
              strokeColor: Colors.white,
            ),
          ),
        ),
      ],
    ));
  }
}

// ---------------- Culprits ----------------

/// The items / categories / expenses / customers behind a KPI, worst first.
class CulpritList extends StatefulWidget {
  final FinanceService svc;
  final Kpi kpi;
  final FinPeriod period;
  final int limit;
  const CulpritList({super.key, required this.svc, required this.kpi, required this.period, this.limit = 25});

  @override
  State<CulpritList> createState() => _CulpritListState();
}

class _CulpritListState extends State<CulpritList> {
  bool _byCategory = false;
  String? _group; // a category opened from the category list
  bool _all = false;

  bool get _salesKind =>
      const [Kpi.netProfit, Kpi.grossMargin, Kpi.breakEven, Kpi.netSales, Kpi.avgBill].contains(widget.kpi);

  @override
  Widget build(BuildContext context) {
    final svc = widget.svc;
    final p = widget.period;
    final f = svc.figures(p);
    final k = widget.kpi;
    String title = '';
    String hint = '';
    List<FinRow> rows = const [];
    switch (k) {
      case Kpi.netProfit:
      case Kpi.breakEven:
        title = 'Low-profit culprits — worst first';
        hint = 'Sorted by how many rupees each is short of ${pct(svc.settings.targetNet)} real profit after its share of '
            'expenses and credit delay (${pct(f.itemExpenseRatio)} of sales). Fix the top ones first.';
        rows = svc.profitCulprits(p, byCategory: _byCategory);
      case Kpi.grossMargin:
        title = 'Low-margin culprits — worst first';
        hint = 'Sorted by rupees short of a ${pct(svc.settings.targetGross)} margin.';
        rows = svc.marginCulprits(p, byCategory: _byCategory);
      case Kpi.netSales:
      case Kpi.avgBill:
        title = 'Biggest sales falls — worst first';
        hint = 'Change against ${p.prevWord}${p.isCurrent ? ' (this period at its current pace)' : ''}.';
        rows = svc.salesDropCulprits(p, byCategory: _byCategory);
      case Kpi.expenseRatio:
        title = 'Expenses — largest first';
        hint = 'Fixed costs stay the same; more sales makes their share smaller.';
        rows = svc.expenseRows(p);
      case Kpi.collection:
      case Kpi.credit:
        title = 'Customers who owe — oldest dues first';
        hint = 'Dues older than ${svc.settings.maxCreditDays.round()} days come first.';
        rows = svc.creditRows(p);
      case Kpi.stock:
        title = 'Money stuck in stock — worst first';
        hint = 'Stock beyond ${svc.settings.maxStockDays.round()} days of sales. Unsold items come first — '
            'clear them with an offer or a status video.';
        rows = svc.stockRows(p);
      case Kpi.supplier:
        title = 'Suppliers to pay — largest first';
        hint = 'Pay on time to keep credit and good rates.';
        rows = svc.supplierRows(p);
    }
    if (_salesKind && !_byCategory && _group != null) {
      rows = rows.where((r) => r.group == _group).toList();
    }
    final shown = _all ? rows : rows.take(widget.limit).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      const SizedBox(height: 4),
      Text(hint, style: const TextStyle(fontSize: 12, color: Colors.black54, height: 1.3)),
      if (_salesKind) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          ChoiceChip(
              label: const Text('Items'),
              selected: !_byCategory,
              onSelected: (_) => setState(() {
                    _byCategory = false;
                    _group = null;
                  })),
          ChoiceChip(
              label: const Text('Categories'),
              selected: _byCategory,
              onSelected: (_) => setState(() {
                    _byCategory = true;
                    _group = null;
                  })),
          if (_group != null && !_byCategory)
            InputChip(label: Text(_group!), onDeleted: () => setState(() => _group = null)),
        ]),
      ],
      const SizedBox(height: 6),
      if (rows.isEmpty)
        const Padding(padding: EdgeInsets.all(16), child: Text('Nothing to show for this period.')),
      for (var i = 0; i < shown.length; i++) _row(i, shown[i], f),
      if (!_all && rows.length > shown.length)
        TextButton(onPressed: () => setState(() => _all = true), child: Text('Show all ${rows.length}')),
    ]);
  }

  Widget _row(int i, FinRow r, FinFigures f) {
    final svc = widget.svc;
    final k = widget.kpi;
    final er = f.itemExpenseRatio;
    final target = svc.settings.targetNet;
    Color c = Colors.blueGrey;
    String right = '';
    String line2 = '';
    switch (k) {
      case Kpi.netProfit:
      case Kpi.breakEven:
      case Kpi.grossMargin:
        if (r.costMissing) {
          c = Colors.blueGrey;
          line2 = 'No purchase cost entered — add it in Inventory to judge this item';
        } else {
          final after = r.profitAfterPct(er);
          c = profitColor(after, target);
          final gap = k == Kpi.grossMargin ? r.sales * svc.settings.targetGross / 100 - r.gp : r.gap(er, target);
          line2 = 'Margin ${pct(r.margin)} · after expenses ${pct(after)}'
              '${gap > 0 ? ' · short ${rs(gap)}' : ' · on target'}'
              '${r.prevSales > 0 ? ' · ${f.period.prevWord} ${pct(r.prevMargin)}' : ''}';
        }
        right = rs(r.sales);
      case Kpi.netSales:
      case Kpi.avgBill:
        c = r.amount < 0 ? lightColor(Light.red) : lightColor(Light.green);
        right = '${r.amount >= 0 ? '+' : '−'}${rs(r.amount.abs())}';
        line2 = 'Now ${rs(r.sales)} · ${f.period.prevWord} ${rs(r.prevSales)}';
      case Kpi.expenseRatio:
        right = rs(r.amount);
        final share = f.netSales > 0 ? r.amount / f.netSales * 100 : 0.0;
        line2 = '${pct(share)} of sales · ${f.period.prevWord} ${rs(r.prevAmount)}';
        c = r.amount > r.prevAmount + 1 ? lightColor(Light.orange) : Colors.blueGrey;
      case Kpi.collection:
      case Kpi.credit:
        right = rs(r.amount);
        final age = r.ageDays;
        line2 = age == null ? 'Owes' : 'Oldest unpaid: $age days';
        c = (age ?? 0) > svc.settings.maxCreditDays * 2
            ? lightColor(Light.red)
            : ((age ?? 0) > svc.settings.maxCreditDays ? lightColor(Light.orange) : lightColor(Light.green));
      case Kpi.stock:
        right = rs(r.stockValue);
        final cover = r.daysCover;
        line2 = '${_qty(r.stockQty)} in stock · ${cover == null ? 'not sold this period' : '${cover.round()} days of sales'}'
            '${r.excessStock > 1 ? ' · stuck ${rs(r.excessStock)}' : ''}';
        c = cover == null
            ? lightColor(Light.red)
            : (cover > svc.settings.maxStockDays * 2
                ? lightColor(Light.red)
                : (cover > svc.settings.maxStockDays ? lightColor(Light.orange) : lightColor(Light.green)));
      case Kpi.supplier:
        right = rs(r.amount);
        line2 = 'To pay';
    }
    final canOpenGroup = _salesKind && _byCategory;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: canOpenGroup
            ? () => setState(() {
                  _group = r.name;
                  _byCategory = false;
                })
            : null,
        child: Container(
          decoration: BoxDecoration(border: Border(left: BorderSide(color: c, width: 4))),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Row(children: [
            SizedBox(
              width: 24,
              child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black45)),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(line2, style: TextStyle(fontSize: 12, color: c == Colors.blueGrey ? Colors.black54 : c, height: 1.3)),
                if (canOpenGroup) const Text('Tap to see its items', style: TextStyle(fontSize: 11, color: Colors.black45)),
              ]),
            ),
            const SizedBox(width: 8),
            Text(right, style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }

  static String _qty(double q) => q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toStringAsFixed(1);
}

// ---------------- Profit & Loss ----------------

class _ProfitLoss extends StatelessWidget {
  final FinanceService svc;
  final FinPeriod period;
  const _ProfitLoss({required this.svc, required this.period});

  @override
  Widget build(BuildContext context) {
    final f = svc.figures(period);
    final p = svc.figures(period.prev);
    final heads = {...f.expenses.keys, ...p.expenses.keys}.toList()
      ..sort((a, b) => (f.expenses[b] ?? 0).compareTo(f.expenses[a] ?? 0));
    final t = svc.settings.targetNet;
    return ListView(padding: const EdgeInsets.fromLTRB(12, 10, 12, 32), children: [
      Text('Profit & Loss statement — ${period.label}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
      const SizedBox(height: 4),
      const Text('Tap any line to see what it means.', style: TextStyle(fontSize: 12, color: Colors.black54)),
      const SizedBox(height: 8),
      Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: Column(children: [
            _PlRow.header(period.prevWord),
            _PlRow('Gross sales', f.grossSales, p.grossSales, f, explain: 'gross_sales'),
            _PlRow('Less: bill discounts', -f.discounts, -p.discounts, f, explain: 'discounts', indent: true),
            _PlRow('NET SALES', f.netSales, p.netSales, f, bold: true, explain: 'net_sales'),
            _PlRow('Less: cost of goods sold', -f.cogs, -p.cogs, f, explain: 'cogs', indent: true),
            _PlRow('GROSS PROFIT', f.grossProfit, p.grossProfit, f,
                bold: true, explain: 'gross_profit', note: 'margin ${pct(f.grossMargin)}'),
            const Divider(),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Operating expenses', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ),
            for (final h in heads)
              _PlRow(h == 'Wages' ? 'Wages / owner\'s salary' : h, -(f.expenses[h] ?? 0), -(p.expenses[h] ?? 0), f,
                  indent: true, explain: 'expense'),
            if (heads.isEmpty) const _PlNote('No expenses entered — set fixed monthly costs (⚙).'),
            _PlRow('TOTAL EXPENSES', -f.expenseTotal, -p.expenseTotal, f,
                bold: true, explain: 'expenses', note: '${pct(f.expenseRatio)} of sales'),
            _PlRow('Add: delivery charges received', f.delivery, p.delivery, f, indent: true, explain: 'delivery'),
            _PlRow('OPERATING PROFIT', f.operatingProfit, p.operatingProfit, f, bold: true, explain: 'operating'),
            _PlRow('Less: stock loss / correction', -f.stockAdjust, -p.stockAdjust, f, indent: true, explain: 'stock_loss'),
            _PlRow('Less: bad debts written off', -f.badDebts, -p.badDebts, f, indent: true, explain: 'bad_debts'),
            _PlRow('NET PROFIT (books)', f.bookProfit, p.bookProfit, f, bold: true, explain: 'book_profit'),
            _PlRow('Less: credit delay cost', -f.creditDelay, -p.creditDelay, f,
                indent: true,
                explain: 'credit_delay',
                note: '${rs(f.creditGiven)} on credit × ${pct(f.delayRate)} a year × ${f.delayDays.round()} days'),
            const Divider(thickness: 1.5),
            _PlRow('REAL NET PROFIT', f.netProfit, p.netProfit, f,
                bold: true,
                explain: 'net_profit',
                color: profitColor(f.netMargin, t),
                note: '${pct(f.netMargin)} of sales · target ${pct(t)}'),
          ]),
        ),
      ),
      if (f.netSales > 0 && f.netMargin < t)
        _Warn('To reach ${pct(t)} you need ${rs(f.netSales * t / 100 - f.netProfit)} more net profit on these sales. '
            'Open "Low-profit culprits" to see which items and categories cause the gap.'),
      if (f.costMissingLines > 0)
        _Warn('${f.costMissingLines} sold lines have no purchase cost (${rs(f.costMissingSales)} of sales) — '
            'cost of goods sold is understated.'),
    ]);
  }
}

class _PlNote extends StatelessWidget {
  final String text;
  const _PlNote(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 0, 4),
        child: Align(alignment: Alignment.centerLeft, child: Text(text, style: const TextStyle(fontSize: 12, color: Colors.black54))),
      );
}

class _PlRow extends StatelessWidget {
  final String label;
  final double now;
  final double before;
  final FinFigures? f;
  final bool bold;
  final bool indent;
  final bool header;
  final String explain;
  final String? note;
  final Color? color;
  final String prevWord;
  const _PlRow(this.label, this.now, this.before, this.f,
      {this.bold = false, this.indent = false, this.explain = '', this.note, this.color})
      : header = false,
        prevWord = '';
  const _PlRow.header(this.prevWord)
      : label = '',
        now = 0,
        before = 0,
        f = null,
        bold = true,
        indent = false,
        header = true,
        explain = '',
        note = null,
        color = null;

  @override
  Widget build(BuildContext context) {
    const small = TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w700);
    if (header) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          const Expanded(child: Text('', style: small)),
          const SizedBox(width: 84, child: Text('This', textAlign: TextAlign.right, style: small)),
          SizedBox(width: 78, child: Text(_cap(prevWord), textAlign: TextAlign.right, style: small)),
          const SizedBox(width: 50, child: Text('% sales', textAlign: TextAlign.right, style: small)),
        ]),
      );
    }
    final share = (f?.netSales ?? 0) > 0 ? now / f!.netSales * 100 : null;
    final st = TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w800 : FontWeight.w400, color: color);
    return InkWell(
      onTap: explain.isEmpty ? null : () => showLineExplain(context, label, explain),
      child: Padding(
        padding: EdgeInsets.fromLTRB(indent ? 12.0 : 0.0, 5, 0, 5),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(label, style: st)),
            SizedBox(width: 84, child: Text(rs(now), textAlign: TextAlign.right, style: st)),
            SizedBox(
                width: 78,
                child: Text(rs(before), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: Colors.black54))),
            SizedBox(
                width: 50,
                child: Text(share == null ? '' : share.toStringAsFixed(1),
                    textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: Colors.black54))),
          ]),
          if (note != null) Text(note!, style: TextStyle(fontSize: 11.5, color: color ?? Colors.black54)),
        ]),
      ),
    );
  }

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ---------------- Cash flow ----------------

class _CashFlow extends StatelessWidget {
  final FinanceService svc;
  final FinPeriod period;
  final VoidCallback onSettings;
  const _CashFlow({required this.svc, required this.period, required this.onSettings});

  @override
  Widget build(BuildContext context) {
    final f = svc.figures(period);
    final day = DateFormat('d MMM yyyy');
    return ListView(padding: const EdgeInsets.fromLTRB(12, 10, 12, 32), children: [
      Text('Cash flow — ${period.label}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
      const SizedBox(height: 8),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            _Line('Cash & bank at start', f.cashStart, bold: true, explain: 'cash_start'),
            _Line('+ Cash sales (paid at the counter)', f.cashSales, explain: 'cash_sales'),
            _Line('+ Credit collected from customers', f.creditCollected, explain: 'credit_collected'),
            _Line('− Paid to suppliers', -f.supplierPaid, explain: 'supplier_paid'),
            _Line('− Expenses paid', -f.expenseTotal, explain: 'expenses'),
            const Divider(),
            _Line(period.isCurrent ? 'Cash & bank now' : 'Cash & bank at end', f.cashEnd, bold: true, explain: 'cash_end'),
          ]),
        ),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Not cash yet', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            _Line('Sold on credit this period', f.creditGiven, explain: 'credit_given'),
            _Line('Bought from suppliers this period', f.purchases, explain: 'purchases'),
          ]),
        ),
      ),
      Card(
        color: const Color(0xFFF1F5F9),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              'Starting point: ${rs(svc.startCash)} on ${day.format(svc.startCashDate)}'
              '${svc.startCashIsEstimate ? ' — an estimate (that month\'s sales). Correct it when you know the real cash + bank balance.' : '.'}',
              style: const TextStyle(fontSize: 12.5, height: 1.3),
            ),
            if (UserRole.instance.isAdmin)
              TextButton.icon(onPressed: onSettings, icon: const Icon(Icons.edit, size: 16), label: const Text('Change starting cash')),
          ]),
        ),
      ),
    ]);
  }
}

class _Line extends StatelessWidget {
  final String label;
  final double value;
  final bool bold;
  final String explain;
  const _Line(this.label, this.value, {this.bold = false, this.explain = ''});

  @override
  Widget build(BuildContext context) {
    final st = TextStyle(fontSize: 13.5, fontWeight: bold ? FontWeight.w800 : FontWeight.w400);
    return InkWell(
      onTap: explain.isEmpty ? null : () => showLineExplain(context, label, explain),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Text(label, style: st)),
          Text(rs(value), style: st.copyWith(color: value < 0 ? const Color(0xFFDC2626) : null)),
        ]),
      ),
    );
  }
}

// ---------------- Balance sheet ----------------

class _BalanceSheet extends StatelessWidget {
  final FinanceService svc;
  final FinPeriod period;
  const _BalanceSheet({required this.svc, required this.period});

  @override
  Widget build(BuildContext context) {
    final f = svc.figures(period);
    final provision = svc.debts(period).provision;
    final assets = f.stockValue + f.receivables - provision + f.cashEnd;
    final liabilities = f.payables;
    final capital = assets - liabilities;
    final current = liabilities > 0 ? assets / liabilities : null;
    final asOf = period.isCurrent ? 'today' : DateFormat('d MMM yyyy').format(period.lastDay);
    return ListView(padding: const EdgeInsets.fromLTRB(12, 10, 12, 32), children: [
      Text('Balance sheet — as of $asOf', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
      const SizedBox(height: 8),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            const Align(
                alignment: Alignment.centerLeft,
                child: Text('WHAT THE SHOP OWNS', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5))),
            _Line('Stock (at purchase cost)', f.stockValue, explain: 'stock_value'),
            _Line('Customers owe you', f.receivables, explain: 'receivables'),
            if (provision > 0) _Line('Less: doubtful dues (90+ days)', -provision, explain: 'provision'),
            _Line('Cash & bank${svc.startCashIsEstimate ? ' (estimate)' : ''}', f.cashEnd, explain: 'cash_end'),
            _Line('TOTAL ASSETS', assets, bold: true),
            const Divider(),
            const Align(
                alignment: Alignment.centerLeft,
                child: Text('WHAT THE SHOP OWES', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5))),
            _Line('Suppliers to pay', f.payables, explain: 'payables'),
            const _Line('Loans', 0, explain: 'loans'),
            _Line('TOTAL LIABILITIES', liabilities, bold: true),
            const Divider(thickness: 1.5),
            _Line("OWNER'S CAPITAL (owns − owes)", capital, bold: true, explain: 'capital'),
          ]),
        ),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            _Line('Working capital', assets - liabilities, explain: 'working_capital'),
            InkWell(
              onTap: () => showLineExplain(context, 'Current ratio', 'current_ratio'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  const Expanded(child: Text('Current ratio (owns ÷ owes)', style: TextStyle(fontSize: 13.5))),
                  Text(current == null ? 'No dues' : '${current.toStringAsFixed(1)} : 1',
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: current == null || current >= 1.5 ? lightColor(Light.green) : lightColor(Light.orange))),
                ]),
              ),
            ),
          ]),
        ),
      ),
      const Text('Shop assets only (no land, building or vehicles). Tap a line to see what it means.',
          style: TextStyle(fontSize: 12, color: Colors.black54)),
    ]);
  }
}

// ---------------- Debts ----------------

class _Debts extends StatelessWidget {
  final FinanceService svc;
  final FinPeriod period;
  final VoidCallback onChanged;
  const _Debts({required this.svc, required this.period, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final d = svc.debts(period);
    final s = svc.settings;
    final asOf = period.isCurrent ? 'today' : DateFormat('d MMM yyyy').format(period.lastDay);
    final colors = [
      lightColor(Light.green),
      const Color(0xFF65A30D),
      lightColor(Light.orange),
      const Color(0xFFEA580C),
      lightColor(Light.red),
    ];
    return ListView(padding: const EdgeInsets.fromLTRB(12, 10, 12, 32), children: [
      Text('Customer debts — as of $asOf', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
      const SizedBox(height: 8),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            _Line('Customers owe you', d.total, bold: true, explain: 'receivables'),
            _Line('Doubtful (half of 91–180 days, all over 180)', -d.provision, explain: 'provision'),
            _Line('Likely to come in', d.total - d.provision, bold: true),
            const Divider(),
            _Line('Value lost per year while waiting (${pct(s.realInflation)} a year)', -d.delayCostPerYear,
                explain: 'credit_delay'),
            InkWell(
              onTap: () => showLineExplain(context, 'Days to pay', 'delay_days'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  const Expanded(child: Text('Average days customers take to pay', style: TextStyle(fontSize: 13.5))),
                  Text(
                    d.measuredDays == null
                        ? 'your figure ${s.creditDelayDays.round()} days'
                        : '${d.measuredDays!.round()} days (your figure ${s.creditDelayDays.round()})',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: (d.measuredDays ?? s.creditDelayDays) > s.maxCreditDays
                            ? lightColor(Light.red)
                            : lightColor(Light.green)),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('How old the dues are', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (var i = 0; i < 5; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  SizedBox(width: 104, child: Text(debtBucketNames[i], style: const TextStyle(fontSize: 12.5))),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: d.total <= 0 ? 0.0 : d.buckets[i] / d.total,
                        minHeight: 10,
                        backgroundColor: Colors.grey.shade200,
                        color: colors[i],
                      ),
                    ),
                  ),
                  SizedBox(
                      width: 84,
                      child: Text(rs(d.buckets[i]),
                          textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
                ]),
              ),
          ]),
        ),
      ),
      const SizedBox(height: 6),
      const Text('Customers — oldest money first', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      Text('Collect from the top first. Target: paid within ${s.maxCreditDays.round()} days.',
          style: const TextStyle(fontSize: 12, color: Colors.black54)),
      const SizedBox(height: 6),
      if (d.rows.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No customer owes anything. 👍')),
      for (final r in d.rows)
        Card(
          margin: const EdgeInsets.only(bottom: 6),
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: (r.oldestDays ?? 0) > 90
                      ? lightColor(Light.red)
                      : ((r.oldestDays ?? 0) > s.maxCreditDays ? lightColor(Light.orange) : lightColor(Light.green)),
                  width: 4,
                ),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                    'Oldest unpaid ${r.oldestDays ?? 0} days'
                    '${r.buckets[4] > 0 ? ' · over 180 days ${rs(r.buckets[4])}' : (r.buckets[3] > 0 ? ' · 91–180 days ${rs(r.buckets[3])}' : '')}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ]),
              ),
              Text(rs(r.total), style: const TextStyle(fontWeight: FontWeight.w800)),
              if (UserRole.instance.isAdmin)
                PopupMenuButton<String>(
                  onSelected: (_) => _writeOff(context, r),
                  itemBuilder: (_) => const [PopupMenuItem(value: 'w', child: Text('Write off as bad debt'))],
                ),
            ]),
          ),
        ),
    ]);
  }

  Future<void> _writeOff(BuildContext context, DebtRow r) async {
    final ctrl = TextEditingController(text: (r.buckets[4] > 0 ? r.buckets[4] : r.total).round().toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Write off — ${r.name}'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Only for money you are sure will never come. It lowers what this customer owes and shows as a '
              'bad debt (a loss) in the Profit & Loss. If they pay later, record it as a normal payment.'),
          const SizedBox(height: 10),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ ', border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Write off')),
        ],
      ),
    );
    final amount = double.tryParse(ctrl.text.trim()) ?? 0;
    ctrl.dispose();
    if (ok != true || amount <= 0) return;
    await DBHelper.instance.writeOffBadDebt(vendorId: r.id, amount: amount > r.total ? r.total : amount);
    onChanged();
  }
}

// ---------------- Share for the CA ----------------

/// Profit & Loss, KPIs and debts as a CSV file (opens in Excel / Sheets).
Future<void> shareStatement(BuildContext context, FinanceService svc, FinPeriod period) async {
  final f = svc.figures(period);
  final p = svc.figures(period.prev);
  final d = svc.debts(period);
  String q(String s) => '"${s.replaceAll('"', '""')}"';
  String n(double v) => v.toStringAsFixed(2);
  final rows = <List<String>>[
    ['Sri Madhura Agro Traders — Financial statement', period.label],
    [],
    ['PROFIT & LOSS', 'This period', 'Previous period', '% of sales'],
    ['Gross sales', n(f.grossSales), n(p.grossSales), ''],
    ['Less: bill discounts', n(-f.discounts), n(-p.discounts), ''],
    ['Net sales', n(f.netSales), n(p.netSales), '100'],
    ['Less: cost of goods sold', n(-f.cogs), n(-p.cogs), f.netSales > 0 ? n(f.cogs / f.netSales * 100) : ''],
    ['Gross profit', n(f.grossProfit), n(p.grossProfit), n(f.grossMargin)],
    for (final e in f.expenses.entries) ['Expense: ${e.key}', n(-e.value), n(-(p.expenses[e.key] ?? 0)), ''],
    ['Total expenses', n(-f.expenseTotal), n(-p.expenseTotal), n(f.expenseRatio)],
    ['Add: delivery charges received', n(f.delivery), n(p.delivery), ''],
    ['Operating profit', n(f.operatingProfit), n(p.operatingProfit), ''],
    ['Less: stock loss / correction', n(-f.stockAdjust), n(-p.stockAdjust), ''],
    ['Less: bad debts written off', n(-f.badDebts), n(-p.badDebts), ''],
    ['Net profit (books)', n(f.bookProfit), n(p.bookProfit), ''],
    ['Less: credit delay cost', n(-f.creditDelay), n(-p.creditDelay), ''],
    ['Real net profit', n(f.netProfit), n(p.netProfit), n(f.netMargin)],
    [],
    ['CASH FLOW'],
    ['Cash & bank at start', n(f.cashStart)],
    ['Cash sales', n(f.cashSales)],
    ['Credit collected', n(f.creditCollected)],
    ['Paid to suppliers', n(-f.supplierPaid)],
    ['Expenses paid', n(-f.expenseTotal)],
    ['Cash & bank at end', n(f.cashEnd)],
    [],
    ['BALANCE SHEET (period end)'],
    ['Stock at cost', n(f.stockValue)],
    ['Customers owe', n(f.receivables)],
    ['Less: doubtful dues', n(-d.provision)],
    ['Cash & bank', n(f.cashEnd)],
    ['Suppliers to pay', n(f.payables)],
    ['Owner\'s capital', n(f.stockValue + f.receivables - d.provision + f.cashEnd - f.payables)],
    [],
    ['DEBTS BY AGE'],
    for (var i = 0; i < 5; i++) [debtBucketNames[i], n(d.buckets[i])],
    [],
    ['KPI', 'Value', 'Target'],
    for (final k in Kpi.values)
      [kpiNames[k]!, kpiText(svc, k, svc.kpiValue(k, f)), svc.kpiTarget(k) == null ? '' : n(svc.kpiTarget(k)!)],
  ];
  final csv = rows.map((r) => r.map(q).join(',')).join('\n');
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/madhura_statement_${DateFormat('yyyy_MM').format(period.start)}_${period.scale.name}.csv');
  await file.writeAsString('\uFEFF$csv');
  await Share.shareXFiles([XFile(file.path, mimeType: 'text/csv')], text: 'Financial statement — ${period.label}');
}
