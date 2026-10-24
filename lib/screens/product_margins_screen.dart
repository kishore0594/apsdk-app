import 'package:flutter/material.dart';
import '../db/db_helper.dart';
import '../services/finance_service.dart';
import '../services/pricing.dart';
import '../services/web_store_service.dart';
import '../utils/app_theme.dart';
import '../utils/user_role.dart';
import 'finance_screen.dart' show rs, pct, lightColor;
import 'finance_settings_screen.dart';

/// Pricing: every product's shop (offline) and online margin against its
/// target, with the suggested prices and one tap to apply them. Online
/// margin is what's left after the payment fee, risk & returns and the
/// packing & handling cost — so online sales earn the same target.
class ProductMarginsScreen extends StatefulWidget {
  const ProductMarginsScreen({super.key});

  @override
  State<ProductMarginsScreen> createState() => _ProductMarginsScreenState();
}

enum _Filter { below, costUp, all, noCost }

class _ProductMarginsScreenState extends State<ProductMarginsScreen> {
  final _db = DBHelper.instance;
  List<Map<String, dynamic>> _products = [];
  Pricing? _pricing;
  bool _loading = true;
  String _search = '';
  _Filter _filter = _Filter.below;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await Future.wait([_db.getProducts(), Pricing.load()]);
      if (!mounted) return;
      setState(() {
        _products = r[0] as List<Map<String, dynamic>>;
        _pricing = r[1] as Pricing;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static double _n(Object? v) => v is num ? v.toDouble() : 0.0;

  _Row _row(Map<String, dynamic> p) {
    final pr = _pricing!;
    final cost = _n(p['cost_price']);
    final cat = FinanceService.tidy(p['category'] as String?);
    final perKg = FinanceService.perKgUnit(p);
    final shop = _n(p['selling_price']);
    final web = WebStoreService.priceOf(p);
    final offer = _n(p['offer_price']);
    final online = WebStoreService.isOnline(p);
    final t = pr.target(cat);
    return _Row(
      p: p,
      cost: cost,
      category: cat,
      perKg: perKg,
      target: t,
      shop: shop,
      shopMargin: Pricing.margin(shop, cost),
      suggestShop: pr.suggestShop(cost, cat),
      online: online,
      web: web,
      webMargin: pr.onlineMargin(web, cost, perKg: perKg),
      suggestWeb: pr.suggestOnline(cost, cat, perKg: perKg),
      offer: offer > 0 && offer < web ? offer : 0.0,
      offerMargin: offer > 0 && offer < web ? pr.onlineMargin(offer, cost, perKg: perKg) : 0.0,
      costPrev: _n(p['cost_prev']),
    );
  }

  bool _matches(_Row r) {
    if (_search.isNotEmpty && !(r.p['name'] ?? '').toString().toLowerCase().contains(_search)) return false;
    switch (_filter) {
      case _Filter.below:
        return r.cost > 0 && (r.shopBelow || r.webBelow);
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

  Future<void> _applyShop(_Row r) async {
    await _db.updateProduct(r.p['id'] as String, {'selling_price': r.suggestShop});
    r.p['selling_price'] = r.suggestShop;
    setState(() {});
  }

  Future<void> _applyWeb(_Row r) async {
    await WebStoreService.instance.updateProductWeb(r.p['id'] as String, {'web_price': r.suggestWeb});
    r.p['web_price'] = r.suggestWeb;
    setState(() {});
  }

  Future<void> _applyAll(List<_Row> rows) async {
    final shopN = rows.where((r) => r.shopBelow).length;
    final webN = rows.where((r) => r.webBelow).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apply all suggested prices?'),
        content: Text('$shopN shop prices and $webN online prices will be raised to reach their margin targets. '
            'The website updates automatically.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apply')),
        ],
      ),
    );
    if (ok != true) return;
    for (final r in rows) {
      if (r.shopBelow) await _applyShop(r);
      if (r.webBelow) await _applyWeb(r);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Prices updated')));
    }
  }

  Future<void> _settings() async {
    final s = FinanceSettings.fromMap(await _db.getFinanceSettings());
    if (!mounted) return;
    final changed =
        await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => FinanceSettingsScreen(settings: s)));
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final pr = _pricing;
    final all = pr == null ? <_Row>[] : _products.map(_row).toList();
    final rows = all.where(_matches).toList()
      ..sort((a, b) => (a.worstGap).compareTo(b.worstGap));
    final below = all.where((r) => r.cost > 0 && (r.shopBelow || r.webBelow)).length;
    final noCost = all.where((r) => r.cost <= 0).length;
    final admin = UserRole.instance.isAdmin;
    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      appBar: AppBar(
        title: const Text('Pricing'),
        actions: [
          if (admin) IconButton(tooltip: 'Margin targets', icon: const Icon(Icons.tune), onPressed: _settings),
        ],
      ),
      body: _loading || pr == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(12, 10, 12, 32), children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('$below products below target · $noCost without cost price',
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: below > 0 ? lightColor(Light.red) : lightColor(Light.green))),
                      const SizedBox(height: 4),
                      Text(
                        'Shop price = cost ÷ (1 − target). Online price also covers payment fee and risk '
                        '(${pct(pr.s.onlineCostPct)}) and packing ₹${pr.s.onlinePackCost.round()} per pack'
                        '${pr.s.onlineTypicalKg != 1 ? ' (spread over ${pr.s.onlineTypicalKg} kg)' : ''}. '
                        'Prices round up to ₹1 (under ₹100) or ₹5.',
                        style: const TextStyle(fontSize: 12, color: Colors.black54, height: 1.3),
                      ),
                      if (admin && rows.any((r) => r.shopBelow || r.webBelow) && _filter != _Filter.noCost) ...[
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: () => _applyAll(rows),
                          icon: const Icon(Icons.auto_fix_high),
                          label: const Text('Apply all suggested prices in this list'),
                        ),
                      ],
                    ]),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(spacing: 6, children: [
                  for (final f in _Filter.values)
                    ChoiceChip(
                      label: Text(switch (f) {
                        _Filter.below => 'Below target',
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
    final floor = _pricing!.s.billMinMargin;
    final unit = (r.p['unit'] ?? '').toString();
    final per = unit.isEmpty ? '' : ' / $unit';
    Widget priceLine(String label, double price, double margin, double suggest, bool below, VoidCallback onApply) {
      final c = r.cost <= 0 ? Colors.blueGrey : lightColor(Pricing.light(margin, r.target, floor));
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(children: [
          SizedBox(width: 56, child: Text(label, style: const TextStyle(fontSize: 12.5, color: Colors.black54))),
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: '${rs(price)}$per', style: const TextStyle(fontWeight: FontWeight.w700)),
              if (r.cost > 0) TextSpan(text: '  →  ${pct(margin)}', style: TextStyle(fontWeight: FontWeight.w800, color: c)),
            ])),
          ),
          if (r.cost > 0 && below)
            admin
                ? OutlinedButton(
                    onPressed: onApply,
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                    child: Text('Use ${rs(suggest)}'),
                  )
                : Text('Suggest ${rs(suggest)}', style: const TextStyle(fontSize: 12.5)),
        ]),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text((r.p['name'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
          Text(
            '${r.category.isEmpty ? 'No category' : r.category} · target ${pct(r.target)} · '
            '${r.cost > 0 ? 'cost ${rs(r.cost)}$per' : 'no cost price — add it in Inventory'}'
            '${r.costPrev > 0 && r.cost > r.costPrev ? ' (up from ${rs(r.costPrev)})' : ''}',
            style: TextStyle(
                fontSize: 12,
                color: r.costPrev > 0 && r.cost > r.costPrev ? lightColor(Light.orange) : Colors.black54),
          ),
          priceLine('Shop', r.shop, r.shopMargin, r.suggestShop, r.shopBelow, () => _applyShop(r)),
          if (r.online)
            priceLine('Online', r.web, r.webMargin, r.suggestWeb, r.webBelow, () => _applyWeb(r)),
          if (r.online && r.offer > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 56),
              child: Text(
                'Offer ${rs(r.offer)} → ${pct(r.offerMargin)}${r.offerMargin < floor ? '  ⚠ below the ${pct(floor)} minimum' : ''}',
                style: TextStyle(
                    fontSize: 12, color: r.offerMargin < floor ? lightColor(Light.red) : Colors.black54),
              ),
            ),
          if (r.online && r.perKg && r.cost > 0) _packs(r),
        ]),
      ),
    );
  }

  /// Small web packs carry the same packing cost, so their margin is lower.
  Widget _packs(_Row r) {
    final pr = _pricing!;
    final price = r.offer > 0 ? r.offer : r.web;
    final parts = [
      for (final kg in const [0.25, 0.5, 1.0, 5.0])
        '${kg < 1 ? '${(kg * 1000).round()} g' : '${kg.round()} kg'} ${pct(pr.packMargin(price, r.cost, kg))}',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 56),
      child: Text('Web packs: ${parts.join(' · ')}', style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
    );
  }
}

class _Row {
  final Map<String, dynamic> p;
  final double cost, target, shop, shopMargin, suggestShop, web, webMargin, suggestWeb, offer, offerMargin, costPrev;
  final String category;
  final bool perKg, online;
  _Row({
    required this.p,
    required this.cost,
    required this.category,
    required this.perKg,
    required this.target,
    required this.shop,
    required this.shopMargin,
    required this.suggestShop,
    required this.online,
    required this.web,
    required this.webMargin,
    required this.suggestWeb,
    required this.offer,
    required this.offerMargin,
    required this.costPrev,
  });

  bool get shopBelow => cost > 0 && shopMargin < target - 0.5 && suggestShop > shop;
  bool get webBelow => online && cost > 0 && webMargin < target - 0.5 && suggestWeb > web;

  /// Lowest first.
  double get worstGap {
    if (cost <= 0) return 1000.0;
    final a = shopMargin - target;
    final b = online ? webMargin - target : 1000.0;
    return a < b ? a : b;
  }
}
