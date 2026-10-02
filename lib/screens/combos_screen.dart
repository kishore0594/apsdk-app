import 'package:flutter/material.dart';
import '../services/web_store_service.dart';
import '../utils/app_theme.dart';
import '../utils/formatters.dart';
import '../utils/keyed_stream.dart';
import '../utils/tamil_names.dart';
import '../utils/user_role.dart';
import 'offer_alerts_screen.dart';

/// Combo offers for the web store: pick products, set a combo price.
/// The shop's maximum discount % is enforced here and again at publish.
class CombosScreen extends StatefulWidget {
  const CombosScreen({super.key});

  @override
  State<CombosScreen> createState() => _CombosScreenState();
}

class _CombosScreenState extends State<CombosScreen> {
  final _svc = WebStoreService.instance;
  final _settings = KeyedStream<Map<String, dynamic>>();
  final _products = KeyedStream<List<Map<String, dynamic>>>();

  bool get _canEdit => UserRole.instance.isAdmin;

  Future<void> _saveCombos(List<Map<String, dynamic>> combos) => _svc.saveSettings({'combos': combos});

  Future<void> _editMax(double current) async {
    final ctrl = TextEditingController(text: current.toStringAsFixed(0));
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Maximum combo discount'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(suffixText: '%', helperText: 'No combo can be priced below this discount'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text.trim())),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (v == null || v <= 0 || v >= 90) return;
    await _svc.saveSettings({'maxComboDiscount': v});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      appBar: AppBar(title: const Text('Combo offers')),
      body: StreamBuilder<Map<String, dynamic>>(
        stream: _settings.get(0, _svc.watchSettings),
        builder: (context, sSnap) => StreamBuilder<List<Map<String, dynamic>>>(
          stream: _products.get(0, _svc.watchProducts),
          builder: (context, pSnap) {
            if (sSnap.hasError || pSnap.hasError) {
              return ErrorState(message: 'Could not load combos.\n${sSnap.error ?? pSnap.error}');
            }
            if (!sSnap.hasData || !pSnap.hasData) return const Center(child: CircularProgressIndicator());
            final settings = sSnap.data!;
            final products = pSnap.data!;
            final byId = {for (final p in products) p['id'] as String: p};
            final combos = WebStoreService.combosOf(settings);
            final maxD = WebStoreService.maxComboDiscount(settings);
            return ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 90),
              children: [
                AppCard(
                  padding: const EdgeInsets.all(14),
                  onTap: _canEdit ? () => _editMax(maxD) : null,
                  child: Row(children: [
                    const IconBadge(icon: Icons.shield_outlined, color: AppTheme.primary, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Maximum discount: ${maxD.toStringAsFixed(0)}%',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                        const SizedBox(height: 2),
                        Text('Combos above this discount can\'t be saved or published',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      ]),
                    ),
                    if (_canEdit) const Icon(Icons.edit_outlined, size: 18, color: Colors.black45),
                  ]),
                ),
                const SizedBox(height: 14),
                if (combos.isEmpty)
                  const EmptyState(
                    icon: Icons.local_offer_outlined,
                    title: 'No combos yet',
                    message: 'Bundle 2 or more products at a special price — e.g. a Millet Starter Pack.',
                  ),
                for (var i = 0; i < combos.length; i++) _comboTile(combos, i, byId, maxD),
              ],
            );
          },
        ),
      ),
      floatingActionButton: _canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _openEditor(null),
              icon: const Icon(Icons.add),
              label: const Text('New combo'),
            )
          : null,
    );
  }

  Widget _comboTile(List<Map<String, dynamic>> combos, int i, Map<String, Map<String, dynamic>> byId, double maxD) {
    final c = combos[i];
    final normal = WebStoreService.comboNormal(c, byId);
    final price = (c['price'] as num?)?.toDouble() ?? 0;
    final problem = WebStoreService.comboProblem(c, byId, maxD);
    final contents = [
      for (final raw in (c['items'] as List? ?? const []))
        () {
          final it = Map<String, dynamic>.from(raw as Map);
          final p = byId[it['id']];
          return p == null ? '(deleted)' : '${p['name']} ${WebStoreService.comboItemLabel(p, (it['qty'] as num).toDouble())}';
        }(),
    ].join(' + ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        onTap: _canEdit ? () => _openEditor(i) : null,
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((c['name'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
              const SizedBox(height: 3),
              Text(contents, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              Text(
                normal > 0
                    ? '${formatCurrency(price)} · normally ${formatCurrency(normal)} · ${((normal - price) / normal * 100).toStringAsFixed(0)}% off'
                    : formatCurrency(price),
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.profit),
              ),
              if (problem != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text('Not on the website: $problem',
                      style: const TextStyle(fontSize: 11.5, color: AppTheme.danger)),
                ),
            ]),
          ),
          if (_canEdit && problem == null && c['active'] != false)
            IconButton(
              tooltip: 'Notify customers',
              icon: const Icon(Icons.campaign_outlined, color: AppTheme.primary),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => OfferAlertsScreen(
                    title: '🌾 New combo: ${(c['name'] ?? '').toString()}',
                    body: '$contents — only ${formatCurrency(price)}'
                        '${normal > price ? ' (save ${formatCurrency(normal - price)})' : ''}. Tap to order.',
                  ),
                ),
              ),
            ),
          Switch(
            value: c['active'] != false,
            onChanged: _canEdit
                ? (on) {
                    final all = [...combos];
                    all[i] = {...c, 'active': on};
                    _saveCombos(all);
                  }
                : null,
          ),
        ]),
      ),
    );
  }

  Future<void> _openEditor(int? index) async {
    final settings = await _svc.settingsRef.get().then((s) => s.data() ?? <String, dynamic>{});
    final products = await _svc.watchProducts().first;
    if (!mounted) return;
    final combos = WebStoreService.combosOf(settings);
    final result = await Navigator.push<Object>(
      context,
      MaterialPageRoute(
        builder: (_) => _ComboEditor(
          combo: index == null ? null : combos[index],
          products: products,
          maxDiscount: WebStoreService.maxComboDiscount(settings),
        ),
      ),
    );
    if (result == null) return;
    final all = [...combos];
    if (result == 'delete' && index != null) {
      all.removeAt(index);
    } else if (result is Map<String, dynamic>) {
      if (index == null) {
        all.add(result);
      } else {
        all[index] = result;
      }
    } else {
      return;
    }
    await _saveCombos(all);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved — the website updates in a few seconds')));
    }
  }
}

class _ComboEditor extends StatefulWidget {
  final Map<String, dynamic>? combo;
  final List<Map<String, dynamic>> products;
  final double maxDiscount;
  const _ComboEditor({required this.combo, required this.products, required this.maxDiscount});

  @override
  State<_ComboEditor> createState() => _ComboEditorState();
}

class _ComboEditorState extends State<_ComboEditor> {
  late final _name = TextEditingController(text: (widget.combo?['name'] ?? '').toString());
  late final _nameTa = TextEditingController(text: (widget.combo?['nameLocal'] ?? '').toString());
  late final _price = TextEditingController(
      text: widget.combo?['price'] == null ? '' : (widget.combo!['price'] as num).toString());
  late final Map<String, double> _qty = {
    for (final raw in (widget.combo?['items'] as List? ?? const []))
      (raw as Map)['id'] as String: (raw['qty'] as num).toDouble(),
  };
  String _query = '';

  List<Map<String, dynamic>> get _online =>
      widget.products.where(WebStoreService.isOnline).toList()
        ..sort((a, b) => (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()));

  Map<String, Map<String, dynamic>> get _byId => {for (final p in widget.products) p['id'] as String: p};

  Map<String, dynamic> _draft() => {
        'id': (widget.combo?['id'] ?? 'c${DateTime.now().millisecondsSinceEpoch}').toString(),
        'name': _name.text.trim(),
        'nameLocal': _nameTa.text.trim(),
        'items': [
          for (final e in _qty.entries)
            if (e.value > 0) {'id': e.key, 'qty': e.value}
        ],
        'price': double.tryParse(_price.text.trim()) ?? 0,
        'active': widget.combo?['active'] != false,
      };

  // kg products move in 250 g steps (0.25 kg), e.g. 250 g trial packs.
  double _step(Map<String, dynamic> p) => WebStoreService.sellsByWeight(p) ? 0.25 : 1;

  @override
  Widget build(BuildContext context) {
    final draft = _draft();
    final normal = WebStoreService.comboNormal(draft, _byId);
    final price = (draft['price'] as double);
    final problem = _name.text.trim().isEmpty
        ? 'Give the combo a name'
        : WebStoreService.comboProblem(draft, _byId, widget.maxDiscount);
    final shown = _online
        .where((p) => (p['name'] ?? '').toString().toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      appBar: AppBar(
        title: Text(widget.combo == null ? 'New combo' : 'Edit combo'),
        actions: [
          if (widget.combo != null)
            IconButton(
              tooltip: 'Delete combo',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Delete this combo?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                    ],
                  ),
                );
                if (ok == true && context.mounted) Navigator.pop(context, 'delete');
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 120),
        children: [
          TextField(
            controller: _name,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
                labelText: 'Combo name', hintText: 'Millet Starter Pack', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _nameTa,
            decoration: InputDecoration(
                labelText: 'Name in Tamil (optional)',
                hintText: autoTamil(_name.text) ?? '',
                border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          const Text('Products in this combo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
          const SizedBox(height: 6),
          TextField(
            decoration: const InputDecoration(
                hintText: 'Search products', prefixIcon: Icon(Icons.search), isDense: true, border: OutlineInputBorder()),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
          const SizedBox(height: 6),
          for (final p in shown) _productRow(p),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(blurRadius: 12, color: Colors.black12)]),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Combo price (₹)', isDense: true, border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('Normal ${formatCurrency(normal)}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                if (normal > 0 && price > 0 && price < normal)
                  Text('${((normal - price) / normal * 100).toStringAsFixed(1)}% off',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.profit)),
              ]),
            ]),
            if (problem != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(problem, style: const TextStyle(fontSize: 12, color: AppTheme.danger)),
              ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: problem == null ? () => Navigator.pop(context, _draft()) : null,
              child: const Text('Save combo'),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _productRow(Map<String, dynamic> p) {
    final id = p['id'] as String;
    final q = _qty[id] ?? 0;
    final step = _step(p);
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 8, 2),
        child: Row(children: [
          Checkbox(
            value: q > 0,
            onChanged: (on) => setState(() => on == true ? _qty[id] = (step < 1 ? 0.25 : 1) : _qty.remove(id)),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((p['name'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                '${formatCurrency(WebStoreService.webPriceOf(p))} per ${WebStoreService.sellsByWeight(p) ? 'kg' : WebStoreService.packLabel(p)}',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
              ),
            ]),
          ),
          if (q > 0) ...[
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: () => setState(() => q - step <= 0 ? _qty.remove(id) : _qty[id] = q - step),
            ),
            Text(WebStoreService.comboItemLabel(p, q), style: const TextStyle(fontWeight: FontWeight.w700)),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => setState(() => _qty[id] = q + step),
            ),
          ],
        ]),
      ),
    );
  }
}
