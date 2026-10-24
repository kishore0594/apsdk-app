import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db/db_helper.dart';
import '../services/finance_service.dart';
import '../utils/app_theme.dart';
import 'expenses_screen.dart';

/// Targets, fixed monthly costs and the starting cash for the financial
/// statements (shared by both phones).
class FinanceSettingsScreen extends StatefulWidget {
  final FinanceSettings settings;
  const FinanceSettingsScreen({super.key, required this.settings});

  @override
  State<FinanceSettingsScreen> createState() => _FinanceSettingsScreenState();
}

class _FinanceSettingsScreenState extends State<FinanceSettingsScreen> {
  late final FinanceSettings s = widget.settings;
  final Map<String, TextEditingController> _targets = {};
  final Map<String, TextEditingController> _fixed = {};
  late final TextEditingController _cash =
      TextEditingController(text: s.startCash == null ? '' : s.startCash!.round().toString());
  late DateTime _cashDate = DateTime.tryParse(s.startCashDate) ?? DateTime.now();
  late bool _auto = s.autoFixed;
  late String _from = s.fixedFrom;
  bool _cashChanged = false;
  bool _saving = false;

  static const _targetFields = [
    ('net', 'Net profit target (% of sales)'),
    ('gross', 'Gross margin target (%)'),
    ('expense', 'Expenses — maximum (% of sales)'),
    ('collection', 'Collection — minimum (%)'),
    ('credit', 'Customer credit — maximum days'),
    ('stock', 'Stock — maximum days'),
    ('official', 'Official inflation (%) — Tamil Nadu CPI'),
    ('real', 'Real family cost rise (%) — your estimate'),
    ('delay', 'Customers take this many days to pay credit'),
  ];

  static const _priceFields = [
    ('default', 'Shop margin target for other categories (%)'),
    ('billmin', 'Lowest margin allowed on a bill or offer (%)'),
    ('fee', 'Online payment fee (% of price)'),
    ('risk', 'Online risk & returns (% of price)'),
    ('pack', 'Online packing & handling (₹ per pack)'),
    ('kg', 'Usual online pack size for loose items (kg)'),
  ];

  double _get(String k) => switch (k) {
        'net' => s.targetNet,
        'gross' => s.targetGross,
        'expense' => s.maxExpense,
        'collection' => s.minCollection,
        'credit' => s.maxCreditDays,
        'stock' => s.maxStockDays,
        'official' => s.officialInflation,
        'delay' => s.creditDelayDays,
        'default' => s.defaultTarget,
        'billmin' => s.billMinMargin,
        'fee' => s.onlineFeePct,
        'risk' => s.onlineRiskPct,
        'pack' => s.onlinePackCost,
        'kg' => s.onlineTypicalKg,
        _ => s.realInflation,
      };

  final Map<String, TextEditingController> _cats = {}; // category -> margin target
  void _loadCategories() async {
    final products = await DBHelper.instance.getProducts();
    final names = <String, String>{};
    for (final p in products) {
      final c = (p['category'] as String? ?? '').trim();
      if (c.isNotEmpty) names.putIfAbsent(c.toLowerCase(), () => c);
    }
    if (!mounted) return;
    setState(() {
      for (final e in names.entries) {
        _catNames[e.key] = e.value;
        _cats[e.key] = TextEditingController(text: _fmt(s.targetFor(e.key)));
      }
    });
  }

  final Map<String, String> _catNames = {};

  @override
  void initState() {
    super.initState();
    for (final f in [..._targetFields, ..._priceFields]) {
      _targets[f.$1] = TextEditingController(text: _fmt(_get(f.$1)));
    }
    _loadCategories();
    for (final e in s.fixed.entries) {
      _fixed[e.key] = TextEditingController(text: e.value.round().toString());
    }
  }

  @override
  void dispose() {
    for (final c in [..._targets.values, ..._fixed.values, ..._cats.values, _cash]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  double _num(TextEditingController c, double def) => double.tryParse(c.text.trim().replaceAll(',', '')) ?? def;

  List<String> get _months {
    final now = DateTime.now();
    return [for (var i = 0; i < 18; i++) DateFormat('yyyy-MM').format(DateTime(now.year, now.month - i))];
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    s.targetNet = _num(_targets['net']!, s.targetNet);
    s.targetGross = _num(_targets['gross']!, s.targetGross);
    s.maxExpense = _num(_targets['expense']!, s.maxExpense);
    s.minCollection = _num(_targets['collection']!, s.minCollection);
    s.maxCreditDays = _num(_targets['credit']!, s.maxCreditDays);
    s.maxStockDays = _num(_targets['stock']!, s.maxStockDays);
    s.officialInflation = _num(_targets['official']!, s.officialInflation);
    s.realInflation = _num(_targets['real']!, s.realInflation);
    s.creditDelayDays = _num(_targets['delay']!, s.creditDelayDays);
    s.defaultTarget = _num(_targets['default']!, s.defaultTarget);
    s.billMinMargin = _num(_targets['billmin']!, s.billMinMargin);
    s.onlineFeePct = _num(_targets['fee']!, s.onlineFeePct);
    s.onlineRiskPct = _num(_targets['risk']!, s.onlineRiskPct);
    s.onlinePackCost = _num(_targets['pack']!, s.onlinePackCost);
    s.onlineTypicalKg = _num(_targets['kg']!, s.onlineTypicalKg);
    s.catTargets = {for (final e in _cats.entries) e.key: _num(e.value, s.defaultTarget)};
    s.fixed = {for (final e in _fixed.entries) e.key: _num(e.value, 0)};
    s.autoFixed = _auto;
    s.fixedFrom = _from;
    if (_cashChanged) {
      s.startCash = _num(_cash, s.startCash ?? 0);
      s.startCashDate = DateFormat('yyyy-MM-dd').format(_cashDate);
      s.startCashEstimate = false;
    }
    try {
      // Whole document, so a removed fixed cost really goes away.
      await DBHelper.instance.replaceFinanceSettings(s.toMap());
      await FinanceService.refreshThisMonthFixed(s);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    }
  }

  void _addHead() async {
    final free = kExpenseCategories.where((c) => !_fixed.containsKey(c)).toList();
    if (free.isEmpty) return;
    final pick = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          for (final c in free) ListTile(title: Text(c), onTap: () => Navigator.pop(ctx, c)),
        ]),
      ),
    );
    if (pick == null) return;
    setState(() => _fixed[pick] = TextEditingController(text: '0'));
  }

  @override
  Widget build(BuildContext context) {
    final total = _fixed.values.fold<double>(0, (a, c) => a + _num(c, 0));
    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      appBar: AppBar(title: const Text('Targets & fixed costs')),
      body: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 32), children: [
        const Text('Fixed monthly costs', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 4),
        const Text(
          'Added to Expenses automatically on the 1st of every month, so net profit is always real. '
          'If you also typed one of these by hand for a month, delete one of the two.',
          style: TextStyle(fontSize: 12.5, color: Colors.black54, height: 1.3),
        ),
        const SizedBox(height: 8),
        for (final e in _fixed.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(child: Text(e.key == 'Wages' ? "Wages / owner's salary" : e.key)),
              SizedBox(
                width: 130,
                child: TextField(
                  controller: e.value,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(prefixText: '₹ ', isDense: true, border: OutlineInputBorder()),
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _fixed.remove(e.key)?.dispose()),
                icon: const Icon(Icons.close, size: 18),
              ),
            ]),
          ),
        Row(children: [
          TextButton.icon(onPressed: _addHead, icon: const Icon(Icons.add), label: const Text('Add a cost')),
          const Spacer(),
          Text('Total ₹${NumberFormat.decimalPattern('en_IN').format(total.round())} / month',
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Add them automatically every month'),
          value: _auto,
          onChanged: (v) => setState(() => _auto = v),
        ),
        Row(children: [
          const Expanded(child: Text('Start from month')),
          DropdownButton<String>(
            value: _months.contains(_from) ? _from : _months.last,
            items: [
              for (final m in _months)
                DropdownMenuItem(value: m, child: Text(DateFormat('MMM yyyy').format(DateTime.parse('$m-01')))),
            ],
            onChanged: (v) => setState(() => _from = v ?? _from),
          ),
        ]),
        const Divider(height: 28),
        const Text('Starting cash & bank', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 4),
        Text(
          s.startCashEstimate
              ? 'Now an estimate (that month\'s sales). Enter the real cash in the drawer + bank balance on a date you know it.'
              : 'Cash in the drawer + bank balance on the date below. The app carries it forward from your sales, '
                  'collections, supplier payments and expenses.',
          style: const TextStyle(fontSize: 12.5, color: Colors.black54, height: 1.3),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _cash,
              keyboardType: TextInputType.number,
              onChanged: (_) => _cashChanged = true,
              decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ ', border: OutlineInputBorder()),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _cashDate,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (d != null) {
                setState(() {
                  _cashDate = d;
                  _cashChanged = true;
                });
              }
            },
            child: Text(DateFormat('d MMM yyyy').format(_cashDate)),
          ),
        ]),
        const Divider(height: 28),
        const Text('Targets', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 8),
        for (final f in _targetFields)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
              controller: _targets[f.$1],
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: f.$2, isDense: true, border: const OutlineInputBorder()),
            ),
          ),
        const Divider(height: 28),
        const Text('Pricing: margin targets', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 4),
        const Text(
          'Shop price = cost ÷ (1 − target). Online price adds the payment fee, risk & returns and packing on top, '
          'so online sales earn the same target.',
          style: TextStyle(fontSize: 12.5, color: Colors.black54, height: 1.3),
        ),
        const SizedBox(height: 8),
        for (final e in _cats.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(child: Text(_catNames[e.key] ?? e.key)),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: e.value,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(suffixText: '%', isDense: true, border: OutlineInputBorder()),
                ),
              ),
            ]),
          ),
        for (final f in _priceFields)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
              controller: _targets[f.$1],
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: f.$2, isDense: true, border: const OutlineInputBorder()),
            ),
          ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: Text(_saving ? 'Saving…' : 'Save'),
        ),
      ]),
    );
  }
}
