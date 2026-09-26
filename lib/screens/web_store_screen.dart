import 'package:flutter/material.dart';
import '../services/web_store_service.dart';
import '../utils/app_theme.dart';
import '../utils/formatters.dart';
import '../utils/keyed_stream.dart';
import '../utils/user_role.dart';
import 'web_content_screen.dart';

/// Manage the web store entirely from the app: shop details, categories,
/// and which products appear online (with Tamil name, pack label, offer
/// price and display order). Prices, stock and photos come straight from
/// Inventory — nothing is typed twice.
class WebStoreScreen extends StatefulWidget {
  const WebStoreScreen({super.key});

  @override
  State<WebStoreScreen> createState() => _WebStoreScreenState();
}

class _WebStoreScreenState extends State<WebStoreScreen> {
  final _svc = WebStoreService.instance;
  final _settingsStream = KeyedStream<Map<String, dynamic>>();
  final _productsStream = KeyedStream<List<Map<String, dynamic>>>();
  String _query = '';

  bool get _canEdit => UserRole.instance.isAdmin;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      appBar: AppBar(title: const Text('Web Store')),
      body: StreamBuilder<Map<String, dynamic>>(
        stream: _settingsStream.get(0, _svc.watchSettings),
        builder: (context, sSnap) {
          return StreamBuilder<List<Map<String, dynamic>>>(
            stream: _productsStream.get(0, _svc.watchProducts),
            builder: (context, pSnap) {
              if (!sSnap.hasData || !pSnap.hasData) {
                if (sSnap.hasError || pSnap.hasError) {
                  return ErrorState(message: 'Could not load the web store.\n${sSnap.error ?? pSnap.error}');
                }
                return const Center(child: CircularProgressIndicator());
              }
              final settings = sSnap.data!;
              final products = [...pSnap.data!]
                ..sort((a, b) => (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()));
              final warnings = WebStoreService.warnings(products, settings);
              final online = products.where(WebStoreService.isOnline).length;
              final shown = products
                  .where((p) => (p['name'] ?? '').toString().toLowerCase().contains(_query.toLowerCase()))
                  .toList();
              return ListView(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
                children: [
                  _syncCard(online, products.length),
                  for (final w in warnings)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _notice(w),
                    ),
                  const SizedBox(height: 12),
                  AppCard(
                    padding: const EdgeInsets.all(14),
                    onTap: () {
                      final present = products.map(WebStoreService.categoryOf).toSet().toList()..sort();
                      Navigator.push(context,
                          MaterialPageRoute(builder: (_) => WebContentScreen(categories: present)));
                    },
                    child: Row(
                      children: [
                        const IconBadge(icon: Icons.web_outlined, color: AppTheme.primary, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Website content',
                                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                              const SizedBox(height: 2),
                              Text('Offer banners, delivery note, trust lines, owner story, contact, category photos',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: Colors.black38),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  _sectionTitle('Shop details'),
                  _shopCard(settings),
                  const SizedBox(height: 18),
                  _sectionTitle('Categories'),
                  _categoriesCard(products, settings),
                  const SizedBox(height: 18),
                  _sectionTitle('Products on the web store'),
                  TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search products',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _query = v.trim()),
                  ),
                  const SizedBox(height: 10),
                  for (final p in shown) _productTile(p),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      );

  Widget _notice(String text) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, size: 18, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5, height: 1.35))),
          ],
        ),
      );

  Widget _syncCard(int online, int total) {
    return ValueListenableBuilder<WebSyncState>(
      valueListenable: _svc.sync,
      builder: (context, state, _) {
        final (IconData icon, Color color, String title) = switch (state) {
          WebSyncState.upToDate => (Icons.cloud_done_outlined, AppTheme.profit, 'Web store is up to date'),
          WebSyncState.pending => (Icons.schedule, Colors.orange, 'Changes will publish in a moment'),
          WebSyncState.publishing => (Icons.cloud_upload_outlined, AppTheme.accent, 'Publishing…'),
          WebSyncState.error => (Icons.error_outline, AppTheme.danger, 'Publishing failed — tap Publish now'),
          WebSyncState.idle => (Icons.cloud_outlined, Colors.grey, _canEdit ? 'Checking…' : 'Published by master accounts'),
        };
        return AppCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              IconBadge(icon: icon, color: color, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text('$online of $total products online · publishes automatically after changes',
                        style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              if (_canEdit)
                TextButton(
                  onPressed: state == WebSyncState.publishing ? null : _svc.publishNow,
                  child: const Text('Publish now'),
                ),
            ],
          ),
        );
      },
    );
  }

  // ---------------- Shop details ----------------

  Widget _shopCard(Map<String, dynamic> settings) {
    final store = Map<String, dynamic>.from((settings['store'] as Map?) ?? const {});
    String v(String k) => (store[k] ?? '').toString();
    final areas = ((store['deliveryAreas'] as List?) ?? const []).join(', ');
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                  width: 110,
                  child: Text(label, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600))),
              Expanded(
                  child: Text(value.isEmpty ? 'Not set' : value,
                      style: TextStyle(
                          fontSize: 13, color: value.isEmpty ? Colors.orange.shade800 : null))),
            ],
          ),
        );
    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: _canEdit ? () => _editShop(store) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row('Shop name', v('name')),
          row('Tamil name', v('nameLocal')),
          row('WhatsApp', v('whatsapp')),
          row('UPI ID', v('upiId')),
          row('Minimum order', (store['minOrder'] ?? 0) == 0 ? 'None' : formatCurrency(store['minOrder'] as num)),
          row('Delivery areas', areas),
          row('Pickup address', v('pickupAddress')),
          if (_canEdit)
            const Align(
              alignment: Alignment.centerRight,
              child: Text('Tap to edit', style: TextStyle(fontSize: 11.5, color: AppTheme.accent)),
            ),
        ],
      ),
    );
  }

  Future<void> _editShop(Map<String, dynamic> store) async {
    final c = <String, TextEditingController>{
      for (final k in ['name', 'nameLocal', 'tagline', 'whatsapp', 'upiId', 'pickupAddress'])
        k: TextEditingController(text: (store[k] ?? '').toString()),
    };
    final minCtrl = TextEditingController(text: ((store['minOrder'] ?? 0) as num).toString());
    final areasCtrl =
        TextEditingController(text: ((store['deliveryAreas'] as List?) ?? const []).join(', '));
    Widget f(String k, String label, {TextInputType? type, String? hint}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
            controller: c[k],
            keyboardType: type,
            decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder()),
          ),
        );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Shop details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              f('name', 'Shop name'),
              f('nameLocal', 'Shop name in Tamil'),
              f('tagline', 'Tagline'),
              f('whatsapp', 'WhatsApp number', type: TextInputType.phone, hint: '919876543210'),
              f('upiId', 'UPI ID', hint: 'shop@upi'),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: minCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Minimum order (₹, 0 = none)', border: OutlineInputBorder()),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: areasCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Delivery areas',
                      hintText: 'Separate with commas; empty = no area choice',
                      border: OutlineInputBorder()),
                ),
              ),
              f('pickupAddress', 'Pickup address'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    final wa = c['whatsapp']!.text.replaceAll(RegExp(r'[^0-9]'), '');
    await _svc.saveSettings({
      'store': {
        'name': c['name']!.text.trim(),
        'nameLocal': c['nameLocal']!.text.trim(),
        'tagline': c['tagline']!.text.trim(),
        'whatsapp': wa.length == 10 ? '91$wa' : wa,
        'upiId': c['upiId']!.text.trim(),
        'minOrder': double.tryParse(minCtrl.text.trim()) ?? 0,
        'deliveryAreas': areasCtrl.text
            .split(',')
            .map((a) => a.trim())
            .where((a) => a.isNotEmpty)
            .toList(),
        'pickupAddress': c['pickupAddress']!.text.trim(),
      }
    });
  }

  // ---------------- Categories ----------------

  Widget _categoriesCard(List<Map<String, dynamic>> products, Map<String, dynamic> settings) {
    final present = products.map(WebStoreService.categoryOf).toSet();
    final order = ((settings['category_order'] as List?) ?? const [])
        .map((e) => e.toString())
        .where(present.contains)
        .toList();
    for (final c in present.toList()..sort()) {
      if (!order.contains(c)) order.add(c);
    }
    final hidden = ((settings['hidden_categories'] as List?) ?? const []).map((e) => e.toString()).toSet();
    final local = Map<String, dynamic>.from((settings['categories_local'] as Map?) ?? const {});
    if (order.isEmpty) {
      return const AppCard(
        padding: EdgeInsets.all(14),
        child: Text('Categories appear here once products have a category in Inventory.'),
      );
    }
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < order.length; i++)
            ListTile(
              dense: true,
              title: Text(order[i], style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text((local[order[i]] ?? '').toString().isEmpty
                  ? (_canEdit ? 'Tap to add Tamil name' : '')
                  : local[order[i]].toString()),
              onTap: _canEdit ? () => _editCategoryLocal(order[i], (local[order[i]] ?? '').toString()) : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_canEdit) ...[
                    IconButton(
                      tooltip: 'Move up',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.arrow_upward, size: 18),
                      onPressed: i == 0
                          ? null
                          : () {
                              final o = [...order];
                              final t = o[i - 1];
                              o[i - 1] = o[i];
                              o[i] = t;
                              _svc.saveSettings({'category_order': o});
                            },
                    ),
                  ],
                  Switch(
                    value: !hidden.contains(order[i]),
                    onChanged: _canEdit
                        ? (on) {
                            final h = {...hidden};
                            on ? h.remove(order[i]) : h.add(order[i]);
                            _svc.saveSettings({'hidden_categories': h.toList()});
                          }
                        : null,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _editCategoryLocal(String category, String current) async {
    final ctrl = TextEditingController(text: current);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Tamil name for $category'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (v == null) return;
    await _svc.saveSettings({
      'categories_local': {category: v}
    });
  }

  // ---------------- Products ----------------

  Widget _productTile(Map<String, dynamic> p) {
    final online = WebStoreService.isOnline(p);
    final price = WebStoreService.priceOf(p);
    final webPrice = WebStoreService.webPriceOf(p);
    final qty = (p['quantity'] as num?)?.toDouble() ?? 0;
    final subtitle = <String>[
      WebStoreService.packLabel(p),
      price <= 0
          ? 'No price'
          : (webPrice < price ? '${formatCurrency(webPrice)} (offer)' : formatCurrency(price)),
      qty > 0 ? 'In stock' : 'Out of stock',
      if ((p['name_local'] ?? '').toString().isNotEmpty) p['name_local'].toString(),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
        onTap: _canEdit ? () => _editProductWeb(p) : null,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text((p['name'] ?? '').toString(),
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: online ? null : Colors.grey.shade500)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                ],
              ),
            ),
            Switch(
              value: p['web_visible'] != false,
              onChanged: (_canEdit && price > 0)
                  ? (on) => _svc.updateProductWeb(p['id'] as String, {'web_visible': on})
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editProductWeb(Map<String, dynamic> p) async {
    final tamil = TextEditingController(text: (p['name_local'] ?? '').toString());
    final pack = TextEditingController(text: (p['web_pack'] ?? '').toString());
    final offer = TextEditingController(
        text: ((p['offer_price'] as num?)?.toDouble() ?? 0) > 0 ? (p['offer_price'] as num).toString() : '');
    final order = TextEditingController(text: ((p['web_order'] as num?)?.toInt() ?? '').toString());
    final desc = TextEditingController(text: (p['web_desc'] ?? '').toString());
    final descTa = TextEditingController(text: (p['web_desc_local'] ?? '').toString());
    final details = TextEditingController(
        text: ((p['web_details'] as List?) ?? const []).map((d) => d.toString()).join('\n'));
    bool homemade = p['web_homemade'] == true;
    bool bestseller = p['web_bestseller'] == true;
    bool isNew = p['web_new'] == true;
    final price = WebStoreService.priceOf(p);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text((p['name'] ?? '').toString(), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Selling price ${formatCurrency(price)} per ${(p['unit'] ?? 'unit')} — change it in Inventory.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 16),
            TextField(
                controller: tamil,
                decoration: const InputDecoration(labelText: 'Tamil name', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(
              controller: pack,
              decoration: InputDecoration(
                  labelText: 'Pack shown to customers',
                  hintText: WebStoreService.packLabel({...p, 'web_pack': ''}),
                  helperText: 'One pack = one ${p['unit'] ?? 'unit'} in Inventory, e.g. "25 kg bag"',
                  border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: offer,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Offer price (optional)',
                  helperText: 'Shown crossed-out against the selling price; must be lower',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: order,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Display order (optional)',
                  helperText: 'Lower numbers show first in their category',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
                controller: desc,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: 'Description (product page)',
                    hintText: 'High-energy pellets for milking cows',
                    border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(
                controller: descTa,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Description in Tamil', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(
                controller: details,
                maxLines: 4,
                decoration: const InputDecoration(
                    labelText: 'Details (one per line)',
                    hintText: 'Protein: 20%\nFeed 2–3 kg per cow per day',
                    border: OutlineInputBorder())),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: homemade,
              title: const Text('Homemade tag'),
              subtitle: const Text('Only for products you prepare yourself'),
              onChanged: (v) => setSheet(() => homemade = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: bestseller,
              title: const Text('Best seller'),
              subtitle: const Text('Also listed in the Best sellers row'),
              onChanged: (v) => setSheet(() => bestseller = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: isNew,
              title: const Text('New arrival'),
              subtitle: const Text('Also listed in the New arrivals row'),
              onChanged: (v) => setSheet(() => isNew = v),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
        ),
      ),
      ),
    );
    if (saved != true) return;
    final offerV = double.tryParse(offer.text.trim()) ?? 0;
    if (offerV > 0 && offerV >= price && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Offer price must be lower than the selling price — offer not saved.')));
    }
    await _svc.updateProductWeb(p['id'] as String, {
      'name_local': tamil.text.trim(),
      'web_pack': pack.text.trim(),
      'offer_price': (offerV > 0 && offerV < price) ? offerV : 0,
      'web_order': int.tryParse(order.text.trim()) ?? 999,
      'web_desc': desc.text.trim(),
      'web_desc_local': descTa.text.trim(),
      'web_details': details.text.split('\n').map((d) => d.trim()).where((d) => d.isNotEmpty).toList(),
      'web_homemade': homemade,
      'web_bestseller': bestseller,
      'web_new': isNew,
    });
  }
}
