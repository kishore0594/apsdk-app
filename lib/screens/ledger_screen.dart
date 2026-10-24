import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../db/db_helper.dart';
import '../services/web_store_service.dart';
import '../utils/app_theme.dart';

/// A professional account statement (ledger) picture for one credit
/// customer — bills with the items bought, payments, running balance,
/// how old the due is, and the shop's UPI QR — sent straight to the
/// customer's WhatsApp chat (you check it and press send).
class LedgerScreen extends StatefulWidget {
  final Map<String, dynamic> vendor;
  const LedgerScreen({super.key, required this.vendor});

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

const _green = Color(0xFF1F5A2A);
const _gold = Color(0xFFE9C46A);
const _red = Color(0xFFC62828);
const _paidGreen = Color(0xFF2E7D32);

/// 0 = since the oldest unpaid bill, -1 = everything.
const _periods = [0, 30, 60, 90, -1];

class _Entry {
  final DateTime date;
  final String title;
  final String detail;
  final double purchase;
  final double paid;
  double balance = 0;
  _Entry(this.date, this.title, this.detail, this.purchase, this.paid);
}

class _LedgerScreenState extends State<LedgerScreen> {
  final _db = DBHelper.instance;
  final _cardKey = GlobalKey();
  String _lang = 'en';
  int _period = 0;
  bool _loading = true;
  bool _sending = false;
  String? _error;

  Map<String, dynamic> _vendor = {};
  List<Map<String, dynamic>> _txns = [];
  final Map<String, List<Map<String, dynamic>>> _items = {};
  final Map<String, String> _units = {};
  Map<String, dynamic> _store = {};
  Uint8List? _qr;
  String _upi = '';
  String _site = '';

  bool get _ta => _lang == 'ta';
  String t(String en, String ta) => _ta ? ta : en;

  @override
  void initState() {
    super.initState();
    _vendor = Map<String, dynamic>.from(widget.vendor);
    _load();
  }

  Future<void> _load() async {
    try {
      final id = _vendor['id'] as String;
      final results = await Future.wait([
        _db.getVendorTransactions(id),
        _db.getProducts(),
        WebStoreService.instance.settingsRef.get(),
      ]);
      _txns = (results[0] as List<Map<String, dynamic>>).toList()
        ..sort((a, b) => (a['date'] as String? ?? '').compareTo(b['date'] as String? ?? ''));
      for (final p in results[1] as List<Map<String, dynamic>>) {
        _units[p['id'] as String] = (p['unit'] ?? '').toString();
      }
      final settings = (results[2] as DocumentSnapshot<Map<String, dynamic>>).data() ?? const <String, dynamic>{};
      _store = Map<String, dynamic>.from((settings['store'] as Map?) ?? const {});
      final site = Map<String, dynamic>.from((settings['site'] as Map?) ?? const {});
      _upi = (_store['upiId'] ?? '').toString().trim();
      _qr = await WebStoreService.instance.siteImageBytes((site['payQr'] ?? '').toString());
      _site = WebStoreService.siteBaseFor(Firebase.app().options.projectId).replaceFirst(RegExp(r'^https?://'), '');
      // Items of every credit bill.
      final saleIds = {
        for (final t in _txns)
          if (t['type'] == 'CREDIT' && (t['sale_id'] ?? '').toString().isNotEmpty) t['sale_id'] as String
      };
      await Future.wait(saleIds.map((sid) async {
        try {
          _items[sid] = await _db.getSaleItems(sid);
        } catch (_) {/* items optional */}
      }));
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load this account: $e';
        });
      }
    }
  }

  static double _n(Object? v) => v is num ? v.toDouble() : 0.0;
  static DateTime? _d(Object? v) => v is String ? DateTime.tryParse(v) : null;

  String _rs(double v) => NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(v.round());

  String _day(DateTime d) {
    if (!_ta) return DateFormat('dd MMM').format(d);
    const m = ['ஜன', 'பிப்', 'மார்', 'ஏப்', 'மே', 'ஜூன்', 'ஜூலை', 'ஆக', 'செப்', 'அக்', 'நவ', 'டிச'];
    return '${d.day.toString().padLeft(2, '0')} ${m[d.month - 1]}';
  }

  String _fullDay(DateTime d) => '${_day(d)} ${d.year}';

  /// Oldest-first matching of payments to bills: what is still unpaid,
  /// with dates (for "oldest unpaid" and the age boxes).
  List<(DateTime, double)> _unpaidLots() {
    final lots = <List<Object>>[];
    final opening = _n(_vendor['opening_balance']);
    if (opening > 0.005) lots.add([_d(_vendor['created_at']) ?? DateTime(2020), opening]);
    double advance = opening < 0 ? -opening : 0.0;
    for (final x in _txns) {
      final amount = _n(x['amount']);
      final date = _d(x['date']);
      if (amount <= 0 || date == null) continue;
      if (x['type'] == 'CREDIT') {
        var rem = amount;
        if (advance > 0) {
          final used = advance < rem ? advance : rem;
          rem -= used;
          advance -= used;
        }
        if (rem > 0.005) lots.add([date, rem]);
      } else {
        var pay = amount;
        while (pay > 0.005 && lots.isNotEmpty) {
          final rem = lots.first[1] as double;
          if (rem <= pay + 0.005) {
            pay -= rem;
            lots.removeAt(0);
          } else {
            lots.first[1] = rem - pay;
            pay = 0;
          }
        }
        if (pay > 0.005) advance += pay;
      }
    }
    return [for (final l in lots) (l[0] as DateTime, l[1] as double)];
  }

  String _itemsOf(String? saleId) {
    if (saleId == null) return '';
    final items = _items[saleId];
    if (items == null || items.isEmpty) return '';
    String q(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    final parts = [
      for (final i in items.where((i) => i['status'] != 'cancelled'))
        '${(i['product_name'] ?? '').toString().trim()} ${q((i['quantity'] as num?) ?? 0)}'
            '${(_units[i['product_id']] ?? '').isEmpty ? '' : ' ${_units[i['product_id']]}'}',
    ];
    if (parts.length > 4) return '${parts.take(4).join(' · ')} +${parts.length - 4}';
    return parts.join(' · ');
  }

  ({DateTime start, double opening, List<_Entry> entries, double purchases, double paid, double due}) _ledger(
      List<(DateTime, double)> lots) {
    final now = DateTime.now();
    DateTime start;
    if (_period > 0) {
      start = DateTime(now.year, now.month, now.day).subtract(Duration(days: _period));
    } else if (_period == 0 && lots.isNotEmpty) {
      final o = lots.first.$1;
      start = DateTime(o.year, o.month, o.day);
    } else if (_period == 0) {
      start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 30));
    } else {
      start = DateTime(2000);
    }
    double opening = _n(_vendor['opening_balance']);
    final entries = <_Entry>[];
    for (final x in _txns) {
      final date = _d(x['date']);
      if (date == null) continue;
      final amount = _n(x['amount']);
      final type = x['type'];
      if (date.isBefore(start)) {
        opening += type == 'CREDIT' ? amount : -amount;
        continue;
      }
      if (type == 'CREDIT') {
        final sid = (x['sale_id'] ?? '').toString();
        entries.add(_Entry(
          date,
          sid.isEmpty ? t('Credit', 'கடன்') : '${t('Bill', 'பில்')} #${sid.substring(0, sid.length < 6 ? sid.length : 6).toUpperCase()}',
          _itemsOf(sid.isEmpty ? null : sid),
          amount,
          0,
        ));
      } else {
        final notes = (x['notes'] ?? '').toString();
        final String title;
        if (type == 'PAYMENT') {
          title = t('Payment received', 'பணம் பெறப்பட்டது');
        } else if (x['bad_debt'] == true) {
          title = t('Written off', 'தள்ளுபடி செய்யப்பட்டது');
        } else if (notes.toLowerCase().contains('cancel')) {
          title = t('Bill cancelled', 'பில் ரத்து');
        } else {
          title = t('Adjustment', 'சரிசெய்தல்');
        }
        entries.add(_Entry(date, title, '', 0, amount));
      }
    }
    // Keep the picture readable: the last 18 entries, older ones in the opening.
    while (entries.length > 18) {
      final e = entries.removeAt(0);
      opening += e.purchase - e.paid;
      start = entries.first.date;
    }
    var bal = opening;
    double purchases = 0, paid = 0;
    for (final e in entries) {
      bal += e.purchase - e.paid;
      e.balance = bal;
      purchases += e.purchase;
      paid += e.paid;
    }
    return (start: start, opening: opening, entries: entries, purchases: purchases, paid: paid, due: bal);
  }

  Future<File> _capture() async {
    await WidgetsBinding.instance.endOfFrame;
    final boundary = _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) throw StateError('Picture not ready');
    final image = await boundary.toImage(pixelRatio: 1080 / 400);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) throw StateError('Picture not ready');
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/statement_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(bytes.buffer.asUint8List());
    return file;
  }

  String _caption(double due) {
    final name = (_vendor['name'] ?? '').toString();
    final shop = (_store['name'] ?? '').toString().trim().isEmpty ? 'Sri Madhura Agro Traders' : _store['name'].toString();
    return _ta
        ? 'அன்புள்ள $name,\n\n$shop கடையில் உங்கள் கணக்கு அறிக்கையை இணைத்துள்ளோம். செலுத்த வேண்டிய தொகை: ${_rs(due)}.'
            '\nதயவுசெய்து தொகையை செலுத்தி முடிக்கவும். நன்றி!\n\n- $shop'
        : 'Dear $name,\n\nPlease find your account statement from $shop attached. Amount due: ${_rs(due)}.'
            '\nKindly complete the payment. Thank you!\n\n- $shop';
  }

  Future<void> _send({required bool whatsapp, required double due, required int? oldestDays}) async {
    setState(() => _sending = true);
    try {
      final file = await _capture();
      final text = _caption(due);
      var digits = (_vendor['phone'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length == 10) digits = '91$digits';
      var sent = false;
      if (whatsapp && digits.length >= 11) {
        try {
          final outcome = await const MethodChannel('madhura/whatsapp')
              .invokeMethod<String>('sendImage', {'phone': digits, 'text': text, 'path': file.path});
          sent = outcome == 'ok';
        } catch (_) {/* fall back to the share sheet */}
      }
      if (!sent) {
        await Share.shareXFiles([XFile(file.path, mimeType: 'image/png')], text: text);
      }
      await _db.logReminder(
        vendorId: _vendor['id'] as String,
        balance: due,
        daysOutstanding: oldestDays,
        language: _lang,
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not send: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(appBar: AppBar(title: const Text('Account statement')), body: const Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(appBar: AppBar(title: const Text('Account statement')), body: Center(child: Text(_error!)));
    }
    final lots = _unpaidLots();
    final l = _ledger(lots);
    final now = DateTime.now();
    final oldestDays = lots.isEmpty ? null : now.difference(lots.first.$1).inDays;
    final ages = List<double>.filled(4, 0);
    for (final lot in lots) {
      final d = now.difference(lot.$1).inDays;
      ages[d <= 30 ? 0 : (d <= 60 ? 1 : (d <= 90 ? 2 : 3))] += lot.$2;
    }
    final phone = (_vendor['phone'] ?? '').toString().trim();
    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      appBar: AppBar(title: const Text('Account statement')),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 10, 12, 32), children: [
        Wrap(spacing: 8, runSpacing: 4, children: [
          ChoiceChip(label: const Text('English'), selected: !_ta, onSelected: (_) => setState(() => _lang = 'en')),
          ChoiceChip(label: const Text('தமிழ்'), selected: _ta, onSelected: (_) => setState(() => _lang = 'ta')),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final p in _periods)
            ChoiceChip(
              label: Text(switch (p) {
                0 => 'Since oldest unpaid bill',
                -1 => 'Everything',
                _ => 'Last $p days',
              }),
              selected: _period == p,
              onSelected: (_) => setState(() => _period = p),
            ),
        ]),
        const SizedBox(height: 10),
        Center(
          child: FittedBox(
            child: RepaintBoundary(
              key: _cardKey,
              child: _card(l, ages, oldestDays),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _sending ? null : () => _send(whatsapp: true, due: l.due, oldestDays: oldestDays),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF128C7E), minimumSize: const Size.fromHeight(48)),
              icon: const Icon(Icons.chat),
              label: Text(_sending ? 'Preparing…' : (phone.isEmpty ? 'Share picture' : 'Send on WhatsApp')),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: _sending ? null : () => _send(whatsapp: false, due: l.due, oldestDays: oldestDays),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
            icon: const Icon(Icons.share),
            label: const Text('Other apps'),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          phone.isEmpty
              ? 'No phone number saved for this customer — add it to send straight to their WhatsApp.'
              : 'Opens this customer\'s WhatsApp chat with the statement attached. Check it and press send.',
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ]),
    );
  }

  // ---------------- the picture (400 wide, saved at 1080 px) ----------------

  TextStyle _s(double size, {double w = 500, Color color = const Color(0xFF1F2A1C), double? height}) => TextStyle(
        fontFamily: 'Baloo',
        fontSize: size,
        color: color,
        height: height,
        fontWeight: w >= 700 ? FontWeight.w800 : FontWeight.w400,
        fontVariations: [ui.FontVariation('wght', w)],
      );

  Widget _card(
      ({DateTime start, double opening, List<_Entry> entries, double purchases, double paid, double due}) l,
      List<double> ages,
      int? oldestDays) {
    final shop = (_store['name'] ?? '').toString().trim().isEmpty ? 'Sri Madhura Agro Traders' : _store['name'].toString();
    final shopTa = (_store['nameLocal'] ?? '').toString().trim();
    final place = (_vendor['address'] ?? '').toString().trim();
    final phone = (_vendor['phone'] ?? '').toString().trim();
    final now = DateTime.now();
    final address = (_store['pickupAddress'] ?? '').toString().trim();
    final shopPhone = (_store['whatsapp'] ?? '').toString().trim();
    Widget box(String k, double v, {Color? color, bool due = false}) => Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 7),
            decoration: BoxDecoration(
              color: due ? const Color(0xFFFDECEA) : Colors.white,
              border: Border.all(color: due ? const Color(0xFFE3A29B) : const Color(0xFFE5DFCC), width: 1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(k, maxLines: 2, style: _s(7.5, w: 600, color: const Color(0xFF6B7563), height: 1.15)),
              const SizedBox(height: 2),
              Text(_rs(v), style: _s(due ? 13 : 11.5, w: 800, color: color ?? const Color(0xFF1F2A1C))),
            ]),
          ),
        );
    const ageColors = [Color(0xFF2E7D32), Color(0xFFD97706), Color(0xFFEA580C), Color(0xFFC62828)];
    final ageNames = _ta
        ? const ['0–30 நாள்', '31–60 நாள்', '61–90 நாள்', '90 நாளுக்கு மேல்']
        : const ['0–30 days', '31–60 days', '61–90 days', 'Over 90 days'];
    const head = TextStyle(fontFamily: 'Baloo', fontSize: 7.5, fontWeight: FontWeight.w800, color: Color(0xFF3A4535));
    Widget cell(String text, {TextStyle? style, TextAlign align = TextAlign.right}) =>
        Text(text, textAlign: align, style: style ?? _s(8.5, w: 600));
    return Container(
      width: 400,
      color: Colors.white,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Header
        Container(
          color: _green,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _gold, width: 1.5), color: Colors.white),
              clipBehavior: Clip.antiAlias,
              child: Image.asset('assets/logo.png', fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_ta && shopTa.isNotEmpty ? shopTa : shop, style: _s(14, w: 800, color: Colors.white, height: 1.1)),
                Text(t('Millets · Rice · Cattle feeds', 'சிறுதானியம் · அரிசி · மாட்டுத் தீவனம்'),
                    style: _s(8, color: _gold)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(t('Account Statement', 'கணக்கு அறிக்கை'), style: _s(13, w: 800, color: Colors.white)),
              Text(t('Your account with us', 'எங்களிடம் உங்கள் கணக்கு'), style: _s(7.5, color: Colors.white70)),
            ]),
          ]),
        ),
        // Customer + date
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              flex: 6,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('Customer', 'வாடிக்கையாளர்'), style: _s(7.5, w: 600, color: const Color(0xFF6B7563))),
                Text((_vendor['name'] ?? '').toString(), style: _s(12.5, w: 800)),
                Text([if (phone.isNotEmpty) '📞 $phone', if (place.isNotEmpty) '📍 $place'].join('  ·  '),
                    style: _s(8.5, color: const Color(0xFF3A4535))),
              ]),
            ),
            Expanded(
              flex: 4,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('Statement date', 'அறிக்கை தேதி'), style: _s(7.5, w: 600, color: const Color(0xFF6B7563))),
                Text(_fullDay(now), style: _s(12.5, w: 800)),
                Text('${t('Period', 'காலம்')}: ${l.start.year < 2001 ? t('all', 'முழுவதும்') : '${_day(l.start)} – ${_day(now)}'}',
                    style: _s(8.5, color: const Color(0xFF3A4535))),
              ]),
            ),
          ]),
        ),
        // Summary
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(children: [
            box(t('Opening balance', 'முந்தைய நிலுவை'), l.opening),
            const SizedBox(width: 6),
            box(t('Purchases', 'வாங்கியது'), l.purchases),
            const SizedBox(width: 6),
            box(t('Payments received', 'செலுத்தியது'), l.paid, color: _paidGreen),
            const SizedBox(width: 6),
            box(t('Amount due', 'செலுத்த வேண்டியது'), l.due, color: _red, due: true),
          ]),
        ),
        if (oldestDays != null && l.due > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
                '⏱ ${t('Oldest unpaid bill: $oldestDays days', 'பழைய நிலுவை பில்: $oldestDays நாட்கள்')}',
                style: _s(8.5, w: 800, color: const Color(0xFFB26A00))),
          ),
        // Table
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Table(
            columnWidths: const {
              0: FixedColumnWidth(42),
              1: FlexColumnWidth(),
              2: FixedColumnWidth(58),
              3: FixedColumnWidth(54),
              4: FixedColumnWidth(60),
            },
            border: const TableBorder(horizontalInside: BorderSide(color: Color(0xFFEEE8D6), width: 0.6)),
            children: [
              TableRow(
                decoration: const BoxDecoration(color: Color(0xFFF3EEDF)),
                children: [
                  for (final h in [
                    t('Date', 'தேதி'),
                    t('Details', 'விவரம்'),
                    t('Purchase', 'வாங்கியது'),
                    t('Paid', 'செலுத்தியது'),
                    t('Balance', 'நிலுவை'),
                  ])
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                      child: Text(h,
                          textAlign: h == t('Date', 'தேதி') || h == t('Details', 'விவரம்') ? TextAlign.left : TextAlign.right,
                          style: head),
                    ),
                ],
              ),
              TableRow(
                decoration: const BoxDecoration(color: Color(0xFFFAFAF5)),
                children: [
                  const SizedBox(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                    child: Text(
                        l.start.year < 2001
                            ? t('Opening balance', 'தொடக்க நிலுவை')
                            : t('Opening balance (before ${_day(l.start)})', 'முந்தைய நிலுவை (${_day(l.start)} முன்)'),
                        style: _s(8.5, w: 600, color: const Color(0xFF5E6B57))),
                  ),
                  const SizedBox(),
                  const SizedBox(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                    child: cell(_rs(l.opening), style: _s(8.5, w: 800, color: const Color(0xFF5E6B57))),
                  ),
                ],
              ),
              for (final e in l.entries)
                TableRow(children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                    child: cell(_day(e.date), style: _s(8, color: const Color(0xFF5E6B57)), align: TextAlign.left),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(e.title, style: _s(8.5, w: 700)),
                      if (e.detail.isNotEmpty) Text(e.detail, style: _s(7, color: const Color(0xFF6B7563), height: 1.2)),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                    child: cell(e.purchase > 0 ? _rs(e.purchase) : ''),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                    child: cell(e.paid > 0 ? _rs(e.paid) : '', style: _s(8.5, w: 700, color: _paidGreen)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                    child: cell(_rs(e.balance), style: _s(8.5, w: 800)),
                  ),
                ]),
            ],
          ),
        ),
        Container(margin: const EdgeInsets.symmetric(horizontal: 16), height: 1.5, color: _green),
        // Age of the due
        if (l.due > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('How old is the amount due', 'நிலுவை எத்தனை நாளாக'), style: _s(8.5, w: 800)),
              const SizedBox(height: 5),
              Row(children: [
                for (var i = 0; i < 4; i++) ...[
                  if (i > 0) const SizedBox(width: 5),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(7, 5, 7, 5),
                      decoration: BoxDecoration(color: ageColors[i], borderRadius: BorderRadius.circular(6)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_rs(ages[i]), style: _s(10.5, w: 800, color: Colors.white)),
                        Text(ageNames[i], style: _s(7, color: Colors.white)),
                      ]),
                    ),
                  ),
                ],
              ]),
            ]),
          ),
        // Pay
        Container(
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFF1F7EE), borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            if (_qr != null || _upi.isNotEmpty)
              Container(
                width: 74,
                height: 74,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
                child: _qr != null
                    ? Image.memory(_qr!, fit: BoxFit.contain)
                    : QrImageView(
                        data: 'upi://pay?pa=$_upi&pn=${Uri.encodeComponent(shop)}&cu=INR',
                        version: QrVersions.auto,
                        padding: EdgeInsets.zero,
                        backgroundColor: Colors.white,
                      ),
              ),
            if (_qr != null || _upi.isNotEmpty) const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('Pay easily', 'எளிதாக செலுத்துங்கள்'), style: _s(11, w: 800, color: _green)),
                if (_upi.isNotEmpty || shopPhone.isNotEmpty)
                  Text(
                      [
                        if (_upi.isNotEmpty) 'UPI: $_upi',
                        if (shopPhone.isNotEmpty) 'GPay / PhonePe: $shopPhone',
                      ].join('  ·  '),
                      style: _s(8.5)),
                const SizedBox(height: 3),
                Text(
                    l.due > 0
                        ? t('Kindly complete the payment of ${_rs(l.due)}. Thank you for your business!',
                            'தயவுசெய்து ${_rs(l.due)} தொகையை செலுத்தி முடிக்கவும். உங்கள் ஆதரவுக்கு நன்றி!')
                        : t('No amount due. Thank you for your business!', 'நிலுவை இல்லை. உங்கள் ஆதரவுக்கு நன்றி!'),
                    style: _s(9.5, w: 800, color: l.due > 0 ? _red : _paidGreen, height: 1.25)),
              ]),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(
              t('Please tell us if anything here does not match your records.',
                  'ஏதேனும் வித்தியாசம் இருந்தால் எங்களிடம் தெரிவிக்கவும்.'),
              textAlign: TextAlign.center,
              style: _s(7.5, color: const Color(0xFF6B7563))),
        ),
        Container(
          color: _green,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            [shop, if (address.isNotEmpty) address, if (_site.isNotEmpty) _site].join('  ·  '),
            textAlign: TextAlign.center,
            style: _s(7.5, color: const Color(0xFFE9F0E5)),
          ),
        ),
      ]),
    );
  }
}

