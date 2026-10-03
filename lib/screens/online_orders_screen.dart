import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
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
  'dispatched': 'Dispatched',
  'delivered': 'Delivered',
  'paid': 'Paid',
  'cancelled': 'Cancelled',
};
const _statusColor = {
  'requested': Color(0xFFE36A06),
  'confirmed': Color(0xFF7C3AED),
  'dispatched': Color(0xFF0E7490),
  'delivered': Color(0xFF16619A),
  'paid': Color(0xFF1E6F5C),
  'cancelled': Color(0xFF6B7280),
};
const _nextStatus = {'requested': 'confirmed', 'confirmed': 'dispatched', 'dispatched': 'delivered', 'delivered': 'paid'};
const _nextLabel = {
  'requested': 'Confirm order',
  'confirmed': 'Mark dispatched',
  'dispatched': 'Mark delivered',
  'delivered': 'Mark paid',
};

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
    final check = WebStoreService.priceCheck(o, byId, WebStoreService.combosById(settings));
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
                Text(formatCurrency(WebStoreService.orderTotal(o)),
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
                if (o['payVia'] == 'whatsapp' && o['payment_verified'] != true)
                  _pill('Pays on WhatsApp', const Color(0xFF128C7E)),
                if (o['payment_verified'] == true)
                  _pill('Payment verified', AppTheme.profit)
                else if (o['proof'] == true)
                  _pill('Payment screenshot', const Color(0xFFE36A06)),
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
    if (s == 'dispatched') {
      final courier = TextEditingController(text: (_o['courier'] ?? '').toString());
      final no = TextEditingController(text: (_o['trackingNo'] ?? '').toString());
      final url = TextEditingController(text: (_o['trackingUrl'] ?? '').toString());
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Mark dispatched'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Courier details show on the customer\'s tracking page. All optional.',
                  style: TextStyle(fontSize: 12.5, color: Colors.black54)),
              const SizedBox(height: 10),
              TextField(controller: courier, decoration: const InputDecoration(labelText: 'Courier / delivery by', hintText: 'DTDC, ST Courier, own delivery…', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(controller: no, decoration: const InputDecoration(labelText: 'Tracking number', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(controller: url, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Tracking link (https://…)', border: OutlineInputBorder())),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Dispatch')),
          ],
        ),
      );
      if (go != true) return;
      setState(() => _busy = true);
      await _svc.setOrderStatus(_id, s,
          courier: courier.text.trim(), trackingNo: no.text.trim(), trackingUrl: url.text.trim());
      if (mounted) setState(() {
        _busy = false;
        _o = {..._o, 'status': s, 'courier': courier.text.trim(), 'trackingNo': no.text.trim(), 'trackingUrl': url.text.trim()};
      });
      return;
    }
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

  late final Future<String?> _proof =
      _o['proof'] == true ? _svc.paymentProof(_id) : Future<String?>.value(null);

  Widget _proofSection(bool canEdit) => FutureBuilder<String?>(
        future: _proof,
        builder: (context, snap) {
          final data = snap.data;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (snap.connectionState != ConnectionState.done)
                const Text('Loading payment screenshot…', style: TextStyle(fontSize: 12.5, color: Colors.black54))
              else if (data == null)
                const Text('Payment screenshot not available (check your connection).',
                    style: TextStyle(fontSize: 12.5, color: Colors.black54))
              else
                GestureDetector(
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (ctx) => Dialog(
                      insetPadding: const EdgeInsets.all(12),
                      child: InteractiveViewer(child: Image.memory(base64Decode(data.split(',').last))),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(base64Decode(data.split(',').last), height: 180, fit: BoxFit.contain),
                  ),
                ),
              if (canEdit && _o['payment_verified'] != true) ...[
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          await _svc.setPaymentVerified(_id);
                          if (mounted) setState(() {
                            _busy = false;
                            _o = {..._o, 'payment_verified': true};
                          });
                        },
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.profit),
                  icon: const Icon(Icons.verified_outlined),
                  label: const Text('Payment verified (money received)'),
                ),
              ],
            ]),
          );
        },
      );

  Widget _moneyRow(String label, double v, {bool bold = false, bool freeIfZero = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal))),
          Text(freeIfZero && v == 0 ? 'Free' : formatCurrency(v),
              style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.w600, fontSize: bold ? 16 : 14)),
        ]),
      );

  Future<void> _changeDelivery() async {
    final ctrl = TextEditingController(text: WebStoreService.orderDelivery(_o).toStringAsFixed(0));
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delivery charge for this order'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(prefixText: '₹ ', helperText: 'e.g. courier cost for this distance; 0 = free'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text.trim())), child: const Text('Save')),
        ],
      ),
    );
    if (v == null || v < 0) return;
    await _svc.setDeliveryCharge(_id, v);
    if (mounted) setState(() => _o = {..._o, 'delivery_charge_override': v});
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
    final ta = lang == 'ta';
    final shop = ((ta ? _store['nameLocal'] : null) ?? _store['name'] ?? 'our shop').toString();
    final items = ((_o['items'] as List?) ?? const []).map((x) => Map<String, dynamic>.from(x as Map)).toList();
    final itemsTotal = WebStoreService.orderItemsTotal(_o);
    final delivery = WebStoreService.orderDelivery(_o);
    final total = WebStoreService.orderTotal(_o);
    final pickup = _o['fulfilment'] == 'pickup';
    final upiId = (_store['upiId'] ?? '').toString();
    final qtyStr = (num q) => q == q.roundToDouble() ? q.toInt().toString() : q.toString();
    final lines = <String>[
      ta ? 'வணக்கம் ${_customer['name']} 🙏' : 'Hello ${_customer['name']} 🙏',
      ta ? '$shop-இல் ஆர்டர் செய்ததற்கு நன்றி!' : 'Thank you for ordering from $shop!',
      ta ? 'ஆர்டர் ${_o['orderNo']} — உறுதிசெய்யப்பட்டது ✅' : 'Order ${_o['orderNo']} — confirmed ✅',
      '',
      ta ? '🧾 *பொருட்கள்*' : '🧾 *Items*',
      for (var k = 0; k < items.length; k++)
        '${k + 1}. ${items[k]['name']} (${items[k]['pack']}) × ${qtyStr((items[k]['qty'] as num?) ?? 0)} = ${formatCurrency((items[k]['lineTotal'] as num?) ?? 0)}',
      '',
      '${ta ? 'பொருட்கள் மொத்தம்' : 'Items total'}: ${formatCurrency(itemsTotal)}',
      if (!pickup)
        '${ta ? 'டெலிவரி கட்டணம்' : 'Delivery charge'}: ${delivery == 0 ? (ta ? 'இலவசம்' : 'Free') : formatCurrency(delivery)}',
      '*${ta ? 'செலுத்த வேண்டிய தொகை' : 'Total to pay'}: ${formatCurrency(total)}*',
      '',
      if (pickup) ...[
        ta ? '🏪 *கடையில் பெற்றுக்கொள்ளவும்*' : '🏪 *Pickup from the shop*',
        if ((_store['pickupAddress'] ?? '').toString().isNotEmpty) _store['pickupAddress'].toString(),
      ] else ...[
        ta ? '📍 *டெலிவரி முகவரி*' : '📍 *Delivery address*',
        WebStoreService.orderAddress(_customer),
        ta
            ? 'இந்த முகவரி சரியா? *ஆம்* என பதில் அனுப்பவும், அல்லது சரியான முகவரியை அனுப்பவும்.'
            : 'Is this address correct? Please reply *YES*, or send the correct address.',
      ],
      '',
      ta ? '💳 *பணம் செலுத்துதல்*' : '💳 *Payment*',
      if (_o['payment_verified'] == true)
        ta ? '✅ உங்கள் பணம் பெறப்பட்டது. நன்றி!' : '✅ Your payment has been received. Thank you!'
      else if (_o['proof'] == true)
        ta ? '✅ பணம் செலுத்திய ஸ்கிரீன்ஷாட் கிடைத்தது.' : '✅ Payment screenshot received.'
      else if (_o['payment'] == 'upi') ...[
        upiId.isEmpty
            ? (ta ? '${formatCurrency(total)} UPI மூலம் செலுத்தவும்.' : 'Please pay ${formatCurrency(total)} by UPI.')
            : (ta ? '${formatCurrency(total)} ஐ UPI: $upiId க்கு செலுத்தவும்.' : 'Please pay ${formatCurrency(total)} to UPI: $upiId'),
        ta
            ? 'செலுத்திய பின் *பணம் செலுத்திய ஸ்கிரீன்ஷாட்டை* இங்கே அனுப்பவும் — பெற்றதும் உறுதிசெய்வோம்.'
            : 'After paying, please send the *payment screenshot* here — we will confirm once received.',
      ] else
        ta
            ? 'டெலிவரியின் போது ${formatCurrency(total)} ரொக்கமாக செலுத்தவும்.'
            : 'Please keep ${formatCurrency(total)} ready to pay in cash on delivery.',
      '',
      ta ? '📦 உங்கள் ஆர்டரை கண்காணிக்க:' : '📦 Track your order:',
      WebStoreService.trackingLink((_o['orderNo'] ?? _id).toString(), Firebase.app().options.projectId),
      '',
      '— $shop',
    ];
    return lines.join('\n');
  }

  String _receiptMessage(String lang) {
    final ta = lang == 'ta';
    final shop = ((ta ? _store['nameLocal'] : null) ?? _store['name'] ?? 'our shop').toString();
    final total = formatCurrency(WebStoreService.orderTotal(_o));
    return ta
        ? 'வணக்கம் ${_customer['name']} 🙏\nஆர்டர் ${_o['orderNo']}-க்கு $total பணம் பெற்றுக்கொண்டோம் ✅\nநன்றி!\n— $shop'
        : 'Hello ${_customer['name']} 🙏\nPayment of $total received for order ${_o['orderNo']} ✅\nThank you!\n— $shop';
  }

  Future<void> _sendWhatsApp({bool receipt = false}) async {
    final phone = (_customer['phone'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.length != 10) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('This order has no valid phone number.')));
      return;
    }
    final lang = await _askLanguage();
    if (lang == null) return;
    final url = Uri.parse('https://wa.me/91$phone?text=${Uri.encodeComponent(receipt ? _receiptMessage(lang) : _message(lang))}');
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
    final check = WebStoreService.priceCheck(_o, widget.productsById, WebStoreService.combosById(widget.settings));
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
        customerName: (_customer['name'] ?? '').toString(),
        customerPhone: phone,
        customerPlace: [_customer['city'], _customer['area']]
            .map((x) => (x ?? '').toString().trim())
            .firstWhere((x) => x.isNotEmpty && x != 'Other area', orElse: () => ''),
      ),
    );
    if (result == null) return;
    setState(() => _busy = true);
    try {
      final useApp = result['use_app_prices'] == true;
      final credit = result['payment'] == 'CREDIT';
      var vendorId = result['vendor_id'] as String?;
      if (result['save_customer'] == true && vendorId == null) {
        // New customer from the website: saved to Vendors with the order's
        // name, phone and town, exactly like adding one by hand.
        final place = (result['place'] ?? '').toString();
        vendorId = await DBHelper.instance.insertVendor({
          'name': (_customer['name'] ?? 'Web customer').toString().trim(),
          'phone': phone,
          'address': place,
          'opening_balance': 0,
          'created_at': DateTime.now().toIso8601String(),
          'source': 'web',
        });
        if (place.isNotEmpty) {
          try {
            await DBHelper.instance.addVendorPlace(place);
          } catch (_) {/* place list is a convenience only */}
        }
      }
      final total = useApp ? appTotal : orderTotal;
      final saleId = await DBHelper.instance.createSale(
        items: [
          for (final c in check)
            {
              'product_id': c['id'],
              'product_name': ((c['product'] as Map)['name'] ?? c['name']).toString(),
              // Inventory quantity in app units (kg for weight items),
              // priced per unit so the sale total matches the order.
              'quantity': c['units'],
              'unit_price': ((useApp ? c['current_price'] : c['ordered_price']) as double) / (c['per_pack'] as double),
            }
        ],
        discount: 0,
        paymentType: credit ? 'CREDIT' : 'CASH',
        // Linked for paid sales too, so the sale shows in the customer's history.
        vendorId: vendorId,
        paidAmount: credit ? 0 : total + WebStoreService.orderDelivery(_o),
        notes: 'Web order ${_o['orderNo']}',
        deliveryCharge: WebStoreService.orderDelivery(_o),
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
    final check = WebStoreService.priceCheck(_o, widget.productsById, WebStoreService.combosById(widget.settings));
    final mismatch = widget.productsById.isNotEmpty && check.any((c) => c['ok'] != true);
    final canEdit = UserRole.instance.isAdmin;
    final log = ((_o['whatsapp_log'] as List?) ?? const []).cast<dynamic>().reversed.toList();
    // Pickup orders skip "Dispatched".
    final next = (_nextStatus[_status] == 'dispatched' && _o['fulfilment'] == 'pickup')
        ? 'delivered'
        : _nextStatus[_status];
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
            _info(Icons.local_shipping_outlined, WebStoreService.orderAddress(_customer)),
          _info(Icons.payments_outlined, [
            _o['payment'] == 'upi' ? 'UPI' : 'Cash on delivery',
            if ((_o['paymentRef'] ?? '').toString().isNotEmpty) 'Ref ${_o['paymentRef']}',
            if (_o['payment_verified'] == true) 'verified ✓',
          ].join(' · ')),
          if (_o['proof'] == true) _proofSection(canEdit),
          if ((_o['weightKg'] as num?) != null && _o['fulfilment'] != 'pickup')
            _info(Icons.scale_outlined, 'Parcel weight: ${(_o['weightKg'] as num).toString()} kg'),
          if ((_o['note'] ?? '').toString().isNotEmpty) _info(Icons.sticky_note_2_outlined, _o['note'].toString()),
          const Divider(height: 28),
          for (final c in check) _itemRow(c),
          const SizedBox(height: 6),
          _moneyRow('Items', WebStoreService.orderItemsTotal(_o)),
          if (_o['fulfilment'] != 'pickup')
            InkWell(
              onTap: canEdit ? _changeDelivery : null,
              child: _moneyRow(
                canEdit ? 'Delivery charge (tap to change)' : 'Delivery charge',
                WebStoreService.orderDelivery(_o),
                freeIfZero: true,
              ),
            ),
          _moneyRow('Total to pay', WebStoreService.orderTotal(_o), bold: true),
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
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _sendWhatsApp(receipt: true),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('Send "payment received" on WhatsApp'),
            ),
            const SizedBox(height: 8),
            if (next != null && _status != 'cancelled')
              OutlinedButton(
                onPressed: _busy ? null : () => _setStatus(next),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                child: Text(next == 'delivered' && _status == 'confirmed' ? 'Mark picked up' : _nextLabel[_status]!),
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
  final String customerName;
  final String customerPhone;
  final String customerPlace;
  const _RecordSaleDialog({
    required this.vendors,
    required this.suggestedVendorId,
    required this.mismatch,
    required this.appTotal,
    required this.orderTotal,
    required this.customerName,
    required this.customerPhone,
    required this.customerPlace,
  });

  @override
  State<_RecordSaleDialog> createState() => _RecordSaleDialogState();
}

class _RecordSaleDialogState extends State<_RecordSaleDialog> {
  late String _payment = widget.suggestedVendorId != null ? 'CREDIT' : 'CASH';
  late String? _vendorId = widget.suggestedVendorId;
  late List<Map<String, dynamic>> _vendors = widget.vendors;
  bool _useAppPrices = true;
  // New web customers are saved to Vendors unless the shop switches it off.
  late bool _saveCustomer = widget.suggestedVendorId == null;

  @override
  Widget build(BuildContext context) {
    final isNew = widget.suggestedVendorId == null;
    final usingNew = isNew && _saveCustomer && (_payment == 'CASH' || _vendorId == null);
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
            if (isNew)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _saveCustomer,
                title: Text('Save ${widget.customerName.isEmpty ? 'customer' : widget.customerName} to Vendors'),
                subtitle: Text([
                  widget.customerPhone,
                  if (widget.customerPlace.isNotEmpty) widget.customerPlace,
                ].join(' · ')),
                onChanged: (v) => setState(() {
                  _saveCustomer = v;
                  if (v) _vendorId = null;
                }),
              )
            else
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text('Already in Vendors — matched by phone number.',
                    style: TextStyle(fontSize: 12, color: AppTheme.profit)),
              ),
            if (_payment == 'CREDIT' && !usingNew) ...[
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
          onPressed: (_payment == 'CREDIT' && _vendorId == null && !usingNew)
              ? null
              : () => Navigator.pop(context, {
                    'payment': _payment,
                    'vendor_id': usingNew ? null : _vendorId,
                    'save_customer': usingNew,
                    'place': widget.customerPlace,
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
