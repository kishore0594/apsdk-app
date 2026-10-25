import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import '../services/finance_service.dart';
import '../utils/app_theme.dart';
import 'finance_screen.dart' show rs, pct, lightColor;

/// Category-wise target vs achieved margin as a table. Tap a category to
/// open its items inside the same table. Worst first (₹ short of the 12%
/// real-profit goal), with a sales-weighted average row and a short
/// profit summary below.
class MarginTable extends StatefulWidget {
  final FinanceService svc;
  final FinPeriod period;
  const MarginTable({super.key, required this.svc, required this.period});

  @override
  State<MarginTable> createState() => _MarginTableState();
}

class _Col {
  final String head;
  final double width;
  const _Col(this.head, this.width);
}

class _MarginTableState extends State<MarginTable> {
  final Set<String> _open = {};

  static const double _nameW = 132;
  static const double _rowH = 46;
  static const double _headH = 52;

  double _target(FinRow r) => widget.svc.settings.targetFor(r.group.isNotEmpty ? r.group : r.name);
  double _shortTarget(FinRow r) => r.costMissing ? 0.0 : r.sales * _target(r) / 100 - r.gp;
  double _shortGoal(FinRow r, double er) => r.costMissing ? 0.0 : r.gap(er, widget.svc.settings.targetNet);

  int _worstFirst(FinRow a, FinRow b, double er) {
    if (a.costMissing != b.costMissing) return a.costMissing ? 1 : -1;
    return _shortGoal(b, er).compareTo(_shortGoal(a, er));
  }

  @override
  Widget build(BuildContext context) {
    final svc = widget.svc;
    final p = widget.period;
    final f = svc.figures(p);
    final er = f.itemExpenseRatio;
    final goal = svc.settings.targetNet;

    final cats = svc.salesRows(p, byCategory: true).where((x) => x.sales > 0).toList()
      ..sort((a, b) => _worstFirst(a, b, er));
    for (final c in cats) {
      c.group = c.name;
    }
    final items = svc.salesRows(p).where((x) => x.sales > 0).toList()..sort((a, b) => _worstFirst(a, b, er));
    final byCat = <String, List<FinRow>>{};
    for (final i in items) {
      byCat.putIfAbsent(i.group.toLowerCase(), () => []).add(i);
    }

    // totals (sales-weighted averages)
    double sales = 0, gp = 0, prevSales = 0, prevGp = 0, disc = 0, tgtW = 0;
    for (final c in cats) {
      sales += c.sales;
      gp += c.gp;
      prevSales += c.prevSales;
      prevGp += c.prevSales - c.prevCost;
      disc += c.discount;
      tgtW += c.sales * _target(c);
    }
    // category-level totals (what the owner reads) — sum of category shortfalls
    double catShortT = 0, catShortG = 0;
    for (final c in cats) {
      final a1 = _shortTarget(c);
      final a2 = _shortGoal(c, er);
      catShortT += a1 > 0 ? a1 : 0.0;
      catShortG += a2 > 0 ? a2 : 0.0;
    }
    final avgTarget = sales > 0 ? tgtW / sales : 0.0;
    final avgMargin = sales > 0 ? gp / sales * 100 : 0.0;
    final prevMargin = prevSales > 0 ? prevGp / prevSales * 100 : null;
    final needed = goal + er;

    final cols = <_Col>[
      const _Col('Sales\n₹', 84),
      const _Col('Sales\n%', 58),
      const _Col('Target\nmargin %', 70),
      const _Col('Achieved\nmargin %', 76),
      _Col('${_cap(p.prevWord)}\nmargin %', 84),
      const _Col('Discounts\n₹', 78),
      const _Col('Short vs\nmy target ₹', 86),
      _Col('Short vs\n${goal.toStringAsFixed(0)}% profit ₹', 92),
    ];

    // rows to show
    final rows = <_TRow>[];
    for (final c in cats) {
      final key = c.name.toLowerCase();
      final kids = byCat[key] ?? const <FinRow>[];
      final open = _open.contains(key);
      rows.add(_TRow(c, isCat: true, open: open, count: kids.length));
      if (open) {
        for (final i in kids) {
          rows.add(_TRow(i));
        }
      }
    }

    if (cats.isEmpty) {
      return const Padding(padding: EdgeInsets.all(24), child: Text('No sales in this period yet.'));
    }

    Widget cell(String t, double w, {Color? color, bool bold = false, Color? bg, double size = 12.5}) => Container(
          width: w,
          height: _rowH,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          color: bg,
          child: Text(t,
              style: TextStyle(
                  fontSize: size,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                  color: color ?? Colors.black87,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        );

    Color achievedColor(FinRow r) {
      if (r.costMissing) return Colors.blueGrey;
      final t = _target(r);
      final m = r.margin;
      if (m >= t) return lightColor(Light.green);
      if (m >= t - 3) return lightColor(Light.orange);
      return lightColor(Light.red);
    }

    List<Widget> valueCells(_TRow tr) {
      final r = tr.r;
      final bg = tr.isCat ? const Color(0xFFF1F7F4) : null;
      final st = _shortTarget(r);
      final sg = _shortGoal(r, er);
      return [
        cell(rs(r.sales), cols[0].width, bold: tr.isCat, bg: bg),
        cell(pct(sales > 0 ? r.sales / sales * 100 : 0.0), cols[1].width, bg: bg, color: Colors.black54),
        cell(pct(_target(r)), cols[2].width, bg: bg),
        cell(r.costMissing ? 'no cost' : pct(r.margin), cols[3].width,
            bold: true, color: achievedColor(r), bg: bg, size: r.costMissing ? 11.0 : 12.5),
        cell(r.prevSales > 0 ? pct(r.prevMargin) : '—', cols[4].width, bg: bg, color: Colors.black54),
        cell(r.discount >= 1 ? rs(r.discount) : '—', cols[5].width, bg: bg, color: Colors.black54),
        cell(r.costMissing ? '—' : (st > 0.5 ? rs(st) : '✓'), cols[6].width,
            bold: st > 0.5, color: st > 0.5 ? lightColor(Light.orange) : lightColor(Light.green), bg: bg),
        cell(r.costMissing ? '—' : (sg > 0.5 ? rs(sg) : '✓'), cols[7].width,
            bold: sg > 0.5, color: sg > 0.5 ? lightColor(Light.red) : lightColor(Light.green), bg: bg),
      ];
    }

    Widget nameCell(_TRow tr) {
      final r = tr.r;
      return InkWell(
        onTap: tr.isCat
            ? () => setState(() {
                  final k = r.name.toLowerCase();
                  _open.contains(k) ? _open.remove(k) : _open.add(k);
                })
            : null,
        child: Container(
          width: _nameW,
          height: _rowH,
          color: tr.isCat ? const Color(0xFFF1F7F4) : Colors.white,
          padding: EdgeInsets.only(left: tr.isCat ? 4 : 18, right: 4),
          child: Row(children: [
            if (tr.isCat)
              Icon(tr.open ? Icons.expand_more : Icons.chevron_right, size: 20, color: AppTheme.primary),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.name,
                    maxLines: tr.isCat ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: tr.isCat ? 13.5 : 12,
                        height: 1.15,
                        fontWeight: tr.isCat ? FontWeight.w800 : FontWeight.w500)),
                if (tr.isCat)
                  Text('${tr.count} item${tr.count == 1 ? '' : 's'}',
                      style: const TextStyle(fontSize: 10.5, color: Colors.black45)),
              ]),
            ),
          ]),
        ),
      );
    }

    Widget headCell(String t, double w, {Alignment a = Alignment.centerRight}) => Container(
          width: w,
          height: _headH,
          alignment: a,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(t,
              textAlign: a == Alignment.centerLeft ? TextAlign.left : TextAlign.right,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white, height: 1.2)),
        );

    const line = Divider(height: 1, thickness: 1, color: Color(0xFFE5ECE8));
    final totalW = cols.fold<double>(0, (a, c) => a + c.width);

    final totalCells = <Widget>[
      cell(rs(sales), cols[0].width, bold: true),
      cell('100%', cols[1].width, bold: true),
      cell(pct(avgTarget), cols[2].width, bold: true),
      cell(pct(avgMargin), cols[3].width,
          bold: true,
          color: avgMargin >= needed
              ? lightColor(Light.green)
              : (avgMargin >= avgTarget ? lightColor(Light.orange) : lightColor(Light.red))),
      cell(prevMargin == null ? '—' : pct(prevMargin), cols[4].width, bold: true),
      cell(disc >= 1 ? rs(disc) : '—', cols[5].width, bold: true),
      cell(catShortT > 0.5 ? rs(catShortT) : '✓', cols[6].width, bold: true, color: lightColor(Light.orange)),
      cell(catShortG > 0.5 ? rs(catShortG) : '✓', cols[7].width, bold: true, color: lightColor(Light.red)),
    ];

    final table = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // fixed first column
        SizedBox(
          width: _nameW,
          child: Column(children: [
            Container(color: AppTheme.primary, child: headCell('Category\n/ item', _nameW, a: Alignment.centerLeft)),
            for (final tr in rows) ...[nameCell(tr), line],
            Container(
              width: _nameW,
              height: _rowH,
              color: const Color(0xFFFFF8E6),
              padding: const EdgeInsets.only(left: 10),
              alignment: Alignment.centerLeft,
              child: const Text('Average /\nTotal', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, height: 1.15)),
            ),
          ]),
        ),
        Container(width: 1, height: _headH + (rows.length + 1) * (_rowH + 1), color: const Color(0xFFD6E2DC)),
        // scrolling figures
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: totalW,
              child: Column(children: [
                Container(color: AppTheme.primary, child: Row(children: [for (final c in cols) headCell(c.head, c.width)])),
                for (final tr in rows) ...[Row(children: valueCells(tr)), SizedBox(width: totalW, child: line)],
                Container(color: const Color(0xFFFFF8E6), child: Row(children: totalCells)),
              ]),
            ),
          ),
        ),
      ]),
    );

    // profit summary from the same figures
    final exp = sales * er / 100;
    final real = gp - exp;
    final want = sales * goal / 100;
    final gapAll = want - real;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Target vs achieved margin', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      const SizedBox(height: 4),
      const Text(
        'Worst first. Tap a category to see its items. Slide the table left for more columns. '
        'Averages are weighted by sales, so bigger categories count more.',
        style: const TextStyle(fontSize: 12, color: Colors.black54, height: 1.3),
      ),
      const SizedBox(height: 10),
      table,
      const SizedBox(height: 10),
      Wrap(spacing: 12, runSpacing: 4, children: [
        _legend(lightColor(Light.green), 'On target'),
        _legend(lightColor(Light.orange), 'Up to 3% below'),
        _legend(lightColor(Light.red), 'More than 3% below'),
      ]),
      const SizedBox(height: 14),
      _Summary(
        sales: sales,
        gp: gp,
        avgMargin: avgMargin,
        avgTarget: avgTarget,
        er: er,
        exp: exp,
        real: real,
        goal: goal,
        want: want,
        gap: gapAll,
        needed: needed,
        projected: p.isCurrent,
      ),
    ]);
  }

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static Widget _legend(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 4),
        Text(t, style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
      ]);
}

class _TRow {
  final FinRow r;
  final bool isCat;
  final bool open;
  final int count;
  _TRow(this.r, {this.isCat = false, this.open = false, this.count = 0});
}

/// Gross profit − expenses & credit delay = real profit, against the goal.
class _Summary extends StatelessWidget {
  final double sales, gp, avgMargin, avgTarget, er, exp, real, goal, want, gap, needed;
  final bool projected;
  const _Summary({
    required this.sales,
    required this.gp,
    required this.avgMargin,
    required this.avgTarget,
    required this.er,
    required this.exp,
    required this.real,
    required this.goal,
    required this.want,
    required this.gap,
    required this.needed,
    required this.projected,
  });

  @override
  Widget build(BuildContext context) {
    final realPct = sales > 0 ? real / sales * 100 : 0.0;
    Widget line(String a, String b, String c, {bool bold = false, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(child: Text(a, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500, fontSize: 13.5))),
            SizedBox(
                width: 62,
                child: Text(b,
                    textAlign: TextAlign.right,
                    style: TextStyle(color: color ?? Colors.black54, fontWeight: bold ? FontWeight.w800 : FontWeight.w500))),
            SizedBox(
                width: 92,
                child: Text(c,
                    textAlign: TextAlign.right,
                    style: TextStyle(color: color, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, fontSize: 14))),
          ]),
        );
    final red = lightColor(Light.red);
    final green = lightColor(Light.green);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD6E2DC)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Profit summary', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 6),
        line('Gross profit (achieved margin)', pct(avgMargin), rs(gp)),
        line('− Expenses + credit delay', pct(er), rs(exp)),
        const Divider(height: 10),
        line('= Real profit', pct(realPct), rs(real), bold: true, color: realPct >= goal ? green : red),
        line('Your goal', pct(goal), rs(want)),
        line(gap > 0 ? 'Short of goal' : 'Above goal', '', rs(gap.abs()), bold: true, color: gap > 0 ? red : green),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFFFF8E6), borderRadius: BorderRadius.circular(10)),
          child: Text(
            'To earn ${pct(goal)} real profit, the average margin must be ${pct(needed)} '
            '(${pct(goal)} + ${pct(er)} expenses & credit delay). '
            'Achieved ${pct(avgMargin)}; your category targets average ${pct(avgTarget)}.'
            '${avgTarget < er ? ' Your targets are below your expenses — even hitting every target makes a loss.' : ''}'
            '${projected ? ' Expenses are counted for the full month at today\'s pace.' : ''}',
            style: const TextStyle(fontSize: 12.5, height: 1.35),
          ),
        ),
      ]),
    );
  }
}
