import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../services/web_store_service.dart';
import '../utils/app_theme.dart';
import '../utils/keyed_stream.dart';
import '../utils/tamil_names.dart';
import '../utils/user_role.dart';

/// Ready-made pictures for WhatsApp Status, Instagram and groups:
/// today's prices (one brand at a time), one product offer, or the
/// first-order coupon. Each picture carries the brand (Madhura Millets,
/// Madhura Rice, Madhura Cattle Feeds), a big web address, a "reply to
/// order" line and a small QR code. "Share link" posts a tappable link
/// (WhatsApp shows it with the product photo). Links carry ?src=status so
/// orders from Status are marked in Online Orders.
class SharePicturesScreen extends StatefulWidget {
  const SharePicturesScreen({super.key});

  @override
  State<SharePicturesScreen> createState() => _SharePicturesScreenState();
}

enum _Kind { prices, offer, coupon }

enum _Extra { none, coupon, today, custom }

class _BrandStyle {
  final String en, ta, tagEn, tagTa;
  final Color dark, accent;
  const _BrandStyle(this.en, this.ta, this.tagEn, this.tagTa, this.dark, this.accent);
}

const _brands = <String, _BrandStyle>{
  'millets': _BrandStyle('Madhura Millets', 'மதுரா மில்லெட்ஸ்', 'Millets & grams', 'சிறுதானியங்கள் & பயறு வகைகள்',
      Color(0xFF1F4D2B), Color(0xFFC9A227)),
  'rice': _BrandStyle('Madhura Rice', 'மதுரா அரிசி', 'Traditional & everyday rice', 'பாரம்பரிய & அன்றாட அரிசி',
      Color(0xFF7A1F2B), Color(0xFFE8C77B)),
  'cattle': _BrandStyle('Madhura Cattle Feeds', 'மதுரா கால்நடை தீவனம்', 'Cattle feed, oil cakes & bran',
      'மாட்டுத் தீவனம், புண்ணாக்கு, தவிடு', Color(0xFF1E3A5F), Color(0xFFD9A441)),
};

class _SharePicturesScreenState extends State<SharePicturesScreen> {
  final _svc = WebStoreService.instance;
  final _settingsStream = KeyedStream<Map<String, dynamic>>();
  final _productsStream = KeyedStream<List<Map<String, dynamic>>>();
  final _cardKey = GlobalKey();
  final _customCtrl = TextEditingController();
  _Kind _kind = _Kind.prices;
  _Extra _extra = _Extra.none;
  String _brand = 'millets'; // brand of the price picture
  bool _tamil = false;
  bool _tall = false; // Status size (9:16) instead of square
  bool _busy = false;
  final Map<String, List<String>> _picked = {}; // brand -> product ids on the price picture
  String? _offerId;
  String _site = '';

  static const _cream = Color(0xFFF8F2E4);
  static const _shopDark = Color(0xFF1F3D27);
  static const _shopAccent = Color(0xFFC9A227);
  static const _wa = Color(0xFF128C7E);

  @override
  void initState() {
    super.initState();
    final projectId = Firebase.app().options.projectId;
    _site = WebStoreService.siteBaseFor(projectId);
    WebStoreService.mainSite(projectId).then((s) {
      if (mounted && s != _site) setState(() => _site = s);
    });
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
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

  Uint8List? _bytes(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return base64Decode(raw.replaceFirst(RegExp(r'^data:image/\w+;base64,'), ''));
    } catch (_) {
      return null;
    }
  }

  List<Map<String, dynamic>> _online(List<Map<String, dynamic>> products, Map<String, dynamic> settings) {
    final hidden = ((settings['hidden_categories'] as List?) ?? const []).map((e) => e.toString()).toSet();
    return products
        .where((p) => WebStoreService.isOnline(p) && !hidden.contains(WebStoreService.categoryOf(p)))
        .toList()
      ..sort((a, b) {
        final oa = (a['web_order'] as num?)?.toInt() ?? 999;
        final ob = (b['web_order'] as num?)?.toInt() ?? 999;
        if (oa != ob) return oa.compareTo(ob);
        return (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString());
      });
  }

  bool _inStock(Map<String, dynamic> p) => ((p['quantity'] as num?)?.toDouble() ?? 0) > 0;

  /// Brand shown on the picture: the chosen brand for prices, the product's
  /// brand for an offer, the shop for the coupon (it works on everything).
  String? _pictureBrand(List<Map<String, dynamic>> online) {
    if (_kind == _Kind.prices) return _brand;
    if (_kind == _Kind.offer) {
      final p = online.where((x) => x['id'] == _offerId).toList();
      return p.isEmpty ? null : WebStoreService.brandOf(p.first);
    }
    return null;
  }

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
            final logos = Map<String, dynamic>.from((settings['brand_logos'] as Map?) ?? const {});
            final brandItems = online.where((p) => WebStoreService.brandOf(p) == _brand).toList();
            _picked[_brand] ??= brandItems.where(_inStock).take(8).map((p) => p['id'] as String).toList();
            final offerList = online.where(_inStock).toList();
            if (_offerId == null || !offerList.any((p) => p['id'] == _offerId)) {
              final withOffer = offerList.where((p) => WebStoreService.webPriceOf(p) < WebStoreService.priceOf(p));
              _offerId = withOffer.isNotEmpty
                  ? withOffer.first['id'] as String
                  : (offerList.isNotEmpty ? offerList.first['id'] as String : null);
            }
            final brand = _pictureBrand(online);
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
                if (_kind == _Kind.prices) ...[
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    for (final e in _brands.entries)
                      ChoiceChip(
                        label: Text(e.value.en),
                        selected: _brand == e.key,
                        onSelected: (_) => setState(() => _brand = e.key),
                      ),
                  ]),
                ],
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  ChoiceChip(label: const Text('English'), selected: !_tamil, onSelected: (_) => setState(() => _tamil = false)),
                  ChoiceChip(label: const Text('தமிழ்'), selected: _tamil, onSelected: (_) => setState(() => _tamil = true)),
                  ChoiceChip(label: const Text('Square'), selected: !_tall, onSelected: (_) => setState(() => _tall = false)),
                  ChoiceChip(label: const Text('Status (tall)'), selected: _tall, onSelected: (_) => setState(() => _tall = true)),
                ]),
                if (_kind != _Kind.coupon) ...[
                  const SizedBox(height: 8),
                  const Text('Offer line on the picture', style: TextStyle(fontSize: 12.5, color: Colors.black54)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    ChoiceChip(label: const Text('None'), selected: _extra == _Extra.none, onSelected: (_) => setState(() => _extra = _Extra.none)),
                    if (coupon['on'] == true)
                      ChoiceChip(
                          label: const Text('First-order coupon'),
                          selected: _extra == _Extra.coupon,
                          onSelected: (_) => setState(() => _extra = _Extra.coupon)),
                    ChoiceChip(label: const Text('Today only'), selected: _extra == _Extra.today, onSelected: (_) => setState(() => _extra = _Extra.today)),
                    ChoiceChip(label: const Text('My own words'), selected: _extra == _Extra.custom, onSelected: (_) => setState(() => _extra = _Extra.custom)),
                  ]),
                  if (_extra == _Extra.custom)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: TextField(
                        controller: _customCtrl,
                        maxLength: 40,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                            labelText: 'Offer line', hintText: 'Free delivery above ₹500', border: OutlineInputBorder()),
                      ),
                    ),
                ],
                const SizedBox(height: 12),
                Center(
                  child: FittedBox(
                    child: RepaintBoundary(
                      key: _cardKey,
                      child: _picture(store, online, slugs, coupon, brand, logos),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : () => _share(slugs, coupon),
                      style: FilledButton.styleFrom(backgroundColor: _wa, minimumSize: const Size.fromHeight(48)),
                      icon: const Icon(Icons.image_outlined),
                      label: Text(_busy ? 'Preparing…' : 'Share picture'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : () => _shareLink(slugs, coupon),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      icon: const Icon(Icons.link),
                      label: const Text('Share link'),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                Text(
                  'Tip: post the picture, then "Share link" as a second Status — WhatsApp shows the link with your '
                  'product photo, and people can tap it to order. Orders from it show "From WhatsApp Status".',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.35),
                ),
                const SizedBox(height: 16),
                if (_kind == _Kind.prices) ..._pricePicker(brandItems, logos),
                if (_kind == _Kind.offer) ..._offerPicker(offerList, logos),
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

  // ---------------- Pickers ----------------

  Widget _logoButton(String brand, Map<String, dynamic> logos) {
    if (!UserRole.instance.isAdmin) return const SizedBox.shrink();
    final has = (logos[brand] ?? '').toString().isNotEmpty;
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => _pickLogo(brand),
        icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
        label: Text('${has ? 'Change' : 'Add'} ${_brands[brand]!.en} logo'),
      ),
    );
  }

  Future<void> _pickLogo(String brand) async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 300, imageQuality: 80);
    if (x == null) return;
    final b64 = base64Encode(await x.readAsBytes());
    await _svc.saveSettings({
      'brand_logos': {brand: b64}
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_brands[brand]!.en} logo saved')));
    }
  }

  List<Widget> _pricePicker(List<Map<String, dynamic>> items, Map<String, dynamic> logos) {
    final picked = _picked[_brand]!;
    return [
      _logoButton(_brand, logos),
      Text('${_brands[_brand]!.en} products on the picture (${picked.length} of 8)',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      const SizedBox(height: 6),
      if (items.isEmpty)
        const Text('No products of this brand are on the website yet.', style: TextStyle(color: Colors.black54)),
      Wrap(spacing: 6, runSpacing: 2, children: [
        for (final p in items)
          FilterChip(
            label: Text((p['name'] ?? '').toString(), style: const TextStyle(fontSize: 12.5)),
            selected: picked.contains(p['id']),
            onSelected: (on) => setState(() {
              final id = p['id'] as String;
              if (on && picked.length < 8) {
                _picked[_brand] = [...picked, id];
              } else if (!on) {
                _picked[_brand] = picked.where((x) => x != id).toList();
              }
            }),
          ),
      ]),
    ];
  }

  List<Widget> _offerPicker(List<Map<String, dynamic>> list, Map<String, dynamic> logos) {
    final current = list.where((p) => p['id'] == _offerId).toList();
    return [
      if (current.isNotEmpty) _logoButton(WebStoreService.brandOf(current.first), logos),
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
  }

  // ---------------- Links ----------------

  /// Page the picture is about. [src]: status (shared link / caption) or qr.
  String _linkFor(Map<String, String> slugs, Map<String, dynamic> coupon, String src) {
    final ta = _tamil ? '/ta' : '';
    if (_kind == _Kind.prices) return '$_site$ta/shop/${WebStoreService.brandSlugs[_brand]}?src=$src';
    if (_kind == _Kind.offer) {
      final slug = _offerId == null ? null : slugs[_offerId];
      return slug == null ? '$_site$ta/?src=$src' : '$_site$ta/p/$slug?src=$src';
    }
    final code = (coupon['code'] ?? '').toString();
    return code.isEmpty ? '$_site$ta/?src=$src' : '$_site$ta/?coupon=$code&src=$src';
  }

  String? _extraText(Map<String, dynamic> coupon) {
    switch (_extra) {
      case _Extra.none:
        return null;
      case _Extra.coupon:
        if (coupon['on'] != true) return null;
        final v = (coupon['value'] as num?)?.toInt() ?? 0;
        final off = coupon['kind'] == 'percent' ? '$v%' : _rs(v.toDouble());
        return _tamil
            ? 'முதல் ஆர்டருக்கு $off தள்ளுபடி · குறியீடு ${coupon['code']}'
            : 'First order $off off · code ${coupon['code']}';
      case _Extra.today:
        return _tamil ? 'இன்று மட்டும்!' : 'Today only!';
      case _Extra.custom:
        final t = _customCtrl.text.trim();
        return t.isEmpty ? null : t;
    }
  }

  // ---------------- The picture ----------------

  Widget _picture(Map<String, dynamic> store, List<Map<String, dynamic>> online, Map<String, String> slugs,
      Map<String, dynamic> coupon, String? brand, Map<String, dynamic> logos) {
    final style = brand == null ? null : _brands[brand];
    final dark = style?.dark ?? _shopDark;
    final accent = style?.accent ?? _shopAccent;
    final local = (store['nameLocal'] ?? '').toString().trim();
    final en = (store['name'] ?? '').toString().trim();
    final shop = _tamil && local.isNotEmpty ? local : (en.isEmpty ? 'Sri Madhura Agro Traders' : en);
    final title = style == null ? shop : (_tamil ? style.ta : style.en);
    final sub = style == null ? '' : (_tamil ? '${style.tagTa} · $shop' : '${style.tagEn} · by $shop');
    final logo = _bytes(brand == null ? null : (logos[brand] ?? '').toString());
    final link = _linkFor(slugs, coupon, 'qr');
    final extra = _kind == _Kind.coupon ? null : _extraText(coupon);

    final Widget body;
    if (_kind == _Kind.prices) {
      final ids = _picked[_brand] ?? const <String>[];
      final items = [
        for (final id in ids) ...online.where((p) => p['id'] == id),
      ];
      body = _pricesBody(items, dark);
    } else if (_kind == _Kind.offer) {
      final p = online.where((x) => x['id'] == _offerId).toList();
      body = p.isEmpty ? _empty('Choose a product below') : _offerBody(p.first, dark);
    } else {
      body = coupon['on'] == true ? _couponBody(coupon, dark, accent) : _empty('Coupon is switched off');
    }

    return Container(
      width: 360,
      height: _tall ? 640 : 360,
      color: _cream,
      child: Column(
        children: [
          // Brand header
          Container(
            color: dark,
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
            child: Row(children: [
              ClipOval(
                child: Container(
                  color: Colors.white,
                  width: 38,
                  height: 38,
                  child: logo != null
                      ? Image.memory(logo, fit: BoxFit.cover)
                      : Image.asset('assets/logo.png', fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800, height: 1.1)),
                  if (sub.isNotEmpty)
                    Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: accent, fontSize: 10.5, fontWeight: FontWeight.w600)),
                ]),
              ),
            ]),
          ),
          if (extra != null)
            Container(
              width: double.infinity,
              color: accent,
              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
              child: Text('🎁 $extra',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: dark, fontSize: 13, fontWeight: FontWeight.w800)),
            ),
          Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(14, 8, 14, 6), child: body)),
          // Order bar: big address + reply line + small QR
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: dark, borderRadius: BorderRadius.circular(999)),
                    child: Text('🛒 $_siteLabel',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _tamil ? '👉 ஆர்டர் செய்ய இந்த ஸ்டேட்டஸுக்கு பதில் அனுப்புங்கள்' : '👉 Reply "ORDER" to this status',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: _wa, fontWeight: FontWeight.w700),
                  ),
                ]),
              ),
              QrImageView(
                data: link,
                version: QrVersions.auto,
                size: 54,
                padding: const EdgeInsets.all(2),
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

  Widget _pricesBody(List<Map<String, dynamic>> items, Color dark) {
    final today = DateFormat('dd-MM-yyyy').format(DateTime.now());
    if (items.isEmpty) return _empty('Choose products below');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(_tamil ? 'இன்றைய விலை · $today' : "Today's prices · $today",
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: dark)),
      const SizedBox(height: 4),
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
                      style: const TextStyle(fontSize: 11, color: Colors.black38, decoration: TextDecoration.lineThrough)),
                  const SizedBox(width: 4),
                ],
                Text(_rs(WebStoreService.webPriceOf(p)),
                    style: TextStyle(fontSize: _tall ? 16 : 14, fontWeight: FontWeight.w800, color: dark)),
              ]),
          ],
        ),
      ),
    ]);
  }

  Widget _offerBody(Map<String, dynamic> p, Color dark) {
    final price = WebStoreService.priceOf(p);
    final now = WebStoreService.webPriceOf(p);
    final photo = _bytes(p['photo'] as String?);
    final save = price - now;
    final en = (p['name'] ?? '').toString().trim();
    final ta = tamilNameOf(p).trim();
    return Column(children: [
      if (save > 0)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          decoration: BoxDecoration(color: const Color(0xFFD94A1E), borderRadius: BorderRadius.circular(999)),
          child: Text(_tamil ? '${_rs(save)} சேமிப்பு' : 'Save ${_rs(save)}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
        ),
      const SizedBox(height: 5),
      if (photo != null)
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(photo, fit: BoxFit.cover, width: double.infinity),
          ),
        )
      else
        Expanded(child: Icon(Icons.grass, size: 72, color: dark.withOpacity(0.5))),
      const SizedBox(height: 5),
      Text(_tamil && ta.isNotEmpty ? ta : en,
          textAlign: TextAlign.center,
          maxLines: 2,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: dark, height: 1.1)),
      if (ta.isNotEmpty && ta != en)
        Text(_tamil ? en : ta, style: const TextStyle(fontSize: 12, color: Colors.black54)),
      Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        if (save > 0) ...[
          Text(_rs(price),
              style: const TextStyle(fontSize: 14, color: Colors.black38, decoration: TextDecoration.lineThrough)),
          const SizedBox(width: 8),
        ],
        Text(_rs(now), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: dark)),
        const SizedBox(width: 6),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('/ ${_pack(p)}', style: const TextStyle(fontSize: 13, color: Colors.black54)),
        ),
      ]),
    ]);
  }

  Widget _couponBody(Map<String, dynamic> c, Color dark, Color accent) {
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
          style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900, color: dark, height: 1.05)),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accent, width: 2),
        ),
        child: Text(code, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 2, color: dark)),
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
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: dark)),
      ],
    ]);
  }

  // ---------------- Share ----------------

  String _caption(Map<String, String> slugs, Map<String, dynamic> coupon) {
    final link = _linkFor(slugs, coupon, 'status');
    if (_kind == _Kind.prices) {
      final b = _brands[_brand]!;
      return _tamil ? '${b.ta} — இன்றைய விலை. ஆர்டர் செய்ய: $link' : "${b.en} — today's prices. Order here: $link";
    }
    if (_kind == _Kind.offer) {
      return _tamil ? 'இன்றைய ஆஃபர் — ஆர்டர் செய்ய: $link' : "Today's offer — order here: $link";
    }
    return _tamil
        ? 'முதல் ஆர்டருக்கு தள்ளுபடி! குறியீடு ${coupon['code']} — $link'
        : 'Discount on your first order! Code ${coupon['code']} — $link';
  }

  Future<void> _share(Map<String, String> slugs, Map<String, dynamic> coupon) async {
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
      await Share.shareXFiles([XFile(file.path)], text: _caption(slugs, coupon));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not make the picture: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A link alone: WhatsApp shows it as a card with the product photo, name
  /// and price, and people can tap it (a picture can't be tapped).
  Future<void> _shareLink(Map<String, String> slugs, Map<String, dynamic> coupon) async {
    final link = _linkFor(slugs, coupon, 'status');
    final String line;
    if (_kind == _Kind.prices) {
      final b = _brands[_brand]!;
      line = _tamil ? '🛒 ${b.ta} — ஆன்லைனில் ஆர்டர் செய்யுங்கள்' : '🛒 ${b.en} — order online';
    } else if (_kind == _Kind.offer) {
      line = _tamil ? '🛒 இன்றைய ஆஃபர் — தட்டி ஆர்டர் செய்யுங்கள்' : "🛒 Today's offer — tap to order";
    } else {
      line = _tamil ? '🎁 முதல் ஆர்டருக்கு தள்ளுபடி — குறியீடு ${coupon['code']}' : '🎁 First order discount — code ${coupon['code']}';
    }
    await Share.share('$line\n$link');
  }
}
