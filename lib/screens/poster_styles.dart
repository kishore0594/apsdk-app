import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Everything one offer poster shows (one product per poster; up to 5
/// posters are shared together and WhatsApp Status plays them in a row).
class PosterData {
  final String brand; // "Madhura Millets"
  final String brandSub; // "by Sri Madhura Agro Traders"
  final String name; // big name (Tamil or English, as chosen)
  final String otherName; // the other language, small
  final String price; // "₹80"
  final String oldPrice; // "₹90" or ''
  final String save; // "Save ₹10" or ''
  final String unit; // "1 kg"
  final Uint8List? photo;
  final Uint8List? logo;
  final Color dark; // brand colour
  final Color accent;
  final String? extra; // offer line, e.g. "Today only!"
  final int index; // 1-based
  final int total;
  final String site; // "madhuraagro.in"
  final String reply; // 'Reply "ORDER" to this status'
  final String qr; // link the QR opens
  final bool tamil;
  final Uint8List? background; // the shop's own photo for this style (optional)
  final List<PosterItem> items; // every chosen product (Variety Grid)
  final String shop; // "Sri Madhura Agro Traders"
  const PosterData({
    this.background,
    this.items = const [],
    this.shop = '',
    required this.brand,
    required this.brandSub,
    required this.name,
    required this.otherName,
    required this.price,
    required this.oldPrice,
    required this.save,
    required this.unit,
    required this.photo,
    required this.logo,
    required this.dark,
    required this.accent,
    required this.extra,
    required this.index,
    required this.total,
    required this.site,
    required this.reply,
    required this.qr,
    required this.tamil,
  });

  String get step => total > 1 ? (tamil ? '$index / $total' : '$index of $total') : '';
}

/// One product on the Variety Grid.
class PosterItem {
  final String name, otherName, price, unit;
  final Uint8List? photo;
  final Color color;
  const PosterItem(this.name, this.otherName, this.price, this.unit, this.photo, this.color);
}

enum PosterStyle { classic, pop, kraft, night, festive, grid, hero, meals, local }

const posterStyleNames = {
  PosterStyle.classic: 'Classic',
  PosterStyle.pop: 'Bold Pop',
  PosterStyle.kraft: 'Fresh Market',
  PosterStyle.night: 'Night Deal',
  PosterStyle.festive: 'Festive Kolam',
  PosterStyle.grid: 'Variety Grid',
  PosterStyle.hero: 'Hero Banner',
  PosterStyle.meals: 'Healthy Meals',
  PosterStyle.local: 'Support Local',
};

/// Styles that make ONE picture for all chosen products (the others make one per product).
bool posterIsSingle(PosterStyle s) => s == PosterStyle.grid || s == PosterStyle.local;

/// Styles that can show the shop's own background photo.
bool posterUsesBackground(PosterStyle s) => s == PosterStyle.hero || s == PosterStyle.meals || s == PosterStyle.local;

const _script = 'Kaushan'; // handwriting font (assets/fonts, SIL Open Font Licence)

/// The designed posters (Status size, 360 × 640 drawn; shared at 3×).
Widget buildPoster(PosterStyle style, PosterData d) => switch (style) {
      PosterStyle.pop => _BoldPop(d),
      PosterStyle.kraft => _FreshMarket(d),
      PosterStyle.night => _NightDeal(d),
      PosterStyle.festive => _Festive(d),
      PosterStyle.grid => _VarietyGrid(d),
      PosterStyle.hero => _HeroBanner(d),
      PosterStyle.meals => _HealthyMeals(d),
      PosterStyle.local => _SupportLocal(d),
      PosterStyle.classic => const SizedBox.shrink(), // drawn by the screen itself
    };

// ---------------- shared bits ----------------

Widget _photo(Uint8List? bytes, Color bg, Color fg, {BoxShape shape = BoxShape.rectangle, double radius = 0}) {
  return Container(
    decoration: BoxDecoration(
      color: bg,
      shape: shape,
      borderRadius: shape == BoxShape.circle ? null : BorderRadius.circular(radius),
      image: bytes == null ? null : DecorationImage(image: MemoryImage(bytes), fit: BoxFit.cover),
    ),
    alignment: Alignment.center,
    child: bytes == null ? Icon(Icons.grass, size: 64, color: fg) : null,
  );
}

Widget _logo(Uint8List? bytes, double size, Color bg) => ClipOval(
      child: Container(
        width: size,
        height: size,
        color: bg,
        child: bytes != null ? Image.memory(bytes, fit: BoxFit.cover) : Image.asset('assets/logo.png', fit: BoxFit.cover),
      ),
    );

Widget _qr(String data, double size, {Color bg = Colors.white}) => QrImageView(
      data: data,
      version: QrVersions.auto,
      size: size,
      padding: const EdgeInsets.all(2),
      backgroundColor: bg,
    );

Widget _cartIcon(Color c) => Icon(Icons.shopping_cart_outlined, size: 18, color: c);

const _waGreen = Color(0xFF0E7A5F);

// ---------------- A · Bold Pop ----------------

class _BoldPop extends StatelessWidget {
  final PosterData d;
  const _BoldPop(this.d);

  @override
  Widget build(BuildContext context) {
    const yellow = Color(0xFFF6C445);
    return Container(
      width: 360,
      height: 640,
      color: const Color(0xFFFFF6E5),
      child: Stack(clipBehavior: Clip.hardEdge, children: [
        Positioned(
          left: -60,
          top: -40,
          child: Transform.rotate(
            angle: -0.14,
            child: Container(
              width: 480,
              height: 400,
              decoration: BoxDecoration(
                  color: d.dark,
                  borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(60), bottomRight: Radius.circular(60))),
            ),
          ),
        ),
        Positioned(
          left: 20,
          top: 20,
          right: 20,
          child: Row(children: [
            _logo(d.logo, 34, Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d.brand,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17)),
                Text(d.brandSub, maxLines: 1, style: const TextStyle(color: yellow, fontSize: 11)),
              ]),
            ),
            if (d.step.isNotEmpty) Text(d.step, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
        ),
        Positioned(
          left: 22,
          top: 84,
          right: 140,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d.name.toUpperCase(),
                maxLines: 2,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w900, fontSize: 44, height: 0.95, letterSpacing: -0.5)),
            const SizedBox(height: 6),
            if (d.otherName.isNotEmpty)
              Text(d.otherName,
                  maxLines: 1,
                  style: const TextStyle(color: yellow, fontSize: 22, fontWeight: FontWeight.w700)),
          ]),
        ),
        Positioned(
          left: 70,
          top: 230,
          width: 220,
          height: 220,
          child: Container(
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 8)),
            child: _photo(d.photo, const Color(0xFFE9DCC0), const Color(0xFF8A7A55), shape: BoxShape.circle),
          ),
        ),
        Positioned(
          right: 16,
          top: 196,
          child: Transform.rotate(
            angle: 0.2,
            child: Container(
              width: 118,
              height: 118,
              decoration: const BoxDecoration(color: yellow, shape: BoxShape.circle),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (d.oldPrice.isNotEmpty)
                  Text(d.oldPrice,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700, decoration: TextDecoration.lineThrough, color: Colors.black54)),
                FittedBox(
                  child: Text(d.price,
                      style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, height: 1, color: Color(0xFF1B1B1B))),
                ),
                Text('/ ${d.unit}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1B1B1B))),
              ]),
            ),
          ),
        ),
        Positioned(
          left: 22,
          right: 22,
          top: 466,
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            if (d.save.isNotEmpty) _pill(d.save, const Color(0xFFD94A1E), Colors.white),
            if (d.extra != null) _pill(d.extra!, Colors.white, d.dark, border: d.dark),
          ]),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 116,
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(children: [
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: d.dark, borderRadius: BorderRadius.circular(999)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      _cartIcon(Colors.white),
                      const SizedBox(width: 6),
                      Text(d.site, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                    ]),
                  ),
                  const SizedBox(height: 6),
                  Text(d.reply,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _waGreen, fontWeight: FontWeight.w800, fontSize: 13)),
                ]),
              ),
              _qr(d.qr, 64),
            ]),
          ),
        ),
      ]),
    );
  }
}

Widget _pill(String text, Color bg, Color fg, {Color? border}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(999), border: border == null ? null : Border.all(color: border, width: 2)),
      child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 13)),
    );

// ---------------- B · Fresh Market ----------------

class _FreshMarket extends StatelessWidget {
  final PosterData d;
  const _FreshMarket(this.d);

  @override
  Widget build(BuildContext context) {
    const kraft = Color(0xFFE8D3A8);
    const ink = Color(0xFF3A2A14);
    const maroon = Color(0xFF7A1F2B);
    return Container(
      width: 360,
      height: 640,
      color: kraft,
      child: Stack(children: [
        Positioned.fill(
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFA9824A), width: 2),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 28,
          child: Column(children: [
            Text(d.tamil ? 'எங்கள் கடையிலிருந்து புதிதாக' : 'fresh from our shop',
                style: const TextStyle(color: maroon, fontSize: 22, fontStyle: FontStyle.italic, fontWeight: FontWeight.w700)),
            Text(d.brand.toUpperCase(),
                style: const TextStyle(color: ink, fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: 1)),
            Text(d.brandSub, style: const TextStyle(color: Color(0xFF6B5330), fontSize: 11)),
            if (d.step.isNotEmpty) Text(d.step, style: const TextStyle(color: Color(0xFF6B5330), fontSize: 11)),
          ]),
        ),
        Positioned(
          left: 50,
          top: 140,
          child: Transform.rotate(
            angle: -0.05,
            child: Container(
              width: 260,
              height: 236,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFFFFDF6), boxShadow: [
                BoxShadow(color: ink.withOpacity(0.25), blurRadius: 14, offset: const Offset(0, 6)),
              ]),
              child: Column(children: [
                SizedBox(height: 172, width: double.infinity, child: _photo(d.photo, const Color(0xFFD9C59A), const Color(0xFF6B5330))),
                const SizedBox(height: 4),
                Text(d.otherName.isEmpty ? d.name : '${d.name} · ${d.otherName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: ink, fontSize: 19, fontWeight: FontWeight.w800, fontStyle: FontStyle.italic)),
              ]),
            ),
          ),
        ),
        Positioned(
          right: 22,
          top: 352,
          child: Transform.rotate(
            angle: 0.14,
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 8, 16, 8),
              decoration: const BoxDecoration(
                color: maroon,
                borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(6), bottomLeft: Radius.circular(6), topRight: Radius.circular(14), bottomRight: Radius.circular(14)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (d.oldPrice.isNotEmpty)
                  Text(d.oldPrice,
                      style: const TextStyle(color: Color(0xFFF3DDB0), fontSize: 12, decoration: TextDecoration.lineThrough)),
                Text(d.price, style: const TextStyle(color: Color(0xFFFFF6E5), fontSize: 32, fontWeight: FontWeight.w900, height: 1)),
                Text('/ ${d.unit}', style: const TextStyle(color: Color(0xFFFFF6E5), fontSize: 12)),
              ]),
            ),
          ),
        ),
        Positioned(
          left: 30,
          top: 404,
          width: 190,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (d.save.isNotEmpty)
              Text(d.save, style: const TextStyle(color: maroon, fontSize: 20, fontWeight: FontWeight.w800, fontStyle: FontStyle.italic)),
            if (d.extra != null)
              Text(d.extra!, maxLines: 2, style: const TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w700)),
          ]),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 28,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(d.site, style: const TextStyle(color: Color(0xFFFFF6E5), fontSize: 20, fontWeight: FontWeight.w900)),
                  Text(d.reply,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFFF6C445), fontSize: 12.5, fontWeight: FontWeight.w700)),
                ]),
              ),
              _qr(d.qr, 56),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ---------------- C · Night Deal ----------------

class _NightDeal extends StatelessWidget {
  final PosterData d;
  const _NightDeal(this.d);

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF12161C);
    const lime = Color(0xFFC8F25A);
    const grey = Color(0xFF9AA3AD);
    final total = d.total < 1 ? 1 : d.total;
    return Container(
      width: 360,
      height: 640,
      color: bg,
      child: Stack(children: [
        Positioned(
          left: 14,
          right: 14,
          top: 12,
          child: Row(children: [
            for (var i = 1; i <= total; i++) ...[
              if (i > 1) const SizedBox(width: 4),
              Expanded(
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                      color: i <= d.index ? Colors.white : Colors.white.withOpacity(0.3), borderRadius: BorderRadius.circular(2)),
                ),
              ),
            ],
          ]),
        ),
        Positioned(
          left: 18,
          right: 18,
          top: 28,
          child: Row(children: [
            _logo(d.logo, 30, lime),
            const SizedBox(width: 8),
            Expanded(
              child: Text(d.brand,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
            ),
            if (d.step.isNotEmpty) Text(d.step, style: const TextStyle(color: grey, fontSize: 12)),
          ]),
        ),
        Positioned(
          left: 18,
          top: 80,
          child: Transform.rotate(
            angle: -0.05,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: lime, borderRadius: BorderRadius.circular(6)),
              child: Text(d.extra ?? (d.tamil ? 'இன்றைய டீல்' : "TODAY'S DEAL"),
                  style: const TextStyle(color: bg, fontWeight: FontWeight.w900, fontSize: 14)),
            ),
          ),
        ),
        Positioned(
          left: 30,
          top: 126,
          width: 300,
          height: 262,
          child: Container(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(28), border: Border.all(color: lime, width: 2)),
            clipBehavior: Clip.antiAlias,
            child: _photo(d.photo, const Color(0xFF232A33), grey, radius: 26),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          top: 400,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w900, height: 1.05)),
            if (d.otherName.isNotEmpty)
              Text(d.otherName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: lime, fontSize: 19, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(d.price, style: const TextStyle(color: lime, fontSize: 44, fontWeight: FontWeight.w900, height: 1)),
              const SizedBox(width: 10),
              if (d.oldPrice.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(d.oldPrice,
                      style: const TextStyle(color: grey, fontSize: 15, decoration: TextDecoration.lineThrough)),
                ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('/ ${d.unit}', style: const TextStyle(color: Colors.white, fontSize: 14)),
              ),
            ]),
          ]),
        ),
        Positioned(
          left: 14,
          right: 14,
          bottom: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(d.site, style: const TextStyle(color: bg, fontSize: 19, fontWeight: FontWeight.w900)),
                  Text(d.total > 1 && d.index < d.total ? '${d.reply} · ${d.tamil ? 'அடுத்தது →' : 'more →'}' : d.reply,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _waGreen, fontSize: 12.5, fontWeight: FontWeight.w800)),
                ]),
              ),
              _qr(d.qr, 52),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ---------------- D · Festive Kolam ----------------

class _Festive extends StatelessWidget {
  final PosterData d;
  const _Festive(this.d);

  @override
  Widget build(BuildContext context) {
    const maroon = Color(0xFF7A1F2B);
    const gold = Color(0xFFF2C14E);
    const cream = Color(0xFFF3DDB0);
    return Container(
      width: 360,
      height: 640,
      color: maroon,
      child: Stack(children: [
        Positioned.fill(
          child: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), border: Border.all(color: gold, width: 3)),
          ),
        ),
        Positioned.fill(
          child: Container(
            margin: const EdgeInsets.all(18),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16), border: Border.all(color: gold.withOpacity(0.55), width: 1.5)),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 30,
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (final r in const [2.0, 3.0, 8.0, 3.0, 2.0])
                Container(
                  width: r * 2,
                  height: r * 2,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: gold, width: 1.6)),
                ),
            ]),
            const SizedBox(height: 4),
            Text(d.extra ?? (d.tamil ? 'பண்டிகை சிறப்பு' : 'Festival special'),
                style: const TextStyle(color: gold, fontSize: 24, fontWeight: FontWeight.w900, height: 1.1)),
            Text(d.brand.toUpperCase(),
                style: const TextStyle(color: Color(0xFFFFF6E5), fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 1)),
            Text(d.step.isEmpty ? d.brandSub : '${d.brandSub} · ${d.step}',
                maxLines: 1, style: const TextStyle(color: cream, fontSize: 11)),
          ]),
        ),
        Positioned(
          left: 60,
          top: 152,
          width: 240,
          height: 240,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: gold, width: 3)),
            child: _photo(d.photo, cream, maroon, shape: BoxShape.circle),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          top: 404,
          child: Column(children: [
            Text(d.name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFFFF6E5), fontSize: 28, fontWeight: FontWeight.w900, height: 1.1)),
            if (d.otherName.isNotEmpty)
              Text(d.otherName, maxLines: 1, style: const TextStyle(color: cream, fontSize: 15)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              decoration: BoxDecoration(color: gold, borderRadius: BorderRadius.circular(999)),
              child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                if (d.oldPrice.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(d.oldPrice,
                        style: const TextStyle(color: Color(0xFF8A3A42), fontSize: 13, decoration: TextDecoration.lineThrough)),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(d.price, style: const TextStyle(color: Color(0xFF5A1520), fontSize: 30, fontWeight: FontWeight.w900)),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6, left: 4),
                  child: Text('/ ${d.unit}', style: const TextStyle(color: Color(0xFF5A1520), fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
          ]),
        ),
        Positioned(
          left: 26,
          right: 26,
          bottom: 30,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: const Color(0xFFFFF6E5), borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(d.site, style: const TextStyle(color: Color(0xFF5A1520), fontSize: 19, fontWeight: FontWeight.w900)),
                  Text(d.reply,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _waGreen, fontSize: 12, fontWeight: FontWeight.w800)),
                ]),
              ),
              _qr(d.qr, 50),
            ]),
          ),
        ),
      ]),
    );
  }
}


// ---------------- shared bits for E–H ----------------

const _leaf = Color(0xFF2E6B2F);
const _wood = Color(0xFF8A5A2A);

Widget _shopRow(PosterData d, {Color text = const Color(0xFF1F2A1C)}) => Row(mainAxisSize: MainAxisSize.min, children: [
      _logo(d.logo, 30, Colors.white),
      const SizedBox(width: 8),
      Flexible(
        child: Text(d.shop.isEmpty ? d.brand : d.shop,
            maxLines: 2, style: TextStyle(color: text, fontSize: 14, fontWeight: FontWeight.w800, height: 1.05)),
      ),
    ]);

Widget _orderBar(PosterData d, {Color bg = Colors.white, Color title = _leaf, Color sub = _waGreen, double radius = 0}) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(radius)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(d.site, style: TextStyle(color: title, fontSize: 18, fontWeight: FontWeight.w900)),
            Text(d.reply, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sub, fontSize: 12, fontWeight: FontWeight.w800)),
          ]),
        ),
        _qr(d.qr, 48),
      ]),
    );

Widget _bgOr(PosterData d, Widget fallback) => d.background != null
    ? Image.memory(d.background!, fit: BoxFit.cover, width: double.infinity, height: double.infinity)
    : fallback;

// ---------------- E · Variety Grid ----------------

class _VarietyGrid extends StatelessWidget {
  final PosterData d;
  const _VarietyGrid(this.d);

  @override
  Widget build(BuildContext context) {
    final items = d.items.take(6).toList();
    return Container(
      width: 360,
      height: 640,
      color: const Color(0xFFFBF5E6),
      child: Stack(children: [
        Positioned(
          left: 28,
          right: 28,
          top: 26,
          child: Transform.rotate(
            angle: -0.035,
            child: Container(
              height: 62,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: _leaf,
                borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(14), bottomRight: Radius.circular(14), topRight: Radius.circular(30), bottomLeft: Radius.circular(30)),
              ),
              child: FittedBox(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(d.name, style: const TextStyle(fontFamily: _script, color: Colors.white, fontSize: 32)),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 96,
          child: Text(d.otherName,
              textAlign: TextAlign.center, style: const TextStyle(fontFamily: _script, fontSize: 18, color: Color(0xFF3A2A14))),
        ),
        Positioned(
          left: 12,
          right: 12,
          top: 132,
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 10,
            children: [
              for (final it in items)
                SizedBox(
                  width: 106,
                  child: Column(children: [
                    Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFFA8743F), width: 5)),
                      child: _photo(it.photo, const Color(0xFFE6D3AE), const Color(0xFF7A5A30), shape: BoxShape.circle),
                    ),
                    Transform.translate(
                      offset: const Offset(0, -10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                        decoration: BoxDecoration(color: it.color, borderRadius: BorderRadius.circular(10)),
                        child: Column(children: [
                          Text(it.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
                          if (it.otherName.isNotEmpty)
                            Text(it.otherName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 9.5)),
                        ]),
                      ),
                    ),
                    Transform.translate(
                      offset: const Offset(0, -6),
                      child: Text('${it.price} / ${it.unit}',
                          maxLines: 1, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF3A2A14))),
                    ),
                  ]),
                ),
            ],
          ),
        ),
        Positioned(
          left: 22,
          right: 22,
          bottom: 74,
          child: Container(
            height: 40,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: _leaf,
              borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12), bottomRight: Radius.circular(12), topRight: Radius.circular(26), bottomLeft: Radius.circular(26)),
            ),
            child: Text(d.extra ?? (d.tamil ? '${d.brand} · ${d.shop}' : '${d.brand} · fresh & cleaned'),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w700)),
          ),
        ),
        Positioned(left: 0, right: 0, bottom: 0, child: _orderBar(d, bg: Colors.transparent)),
      ]),
    );
  }
}

// ---------------- F · Hero Banner ----------------

class _HeroBanner extends StatelessWidget {
  final PosterData d;
  const _HeroBanner(this.d);

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFF8A6A1E);
    return Container(
      width: 360,
      height: 640,
      color: const Color(0xFFF6F3EA),
      child: Stack(children: [
        Positioned(
          left: 0,
          right: 0,
          top: 232,
          height: 290,
          child: _bgOr(d, _photo(d.photo, const Color(0xFFCFE0B8), const Color(0xFF4D6B2A))),
        ),
        Positioned(left: 18, top: 18, right: 150, child: _shopRow(d)),
        Positioned(
          right: 16,
          top: 16,
          child: Transform.rotate(
            angle: -0.14,
            child: Text(d.tamil ? 'நல்ல உணவு\nநலமான வாழ்வு' : 'Good food\nHealthy life',
                textAlign: TextAlign.right, style: const TextStyle(fontFamily: _script, fontSize: 15, color: Color(0xFF4A3A1A), height: 1.15)),
          ),
        ),
        Positioned(
          left: 14,
          right: 14,
          top: 72,
          child: Column(children: [
            FittedBox(
              child: Text(d.name, style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w900, color: _leaf, height: 1.05)),
            ),
            if (d.otherName.isNotEmpty)
              FittedBox(child: Text(d.otherName, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: gold, height: 1.1))),
            const SizedBox(height: 4),
            Text('${d.brand} · ${d.price} / ${d.unit}${d.oldPrice.isNotEmpty ? '  (${d.oldPrice})' : ''}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, color: Color(0xFF8A3B1E), fontWeight: FontWeight.w700)),
            if (d.extra != null)
              Text(d.extra!, maxLines: 1, style: const TextStyle(fontSize: 14, color: Color(0xFF1F2A1C), fontWeight: FontWeight.w700)),
          ]),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 56,
          height: 64,
          child: Container(
            color: _leaf,
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _trust(Icons.eco_outlined, d.tamil ? 'இயற்கை\n& தூய்மை' : 'Natural\n& pure'),
              _trust(Icons.inventory_2_outlined, d.tamil ? 'சுத்தம் செய்து\nபேக் செய்தது' : 'Cleaned\n& packed'),
              _trust(Icons.storefront_outlined, d.tamil ? 'உள்ளூர்\nகடை' : 'Local\nshop'),
            ]),
          ),
        ),
        Positioned(left: 0, right: 0, bottom: 0, height: 56, child: _orderBar(d)),
      ]),
    );
  }
}

Widget _trust(IconData icon, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
        child: Icon(icon, size: 16, color: Colors.white),
      ),
      const SizedBox(width: 6),
      Text(text, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700, height: 1.1)),
    ]);

// ---------------- G · Healthy Meals ----------------

class _HealthyMeals extends StatelessWidget {
  final PosterData d;
  const _HealthyMeals(this.d);

  @override
  Widget build(BuildContext context) {
    final points = d.tamil
        ? ['பாரம்பரிய தமிழ் உணவு', 'சுத்தம் செய்து பேக் செய்தது', 'சமைக்க எளிது', 'வீட்டுக்கே டெலிவரி']
        : ['Traditional Tamil food', 'Cleaned & packed fresh', 'Easy to cook', 'Home delivery'];
    return Container(
      width: 360,
      height: 640,
      color: const Color(0xFFF7EFE2),
      child: Stack(children: [
        Positioned(
          right: -50,
          top: 196,
          width: 264,
          height: 264,
          child: Container(
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _wood, width: 10)),
            child: ClipOval(child: _bgOr(d, _photo(d.photo, const Color(0xFFB9874E), const Color(0xFFFFF6E5), shape: BoxShape.circle))),
          ),
        ),
        Positioned(left: 18, top: 18, right: 18, child: _shopRow(d)),
        Positioned(
          left: 18,
          right: 18,
          top: 62,
          child: Transform.rotate(
            angle: -0.06,
            alignment: Alignment.centerLeft,
            child: Text(d.tamil ? '${d.name}\nகுடும்பத்துக்காக' : '${d.name}\nfor the family',
                maxLines: 2, style: const TextStyle(fontFamily: _script, fontSize: 30, color: _leaf, height: 1.1)),
          ),
        ),
        Positioned(
          left: 22,
          top: 150,
          right: 120,
          child: Text('${d.brand} · ${d.price} / ${d.unit}',
              maxLines: 2, style: const TextStyle(fontSize: 14, color: Color(0xFF2B2116), fontWeight: FontWeight.w700)),
        ),
        Positioned(
          left: 18,
          top: 214,
          width: 160,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final pt in points)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(color: _leaf, shape: BoxShape.circle),
                    child: const Icon(Icons.check, size: 18, color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(pt, style: const TextStyle(fontSize: 12.5, height: 1.15, color: Color(0xFF2B2116)))),
                ]),
              ),
          ]),
        ),
        Positioned(
          left: 20,
          top: 470,
          child: Transform.rotate(
            angle: -0.06,
            child: Text(d.extra ?? (d.tamil ? 'எளிய உணவு…\nவலிமையான குடும்பம்' : 'Simple food…\nstrong family'),
                style: const TextStyle(fontFamily: _script, fontSize: 20, color: Color(0xFF2B2116), height: 1.15)),
          ),
        ),
        Positioned(
          left: 14,
          right: 14,
          bottom: 16,
          child: _orderBar(d, bg: _leaf, title: Colors.white, sub: const Color(0xFFF6C445), radius: 16),
        ),
      ]),
    );
  }
}

// ---------------- H · Support Local ----------------

class _SupportLocal extends StatelessWidget {
  final PosterData d;
  const _SupportLocal(this.d);

  @override
  Widget build(BuildContext context) {
    final lines = d.tamil
        ? ['சுத்தமான, புதிய தானியங்கள்', 'சிறுதானியங்கள் & பாரம்பரிய அரிசி', 'மாட்டுத் தீவனம் கிடைக்கும்', 'நியாயமான விலை', 'வீட்டுக்கே டெலிவரி · UPI']
        : ['Fresh, cleaned grains', 'Millets & traditional rice', 'Cattle feed available', 'Fair prices', 'Home delivery · UPI'];
    return Container(
      width: 360,
      height: 640,
      color: const Color(0xFFEFE3C4),
      child: Stack(children: [
        Positioned(
          left: 0,
          right: 0,
          top: 300,
          bottom: 0,
          child: _bgOr(d, Container(color: const Color(0xFFC9D79E))),
        ),
        Positioned(left: 18, top: 18, right: 18, child: _shopRow(d)),
        Positioned(
          left: 0,
          right: 0,
          top: 66,
          child: Transform.rotate(
            angle: -0.06,
            child: Text(d.tamil ? 'உள்ளூர் கடையை\nஆதரியுங்கள்' : 'Support Local\nBuy Local',
                textAlign: TextAlign.center, style: const TextStyle(fontFamily: _script, fontSize: 34, color: _leaf, height: 1.05)),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 166,
          child: Text(d.tamil ? 'உங்கள் அருகிலுள்ள கடையிலிருந்து' : 'Millets, rice & cattle feed\nfrom your nearby shop',
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 14.5, height: 1.25, color: Color(0xFF1F2A1C))),
        ),
        Positioned(
          left: 38,
          right: 38,
          top: 226,
          child: Transform.rotate(
            angle: -0.035,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _wood,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF6B4220), width: 4),
              ),
              child: Column(children: [
                for (final ln in lines)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      const Icon(Icons.check, size: 16, color: Color(0xFFFFF6E5)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(ln, style: const TextStyle(color: Color(0xFFFFF6E5), fontSize: 13.5, fontWeight: FontWeight.w700)),
                      ),
                    ]),
                  ),
              ]),
            ),
          ),
        ),
        Positioned(
          left: 18,
          bottom: 76,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 16, 8),
            decoration: BoxDecoration(color: _leaf, borderRadius: BorderRadius.circular(999)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.chat_outlined, color: Colors.white, size: 24),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d.tamil ? 'ஆர்டர் & விசாரணைக்கு' : 'For orders & enquiries', style: const TextStyle(color: Colors.white, fontSize: 11)),
                Text(d.tamil ? 'பதில் அனுப்புங்கள்' : 'Reply "ORDER"', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
              ]),
            ]),
          ),
        ),
        Positioned(
          right: 18,
          bottom: 80,
          child: Transform.rotate(
            angle: -0.17,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              color: const Color(0xFFFFF6E5),
              child: Text(d.extra ?? (d.tamil ? 'உங்கள் ஆதரவுக்கு\nநன்றி!' : 'Thank you for\nyour support!'),
                  style: const TextStyle(fontFamily: _script, fontSize: 14, color: Color(0xFF1F2A1C), height: 1.1)),
            ),
          ),
        ),
        Positioned(left: 0, right: 0, bottom: 0, height: 60, child: _orderBar(d)),
      ]),
    );
  }
}
