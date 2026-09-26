import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:url_launcher/url_launcher.dart';
import '../db/db_helper.dart';
import '../services/web_store_service.dart';
import '../utils/app_theme.dart';
import '../utils/formatters.dart';
import '../utils/keyed_stream.dart';
import '../utils/user_role.dart';
import 'vendors_screen.dart';

const _statusLabel = {
  'requested': 'New',
  'confirmed': 'Confirmed',
  'delivered': 'Delivered',
  'paid': 'Paid',
  'cancelled': 'Cancelled',
};
const _statusColor = {
  'requested': Color(0xFFE36A06),
  'confirmed': Color(0xFF7C3AED),
  'delivered': Color(0xFF16619A),
  'paid': Color(0xFF1E6F5C),
  'cancelled': Color(0xFF6B7280),
};
const _nextStatus = {'requested': 'confirmed', 'confirmed': 'delivered', 'delivered': 'paid'};
const _nextLabel = {'requested': 'Confirm order', 'confirmed': 'Mark delivered', 'delivered': 'Mark paid'};

DateTime? _orderTime(Map<String, dynamic> o) {
  final ts = o['createdAt'];
  if (ts is Timestamp) return ts.toDate();
  return DateTime.tryParse((o['clientTime'] ?? '').toString());
}

String _when(Map<String, dynamic> o) {
  final t = _orderTime(o);
  if (t == null) return '';
  final hh = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final mm = t.minute.toString().padLeft(2, '0');
  return '${formatDay(t.toIso8601String())}, $hh:$mm ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// Orders placed on the web store, live.
class OnlineOrdersScreen extends StatefulWidget {
  const OnlineOrdersScreen({super.key});

  @override
  State<OnlineOrdersScreen> createState() => _OnlineOrdersScreenState();
}

class _OnlineOrdersScreenState extends State<OnlineOrdersScreen> {
  final _svc = WebStoreService.instance;
  final _ordersStream = KeyedStream<List<Map<String, dynamic>>>();
  final _productsStream = KeyedStream<List<Map<String, dynamic>>>();
  final _settingsStream = KeyedStream<Map<String, dynamic>>();
  String _filter = 'requested';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      appBar: AppBar(title: const Text('Online Orders')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _ordersStream.get(0, _svc.watchOrders),
        builder: (context, oSnap) {
          if (oSnap.hasError) {
            return ErrorState(message: 'Could not load orders.\n${oSnap.error}');
          }
          if (!oSnap.hasData) return const Center(child: CircularProgressIndicator());
          return StreamBuilder<List<Map<String, dynamic>>>(
            stream: _productsStream.get(0, _svc.watchProducts),
            builder: (context, pSnap) {
              return StreamBuilder<Map<String, dynamic>>(
                stream: _settingsStream.get(0, _svc.watchSettings),
                builder: (context, sSnap) {
                  final orders = oSnap.data!;
                  final byId = {
                    for (final p in (pSnap.data ?? const <Map<String, dynamic>>[])) p['id'] as String: p
                  };
                  final settings = sSnap.data ?? const <String, dynamic>{};
                  final counts = <String, int>{};
                  for (final o in orders) {
                    final s = (o['status'] ?? 'requested').toString();
                    counts[s] = (counts[s] ?? 0) + 1;
                  }
                  final shown = _filter == 'all'
                      ? orders
                      : orders.where((o) => (o['status'] ?? 'requested') == _filter).toList();
                  return Column(
                    children: [
                      SizedBox(
                        height: 52,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                          children: [
                            for (final s in [...WebStoreService.statuses, 'all'])
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(s == 'all'
                                      ? 'All (${orders.length})'
                                      : '${_statusLabel[s]} (${counts[s] ?? 0})'),
                                  selected: _filter == s,
                                  onSelected: (_) => setState(() => _filter = s),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: shown.isEmpty
                            ? EmptyState(
                                icon: Icons.shopping_bag_outlined,
                                title: _filter == 'requested' ? 'No new orders' : 'No orders here',
                                message: _filter == 'requested'
                                    ? 'New web store orders appear here the moment they are placed.'
                                    : 'Try another filter above.',
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
                                itemCount: shown.length,
                                itemBuilder: (context, i) => _orderCard(shown[i], byId, settings),
                              ),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _orderCard(Map<String, dynamic> o, Map<String, Map<String, dynamic>> byId,
      Map<String, dynamic> settings) {
    final status = (o['status'] ?? 'requested').toString();
    final check = WebStoreService.priceCheck(o, byId);
    final mismatch = byId.isNotEmpty && check.any((c) => c['ok'] != true);
    final customer = Map<String, dynamic>.from((o['customer'] as Map?) ?? const {});
    final wa = (o['whatsapp_count'] as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        onTap: () => _openOrder(o, byId, settings),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text((customer['name'] ?? '').toString(),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                Text(formatCurrency((o['total'] as num?) ?? 0),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 4),
            Text('${o['orderNo'] ?? o['id']} · ${_when(o)}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _pill(_statusLabel[status] ?? status, _statusColor[status] ?? Colors.grey),
                _pill(o['fulfilment'] == 'pickup' ? 'Pickup' : 'Delivery', Colors.blueGrey),
                _pill(o['payment'] == 'upi' ? 'UPI' : 'Cash on delivery', Colors.blueGrey),
                if (mismatch) _pill('Price check', AppTheme.danger),
                if (o['sale_id'] != null) _pill('Sale recorded', AppTheme.profit),
                if (wa > 0) _pill('WhatsApp ×$wa', const Color(0xFF128C7E)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w600)),
      );

  void _openOrder(Map<String, dynamic> o, Map<String, Map<String, dynamic>> byId,
      Map<String, dynamic> settings) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _OrderSheet(order: o, productsById: byId, settings: settings),
    );
  }
}

class _OrderSheet extends StatefulWidget {
  final Map<String, dynamic> order;
  final Map<String, Map<String, dynamic>> productsById;
  final Map<String, dynamic> settings;
  const _OrderSheet({required this.order, required this.productsById, required this.settings});

  @override
  State<_OrderSheet> createState() => _OrderSheetState();
}

class _OrderSheetState extends State<_OrderSheet> {
  final _svc = WebStoreService.instance;
  late Map<String, dynamic> _o = widget.order;
  bool _busy = false;

  String get _id => _o['id'] as String;
  String get _status => (_o['status'] ?? 'requested').toString();
  Map<String, dynamic> get _customer => Map<String, dynamic>.from((_o['customer'] as Map?) ?? const {});
  Map<String, dynamic> get _store => Map<String, dynamic>.from((widget.settings['store'] as Map?) ?? const {});

  Future<void> _setStatus(String s) async {
    if (s == 'cancelled') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cancel this order?'),
          content: Text(_o['sale_id'] != null
              ? 'A sale was already recorded for it. That sale stays in Sales — cancel it there too if needed.'
              : 'The customer should be told on WhatsApp.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancel order')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    await _svc.setOrderStatus(_id, s);
    if (mounted) setState(() {
      _busy = false;
      _o = {..._o, 'status': s};
    });
  }

  Future<String?> _askLanguage() => showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Message language'),
          children: [
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'en'), child: const Text('English')),
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'ta'), child: const Text('தமிழ்')),
          ],
        ),
      );

  String _message(String lang) {
    final items = WebStoreService.priceCheck(_o, widget.productsById);
    final ta = lang == 'ta';
    final shop = ((ta ? _store['nameLocal'] : null) ?? _store['name'] ?? 'our shop').toString();
    final lines = <String>[
      ta ? 'வணக்கம் ${_customer['name']},' : 'Hello ${_customer['name']},',
      '',
      ta
          ? '$shop-இல் உங்கள் ஆர்டர் ${_o['orderNo']} உறுதிசெய்யப்பட்டது.'
          : 'Your order ${_o['orderNo']} with $shop is confirmed.',
      '',
      for (final i in items)
        '• ${i['name']} (${i['pack']}) × ${(i['qty'] as double).toStringAsFixed(0)} = ${formatCurrency((i['ordered_price'] as double) * (i['qty'] as double))}',
      '',
      '${ta ? 'மொத்தம்' : 'Total'}: ${formatCurrency((_o['total'] as num?) ?? 0)}',
      if (_o['fulfilment'] == 'pickup')
        ta
            ? 'கடையில் பெற்றுக்கொள்ளவும்${(_store['pickupAddress'] ?? '').toString().isEmpty ? '' : ': ${_store['pickupAddress']}'}'
            : 'Pickup from the shop${(_store['pickupAddress'] ?? '').toString().isEmpty ? '' : ': ${_store['pickupAddress']}'}'
      else
        ta
            ? 'டெலிவரி: ${_customer['address']} ${_customer['area']}'.trim()
            : 'Delivery to: ${_customer['address']} ${_customer['area']}'.trim(),
      if (_o['payment'] == 'upi')
        ta
            ? 'UPI மூலம் செலுத்தவும்${(_store['upiId'] ?? '').toString().isEmpty ? '' : ': ${_store['upiId']}'}'
            : 'Please pay by UPI${(_store['upiId'] ?? '').toString().isEmpty ? '' : ' to ${_store['upiId']}'}'
      else
        ta ? 'டெலிவரியின் போது பணம் செலுத்தலாம்.' : 'Payment: cash on delivery.',
      '',
      ta ? 'நன்றி!' : 'Thank you!',
    ];
    return lines.join('\n');
  }

  Future<void> _sendWhatsApp() async {
    final phone = (_customer['phone'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.length != 10) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('This order has no valid phone number.')));
      return;
    }
    final lang = await _askLanguage();
    if (lang == null) return;
    final url = Uri.parse('https://wa.me/91$phone?text=${Uri.encodeComponent(_message(lang))}');
    try {
      final launched = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (launched) {
        await _svc.logOrderWhatsApp(_id, lang);
        if (mounted) {
          setState(() => _o = {..._o, 'whatsapp_count': ((_o['whatsapp_count'] as num?)?.toInt() ?? 0) + 1});
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open WhatsApp')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open WhatsApp: $e')));
      }
    }
  }

  Future<void> _recordSale() async {
    final check = WebStoreService.priceCheck(_o, widget.productsById);
    if (check.any((c) => c['product'] == null)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('An item in this order is no longer in Inventory, so it can\'t be recorded automatically.')));
      return;
    }
    final mismatch = check.any((c) => c['ok'] != true);
    final appTotal = check.fold<double>(0, (s, c) => s + (c['current_price'] as double) * (c['qty'] as double));
    final orderTotal =
        check.fold<double>(0, (s, c) => s + (c['ordered_price'] as double) * (c['qty'] as double));
    final vendors = await DBHelper.instance.getVendors();
    if (!mounted) return;
    final phone = (_customer['phone'] ?? '').toString();
    String digits(String s) {
      final d = s.replaceAll(RegExp(r'[^0-9]'), '');
      return d.length > 10 ? d.substring(d.length - 10) : d;
    }

    final matched = vendors.where((v) => digits((v['phone'] ?? '').toString()) == phone).toList();
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _RecordSaleDialog(
        vendors: vendors,
        suggestedVendorId: matched.isEmpty ? null : matched.first['id'] as String,
        mismatch: mismatch,
        appTotal: appTotal,
        orderTotal: orderTotal,
      ),
    );
    if (result == null) return;
    setState(() => _busy = true);
    try {
      final useApp = result['use_app_prices'] == true;
      final credit = result['payment'] == 'CREDIT';
      final total = useApp ? appTotal : orderTotal;
      final saleId = await DBHelper.instance.createSale(
        items: [
          for (final c in check)
            {
              'product_id': c['id'],
              'product_name': ((c['product'] as Map)['name'] ?? c['name']).toString(),
              'quantity': c['qty'],
              'unit_price': useApp ? c['current_price'] : c['ordered_price'],
            }
        ],
        discount: 0,
        paymentType: credit ? 'CREDIT' : 'CASH',
        vendorId: credit ? result['vendor_id'] as String? : null,
        paidAmount: credit ? 0 : total,
        notes: 'Web order ${_o['orderNo']}',
      );
      await _svc.linkSale(_id, saleId, confirm: _status == 'requested');
      if (mounted) {
        setState(() => _o = {
              ..._o,
              'sale_id': saleId,
              if (_status == 'requested') 'status': 'confirmed',
            });
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sale recorded — stock and reports are updated.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not record the sale: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final check = WebStoreService.priceCheck(_o, widget.productsById);
    final mismatch = widget.productsById.isNotEmpty && check.any((c) => c['ok'] != true);
    final canEdit = UserRole.instance.isAdmin;
    final log = ((_o['whatsapp_log'] as List?) ?? const []).cast<dynamic>().reversed.toList();
    final next = _nextStatus[_status];
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        children: [
          Text((_customer['name'] ?? '').toString(),
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text('${_o['orderNo'] ?? _id} · ${_when(_o)} · ${_statusLabel[_status] ?? _status}',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          _info(Icons.phone_outlined, (_customer['phone'] ?? '').toString()),
          if (_o['fulfilment'] == 'pickup')
            _info(Icons.storefront_outlined, 'Pickup from shop')
          else
            _info(Icons.local_shipping_outlined, '${_customer['address'] ?? ''} ${_customer['area'] ?? ''}'.trim()),
          _info(Icons.payments_outlined, _o['payment'] == 'upi' ? 'UPI' : 'Cash on delivery'),
          if ((_o['note'] ?? '').toString().isNotEmpty) _info(Icons.sticky_note_2_outlined, _o['note'].toString()),
          const Divider(height: 28),
          for (final c in check) _itemRow(c),
          const SizedBox(height: 6),
          Row(
            children: [
              const Expanded(child: Text('Order total', style: TextStyle(fontWeight: FontWeight.bold))),
              Text(formatCurrency((_o['total'] as num?) ?? 0),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          if (mismatch)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: AppTheme.danger.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
              child: const Text(
                'Some prices differ from today\'s prices in the app (shown in red). The price may have '
                'changed after the customer ordered — or the page was altered. Check before confirming.',
                style: TextStyle(fontSize: 12.5, height: 1.35, color: AppTheme.danger),
              ),
            ),
          const SizedBox(height: 18),
          if (canEdit) ...[
            FilledButton.icon(
              onPressed: _busy ? null : _sendWhatsApp,
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF128C7E), minimumSize: const Size.fromHeight(48)),
              icon: const Icon(Icons.chat_outlined),
              label: const Text('Send confirmation on WhatsApp'),
            ),
            const SizedBox(height: 8),
            if (next != null && _status != 'cancelled')
              OutlinedButton(
                onPressed: _busy ? null : () => _setStatus(next),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                child: Text(_nextLabel[_status]!),
              ),
            if (_o['sale_id'] == null && _status != 'cancelled') ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _recordSale,
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Record as sale'),
              ),
            ],
            if (_status != 'cancelled' && _status != 'paid')
              TextButton(
                onPressed: _busy ? null : () => _setStatus('cancelled'),
                style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
                child: const Text('Cancel order'),
              ),
          ],
          if (log.isNotEmpty) ...[
            const Divider(height: 28),
            Text('WhatsApp messages sent: ${log.length}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            for (final e in log.take(10))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${formatDay(((e as Map)['at'] ?? '').toString())} · ${e['lang'] == 'ta' ? 'தமிழ்' : 'English'}',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _info(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: Colors.grey.shade600),
            const SizedBox(width: 10),
            Expanded(child: Text(text.isEmpty ? '—' : text, style: const TextStyle(fontSize: 13.5))),
          ],
        ),
      );

  Widget _itemRow(Map<String, dynamic> c) {
    final ordered = c['ordered_price'] as double;
    final current = c['current_price'] as double?;
    final qty = c['qty'] as double;
    final ok = c['ok'] == true || widget.productsById.isEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('${c['pack']} × ${qty.toStringAsFixed(0)} at ${formatCurrency(ordered)}',
                    style: TextStyle(fontSize: 12, color: ok ? Colors.grey.shade600 : AppTheme.danger)),
                if (!ok)
                  Text(
                    current == null
                        ? 'No longer in Inventory'
                        : 'App price today: ${formatCurrency(current)}',
                    style: const TextStyle(fontSize: 12, color: AppTheme.danger, fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),
          Text(formatCurrency(ordered * qty), style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _RecordSaleDialog extends StatefulWidget {
  final List<Map<String, dynamic>> vendors;
  final String? suggestedVendorId;
  final bool mismatch;
  final double appTotal;
  final double orderTotal;
  const _RecordSaleDialog({
    required this.vendors,
    required this.suggestedVendorId,
    required this.mismatch,
    required this.appTotal,
    required this.orderTotal,
  });

  @override
  State<_RecordSaleDialog> createState() => _RecordSaleDialogState();
}

class _RecordSaleDialogState extends State<_RecordSaleDialog> {
  late String _payment = widget.suggestedVendorId != null ? 'CREDIT' : 'CASH';
  late String? _vendorId = widget.suggestedVendorId;
  late List<Map<String, dynamic>> _vendors = widget.vendors;
  bool _useAppPrices = true;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Record as sale'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Stock is reduced and the sale appears in Sales and Reports.',
                style: TextStyle(fontSize: 12.5)),
            const SizedBox(height: 12),
            if (widget.mismatch) ...[
              RadioListTile<bool>(
                value: true,
                groupValue: _useAppPrices,
                contentPadding: EdgeInsets.zero,
                title: Text('Use today\'s app prices (${formatCurrency(widget.appTotal)})'),
                onChanged: (v) => setState(() => _useAppPrices = v!),
              ),
              RadioListTile<bool>(
                value: false,
                groupValue: _useAppPrices,
                contentPadding: EdgeInsets.zero,
                title: Text('Use the ordered prices (${formatCurrency(widget.orderTotal)})'),
                onChanged: (v) => setState(() => _useAppPrices = v!),
              ),
              const Divider(),
            ],
            RadioListTile<String>(
              value: 'CASH',
              groupValue: _payment,
              contentPadding: EdgeInsets.zero,
              title: const Text('Paid (cash or UPI)'),
              onChanged: (v) => setState(() => _payment = v!),
            ),
            RadioListTile<String>(
              value: 'CREDIT',
              groupValue: _payment,
              contentPadding: EdgeInsets.zero,
              title: const Text('On credit to a vendor'),
              onChanged: (v) => setState(() => _payment = v!),
            ),
            if (_payment == 'CREDIT') ...[
              DropdownButtonFormField<String>(
                value: _vendors.any((v) => v['id'] == _vendorId) ? _vendorId : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Vendor'),
                items: [
                  for (final v in _vendors)
                    DropdownMenuItem(value: v['id'] as String, child: Text((v['name'] ?? '').toString())),
                ],
                onChanged: (v) => setState(() => _vendorId = v),
              ),
              if (widget.suggestedVendorId != null)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('Matched by the customer\'s phone number.',
                      style: TextStyle(fontSize: 11.5, color: AppTheme.profit)),
                ),
              TextButton.icon(
                onPressed: () async {
                  final id = await showAddVendorDialog(context);
                  if (id == null) return;
                  final list = await DBHelper.instance.getVendors();
                  if (mounted) setState(() {
                    _vendors = list;
                    _vendorId = id;
                  });
                },
                icon: const Icon(Icons.person_add_alt, size: 18),
                label: const Text('Add new vendor'),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: (_payment == 'CREDIT' && _vendorId == null)
              ? null
              : () => Navigator.pop(context, {
                    'payment': _payment,
                    'vendor_id': _vendorId,
                    'use_app_prices': !widget.mismatch || _useAppPrices,
                  }),
          child: const Text('Record sale'),
        ),
      ],
    );
  }
}

/// Dashboard bell: live count of new web orders, with a vibration and
/// sound when a new one arrives while the app is open (any screen).
class NewOrdersBell extends StatefulWidget {
  const NewOrdersBell({super.key});

  @override
  State<NewOrdersBell> createState() => _NewOrdersBellState();
}

class _NewOrdersBellState extends State<NewOrdersBell> {
  late final Stream<int> _count = WebStoreService.instance.watchNewOrderCount();
  int? _last;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _count,
      builder: (context, snap) {
        final n = snap.data ?? 0;
        if (snap.hasData) {
          if (_last != null && n > _last!) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              HapticFeedback.heavyImpact();
              SystemSound.play(SystemSoundType.click);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: const Text('New web store order'),
                  action: SnackBarAction(
                    label: 'Open',
                    onPressed: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => const OnlineOrdersScreen())),
                  ),
                ));
              }
            });
          }
          _last = n;
        }
        return IconButton(
          tooltip: 'Online orders',
          icon: Badge(
            isLabelVisible: n > 0,
            label: Text('$n'),
            child: const Icon(Icons.shopping_bag_outlined),
          ),
          onPressed: () =>
              Navigator.push(context, MaterialPageRoute(builder: (_) => const OnlineOrdersScreen())),
        );
      },
    );
  }
}
