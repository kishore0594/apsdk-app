import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/db_helper.dart';
import '../services/category_sales.dart';
import '../services/finance_service.dart';
import '../services/pricing.dart';
import '../services/web_store_service.dart';
import '../utils/app_theme.dart';
import '../utils/csv_helper.dart';
import '../utils/user_role.dart';
import 'finance_screen.dart' show rs, pct, lightColor;
import 'inventory_screen.dart' show openProductEditor;

/// Pricing: every product's shop and online price split into the four
/// parts the owner decides with — cost, expenses, partner commission and
/// net profit — using the price rules (app_settings/price_rules). Prices
/// are changed by hand (✏) with the four parts shown live.
class ProductMarginsScreen extends StatefulWidget {
  const ProductMarginsScreen({super.key});

  @override
  State<ProductMarginsScreen> createState() => _ProductMarginsScreenState();
}

enum _Filter { below, aboveMarket, costUp, all, noCost }

class _ProductMarginsScreenState extends State<ProductMarginsScreen> {
  final _db = DBHelper.instance;
  List<Map<String, dynamic>> _products = [];
  PriceRules _rules = PriceRules.cached;
  bool _rulesLoaded = false;
  bool _loading = true;
  String _search = '';
  _Filter _filter = _Filter.below;
  String _cat = ''; // '' = all categories (lower-case key otherwise)
  static const _catKey = 'pricing_category';
  bool _lastMonth = false;
  Future<Map<String, CategorySales>>? _salesFuture;

  @override
  void initState() {
    super.initState();
    _restoreCat();
    _load();
  }

  Future<void> _restoreCat() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_catKey) ?? '';
      if (mounted && v != _cat) setState(() => _cat = v);
    } catch (_) {}
  }

  Future<void> _setCat(String v) async {
    setState(() => _cat = v);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_catKey, v);
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await Future.wait([_db.getProducts(), PriceRules.load()]);
      if (!mounted) return;
      setState(() {
        _products = r[0] as List<Map<String, dynamic>>;
        _rules = r[1] as PriceRules;
        _rulesLoaded = true;
        _salesFuture = null;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static double _n(Object? v) => v is num ? v.toDouble() : 0.0;

  _Row _row(Map<String, dynamic> p) {
    final ru = _rules;
    final cost = _n(p['cost_price']);
    final cat = FinanceService.tidy(p['category'] as String?);
    final perKg = FinanceService.perKgUnit(p);
    final shop = _n(p['selling_price']);
    final web = WebStoreService.priceOf(p);
    final offer = _n(p['offer_price']);
    final online = WebStoreService.isOnline(p);
    final market = _n(p['market_price']);
    final own = (p['partner_pct'] as num?)?.toDouble();
    final plan = ru.onlinePlan(cost, cat, perKg, market: market);
    return _Row(
      p: p,
      cost: cost,
      category: cat,
      perKg: perKg,
      shop: shop,
      shopBreak: ru.shopBreak(shop, cost),
      suggestShop: ru.shopPrice(cost, cat),
      online: online,
      web: web,
      webBreak: ru.onlineBreak(web, cost, cat, perKg, productPct: own),
      suggestWeb: plan.price,
      market: market,
      plan: plan,
      offer: offer > 0 && offer < web ? offer : 0.0,
      offerBreak: ru.onlineBreak(offer > 0 && offer < web ? offer : 0.0, cost, cat, perKg, productPct: own),
      costPrev: _n(p['cost_prev']),
      shopTarget: ru.shopProfitFor(cat),
      webTarget: ru.onlineMinFor(cat),
    );
  }

  bool _matches(_Row r) {
    if (_search.isNotEmpty && !(r.p['name'] ?? '').toString().toLowerCase().contains(_search)) return false;
    if (_cat.isNotEmpty && r.category.toLowerCase() != _cat) return false;
    switch (_filter) {
      case _Filter.below:
        return r.cost > 0 && (r.shopBelow || r.webBelow);
      case _Filter.aboveMarket:
        return r.aboveMarket;
      case _Filter.costUp:
        return r.costPrev > 0 && r.cost > r.costPrev;
      case _Filter.noCost:
        return r.cost <= 0;
      case _Filter.all:
        return true;
    }
    // ignore: dead_code
    return true;
  }

  Future<void> _setShop(_Row r, double v) async {
    await _db.updateProduct(r.p['id'] as String, {'selling_price': v});
    r.p['selling_price'] = v;
    if (mounted) setState(() {});
  }

  /// Saves an online price with the partner commission it carries: the
  /// normal rate, or a cut one when the price is below the rule floor.
  Future<void> _setWeb(_Row r, double v, {double? commission}) async {
    final normal = _rules.commissionFor(r.category);
    final c = commission ?? _rules.commissionAt(v, r.cost, r.category, r.perKg);
    final own = c < normal - 0.005 ? (c * 100).roundToDouble() / 100 : null;
    await WebStoreService.instance.updateProductWeb(r.p['id'] as String, {'web_price': v, 'partner_pct': own});
    r.p['web_price'] = v;
    r.p['partner_pct'] = own;
    if (mounted) setState(() {});
  }

  /// Type any price — up or down — and see cost, expenses, commission and
  /// net profit change before saving.
  Future<void> _editPrice(_Row r, {required bool web}) async {
    final ru = _rules;
    final start = web ? r.web : r.shop;
    final suggest = web ? r.suggestWeb : r.suggestShop;
    final target = web ? r.webTarget : r.shopTarget;
    final ctl = TextEditingController(text: start > 0 ? start.toStringAsFixed(start % 1 == 0 ? 0 : 2) : '');
    PriceBreak breakOf(double v) => web
        ? ru.onlineBreak(v, r.cost, r.category, r.perKg, productPct: ru.commissionAt(v, r.cost, r.category, r.perKg))
        : ru.shopBreak(v, r.cost);
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        final x = double.tryParse(ctl.text.trim()) ?? 0.0;
        final b = breakOf(x);
        return AlertDialog(
          title: Text('${web ? 'Online' : 'Shop'} price — ${(r.p['name'] ?? '').toString()}'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                controller: ctl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(prefixText: '₹ ', labelText: 'New price', border: OutlineInputBorder()),
                onChanged: (_) => setD(() {}),
              ),
              const SizedBox(height: 10),
              if (r.cost > 0 && x > 0) _BreakTable(b, target: target),
              if (r.cost > 0 && x > 0 && b.profitPct < target - 0.5)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                      web && b.commission < x * ru.commissionFor(r.category) / 100 - 0.01
                          ? 'Competitive price: commission and profit both cut in the same proportion.'
                          : 'Profit below your ${pct(target)}.',
                      style: TextStyle(color: lightColor(Light.orange), fontSize: 12.5)),
                ),
              if (suggest > 0)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setD(() => ctl.text = suggest.toStringAsFixed(0)),
                    child: Text('Rule price ${rs(suggest)} — tap to use'),
                  ),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: x > 0 ? () => Navigator.pop(ctx, x) : null, child: const Text('Save')),
          ],
        );
      }),
    );
    if (v == null || v <= 0 || v == start) return;
    if (r.cost > 0 && breakOf(v).profit < 0) {
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('This price makes a loss'),
          content: Text('At ${rs(v)} you lose ${rs(-breakOf(v).profit)} on each sale. Save anyway?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Don't save")),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save anyway')),
          ],
        ),
      );
      if (ok != true) return;
    }
    web ? await _setWeb(r, v) : await _setShop(r, v);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Price saved: ${rs(v)}')));
    }
  }

  Future<void> _openInInventory(_Row r) async {
    await openProductEditor(context, r.p);
    _load();
  }

  /// The price rules: bills, packing, payment & returns, commission, profit.
  Future<void> _editRules() async {
    final r = _rules;
    String f(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toString();
    final c = <String, TextEditingController>{
      'monthly_bills': TextEditingController(text: f(r.monthlyBills)),
      'target_revenue': TextEditingController(text: f(r.targetRevenue)),
      'credit_pct': TextEditingController(text: f(r.creditPct)),
      'pack_cost': TextEditingController(text: f(r.packCost)),
      'bag_pack_cost': TextEditingController(text: f(r.bagPackCost)),
      'pay_pct': TextEditingController(text: f(r.payPct)),
      'commission_pct': TextEditingController(text: f(r.commissionPct)),
      'rice_commission_pct': TextEditingController(text: f(r.riceCommissionPct)),
      'bag_commission': TextEditingController(text: f(r.bagCommission)),
      'shop_profit': TextEditingController(text: f(r.shopProfit)),
      'online_profit_min': TextEditingController(text: f(r.onlineProfitMin)),
      'online_profit_max': TextEditingController(text: f(r.onlineProfitMax)),
      'keep_pct': TextEditingController(text: f(r.keepPct)),
    };
    const labels = {
      'monthly_bills': 'Monthly bills ₹ (rent, wages, power…)',
      'target_revenue': 'Target sales per month ₹',
      'credit_pct': 'Credit delay %',
      'pack_cost': 'Online packing ₹ per pack',
      'bag_pack_cost': 'Online packing ₹ per bag / unit',
      'pay_pct': 'Online payment & returns %',
      'commission_pct': 'Partner commission % (millets, flour, grams & nuts)',
      'rice_commission_pct': 'Partner commission % (rice)',
      'bag_commission': 'Partner commission ₹ per cattle-feed bag',
      'shop_profit': 'Shop profit %',
      'online_profit_min': 'Online profit % — lowest',
      'online_profit_max': 'Online profit % — highest',
      'keep_pct': 'To meet market: keep at least this % of commission & profit',
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Price rules'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final k in c.keys)
              TextField(
                controller: c[k],
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: labels[k]),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    final m = <String, dynamic>{...r.toMap()};
    for (final e in c.entries) {
      final v = double.tryParse(e.value.text.trim());
      if (v != null && v >= 0) m[e.key] = v;
    }
    final next = PriceRules.fromMap(m);
    await PriceRules.save(next);
    if (mounted) setState(() => _rules = next);
  }

  // ---------------- Category sales (this month / last month) ----------------

  Future<Map<String, CategorySales>> _sales() {
    final now = DateTime.now();
    final start = _lastMonth ? DateTime(now.year, now.month - 1, 1) : DateTime(now.year, now.month, 1);
    final end = _lastMonth ? DateTime(now.year, now.month, 1) : DateTime(now.year, now.month + 1, 1);
    return _salesFuture ??= CategorySales.load(start, end, _rules);
  }

  Widget _partsBlock(String label, SalesParts x, double target) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$label: sales ${rs(x.revenue)} · ${x.bills} bills',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          if (x.revenue > 0) _BreakTable(x.asBreak, target: target),
        ]),
      );

  Widget _salesCard(String catName, List<_Row> inCat, bool admin) {
    final ru = _rules;
    final key = _cat;
    String n(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    final shopT = key.isEmpty ? ru.shopProfit : ru.shopProfitFor(catName);
    final webT = key.isEmpty ? ru.onlineProfitMin : ru.onlineMinFor(catName);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(key.isEmpty ? 'All categories — sales' : '$catName — sales',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
            ),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: false, label: Text('This month')),
                ButtonSegment(value: true, label: Text('Last month')),
              ],
              selected: {_lastMonth},
              onSelectionChanged: (v) => setState(() {
                _lastMonth = v.first;
                _salesFuture = null;
              }),
            ),
          ]),
          FutureBuilder<Map<String, CategorySales>>(
            future: _sales(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Padding(
                    padding: const EdgeInsets.only(top: 8), child: Text('Could not load sales: ${snap.error}'));
              }
              final all = snap.data;
              if (all == null) {
                return const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()));
              }
              final c = key.isEmpty ? CategorySales.sum(all.values) : (all[key] ?? CategorySales());
              final t = c.total;
              if (t.revenue <= 0) {
                return const Padding(
                    padding: EdgeInsets.only(top: 8), child: Text('No sales in this month yet.'));
              }
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _partsBlock('Shop', c.shop, shopT),
                if (c.online.revenue > 0) _partsBlock('Online', c.online, webT),
                if (c.online.revenue > 0) _partsBlock('Total', t, shopT),
                const SizedBox(height: 4),
                const Text('Cost and commission are real; expenses use the price rules.',
                    style: TextStyle(fontSize: 11, color: Colors.black54)),
              ]);
            },
          ),
          if (key.isNotEmpty) ...[
            const Divider(height: 20),
            Text(
              'Profit for $catName: shop ${n(shopT)}% · online ${n(webT)}–${n(ru.onlineMaxFor(catName))}%'
              '${ru.hasCategoryProfit(catName) ? ' (own setting)' : ''}',
              style: const TextStyle(fontSize: 12.5),
            ),
            if (admin)
              Wrap(spacing: 8, runSpacing: 4, children: [
                OutlinedButton.icon(
                  onPressed: () => _categoryProfit(catName),
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('Change profit'),
                ),
                FilledButton.icon(
                  onPressed: () => _applyRulePrices(catName, inCat),
                  icon: const Icon(Icons.price_change_outlined, size: 18),
                  label: const Text('Use rule prices'),
                ),
              ]),
          ] else
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Choose a category to change its profit or use rule prices.',
                  style: TextStyle(fontSize: 11.5, color: Colors.black54)),
            ),
        ]),
      ),
    );
  }

  Future<void> _categoryProfit(String catName) async {
    final ru = _rules;
    final shop = TextEditingController(text: ru.shopProfitFor(catName).toString());
    final online = TextEditingController(text: ru.onlineMinFor(catName).toString());
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Profit — $catName'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: shop,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Shop profit % (normal ${ru.shopProfit})'),
          ),
          TextField(
            controller: online,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Online profit % — lowest (normal ${ru.onlineProfitMin})'),
          ),
          const SizedBox(height: 8),
          const Text('Then tap "Use rule prices" to see the new prices before saving them.',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'reset'), child: const Text('Back to normal')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Save')),
        ],
      ),
    );
    if (r == null) return;
    final next = r == 'reset'
        ? ru.withCategoryProfit(catName)
        : ru.withCategoryProfit(catName,
            shop: double.tryParse(shop.text.trim()) ?? ru.shopProfitFor(catName),
            online: double.tryParse(online.text.trim()) ?? ru.onlineMinFor(catName));
    await PriceRules.save(next);
    if (mounted) setState(() => _rules = next);
  }

  /// Rule prices for every product in the category — see them, untick any,
  /// then save. Cost and expenses fixed; to meet a lower market price the
  /// commission and profit are cut in the same proportion.
  Future<void> _applyRulePrices(String catName, List<_Row> rows) async {
    final changes = <_Change>[];
    for (final r in rows) {
      if (r.cost <= 0) continue;
      final newShop = r.suggestShop;
      final newWeb = r.online ? r.plan.price : r.web;
      final shopChanged = newShop > 0 && (newShop - r.shop).abs() >= 1;
      final webChanged = r.online && newWeb > 0 && (newWeb - r.web).abs() >= 1;
      if (shopChanged || webChanged) changes.add(_Change(r, shopChanged ? newShop : null, webChanged ? newWeb : null));
    }
    if (changes.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('All $catName prices already follow the rules.')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        final n = changes.where((c) => c.use).length;
        return AlertDialog(
          title: Text('Rule prices — $catName'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(shrinkWrap: true, children: [
              const Text('Untick any product you want to keep as it is.',
                  style: TextStyle(fontSize: 12, color: Colors.black54)),
              for (final c in changes)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: c.use,
                  onChanged: (v) => setD(() => c.use = v ?? false),
                  title: Text((c.r.p['name'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text([
                    if (c.shop != null) 'Shop ${rs(c.r.shop)} → ${rs(c.shop!)}',
                    if (c.web != null)
                      'Online ${rs(c.r.web)} → ${rs(c.web!)}'
                          '${c.r.plan.commissionCut ? ' (commission ${pct(c.r.plan.commissionPct)}, profit ${pct(c.r.plan.profitPct)})' : ''}'
                          '${c.r.plan.kind == PlanKind.aboveMarket ? ' 🔴 still above market' : ''}',
                  ].join('\n')),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: n == 0 ? null : () => Navigator.pop(ctx, true), child: Text('Save $n')),
          ],
        );
      }),
    );
    if (ok != true) return;
    var done = 0;
    for (final c in changes.where((c) => c.use)) {
      if (c.shop != null) await _setShop(c.r, c.shop!);
      if (c.web != null) await _setWeb(c.r, c.web!, commission: c.r.plan.commissionPct);
      done++;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$done prices saved — the website updates automatically.')));
    }
  }

  /// Monthly market prices file (market_prices_YYYY-MM.csv): matched to
  /// products by name; saved as each product's market price.
  Future<void> _importMarket() async {
    String text;
    try {
      final picked = await FilePicker.platform
          .pickFiles(type: FileType.custom, allowedExtensions: ['csv'], withData: true);
      final bytes = picked?.files.single.bytes;
      if (bytes == null) return;
      text = String.fromCharCodes(bytes);
      try {
        text = const Utf8Decoder(allowMalformed: true).convert(bytes);
      } catch (_) {}
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open the file: $e')));
      return;
    }
    final rows = parseCsv(text.replaceFirst('﻿', ''));
    if (rows.length < 2) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('The file is empty.')));
      return;
    }
    final head = rows.first.map((h) => h.trim().toLowerCase()).toList();
    int col(String n) => head.indexOf(n);
    final iName = col('product_name'), iPrice = col('market_price'), iSrc = col('source'), iUrl = col('source_url');
    final iDate = col('checked_on'), iStatus = col('status');
    if (iName < 0 || iPrice < 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('This is not the market prices file (needs product_name and market_price).')));
      }
      return;
    }
    String cell(List<String> r, int i) => i >= 0 && i < r.length ? r[i].trim() : '';
    String key(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    final byName = <String, Map<String, dynamic>>{for (final p in _products) key((p['name'] ?? '').toString()): p};
    var found = 0, notFound = 0;
    final unknown = <String>[];
    for (final r in rows.skip(1)) {
      final name = cell(r, iName);
      if (name.isEmpty) continue;
      final p = byName[key(name)];
      if (p == null) {
        unknown.add(name);
        continue;
      }
      final price = double.tryParse(cell(r, iPrice).replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
      final ok = price > 0 && cell(r, iStatus).toLowerCase() != 'not_found';
      final data = <String, dynamic>{
        'market_price': ok ? price : 0,
        'market_date': cell(r, iDate),
        'market_source': cell(r, iSrc),
        'market_url': cell(r, iUrl),
      };
      await _db.updateProduct(p['id'] as String, data);
      p.addAll(data);
      ok ? found++ : notFound++;
    }
    if (!mounted) return;
    setState(() {});
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Market prices imported'),
        content: Text('$found products got a market price.\n'
            '$notFound not found — they use the rule price (🔵).'
            '${unknown.isEmpty ? '' : '\n\nNot in the app (check the name):\n${unknown.join('\n')}'}'),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ru = _rules;
    final ready = _rulesLoaded;
    final all = !ready ? <_Row>[] : _products.map(_row).toList();
    final catNames = <String, String>{};
    for (final r in all) {
      if (r.category.isNotEmpty) catNames.putIfAbsent(r.category.toLowerCase(), () => r.category);
    }
    final catKeys = catNames.keys.toList()..sort();
    if (_cat.isNotEmpty && ready && !catNames.containsKey(_cat)) _cat = '';
    final rows = all.where(_matches).toList()
      ..sort((a, b) => (a.worstGap).compareTo(b.worstGap));
    final inCat = _cat.isEmpty ? all : all.where((r) => r.category.toLowerCase() == _cat).toList();
    final below = inCat.where((r) => r.cost > 0 && (r.shopBelow || r.webBelow)).length;
    final noCost = inCat.where((r) => r.cost <= 0).length;
    final admin = UserRole.instance.isAdmin;
    String n(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      appBar: AppBar(
        title: const Text('Pricing'),
        actions: [
          if (admin)
            IconButton(tooltip: 'Import market prices (CSV)', icon: const Icon(Icons.upload_file), onPressed: _importMarket),
          if (admin) IconButton(tooltip: 'Price rules', icon: const Icon(Icons.tune), onPressed: _editRules),
        ],
      ),
      body: _loading || !ready
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(12, 10, 12, 32), children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('$below products below profit · $noCost without cost price',
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: below > 0 ? lightColor(Light.red) : lightColor(Light.green))),
                      const SizedBox(height: 6),
                      Text(
                        'Every price = cost + expenses + commission + net profit.\n'
                        '• Expenses: shop bills ${n(ru.billsPct)}% (₹${n(ru.monthlyBills)} ÷ ₹${n(ru.targetRevenue)} sales + '
                        '${n(ru.creditPct)}% credit). Online also packing ₹${n(ru.packCost)} a pack and ${n(ru.payPct)}% payment & returns.\n'
                        '• Commission (online): ${n(ru.commissionPct)}% for partners — rice ${n(ru.riceCommissionPct)}%.\n'
                        '• Profit: shop ${n(ru.shopProfit)}% · online ${n(ru.onlineProfitMin)}–${n(ru.onlineProfitMax)}%. '
                        'Delivery is charged at checkout, not in the price.\n'
                        'Tap ✏ to change a price and see the four parts change.',
                        style: const TextStyle(fontSize: 12, color: Colors.black54, height: 1.35),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  key: ValueKey('cat-$_cat'),
                  value: _cat,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    prefixIcon: Icon(Icons.category_outlined),
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(value: '', child: Text('All categories (${all.length})')),
                    for (final k in catKeys)
                      DropdownMenuItem(
                        value: k,
                        child: Text('${catNames[k]}  ·  ${all.where((r) => r.category.toLowerCase() == k).length} items',
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => _setCat(v ?? ''),
                ),
                const SizedBox(height: 6),
                _salesCard(catNames[_cat] ?? '', inCat, admin),
                const SizedBox(height: 6),
                Wrap(spacing: 6, children: [
                  for (final f in _Filter.values)
                    ChoiceChip(
                      label: Text(switch (f) {
                        _Filter.below => 'Below profit',
                        _Filter.aboveMarket => 'Above market',
                        _Filter.costUp => 'Cost went up',
                        _Filter.all => 'All',
                        _Filter.noCost => 'No cost price',
                      }),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                ]),
                const SizedBox(height: 6),
                TextField(
                  decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search), hintText: 'Search products', isDense: true, border: OutlineInputBorder()),
                  onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
                ),
                const SizedBox(height: 8),
                if (rows.isEmpty)
                  const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('Nothing here — well done.'))),
                for (final r in rows) _card(r, admin),
              ]),
            ),
    );
  }

  Widget _card(_Row r, bool admin) {
    final unit = (r.p['unit'] ?? '').toString();
    final per = unit.isEmpty ? '' : ' / $unit';
    Widget priceBlock(String label, double price, PriceBreak b, double target, double suggest, VoidCallback onEdit,
        {Widget? extra}) {
      final c = r.cost <= 0 ? Colors.blueGrey : lightColor(Pricing.light(b.profitPct, target, 0));
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            SizedBox(width: 56, child: Text(label, style: const TextStyle(fontSize: 12.5, color: Colors.black54))),
            Expanded(
              child: Text.rich(TextSpan(children: [
                TextSpan(text: '${rs(price)}$per', style: const TextStyle(fontWeight: FontWeight.w700)),
                if (r.cost > 0)
                  TextSpan(text: '  →  profit ${pct(b.profitPct)}', style: TextStyle(fontWeight: FontWeight.w800, color: c)),
              ])),
            ),
            if (admin)
              IconButton(
                tooltip: 'Change price',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_outlined, size: 20),
                onPressed: onEdit,
              ),
          ]),
          if (extra != null) extra,
          if (r.cost > 0 && price > 0) _BreakTable(b, target: target, compact: true),
          if (r.cost > 0 && suggest > 0 && (suggest - price).abs() >= 1)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('Rule price ${rs(suggest)}', style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
            ),
        ]),
      );
    }

    Widget? marketLine;
    if (r.online && r.cost > 0) {
      final up = r.aboveMarket;
      final cut = r.plan.commissionCut;
      final text = r.market > 0
          ? '${up ? '🔴' : '🟢'} Market ${rs(r.market)}${up ? ' — you are above' : ' — you are at or below'}'
              '${cut ? ' · rule price ${rs(r.plan.price)} with commission ${pct(r.plan.commissionPct)}, profit ${pct(r.plan.profitPct)}' : ''}'
          : '🔵 No market price yet — rule price ${rs(r.plan.price)}';
      marketLine = Padding(
        padding: const EdgeInsets.only(left: 56, top: 2),
        child: Text(text, style: const TextStyle(fontSize: 11.5)),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: admin ? () => _openInInventory(r) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text((r.p['name'] ?? '').toString(),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
              ),
              if (admin)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('Inventory', style: TextStyle(fontSize: 11.5, color: AppTheme.primary, fontWeight: FontWeight.w600)),
                    Icon(Icons.chevron_right, size: 18, color: AppTheme.primary),
                  ]),
                ),
            ]),
            Text(
              '${r.category.isEmpty ? 'No category' : r.category} · '
              '${r.cost > 0 ? 'cost ${rs(r.cost)}$per' : 'no cost price — add it in Inventory'}'
              '${r.costPrev > 0 && r.cost > r.costPrev ? ' (up from ${rs(r.costPrev)})' : ''}',
              style: TextStyle(
                  fontSize: 12,
                  color: r.costPrev > 0 && r.cost > r.costPrev ? lightColor(Light.orange) : Colors.black54),
            ),
            priceBlock('Shop', r.shop, r.shopBreak, r.shopTarget, r.suggestShop, () => _editPrice(r, web: false)),
            if (r.online)
              priceBlock('Online', r.web, r.webBreak, r.webTarget, r.suggestWeb, () => _editPrice(r, web: true),
                  extra: marketLine),
            if (r.online && r.offer > 0 && r.cost > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 56),
                child: Text(
                  'Offer ${rs(r.offer)} → profit ${pct(r.offerBreak.profitPct)}',
                  style: TextStyle(
                      fontSize: 12, color: r.offerBreak.profit < 0 ? lightColor(Light.red) : Colors.black54),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Cost · Expenses · Commission · Net profit — in ₹ and % of the price.
class _BreakTable extends StatelessWidget {
  final PriceBreak b;
  final double target;
  final bool compact;
  const _BreakTable(this.b, {required this.target, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final profitColor = b.profit < 0
        ? lightColor(Light.red)
        : b.profitPct < target - 0.5
            ? lightColor(Light.orange)
            : lightColor(Light.green);
    String money(double v) => '₹${v.toStringAsFixed(v.abs() >= 100 || v % 1 == 0 ? 0 : 1)}';
    Widget cell(String head, double v, double p, {Color? color}) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: EdgeInsets.symmetric(vertical: compact ? 4 : 8, horizontal: 2),
            decoration: BoxDecoration(
              color: (color ?? Colors.blueGrey).withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(children: [
              Text(head, style: const TextStyle(fontSize: 10.5, color: Colors.black54)),
              Text(money(v),
                  style: TextStyle(fontSize: compact ? 12 : 13.5, fontWeight: FontWeight.w800, color: color)),
              Text(pct(p), style: TextStyle(fontSize: 10.5, color: color ?? Colors.black54)),
            ]),
          ),
        );
    return Padding(
      padding: EdgeInsets.only(left: compact ? 52 : 0, right: compact ? 8 : 0, top: 4),
      child: Row(children: [
        cell('Cost', b.cost, b.costPct),
        cell('Expenses', b.expenses, b.expensesPct),
        cell('Commission', b.commission, b.commissionPct),
        cell('Net profit', b.profit, b.profitPct, color: profitColor),
      ]),
    );
  }
}

class _Row {
  final Map<String, dynamic> p;
  final double cost, shop, suggestShop, web, suggestWeb, market, offer, costPrev, shopTarget, webTarget;
  final PriceBreak shopBreak, webBreak, offerBreak;
  final OnlinePlan plan;
  final String category;
  final bool perKg, online;
  _Row({
    required this.p,
    required this.cost,
    required this.category,
    required this.perKg,
    required this.shop,
    required this.shopBreak,
    required this.suggestShop,
    required this.online,
    required this.web,
    required this.webBreak,
    required this.suggestWeb,
    required this.market,
    required this.plan,
    required this.offer,
    required this.offerBreak,
    required this.costPrev,
    required this.shopTarget,
    required this.webTarget,
  });

  bool get aboveMarket => online && market > 0 && web > market + 0.5;
  bool get shopBelow => cost > 0 && shopBreak.profitPct < shopTarget - 0.5;
  bool get webBelow => online && cost > 0 && webBreak.profitPct < webTarget - 0.5;

  /// Lowest first.
  double get worstGap {
    if (cost <= 0) return 1000.0;
    final a = shopBreak.profitPct - shopTarget;
    final b = online ? webBreak.profitPct - webTarget : 1000.0;
    return a < b ? a : b;
  }
}

class _Change {
  final _Row r;
  final double? shop, web;
  bool use = true;
  _Change(this.r, this.shop, this.web);
}
