import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../db/db_helper.dart';
import '../services/customer_pattern.dart';
import '../utils/app_info.dart';
import '../utils/app_theme.dart';
import 'vendors_screen.dart';

final _rsF = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
String _rs(double v) => _rsF.format(v.round());
String _day(DateTime d) => DateFormat('d MMM').format(d);
const _weekdayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _red = Color(0xFFDC2626);
const _orange = Color(0xFFD97706);
const _green = Color(0xFF16A34A);

const _groupIcons = {
  CustGroup.late: Icons.error_outline,
  CustGroup.due: Icons.event_available_outlined,
  CustGroup.dropping: Icons.trending_down,
  CustGroup.lost: Icons.person_off_outlined,
  CustGroup.top: Icons.star_outline,
  CustGroup.regular: Icons.repeat,
  CustGroup.newbie: Icons.fiber_new_outlined,
};
const _groupColors = {
  CustGroup.late: _red,
  CustGroup.due: _orange,
  CustGroup.dropping: _orange,
  CustGroup.lost: Colors.black54,
  CustGroup.top: Color(0xFFB7791F),
  CustGroup.regular: _green,
  CustGroup.newbie: Color(0xFF2563EB),
};

/// Loads (once per app session, pull to refresh) and keeps the patterns.
class PatternStore {
  static CustomerPatterns? _cache;
  static void put(CustomerPatterns p) => _cache = p;
  static Future<CustomerPatterns> load({bool fresh = false}) async {
    if (!fresh && _cache != null) return _cache!;
    final raw = await DBHelper.instance.getFinanceRaw();
    _cache = CustomerPatterns.build(
      vendors: raw['vendors'] ?? const [],
      sales: raw['sales'] ?? const [],
      items: raw['items'] ?? const [],
      credit: raw['credit'] ?? const [],
      products: raw['products'] ?? const [],
    );
    return _cache!;
  }
}

String _qty(double q) => q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toStringAsFixed(1);
String itemText(CustItem i) => '${_qty(i.usualQty)}${i.unit.isEmpty ? '' : ' ${i.unit}'} ${i.name}';

/// Vendor Insights → Buying pattern: summary, priority groups with a
/// category filter, and one row per customer.
class BuyingPatternView extends StatefulWidget {
  final String search;
  final CustGroup? initialGroup;
  const BuyingPatternView({super.key, this.search = '', this.initialGroup});

  @override
  State<BuyingPatternView> createState() => _BuyingPatternViewState();
}

class _BuyingPatternViewState extends State<BuyingPatternView> {
  CustomerPatterns? _p;
  String? _error;
  late CustGroup? _group = widget.initialGroup ?? CustGroup.late;
  String _cat = '';
  bool _all = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool fresh = false}) async {
    try {
      final p = await PatternStore.load(fresh: fresh);
      if (mounted) setState(() => _p = p);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load buying patterns: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    if (_error != null) return Padding(padding: const EdgeInsets.all(16), child: Text(_error!));
    if (p == null) return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
    if (p.all.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No bills with a customer name yet. Choose the customer while billing to see their pattern.'),
      );
    }
    final q = widget.search.toLowerCase();
    var list = p.list(_group, category: _cat);
    if (q.isNotEmpty) list = list.where((c) => c.name.toLowerCase().contains(q) || c.place.toLowerCase().contains(q)).toList();
    final shown = _all ? list : list.take(50).toList();
    final cats = p.categories.where((c) => c != 'Uncategorised').toList();
    if (_cat.isNotEmpty && !cats.any((c) => c.toLowerCase() == _cat)) _cat = '';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _summary(p.summary),
      const SizedBox(height: 14),
      DropdownButtonFormField<String>(
        key: ValueKey('pcat-$_cat'),
        value: _cat,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Category',
          prefixIcon: Icon(Icons.category_outlined),
          isDense: true,
          border: OutlineInputBorder(),
        ),
        items: [
          const DropdownMenuItem(value: '', child: Text('All categories')),
          for (final c in cats) DropdownMenuItem(value: c.toLowerCase(), child: Text('$c buyers')),
        ],
        onChanged: (v) => setState(() {
          _cat = v ?? '';
          _all = false;
        }),
      ),
      const SizedBox(height: 10),
      SizedBox(
        height: 40,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final g in CustGroup.values) ...[
            ChoiceChip(
              avatar: Icon(_groupIcons[g], size: 16, color: _groupColors[g]),
              label: Text('${custGroupNames[g]} ${p.count(g, category: _cat)}'),
              selected: _group == g,
              onSelected: (_) => setState(() {
                _group = g;
                _all = false;
              }),
            ),
            const SizedBox(width: 6),
          ],
          ChoiceChip(
            label: Text('All ${p.list(null, category: _cat).length}'),
            selected: _group == null,
            onSelected: (_) => setState(() {
              _group = null;
              _all = false;
            }),
          ),
        ]),
      ),
      const SizedBox(height: 6),
      Text(
        _group == null ? 'Everyone who has bought, biggest buyers (last 6 months) first.' : custGroupHelp[_group]!,
        style: const TextStyle(fontSize: 12, color: Colors.black54, height: 1.3),
      ),
      const SizedBox(height: 8),
      if (list.isEmpty)
        const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('Nobody here right now — good.'))),
      for (final c in shown) _row(c, p),
      if (!_all && list.length > shown.length)
        Center(child: TextButton(onPressed: () => setState(() => _all = true), child: Text('Show all ${list.length}'))),
      const SizedBox(height: 4),
      Center(
        child: TextButton.icon(
          onPressed: () {
            setState(() => _p = null);
            _load(fresh: true);
          },
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Refresh patterns'),
        ),
      ),
    ]);
  }

  Widget _summary(PatternSummary s) {
    Widget tile(String v, String l, Color c) => Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2EAE6)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(v, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: c)),
            const SizedBox(height: 2),
            Text(l, style: const TextStyle(fontSize: 11.5, color: Colors.black54, height: 1.2)),
          ]),
        );
    final tiles = [
      tile('${s.active}', 'Active customers this month', AppTheme.primary),
      tile('${s.repeatRate.round()}%', 'Repeat rate (2+ visits in 90 days)', AppTheme.primary),
      tile('${s.due}', 'Due this week', _orange),
      tile('${s.late}', 'Late', _red),
      tile('${s.newbies}', 'New (30 days)', const Color(0xFF2563EB)),
      tile('${s.topShare.round()}%', 'Sales from top 20% customers', const Color(0xFFB7791F)),
    ];
    return LayoutBuilder(builder: (context, box) {
      final w = (box.maxWidth - 16) / 3;
      return Wrap(spacing: 8, runSpacing: 8, children: [for (final t in tiles) SizedBox(width: w, child: t)]);
    });
  }

  Widget _row(CustPattern c, CustomerPatterns p) {
    final g = c.usualGap;
    final late = c.lateDays;
    String visit;
    Color vc = Colors.black54;
    if (g == null) {
      visit = 'Only 1 visit · ${c.daysSince} days ago';
    } else {
      visit = 'Every $g days · last ${c.daysSince == 0 ? 'today' : '${c.daysSince} days ago'}';
      if (c.groups.contains(CustGroup.lost)) {
        visit += ' · not seen for ${c.daysSince} days';
        vc = Colors.black54;
      } else if (late != null && late > 0) {
        visit += ' · $late days late';
        vc = c.groups.contains(CustGroup.late) ? _red : _orange;
      } else if (c.nextDue != null) {
        final inDays = -(late ?? 0);
        visit += inDays == 0 ? ' · due today' : ' · due in $inDays days';
        vc = inDays <= 7 ? _orange : Colors.black54;
      }
    }
    final usual = c.usualItems(category: _cat, max: 2);
    final ch = c.changePct;
    final fav = c.favWeekday;
    final line3 = [
      if (ch != null && ch.abs() >= 10) 'Spend ${ch < 0 ? '▼' : '▲'} ${ch.abs().round()}% vs 3-month average',
      if (fav != null) 'Usually ${_weekdayNames[fav]}',
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerPatternScreen(c: c))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text('${c.name}${c.place.isEmpty ? '' : ', ${c.place}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
              ),
              if (c.balance > 0.5)
                Text('${_rs(c.balance)} due', style: const TextStyle(color: _red, fontWeight: FontWeight.w700, fontSize: 12.5)),
            ]),
            const SizedBox(height: 3),
            Text(visit, style: TextStyle(fontSize: 12.5, color: vc, fontWeight: vc == Colors.black54 ? FontWeight.w500 : FontWeight.w700)),
            if (usual.isNotEmpty)
              Text('Usually: ${usual.map(itemText).join(' · ')}',
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
            if (line3.isNotEmpty)
              Text(line3,
                  style: TextStyle(fontSize: 12, color: (ch ?? 0) <= -30 ? _red : Colors.black54)),
            const SizedBox(height: 4),
            Wrap(spacing: 4, runSpacing: 4, children: [
              for (final gr in CustGroup.values)
                if (c.groups.contains(gr)) _tag(gr),
            ]),
          ]),
        ),
      ),
    );
  }

  static Widget _tag(CustGroup g) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: _groupColors[g]!.withOpacity(0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(custGroupNames[g]!, style: TextStyle(fontSize: 10.5, color: _groupColors[g], fontWeight: FontWeight.w700)),
      );
}

/// One customer's full buying pattern with WhatsApp actions.
class CustomerPatternScreen extends StatelessWidget {
  final CustPattern c;
  const CustomerPatternScreen({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    final g = c.usualGap;
    final late = c.lateDays;
    final now = DateTime.now();
    final items = c.items.values.toList()..sort((a, b) => b.days.length.compareTo(a.days.length));
    final monthNames = [
      for (var i = 5; i >= 0; i--) DateFormat('MMM').format(DateTime(now.year, now.month - i)),
    ];
    final maxMonth = c.months.fold<double>(0, (a, b) => b > a ? b : a);
    final maxWd = c.weekdays.fold<int>(0, (a, b) => b > a ? b : a);

    Widget section(String title, List<Widget> kids) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2EAE6)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 8),
            ...kids,
          ]),
        );
    Widget fact(String a, String b, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(a, style: const TextStyle(color: Colors.black54, fontSize: 13))),
            Text(b, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: color)),
          ]),
        );

    String nextText;
    Color? nextColor;
    if (g == null) {
      nextText = 'Needs 2+ visits';
    } else if (late != null && late > 0) {
      nextText = '${_day(c.nextDue!)} · $late days late';
      nextColor = c.groups.contains(CustGroup.late) || c.groups.contains(CustGroup.lost) ? _red : _orange;
    } else {
      nextText = _day(c.nextDue!);
      nextColor = _orange;
    }

    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      appBar: AppBar(
        title: Text(c.name),
        actions: [
          IconButton(
            tooltip: 'Open account',
            icon: const Icon(Icons.account_balance_wallet_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VendorDetailScreen(vendor: c.vendor))),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 32), children: [
        Text(
          [if (c.place.isNotEmpty) '📍 ${c.place}', if (c.phone.isNotEmpty) '📞 ${c.phone}'].join('   '),
          style: const TextStyle(fontSize: 13, color: Colors.black54),
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 4, runSpacing: 4, children: [
          for (final gr in CustGroup.values)
            if (c.groups.contains(gr)) _BuyingPatternViewState._tag(gr),
        ]),
        const SizedBox(height: 10),
        _actions(context),
        const SizedBox(height: 12),
        section('Visits', [
          fact('Comes every', g == null ? '—' : '$g days'),
          fact('Last visit', c.last == null ? '—' : '${_day(c.last!)} (${c.daysSince} days ago)'),
          fact('Next expected', nextText, color: nextColor),
          fact('Visits in last 60 days', '${c.visits60}'),
          fact('Bills / customer since', '${c.bills} · ${c.first == null ? '—' : DateFormat('MMM yyyy').format(c.first!)}'),
          const SizedBox(height: 8),
          const Text('Visit days', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          _bars([for (final w in c.weekdays) w.toDouble()], ['M', 'T', 'W', 'T', 'F', 'S', 'S'], maxWd.toDouble(),
              (v) => v.round().toString()),
        ]),
        section('Spending', [
          fact('Last 30 days', _rs(c.spend30)),
          fact('3-month average (per 30 days)', _rs(c.avgPrev30)),
          if (c.changePct != null)
            fact('Change', '${c.changePct! < 0 ? '▼' : '▲'} ${c.changePct!.abs().round()}%',
                color: c.changePct! <= -30 ? _red : (c.changePct! < 0 ? _orange : _green)),
          fact('Per visit (average)', _rs(c.perVisit)),
          const SizedBox(height: 8),
          _bars(c.months, monthNames, maxMonth, (v) => v >= 1000 ? '${(v / 1000).toStringAsFixed(v >= 10000 ? 0 : 1)}k' : v.round().toString()),
        ]),
        section('What they buy', [
          Row(children: const [
            Expanded(flex: 5, child: Text('Item', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.black54))),
            Expanded(flex: 3, child: Text('Usual', textAlign: TextAlign.right, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.black54))),
            Expanded(flex: 3, child: Text('Every', textAlign: TextAlign.right, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.black54))),
            Expanded(flex: 4, child: Text('Next due', textAlign: TextAlign.right, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.black54))),
          ]),
          const Divider(height: 10),
          for (final i in items.take(15)) _itemRow(i, now),
        ]),
        section('Payment habit', [
          fact('Cash / credit', '${(100 - c.creditShare).round()}% / ${c.creditShare.round()}%'),
          fact('Average days to pay', c.avgDaysToPay == null ? '—' : '${c.avgDaysToPay!.round()} days',
              color: (c.avgDaysToPay ?? 0) > 50 ? _red : ((c.avgDaysToPay ?? 0) > 30 ? _orange : null)),
          fact('Owes now', _rs(c.balance), color: c.balance > 0.5 ? _red : _green),
          if (c.creditShare > 50 && (c.avgDaysToPay ?? 0) > 50)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('⚠ Buys mostly on credit and pays slowly — keep a credit limit.',
                  style: TextStyle(color: _red, fontSize: 12.5)),
            ),
        ]),
        section('Profit from this customer', [
          fact('Profit (all bills with cost)', _rs(c.profit)),
          fact('Margin', '${c.margin.toStringAsFixed(1)}%'),
          for (final e in (c.catSpend.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(4))
            fact('Bought: ${e.key}', _rs(e.value)),
        ]),
        if (c.missingCats.isNotEmpty)
          section('Never bought', [
            Text('${c.missingCats.join(', ')} — popular in your shop. Suggest them on the next visit or by WhatsApp.',
                style: const TextStyle(fontSize: 13, height: 1.35)),
          ]),
      ]),
    );
  }

  Widget _itemRow(CustItem i, DateTime now) {
    final next = i.nextDue;
    final today = DateTime(now.year, now.month, now.day);
    final lateBy = next == null ? null : today.difference(next).inDays;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(
          flex: 5,
          child: Text(i.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        ),
        Expanded(
          flex: 3,
          child: Text('${_qty(i.usualQty)} ${i.unit}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5)),
        ),
        Expanded(
          flex: 3,
          child: Text(i.cycleDays == null ? '—' : '${i.cycleDays} d', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5)),
        ),
        Expanded(
          flex: 4,
          child: Text(
            next == null ? (i.last == null ? '—' : 'last ${_day(i.last!)}') : (lateBy! > 0 ? '${lateBy}d late' : _day(next)),
            textAlign: TextAlign.right,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: next == null ? Colors.black54 : (lateBy! > 0 ? _red : (lateBy! > -7 ? _orange : Colors.black87))),
          ),
        ),
      ]),
    );
  }

  static Widget _bars(List<double> v, List<String> labels, double max, String Function(double) fmt) {
    return SizedBox(
      height: 96,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < v.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text(v[i] > 0 ? fmt(v[i]) : '', style: const TextStyle(fontSize: 9.5, color: Colors.black54)),
                const SizedBox(height: 2),
                Container(
                  height: max > 0 ? 3 + 55 * v[i] / max : 3,
                  decoration: BoxDecoration(
                    color: i == v.length - 1 && labels.length == 6 ? AppTheme.primary : AppTheme.primary.withOpacity(0.45),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 3),
                Text(labels[i], style: const TextStyle(fontSize: 10.5, color: Colors.black54)),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _actions(BuildContext context) {
    final usual = c.usualItems(max: 2);
    final hasPhone = c.phone.replaceAll(RegExp(r'[^0-9]'), '').length >= 10;
    Widget btn(IconData ic, String label, _Msg m) => OutlinedButton.icon(
          onPressed: hasPhone ? () => _sendPatternMessage(context, c, m) : null,
          icon: Icon(ic, size: 18),
          label: Text(label),
        );
    return Wrap(spacing: 8, runSpacing: 6, children: [
      if (usual.isNotEmpty) btn(Icons.event_available_outlined, 'Due reminder', _Msg.due),
      btn(Icons.favorite_border, 'Win-back offer', _Msg.winBack),
      if (c.missingCats.isNotEmpty) btn(Icons.add_shopping_cart, 'Try ${c.missingCats.first}', _Msg.tryCat),
      if (!hasPhone)
        const Text('Add a phone number to this customer to send WhatsApp messages.',
            style: TextStyle(fontSize: 12, color: Colors.black54)),
    ]);
  }
}

enum _Msg { due, winBack, tryCat }

String _message(CustPattern c, _Msg m, bool ta) {
  final items = c.usualItems(max: 2).map(itemText).join(ta ? ', ' : ' and ');
  final shop = AppInfo.appName;
  final cat = c.missingCats.isEmpty ? '' : c.missingCats.first;
  switch (m) {
    case _Msg.due:
      return ta
          ? 'வணக்கம் ${c.name},\n\nஉங்கள் வழக்கமான $items வாங்கும் நேரம் வந்துவிட்டது. உங்களுக்காக தயாராக வைத்திருக்கலாமா?\n\n- $shop'
          : 'Vanakkam ${c.name},\n\nYour usual $items is due. Shall we keep it ready for you?\n\n- $shop';
    case _Msg.winBack:
      return ta
          ? 'வணக்கம் ${c.name},\n\nஉங்களை சில நாட்களாக எங்கள் கடையில் காணவில்லை!${items.isEmpty ? '' : ' உங்கள் வழக்கமான $items கையிருப்பில் உள்ளது.'} இந்த வாரம் வாருங்கள் — உங்களுக்கு சிறப்பு விலை உண்டு.\n\n- $shop'
          : 'Vanakkam ${c.name},\n\nWe have missed you at our shop!${items.isEmpty ? '' : ' Your usual $items is in stock.'} Visit us this week — we have a special price for you.\n\n- $shop';
    case _Msg.tryCat:
      return ta
          ? 'வணக்கம் ${c.name},\n\nஉங்கள் வழக்கமான பொருட்களுடன் எங்கள் $cat-ஐயும் முயற்சி செய்யுங்கள் — புதிய சரக்கு, நல்ல விலை. அடுத்த முறை வரும்போது கேளுங்கள்.\n\n- $shop'
          : 'Vanakkam ${c.name},\n\nAlong with your usual items, try our $cat — fresh stock, good price. Ask us on your next visit.\n\n- $shop';
  }
  // ignore: dead_code
  return '';
}

/// Lets the owner pick English / Tamil, edit the text, then opens WhatsApp.
Future<void> _sendPatternMessage(BuildContext context, CustPattern c, _Msg m) async {
  var ta = false;
  final ctl = TextEditingController(text: _message(c, m, ta));
  final text = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('WhatsApp to ${c.name}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: const [ButtonSegment(value: false, label: Text('English')), ButtonSegment(value: true, label: Text('தமிழ்'))],
            selected: {ta},
            onSelectionChanged: (s) => setS(() {
              ta = s.first;
              ctl.text = _message(c, m, ta);
            }),
          ),
          const SizedBox(height: 10),
          TextField(controller: ctl, maxLines: 8, minLines: 4, decoration: const InputDecoration(border: OutlineInputBorder())),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
              icon: const Icon(Icons.send),
              label: const Text('Open WhatsApp'),
            ),
          ),
        ]),
      ),
    ),
  );
  if (text == null || text.isEmpty) return;
  var digits = c.phone.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length == 10) digits = '91$digits';
  final url = Uri.parse('https://wa.me/$digits?text=${Uri.encodeComponent(text)}');
  try {
    final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open WhatsApp')));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open WhatsApp: $e')));
    }
  }
}
