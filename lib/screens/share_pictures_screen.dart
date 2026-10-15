import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../services/web_store_service.dart';
import '../utils/app_theme.dart';
import '../utils/keyed_stream.dart';
import '../utils/tamil_names.dart';

/// Ready-made pictures for WhatsApp Status, Instagram and groups:
/// today's prices, one product offer, or the first-order coupon. Every
/// picture carries the shop name, the website address and a QR code that
/// opens the right page, so people who see it can order straight away.
class SharePicturesScreen extends StatefulWidget {
  const SharePicturesScreen({super.key});

  @override
  State<SharePicturesScreen> createState() => _SharePicturesScreenState();
}

enum _Kind { prices, offer, coupon }

class _SharePicturesScreenState extends State<SharePicturesScreen> {
  final _svc = WebStoreService.instance;
  final _settingsStream = KeyedStream<Map<String, dynamic>>();
  final _productsStream = KeyedStream<List<Map<String, dynamic>>>();
  final _cardKey = GlobalKey();
  _Kind _kind = _Kind.prices;
  bool _tamil = false;
  bool _tall = false; // Status size (9:16) instead of square
  bool _busy = false;
  List<String>? _picked; // product ids on the price picture
  String? _offerId;
  String _site = '';

  static const _cream = Color(0xFFF6EFDF);
  static const _green = Color(0xFF1F3D27);
  static const _gold = Color(0xFFB8860B);

  @override
  void initState() {
    super.initState();
    final projectId = Firebase.app().options.projectId;
    _site = WebStoreService.siteBaseFor(projectId);
    WebStoreService.mainSite(projectId).then((s) {
      if (mounted && s != _site) setState(() => _site = s);
    });
  }

  String get _siteLabel => _site.replaceFirst(RegExp(r'^https?://'), '');

  static String _rs(double v) => '₹${NumberFormat.decimalPattern('en_IN').format(v.round())}';

  String _name(Map<String, dynamic> p) {
    final en = (p['name'] ?? '').toString().trim();
    if (!_tamil) return en;
    final ta = tamilNameOf(p).trim();
    return ta.isEmpty ? en : ta;
  }

  String _pack(Map<String, dynamic> p) => WebStoreService.sellsByWeight(p) ? '1 kg' : WebStoreService.packLabel(p);

  Uint8List? _photo(Map<String, dynamic> p) {
    final raw = (p['photo'] ?? '').toString();
    if (raw.isEmpty) return null;
    try {
      return base64Decode(raw.replaceFirst(RegExp(r'^data:image/\w+;base64,'), ''));
    } catch (_) {
      return null;
    }
  }

  List<Map<String, dynamic>> _online(List<Map<String, dynamic>> products, Map<String, dynamic> settings) {
    final hidden = ((settings['hidden_categories'] as List?) ?? const []).map((e) => e.toString()).toSet();
    final list = products
        .where((p) => WebStoreService.isOnline(p) && !hidden.contains(WebStoreService.categoryOf(p)))
        .toList()
      ..sort((a, b) {
        final oa = (a['web_order'] as num?)?.toInt() ?? 999;
        final ob = (b['web_order'] as num?)?.toInt() ?? 999;
        if (oa != ob) return oa.compareTo(ob);
        return (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString());
      });
    return list;
  }

  bool _inStock(Map<String, dynamic> p) => ((p['quantity'] as num?)?.toDouble() ?? 0) > 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      appBar: AppBar(title: const Text('Share pictures')),
      body: StreamBuilder<Map<String, dynamic>>(
        stream: _settingsStream.get(0, _svc.watchSettings),
        builder: (context, sSnap) => StreamBuilder<List<Map<String, dynamic>>>(
          stream: _productsStream.get(0, _svc.watchProducts),
          builder: (context, pSnap) {
            if (sSnap.hasError || pSnap.hasError) {
              return ErrorState(message: 'Could not load products.\n${sSnap.error ?? pSnap.error}');
            }
            if (!sSnap.hasData || !pSnap.hasData) return const Center(child: CircularProgressIndicator());
            final settings = sSnap.data!;
            final online = _online(pSnap.data!, settings);
            final slugs = WebStoreService.productSlugs(pSnap.data!, settings);
            final store = Map<String, dynamic>.from((settings['store'] as Map?) ?? const {});
            final site = Map<String, dynamic>.from((settings['site'] as Map?) ?? const {});
            final coupon = Map<String, dynamic>.from((site['coupon'] as Map?) ?? const {});
            _picked ??= online.where(_inStock).take(8).map((p) => p['id'] as String).toList();
            final offerList = online.where(_inStock).toList();
            if (_offerId == null || !offerList.any((p) => p['id'] == _offerId)) {
              final withOffer = offerList.where((p) => WebStoreService.webPriceOf(p) < WebStoreService.priceOf(p));
              _offerId = withOffer.isNotEmpty
                  ? withOffer.first['id'] as String
                  : (offerList.isNotEmpty ? offerList.first['id'] as String : null);
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
              children: [
                SegmentedButton<_Kind>(
                  segments: const [
                    ButtonSegment(value: _Kind.prices, label: Text('Prices'), icon: Icon(Icons.list_alt, size: 18)),
                    ButtonSegment(value: _Kind.offer, label: Text('Offer'), icon: Icon(Icons.local_offer_outlined, size: 18)),
                    ButtonSegment(value: _Kind.coupon, label: Text('Coupon'), icon: Icon(Icons.card_giftcard, size: 18)),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (x) => setState(() => _kind = x.first),
                ),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  ChoiceChip(label: const Text('English'), selected: !_tamil, onSelected: (_) => setState(() => _tamil = false)),
                  ChoiceChip(label: const Text('தமிழ்'), selected: _tamil, onSelected: (_) => setState(() => _tamil = true)),
                  ChoiceChip(label: const Text('Square'), selected: !_tall, onSelected: (_) => setState(() => _tall = false)),
                  ChoiceChip(label: const Text('Status (tall)'), selected: _tall, onSelected: (_) => setState(() => _tall = true)),
                ]),
                const SizedBox(height: 12),
                Center(
                  child: FittedBox(
                    child: RepaintBoundary(
                      key: _cardKey,
                      child: _picture(store, online, slugs, coupon),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _share(store, slugs, coupon),
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF128C7E), minimumSize: const Size.fromHeight(48)),
                  icon: const Icon(Icons.share),
                  label: Text(_busy ? 'Preparing…' : 'Share picture (WhatsApp Status, Instagram…)'),
                ),
                const SizedBox(height: 6),
                Text(
                  'The QR code opens ${_linkFor(slugs, coupon).replaceFirst(RegExp(r'^https?://'), '')}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
                if (_kind == _Kind.prices) ..._pricePicker(online),
                if (_kind == _Kind.offer) ..._offerPicker(offerList),
                if (_kind == _Kind.coupon && coupon['on'] != true)
                  const Text(
                    'The first-order coupon is switched off. Turn it on in Web Store → Website content → '
                    'First-order coupon, then come back here.',
                    style: TextStyle(fontSize: 13, color: AppTheme.danger),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _pricePicker(List<Map<String, dynamic>> online) => [
        Text('Products on the picture (${_picked!.length} of 8)',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 2, children: [
          for (final p in online)
            FilterChip(
              label: Text((p['name'] ?? '').toString(), style: const TextStyle(fontSize: 12.5)),
              selected: _picked!.contains(p['id']),
              onSelected: (on) => setState(() {
                final id = p['id'] as String;
                if (on && _picked!.length < 8) {
                  _picked = [..._picked!, id];
                } else if (!on) {
                  _picked = _picked!.where((x) => x != id).toList();
                }
              }),
            ),
        ]),
      ];

  List<Widget> _offerPicker(List<Map<String, dynamic>> list) => [
        const Text('Product', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 6),
        for (final p in list)
          RadioListTile<String>(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: p['id'] as String,
            groupValue: _offerId,
            onChanged: (v) => setState(() => _offerId = v),
            title: Text((p['name'] ?? '').toString()),
            subtitle: Text(WebStoreService.webPriceOf(p) < WebStoreService.priceOf(p)
                ? 'Offer ${_rs(WebStoreService.webPriceOf(p))} (was ${_rs(WebStoreService.priceOf(p))}) · ${_pack(p)}'
                : '${_rs(WebStoreService.priceOf(p))} · ${_pack(p)} · no offer price set'),
          ),
      ];

  String _linkFor(Map<String, String> slugs, Map<String, dynamic> coupon) {
    if (_kind == _Kind.prices) return '$_site${_tamil ? '/ta/prices' : '/prices'}';
    if (_kind == _Kind.offer) {
      final slug = _offerId == null ? null : slugs[_offerId];
      return slug == null ? '$_site/' : '$_site${_tamil ? '/ta' : ''}/p/$slug';
    }
    final code = (coupon['code'] ?? '').toString();
    return code.isEmpty ? '$_site/' : '$_site${_tamil ? '/ta/' : '/'}?coupon=$code';
  }

  // ---------------- The picture ----------------

  Widget _picture(Map<String, dynamic> store, List<Map<String, dynamic>> online, Map<String, String> slugs,
      Map<String, dynamic> coupon) {
    final local = (store['nameLocal'] ?? '').toString().trim();
    final en = (store['name'] ?? '').toString().trim();
    final shop = _tamil && local.isNotEmpty ? local : (en.isEmpty ? 'Sri Madhura Agro Traders' : en);
    final wa = (store['whatsapp'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
    final phone = wa.length > 10 ? wa.substring(wa.length - 10) : wa;
    final link = _linkFor(slugs, coupon);
    final Widget body;
    if (_kind == _Kind.prices) {
      final items = [
        for (final id in _picked!) ...online.where((p) => p['id'] == id),
      ];
      body = _pricesBody(items);
    } else if (_kind == _Kind.offer) {
      final p = online.where((x) => x['id'] == _offerId).toList();
      body = p.isEmpty ? _empty('Choose a product below') : _offerBody(p.first);
    } else {
      body = coupon['on'] == true ? _couponBody(coupon) : _empty('Coupon is switched off');
    }
    return Container(
      width: 360,
      height: _tall ? 640 : 360,
      color: _cream,
      child: Column(
        children: [
          Container(
            color: _green,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(children: [
              ClipOval(child: Image.asset('assets/logo.png', width: 34, height: 34, fit: BoxFit.cover)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(shop,
                    maxLines: 2,
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, height: 1.15)),
              ),
            ]),
          ),
          Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(14, 10, 14, 6), child: body)),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(_tamil ? 'ஆன்லைனில் ஆர்டர் செய்ய' : 'Order online',
                      style: const TextStyle(fontSize: 11, color: Colors.black54)),
                  Text(_siteLabel,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _green)),
                  if (phone.isNotEmpty)
                    Text('WhatsApp $phone', style: const TextStyle(fontSize: 12, color: Color(0xFF128C7E), fontWeight: FontWeight.w600)),
                ]),
              ),
              QrImageView(
                data: link,
                version: QrVersions.auto,
                size: 74,
                padding: const EdgeInsets.all(3),
                backgroundColor: Colors.white,
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _empty(String text) =>
      Center(child: Text(text, style: const TextStyle(color: Colors.black45, fontSize: 14)));

  Widget _pricesBody(List<Map<String, dynamic>> items) {
    final today = DateFormat('dd-MM-yyyy').format(DateTime.now());
    if (items.isEmpty) return _empty('Choose products below');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(_tamil ? 'இன்றைய விலை · $today' : "Today's prices · $today",
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _green)),
      const SizedBox(height: 6),
      Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final p in items)
              Row(children: [
                Expanded(
                  child: Text(_name(p),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: _tall ? 15 : 13, fontWeight: FontWeight.w600, color: const Color(0xFF2B2B2B))),
                ),
                Text(_pack(p), style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
                const SizedBox(width: 8),
                if (WebStoreService.webPriceOf(p) < WebStoreService.priceOf(p)) ...[
                  Text(_rs(WebStoreService.priceOf(p)),
                      style: const TextStyle(
                          fontSize: 11, color: Colors.black38, decoration: TextDecoration.lineThrough)),
                  const SizedBox(width: 4),
                ],
                Text(_rs(WebStoreService.webPriceOf(p)),
                    style: TextStyle(fontSize: _tall ? 16 : 14, fontWeight: FontWeight.w800, color: _green)),
              ]),
          ],
        ),
      ),
    ]);
  }

  Widget _offerBody(Map<String, dynamic> p) {
    final price = WebStoreService.priceOf(p);
    final now = WebStoreService.webPriceOf(p);
    final photo = _photo(p);
    final save = price - now;
    final en = (p['name'] ?? '').toString().trim();
    final ta = tamilNameOf(p).trim();
    return Column(children: [
      if (save > 0)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: const Color(0xFFD94A1E), borderRadius: BorderRadius.circular(999)),
          child: Text(_tamil ? '${_rs(save)} சேமிப்பு' : 'Save ${_rs(save)}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
        ),
      const SizedBox(height: 6),
      if (photo != null)
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(photo, fit: BoxFit.cover, width: double.infinity),
          ),
        )
      else
        const Expanded(child: Icon(Icons.grass, size: 72, color: _gold)),
      const SizedBox(height: 6),
      Text(_tamil && ta.isNotEmpty ? ta : en,
          textAlign: TextAlign.center,
          maxLines: 2,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _green, height: 1.1)),
      if (ta.isNotEmpty && ta != en)
        Text(_tamil ? en : ta, style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
      const SizedBox(height: 4),
      Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        if (save > 0) ...[
          Text(_rs(price),
              style: const TextStyle(fontSize: 14, color: Colors.black38, decoration: TextDecoration.lineThrough)),
          const SizedBox(width: 8),
        ],
        Text(_rs(now), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: _green)),
        const SizedBox(width: 6),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('/ ${_pack(p)}', style: const TextStyle(fontSize: 13, color: Colors.black54)),
        ),
      ]),
    ]);
  }

  Widget _couponBody(Map<String, dynamic> c) {
    final code = (c['code'] ?? '').toString();
    final value = (c['value'] as num?)?.toInt() ?? 0;
    final min = (c['min'] as num?)?.toInt() ?? 0;
    final max = (c['max'] as num?)?.toInt() ?? 0;
    final off = c['kind'] == 'percent' ? '$value%' : _rs(value.toDouble());
    final cap = c['kind'] == 'percent' && max > 0
        ? (_tamil ? ' (அதிகபட்சம் ${_rs(max.toDouble())})' : ' (up to ${_rs(max.toDouble())})')
        : '';
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(_tamil ? 'முதல் ஆன்லைன் ஆர்டருக்கு' : 'On your first online order',
          style: const TextStyle(fontSize: 15, color: Color(0xFF4C5B49), fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Text(_tamil ? '$off தள்ளுபடி$cap' : '$off OFF$cap',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: _green, height: 1.05)),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _gold, width: 2),
        ),
        child: Text(code, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 2, color: _gold)),
      ),
      const SizedBox(height: 8),
      Text(
        _tamil
            ? 'செக்அவுட்டில் இந்த குறியீட்டை உள்ளிடுங்கள்${min > 0 ? ' · ${_rs(min.toDouble())}க்கு மேல் ஆர்டருக்கு' : ''}'
            : 'Type this code at checkout${min > 0 ? ' · orders above ${_rs(min.toDouble())}' : ''}',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12.5, color: Colors.black54),
      ),
      if (_tall) ...[
        const SizedBox(height: 18),
        Text(_tamil ? 'சிறுதானியங்கள் · அரிசி · மாட்டுத் தீவனம்' : 'Millets · Rice · Cattle feed',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _gold)),
      ],
    ]);
  }

  // ---------------- Share ----------------

  Future<void> _share(Map<String, dynamic> store, Map<String, String> slugs, Map<String, dynamic> coupon) async {
    setState(() => _busy = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 60)); // let the picture finish drawing
      final boundary = _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('Picture not ready');
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('Picture not ready');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/madhura_${_kind.name}_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      final link = _linkFor(slugs, coupon);
      final String text;
      if (_kind == _Kind.prices) {
        text = _tamil ? 'இன்றைய விலைகள் — ஆன்லைனில் ஆர்டர் செய்ய: $link' : "Today's prices — order online: $link";
      } else if (_kind == _Kind.offer) {
        text = _tamil ? 'இன்றைய ஆஃபர் — ஆர்டர் செய்ய: $link' : "Today's offer — order here: $link";
      } else {
        text = _tamil
            ? 'முதல் ஆர்டருக்கு தள்ளுபடி! குறியீடு ${coupon['code']} — $link'
            : 'Discount on your first order! Code ${coupon['code']} — $link';
      }
      await Share.shareXFiles([XFile(file.path)], text: text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not make the picture: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
