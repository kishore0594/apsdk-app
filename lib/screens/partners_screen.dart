import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../db/db_helper.dart';
import '../services/partners.dart';
import '../services/pricing.dart';
import '../utils/app_theme.dart';
import '../utils/user_role.dart';

String _money(double v) {
  final r = (v * 100).roundToDouble() / 100;
  final f = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: r % 1 == 0 ? 0 : 2);
  return f.format(r);
}

String _day(String iso) {
  final d = DateTime.tryParse(iso);
  return d == null ? '' : DateFormat('d MMM').format(d);
}

String _digits(String phone) {
  final d = phone.replaceAll(RegExp(r'[^0-9]'), '');
  return d.length > 10 ? d.substring(d.length - 10) : d;
}

/// Partners: friends who bring new customers and earn a commission.
class PartnersScreen extends StatelessWidget {
  const PartnersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final admin = UserRole.instance.isAdmin;
    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      appBar: AppBar(title: const Text('Partners')),
      floatingActionButton: admin
          ? FloatingActionButton.extended(
              onPressed: () => _editPartner(context, null),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Add partner'),
            )
          : null,
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: Partners.instance.watchPartners(),
        builder: (context, snap) {
          final list = snap.data ?? const <Map<String, dynamic>>[];
          return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 96), children: [
            const _RulesCard(),
            const SizedBox(height: 8),
            if (snap.connectionState == ConnectionState.waiting && list.isEmpty)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
            if (snap.hasData && list.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No partners yet. Tap "Add partner" — each one gets their own link and QR code.',
                    textAlign: TextAlign.center),
              ),
            for (final p in list) _PartnerTile(p),
          ]);
        },
      ),
    );
  }
}

class _RulesCard extends StatelessWidget {
  const _RulesCard();

  @override
  Widget build(BuildContext context) {
    final r = PriceRules.cached;
    String n(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return Card(
      color: const Color(0xFFF1F7EE),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('How partners earn', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 6),
          Text(
            '• ${n(r.commissionPct)}% on millets, millet flour, grams & nuts\n'
            '• ${n(r.riceCommissionPct)}% on rice · ₹${n(r.bagCommission)} per cattle-feed bag\n'
            '• Only NEW customers, for ${Partners.linkDays} days — online orders and shop bills\n'
            '• "Waiting" until the customer pays, then "Earned"; cancelled bills drop out\n'
            '• Pay monthly by UPI — saved as a Marketing expense',
            style: const TextStyle(fontSize: 12.5, height: 1.45),
          ),
        ]),
      ),
    );
  }
}

class _PartnerTile extends StatefulWidget {
  final Map<String, dynamic> p;
  const _PartnerTile(this.p);

  @override
  State<_PartnerTile> createState() => _PartnerTileState();
}

class _PartnerTileState extends State<_PartnerTile> {
  late Future<PartnerAccount> _acc = Partners.instance.account(widget.p['id'] as String);

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final active = p['active'] != false;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: active ? AppTheme.primary : Colors.grey,
          foregroundColor: Colors.white,
          child: Text((p['name'] ?? '?').toString().trim().isEmpty ? '?' : p['name'].toString().trim()[0].toUpperCase()),
        ),
        title: Text('${p['name'] ?? ''}${active ? '' : '  (paused)'}', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: FutureBuilder<PartnerAccount>(
          future: _acc,
          builder: (_, s) {
            final a = s.data;
            return Text(a == null
                ? 'Code ${p['code'] ?? ''}'
                : 'Code ${p['code'] ?? ''} · ${a.customers.length} customers · due ${_money(a.due)}'
                    '${a.pending > 0 ? ' · waiting ${_money(a.pending)}' : ''}');
          },
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => PartnerDetailScreen(partner: p)));
          if (mounted) {
            setState(() {
              _acc = Partners.instance.account(p['id'] as String);
            });
          }
        },
      ),
    );
  }
}

/// Add (partner == null) or edit a partner.
Future<void> _editPartner(BuildContext context, Map<String, dynamic>? partner) async {
  final name = TextEditingController(text: (partner?['name'] ?? '').toString());
  final phone = TextEditingController(text: (partner?['phone'] ?? '').toString());
  final upi = TextEditingController(text: (partner?['upi'] ?? '').toString());
  final place = TextEditingController(text: (partner?['place'] ?? '').toString());
  var active = partner?['active'] != false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Text(partner == null ? 'Add partner' : 'Edit partner'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
            TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'WhatsApp number')),
            TextField(controller: upi, decoration: const InputDecoration(labelText: 'UPI ID (for paying commission)')),
            TextField(controller: place, decoration: const InputDecoration(labelText: 'Place')),
            if (partner != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                subtitle: const Text('Paused partners keep what they earned'),
                value: active,
                onChanged: (v) => setD(() => active = v),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isEmpty || _digits(phone.text).length != 10) {
                ScaffoldMessenger.of(ctx)
                    .showSnackBar(const SnackBar(content: Text('Enter a name and a 10-digit phone number')));
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  if (ok != true) return;
  if (partner == null) {
    final existing = await Partners.instance.getPartners().catchError((_) => <Map<String, dynamic>>[]);
    await Partners.instance.addPartner(
      name: name.text,
      phone: _digits(phone.text),
      upi: upi.text,
      place: place.text,
      takenCodes: existing.map((e) => (e['code'] ?? '').toString()),
    );
  } else {
    await Partners.instance.updatePartner(partner['id'] as String, {
      'name': name.text.trim(),
      'phone': _digits(phone.text),
      'upi': upi.text.trim(),
      'place': place.text.trim(),
      'active': active,
    });
  }
}

class PartnerDetailScreen extends StatefulWidget {
  final Map<String, dynamic> partner;
  const PartnerDetailScreen({super.key, required this.partner});

  @override
  State<PartnerDetailScreen> createState() => _PartnerDetailScreenState();
}

class _PartnerDetailScreenState extends State<PartnerDetailScreen> {
  late Map<String, dynamic> _p = widget.partner;
  late Future<PartnerAccount> _acc;
  final _qrKey = GlobalKey();
  bool _busy = false;

  String get _code => (_p['code'] ?? '').toString();
  String get _link => Partners.linkFor(_code);
  String get _phone => _digits((_p['phone'] ?? '').toString());

  @override
  void initState() {
    super.initState();
    _acc = Partners.instance.account(_p['id'] as String);
    PriceRules.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  void _reload() {
    setState(() {
      _acc = Partners.instance.account(_p['id'] as String);
    });
  }

  Future<void> _refreshPartner() async {
    final list = await Partners.instance.getPartners().catchError((_) => <Map<String, dynamic>>[]);
    final me = list.where((e) => e['id'] == _p['id']);
    if (me.isNotEmpty && mounted) setState(() => _p = me.first);
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _openWhatsApp(String text) async {
    final url = Uri.parse('https://wa.me/91$_phone?text=${Uri.encodeComponent(text)}');
    try {
      final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!ok) await Share.share(text);
    } catch (_) {
      await Share.share(text);
    }
  }

  Future<File> _captureQr() async {
    await WidgetsBinding.instance.endOfFrame;
    final boundary = _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) throw StateError('Picture not ready');
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) throw StateError('Picture not ready');
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/partner_${_code}_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(bytes.buffer.asUint8List());
    return file;
  }

  String _welcomeText() => 'Hi ${_p['name']}! 🙏\n\n'
      'Your Sri Madhura Agro Traders partner link:\n$_link\n\n'
      'Share this link or the QR picture with friends and family. When a NEW customer orders through it, '
      'you earn ${_n(PriceRules.cached.commissionPct)}% on millets, millet flour, grams & nuts '
      '(${_n(PriceRules.cached.riceCommissionPct)}% on rice) for ${Partners.linkDays} days — online and at our shop. '
      'Paid every month by UPI.\n\n'
      'உங்கள் லிங்க் / QR-ஐ நண்பர்களுடன் பகிருங்கள். புதிய வாடிக்கையாளர் வாங்கும் ஒவ்வொரு முறையும் உங்களுக்கு கமிஷன் கிடைக்கும்.';

  static String _n(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  Future<void> _sendQr() async {
    setState(() => _busy = true);
    try {
      final file = await _captureQr();
      final text = _welcomeText();
      var sent = false;
      if (_phone.length == 10) {
        try {
          final outcome = await const MethodChannel('madhura/whatsapp')
              .invokeMethod<String>('sendImage', {'phone': '91$_phone', 'text': text, 'path': file.path});
          sent = outcome == 'ok';
        } catch (_) {/* fall back to the share sheet */}
      }
      if (!sent) await Share.shareXFiles([XFile(file.path, mimeType: 'image/png')], text: text);
    } catch (e) {
      _snack('Could not share: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _statementText(PartnerAccount a) {
    final now = DateFormat('d MMM yyyy').format(DateTime.now());
    final recent = a.entries.where((e) => e.state != 'cancelled').take(10).map((e) {
      final first = e.customer.trim().split(RegExp(r'\s+')).first;
      final mark = e.state == 'earned' ? '✓' : '⏳';
      return '• ${_day(e.date)} · $first · ${_money(e.saleTotal)} → ${_money(e.commission)} $mark';
    }).join('\n');
    return '*Sri Madhura Agro Traders — Partner statement*\n'
        '${_p['name']} · code $_code · till $now\n\n'
        'New customers: ${a.customers.length}\n'
        'Orders: ${a.orders} (${_money(a.sales)})\n'
        'Earned: ${_money(a.earned)}\n'
        'Waiting for customer payment: ${_money(a.pending)}\n'
        'Paid to you: ${_money(a.paid)}\n'
        '*Due to you: ${_money(a.due < 0 ? 0 : a.due)}*\n'
        '${recent.isEmpty ? '' : '\nRecent orders:\n$recent\n'}'
        '\n✓ earned  ⏳ waiting for payment\n'
        'Your link: $_link\n'
        'Thank you! / நன்றி! 🙏';
  }

  Future<void> _pay(PartnerAccount a) async {
    final amt = TextEditingController(text: a.due > 0 ? ((a.due * 100).roundToDouble() / 100).toString() : '');
    final ref = TextEditingController();
    final upi = (_p['upi'] ?? '').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Pay ${_p['name']}'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (upi.isNotEmpty) SelectableText('UPI: $upi', style: const TextStyle(fontWeight: FontWeight.w700)),
          TextField(
            controller: amt,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(prefixText: '₹ ', labelText: 'Amount paid'),
          ),
          TextField(controller: ref, decoration: const InputDecoration(labelText: 'UPI reference (optional)')),
          const SizedBox(height: 8),
          const Text('Also saved as a Marketing expense.', style: TextStyle(fontSize: 12, color: Colors.black54)),
        ]),
        actions: [
          if (upi.isNotEmpty)
            TextButton(
              onPressed: () {
                final v = double.tryParse(amt.text.trim()) ?? 0;
                launchUrl(
                  Uri.parse('upi://pay?pa=${Uri.encodeComponent(upi)}&pn=${Uri.encodeComponent((_p['name'] ?? '').toString())}'
                      '${v > 0 ? '&am=${v.toStringAsFixed(2)}' : ''}&cu=INR&tn=${Uri.encodeComponent('Partner commission')}'),
                  mode: LaunchMode.externalApplication,
                ).catchError((_) => false);
              },
              child: const Text('Open UPI app'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save payment')),
        ],
      ),
    );
    if (ok != true) return;
    final v = double.tryParse(amt.text.trim()) ?? 0;
    if (v <= 0) {
      _snack('Enter the amount paid');
      return;
    }
    await Partners.instance.recordPayment(partner: _p, amount: v, ref: ref.text);
    _snack('Payment of ${_money(v)} saved');
    _reload();
  }

  Future<void> _linkCustomer() async {
    final vendors = await DBHelper.instance.getVendors();
    if (!mounted) return;
    var q = '';
    final picked = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        final list = vendors
            .where((v) =>
                q.isEmpty ||
                (v['name'] ?? '').toString().toLowerCase().contains(q) ||
                (v['phone'] ?? '').toString().contains(q))
            .take(60)
            .toList();
        return AlertDialog(
          title: const Text('Link a new customer'),
          content: SizedBox(
            width: double.maxFinite,
            height: 420,
            child: Column(children: [
              TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Name or phone'),
                onChanged: (v) => setD(() => q = v.trim().toLowerCase()),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: ListView(children: [
                  for (final v in list)
                    ListTile(
                      dense: true,
                      title: Text((v['name'] ?? '').toString()),
                      subtitle: Text([
                        (v['phone'] ?? '').toString(),
                        if ((v['partner_name'] ?? '').toString().isNotEmpty) 'partner: ${v['partner_name']}',
                      ].where((x) => x.isNotEmpty).join(' · ')),
                      onTap: () => Navigator.pop(ctx, v),
                    ),
                ]),
              ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
        );
      }),
    );
    if (picked == null) return;
    final other = (picked['partner_id'] ?? '').toString();
    if (other.isNotEmpty && other != _p['id'] && Partners.linkActive(picked)) {
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Already linked'),
          content: Text('${picked['name']} is linked to ${picked['partner_name']}. Move to ${_p['name']}?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Move')),
          ],
        ),
      );
      if (go != true) return;
    }
    await Partners.instance.linkCustomer(picked['id'] as String, _p);
    _snack('${picked['name']} linked for ${Partners.linkDays} days from today');
    _reload();
  }

  Future<void> _unlink(Map<String, dynamic> v) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove link?'),
        content: Text('Future bills of ${v['name']} will not earn ${_p['name']} commission. Past ones stay.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (go != true) return;
    await Partners.instance.unlinkCustomer(v['id'] as String);
    _reload();
  }

  Widget _tile(String label, double v, Color c) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(color: c.withOpacity(0.10), borderRadius: BorderRadius.circular(10)),
          child: Column(children: [
            Text(_money(v), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: c)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
          ]),
        ),
      );

  Widget _qrCard() => RepaintBoundary(
        key: _qrKey,
        child: Container(
          width: 300,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF2E7D32), width: 3),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Sri Madhura Agro Traders',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF2E7D32))),
            const Text('Millets · Millet flour · Rice · Grams & nuts',
                style: TextStyle(fontSize: 11.5, color: Colors.black54)),
            const SizedBox(height: 10),
            QrImageView(data: _link, version: QrVersions.auto, size: 200, backgroundColor: Colors.white),
            const SizedBox(height: 8),
            const Text('Scan & order online — delivered to your home',
                textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const Text('ஸ்கேன் செய்து ஆர்டர் செய்யுங்கள்', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            const Text('madhuraagro.in', style: TextStyle(fontSize: 12, color: Color(0xFF2E7D32))),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final admin = UserRole.instance.isAdmin;
    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      appBar: AppBar(
        title: Text((_p['name'] ?? 'Partner').toString()),
        actions: [
          if (admin)
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                await _editPartner(context, _p);
                await _refreshPartner();
              },
            ),
        ],
      ),
      body: FutureBuilder<PartnerAccount>(
        future: _acc,
        builder: (context, snap) {
          final a = snap.data;
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 40), children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text([
                      (_p['phone'] ?? '').toString(),
                      (_p['place'] ?? '').toString(),
                      if ((_p['upi'] ?? '').toString().isNotEmpty) 'UPI ${_p['upi']}',
                    ].where((x) => x.isNotEmpty).join(' · ')),
                    const SizedBox(height: 6),
                    Row(children: [
                      Expanded(child: SelectableText(_link, style: const TextStyle(fontWeight: FontWeight.w700))),
                      IconButton(
                        tooltip: 'Copy link',
                        icon: const Icon(Icons.copy, size: 20),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _link));
                          _snack('Link copied');
                        },
                      ),
                    ]),
                    const Text('Customers only see madhuraagro.in — the partner name is never shown to them.',
                        style: TextStyle(fontSize: 11.5, color: Colors.black54)),
                  ]),
                ),
              ),
              const SizedBox(height: 4),
              Center(child: _qrCard()),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _busy ? null : _sendQr,
                icon: const Icon(Icons.qr_code_2),
                label: const Text('Send link & QR to partner (WhatsApp)'),
              ),
              const SizedBox(height: 12),
              if (a == null)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                      child: snap.hasError ? Text('Could not load: ${snap.error}') : const CircularProgressIndicator()),
                )
              else ...[
                Row(children: [
                  _tile('Earned', a.earned, const Color(0xFF16A34A)),
                  _tile('Waiting', a.pending, const Color(0xFFD97706)),
                  _tile('Paid', a.paid, const Color(0xFF2563EB)),
                  _tile('Due', a.due < 0 ? 0 : a.due, const Color(0xFFDC2626)),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openWhatsApp(_statementText(a)),
                      icon: const Icon(Icons.chat_outlined),
                      label: const Text('WhatsApp statement'),
                    ),
                  ),
                  if (admin) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () => _pay(a),
                        icon: const Icon(Icons.currency_rupee),
                        label: const Text('Record payment'),
                      ),
                    ),
                  ],
                ]),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: Text('Customers (${a.customers.length})',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                  if (admin)
                    TextButton.icon(
                      onPressed: _linkCustomer,
                      icon: const Icon(Icons.link, size: 18),
                      label: const Text('Link customer'),
                    ),
                ]),
                if (a.customers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Text('None yet. New customers join through the link, or link one here on their first shop bill.',
                        style: TextStyle(fontSize: 12.5, color: Colors.black54)),
                  ),
                for (final v in a.customers)
                  Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      dense: true,
                      title: Text((v['name'] ?? '').toString()),
                      subtitle: Text(Partners.linkActive(v)
                          ? 'Linked till ${DateFormat('d MMM yyyy').format(Partners.linkEnds(v)!)}'
                          : 'Link ended — no more commission'),
                      trailing: admin
                          ? IconButton(
                              tooltip: 'Remove link',
                              icon: const Icon(Icons.link_off, size: 20),
                              onPressed: () => _unlink(v),
                            )
                          : null,
                    ),
                  ),
                const SizedBox(height: 12),
                const Text('Commission', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                if (a.entries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Text('No orders yet.', style: TextStyle(fontSize: 12.5, color: Colors.black54)),
                  ),
                for (final e in a.entries)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      e.state == 'earned'
                          ? Icons.check_circle
                          : e.state == 'pending'
                              ? Icons.hourglass_bottom
                              : Icons.cancel_outlined,
                      color: e.state == 'earned'
                          ? const Color(0xFF16A34A)
                          : e.state == 'pending'
                              ? const Color(0xFFD97706)
                              : Colors.grey,
                    ),
                    title: Text('${e.customer} · ${e.online ? 'online' : 'shop'}'),
                    subtitle: Text('${_day(e.date)} · bill ${_money(e.saleTotal)} · '
                        '${e.state == 'earned' ? 'earned' : e.state == 'pending' ? 'waiting for payment' : 'cancelled'}'),
                    trailing: Text(_money(e.commission),
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            decoration: e.state == 'cancelled' ? TextDecoration.lineThrough : null)),
                  ),
                if (a.payments.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Payments', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  for (final p in a.payments)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.payments_outlined, color: Color(0xFF2563EB)),
                      title: Text(_money((p['amount'] as num?)?.toDouble() ?? 0)),
                      subtitle: Text([_day((p['date'] ?? '').toString()), (p['ref'] ?? '').toString()]
                          .where((x) => x.isNotEmpty)
                          .join(' · ')),
                    ),
                ],
              ],
            ]),
          );
        },
      ),
    );
  }
}
