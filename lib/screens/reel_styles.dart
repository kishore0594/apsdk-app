import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Status / Reels video: every product gets 3 seconds in its own style,
/// slides swipe into each other, and the video ends on the shop card
/// (logo, web address, QR, "Reply ORDER"). Drawn on a 360 × 640 canvas
/// and exported at 1080 × 1920. Text stays inside the area WhatsApp and
/// Instagram leave free (not the bottom ~95 px or the top ~35 px).

enum ReelStyle { farm, spotlight, slam, pack, podium, story, polaroid, split }

const reelStyleNames = {
  ReelStyle.farm: 'Fresh Farm',
  ReelStyle.spotlight: 'Glow Spotlight',
  ReelStyle.slam: 'Price Slam',
  ReelStyle.pack: 'Pack Float',
  ReelStyle.podium: 'Pack Podium',
  ReelStyle.story: 'Field Story',
  ReelStyle.polaroid: 'Polaroid Drop',
  ReelStyle.split: 'Split Scene',
};

/// "Mix for me" order: lively styles first, calm ones between.
const reelMixOrder = [ReelStyle.farm, ReelStyle.slam, ReelStyle.spotlight, ReelStyle.story, ReelStyle.polaroid];

enum ReelBg { auto, field, millet, harvest, shop, table, koozh, kali, pongal, own }

const reelBgNames = {
  ReelBg.auto: 'Best for style',
  ReelBg.field: 'Millet field',
  ReelBg.millet: 'Millet close-up',
  ReelBg.harvest: 'Harvest',
  ReelBg.shop: 'Grain shop',
  ReelBg.table: 'Grain bowls',
  ReelBg.koozh: 'Koozh pot',
  ReelBg.kali: 'Ragi kali',
  ReelBg.pongal: 'Pongal',
  ReelBg.own: 'My photo',
};

String? reelBgAsset(ReelBg b) => switch (b) {
      ReelBg.auto || ReelBg.own => null,
      _ => 'assets/reel/${b.name}.jpg',
    };

/// Background each style uses when "Best for style" is chosen
/// (null = the style draws its own: product photo or colours).
ReelBg? reelDefaultBg(ReelStyle s) => switch (s) {
      ReelStyle.farm => ReelBg.field,
      ReelStyle.story => ReelBg.shop,
      ReelStyle.polaroid => ReelBg.table,
      ReelStyle.split => ReelBg.harvest,
      _ => null,
    };

class ReelProduct {
  final String id;
  final String name; // big name (chosen language)
  final String otherName; // other language, small
  final String price; // "₹43"
  final String unit; // "500 g"
  final Uint8List? photo;
  ReelStyle style;
  ReelBg bg;
  String? ownBg; // file path when bg == own
  ReelProduct({
    required this.id,
    required this.name,
    required this.otherName,
    required this.price,
    required this.unit,
    required this.photo,
    this.style = ReelStyle.farm,
    this.bg = ReelBg.auto,
    this.ownBg,
  });
}

/// The shop's own photo as a slide (shop front, harvest, delivery…).
class ReelCustom {
  String path;
  String caption;
  ReelCustom(this.path, this.caption);
}

class ReelSlide {
  final ReelProduct? product;
  final ReelCustom? custom;
  const ReelSlide.product(ReelProduct p)
      : product = p,
        custom = null;
  const ReelSlide.custom(ReelCustom c)
      : product = null,
        custom = c;
}

class ReelInfo {
  final String brand; // "Madhura Millets"
  final String shop; // "Sri Madhura Agro Traders"
  final String site; // "madhuraagro.in"
  final String qrLink;
  final Uint8List? logo;
  final bool tamil;
  final Color dark, accent;
  final String? extra; // offer line ("Today only!") or null
  const ReelInfo({
    required this.brand,
    required this.shop,
    required this.site,
    required this.qrLink,
    required this.logo,
    required this.tamil,
    required this.dark,
    required this.accent,
    this.extra,
  });

  String get reply => tamil ? 'ஆர்டருக்கு பதில் அனுப்புங்கள்' : 'Reply "ORDER"';
  String get todayPrice => tamil ? 'இன்றைய விலை' : "TODAY'S PRICE";
  String get headline => tamil ? 'நம்ம ஊர் கடை' : 'From our village shop';
  String get fresh => tamil ? 'புதிய சரக்கு' : 'Fresh stock';
  String get tagline => tamil ? 'நம்ம ஊர் கடையிலிருந்து' : 'Fresh from our family shop';
}

// ---------------- easing ----------------

double _p(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0).toDouble();
double _out(double x) => 1 - math.pow(1 - x, 3).toDouble();
double _back(double x) {
  const c1 = 1.70158, c3 = c1 + 1;
  return (1 + c3 * math.pow(x - 1, 3) + c1 * math.pow(x - 1, 2)).toDouble();
}

double _bounce(double x) {
  const n1 = 7.5625, d1 = 2.75;
  if (x < 1 / d1) return n1 * x * x;
  if (x < 2 / d1) {
    x -= 1.5 / d1;
    return n1 * x * x + 0.75;
  }
  if (x < 2.5 / d1) {
    x -= 2.25 / d1;
    return n1 * x * x + 0.9375;
  }
  x -= 2.625 / d1;
  return n1 * x * x + 0.984375;
}

/// A short "heartbeat" twice: for the Reply ORDER button.
double _pulse(double t, double at) {
  double beat(double s) {
    final x = (t - s) / 0.22;
    return x < 0 || x > 1 ? 0.0 : math.sin(x * math.pi);
  }

  return 1 + 0.07 * (beat(at) + beat(at + 0.35));
}

const _W = 360.0, _H = 640.0, _secs = 3.0, _swipe = 0.4;
const _shadow = [Shadow(color: Color(0x99000000), offset: Offset(0, 2), blurRadius: 8)];
const _fallback = ['Baloo'];
const _waGreen = Color(0xFF25D366);

TextStyle _st(String family, double size, Color color,
        {double weight = 400, List<Shadow>? shadows, double? height, double spacing = 0}) =>
    TextStyle(
      fontFamily: family,
      fontFamilyFallback: _fallback,
      fontSize: size,
      color: color,
      height: height,
      letterSpacing: spacing,
      shadows: shadows,
      fontWeight: weight >= 700 ? FontWeight.w800 : FontWeight.w400,
      fontVariations: family == 'Baloo' ? [ui.FontVariation('wght', weight)] : null,
    );

class ReelRenderer {
  final List<ReelSlide> slides;
  final ReelInfo info;
  ReelRenderer(this.slides, this.info);

  double get duration => (slides.length + 1) * _secs;

  final Map<String, ui.Image> _images = {};
  final Map<String, TextPainter> _texts = {};
  late final List<_Dot> _dots = _makeDots();
  bool loaded = false;

  ui.Image? _img(String? key) => key == null ? null : _images[key];

  static Future<ui.Image?> _decode(Uint8List? bytes, {int? width}) async {
    if (bytes == null || bytes.isEmpty) return null;
    try {
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: width);
      return (await codec.getNextFrame()).image;
    } catch (_) {
      return null;
    }
  }

  Future<void> _put(String key, Future<Uint8List?> bytes, {int? width}) async {
    if (_images.containsKey(key)) return;
    final img = await _decode(await bytes, width: width);
    if (img != null) _images[key] = img;
  }

  static Future<Uint8List?> _asset(String path) async {
    try {
      return (await rootBundle.load(path)).buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// Loads every picture the video needs. [readFile] reads a phone file
  /// (the shop's own photos), passed in so this file stays free of dart:io.
  Future<void> load(Future<Uint8List?> Function(String path) readFile) async {
    final jobs = <Future<void>>[];
    jobs.add(_put('leaves', _asset('assets/reel/leaves.webp'), width: 720));
    jobs.add(_put('applogo', _asset('assets/logo.png'), width: 256));
    jobs.add(_put('field', _asset('assets/reel/field.jpg'), width: 1080));
    if (info.logo != null) jobs.add(_put('logo', Future.value(info.logo), width: 256));
    jobs.add(() async {
      try {
        final qr = await QrPainter(
          data: info.qrLink,
          version: QrVersions.auto,
          gapless: true,
          eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF123A1A)),
          dataModuleStyle:
              const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF123A1A)),
        ).toImage(300);
        _images['qr'] = qr;
      } catch (_) {/* no QR then */}
    }());
    for (final s in slides) {
      final p = s.product;
      if (p != null) {
        jobs.add(_put('photo:${p.id}', Future.value(p.photo), width: 900));
        final bg = _bgKey(p);
        if (bg != null) {
          jobs.add(_put(
              bg, p.bg == ReelBg.own ? readFile(p.ownBg!) : _asset(reelBgAsset(_bgOf(p))!),
              width: 1080));
        }
      }
      final c = s.custom;
      if (c != null) jobs.add(_put('own:${c.path}', readFile(c.path), width: 1080));
    }
    await Future.wait(jobs);
    loaded = true;
  }

  ReelBg _bgOf(ReelProduct p) => p.bg == ReelBg.auto ? (reelDefaultBg(p.style) ?? ReelBg.auto) : p.bg;

  String? _bgKey(ReelProduct p) {
    final b = _bgOf(p);
    if (b == ReelBg.auto) return null;
    if (b == ReelBg.own) return p.ownBg == null ? null : 'own:${p.ownBg}';
    return b.name;
  }

  void dispose() {
    for (final i in _images.values) {
      i.dispose();
    }
    _images.clear();
    _texts.clear();
  }

  // ---------------- frame ----------------

  /// Draws the frame at time [t] seconds into a canvas of [size].
  void paint(Canvas c, Size size, double t) {
    c.save();
    c.scale(size.width / _W, size.height / _H);
    c.clipRect(const Rect.fromLTWH(0, 0, _W, _H));
    c.drawRect(const Rect.fromLTWH(0, 0, _W, _H), Paint()..color = const Color(0xFF123A1A));
    final n = slides.length + 1;
    final i = math.min((t / _secs).floor(), n - 1);
    final lt = t - i * _secs;
    if (i > 0 && lt < _swipe) {
      _slide(c, i - 1, _secs + lt);
      final k = _out(lt / _swipe);
      c.save();
      c.translate((1 - k) * _W * 0.35, 0);
      _fade(c, k, () => _slide(c, i, lt));
      c.restore();
    } else {
      _slide(c, i, lt);
    }
    c.restore();
  }

  void _slide(Canvas c, int i, double lt) {
    if (i >= slides.length) return _end(c, lt);
    final s = slides[i];
    if (s.custom != null) return _custom(c, s.custom!, lt);
    final p = s.product!;
    switch (p.style) {
      case ReelStyle.farm:
        _farm(c, p, lt);
      case ReelStyle.spotlight:
        _spotlight(c, p, lt);
      case ReelStyle.slam:
        _slam(c, p, lt);
      case ReelStyle.pack:
        _pack(c, p, lt);
      case ReelStyle.podium:
        _podium(c, p, lt);
      case ReelStyle.story:
        _story(c, p, lt);
      case ReelStyle.polaroid:
        _polaroid(c, p, lt);
      case ReelStyle.split:
        _split(c, p, lt);
    }
  }

  // ---------------- drawing helpers ----------------

  void _fade(Canvas c, double a, void Function() draw) {
    if (a <= 0.001) return;
    if (a >= 0.999) return draw();
    c.saveLayer(null, Paint()..color = Color.fromRGBO(255, 255, 255, a));
    draw();
    c.restore();
  }

  void _at(Canvas c, Offset pivot, void Function() draw, {double scale = 1, double rot = 0, Offset shift = Offset.zero}) {
    c.save();
    c.translate(pivot.dx + shift.dx, pivot.dy + shift.dy);
    if (rot != 0) c.rotate(rot);
    if (scale != 1) c.scale(scale);
    c.translate(-pivot.dx, -pivot.dy);
    draw();
    c.restore();
  }

  /// Draws [img] to fill [dst] (cropping), with zoom/pan/blur/dim.
  void _cover(Canvas c, ui.Image? img, Rect dst,
      {double zoom = 1, Offset pan = Offset.zero, double blur = 0, double dim = 0, Color? fallback}) {
    c.save();
    c.clipRect(dst);
    if (img == null) {
      c.drawRect(dst, Paint()..color = fallback ?? info.dark);
    } else {
      final iw = img.width.toDouble(), ih = img.height.toDouble();
      final s = math.max(dst.width / iw, dst.height / ih) * zoom;
      final w = iw * s, h = ih * s;
      final r = Rect.fromLTWH(
          dst.center.dx - w / 2 + pan.dx * dst.width, dst.center.dy - h / 2 + pan.dy * dst.height, w, h);
      if (blur > 0) {
        c.saveLayer(dst, Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur, tileMode: TileMode.clamp));
      }
      c.drawImageRect(img, Rect.fromLTWH(0, 0, iw, ih), r, Paint()..filterQuality = FilterQuality.medium);
      if (blur > 0) c.restore();
    }
    if (dim > 0) c.drawRect(dst, Paint()..color = Color.fromRGBO(0, 0, 0, dim));
    c.restore();
  }

  void _round(Canvas c, ui.Image? img, RRect r, {double zoom = 1, bool shadow = true, Color? fallback}) {
    if (shadow) c.drawShadow(Path()..addRRect(r), Colors.black, 14, false);
    c.save();
    c.clipRRect(r);
    if (img == null) {
      c.drawRRect(r, Paint()..color = fallback ?? info.dark);
      _icon(c, r.center, r.width * 0.3);
    } else {
      _cover(c, img, r.outerRect, zoom: zoom);
    }
    c.restore();
  }

  void _disc(Canvas c, ui.Image? img, Offset center, double radius, {double border = 0, Color borderColor = Colors.white}) {
    if (radius <= 0.5) return;
    final rect = Rect.fromCircle(center: center, radius: radius);
    if (border > 0) {
      c.drawShadow(Path()..addOval(rect.inflate(border)), Colors.black, 12, false);
      c.drawCircle(center, radius + border, Paint()..color = borderColor);
    }
    c.save();
    c.clipPath(Path()..addOval(rect));
    if (img == null) {
      c.drawRect(rect, Paint()..color = info.dark);
      _icon(c, center, radius * 0.6);
    } else {
      _cover(c, img, rect);
    }
    c.restore();
  }

  /// A simple grain-stalk mark for products without a photo.
  void _icon(Canvas c, Offset o, double s) {
    final p = Paint()
      ..color = info.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.08
      ..strokeCap = StrokeCap.round;
    c.drawLine(o + Offset(0, s * 0.5), o - Offset(0, s * 0.5), p);
    for (var k = 0; k < 4; k++) {
      final y = -s * 0.35 + k * s * 0.2;
      c.drawOval(Rect.fromCenter(center: o + Offset(-s * 0.13, y), width: s * 0.2, height: s * 0.12), p);
      c.drawOval(Rect.fromCenter(center: o + Offset(s * 0.13, y), width: s * 0.2, height: s * 0.12), p);
    }
  }

  TextPainter _tp(String s, TextStyle st, {double maxW = 320, int lines = 1, TextAlign align = TextAlign.left}) {
    final key = '$s|${st.hashCode}|$maxW|$lines|${align.index}';
    final hit = _texts[key];
    if (hit != null) return hit;
    var size = st.fontSize ?? 20;
    late TextPainter tp;
    while (true) {
      tp = TextPainter(
        text: TextSpan(text: s, style: st.copyWith(fontSize: size)),
        textDirection: TextDirection.ltr,
        textAlign: align,
        maxLines: lines,
        ellipsis: '…',
      )..layout(maxWidth: lines == 1 ? double.infinity : maxW);
      final fits = lines == 1 ? tp.width <= maxW : !tp.didExceedMaxLines;
      if (fits || size <= (st.fontSize ?? 20) * 0.55) break;
      size -= 1;
    }
    if (lines == 1 && tp.width > maxW) {
      tp = TextPainter(
        text: TextSpan(text: s, style: st.copyWith(fontSize: size)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: maxW);
    }
    if (_texts.length > 400) _texts.clear();
    _texts[key] = tp;
    return tp;
  }

  /// Text centred on [cx] at [y] (top). Returns its height.
  double _textC(Canvas c, String s, TextStyle st, double cx, double y, {double maxW = 320, int lines = 1}) {
    if (s.isEmpty) return 0;
    final tp = _tp(s, st, maxW: maxW, lines: lines, align: TextAlign.center);
    tp.paint(c, Offset(cx - tp.width / 2, y));
    return tp.height;
  }

  double _textL(Canvas c, String s, TextStyle st, double x, double y, {double maxW = 320, int lines = 1}) {
    if (s.isEmpty) return 0;
    final tp = _tp(s, st, maxW: maxW, lines: lines);
    tp.paint(c, Offset(x, y));
    return tp.height;
  }

  /// Typewriter reveal from the left.
  void _typed(Canvas c, String s, TextStyle st, double x, double y, double f, {double maxW = 320}) {
    if (f <= 0 || s.isEmpty) return;
    final tp = _tp(s, st, maxW: maxW);
    c.save();
    c.clipRect(Rect.fromLTWH(x - 4, y - 6, (tp.width + 8) * f, tp.height + 12));
    tp.paint(c, Offset(x, y));
    c.restore();
  }

  void _pill(Canvas c, Rect r, Color color, {double radius = 999}) =>
      c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(math.min(radius, r.height / 2))), Paint()..color = color);

  /// Green "Reply ORDER" button with a heartbeat.
  void _reply(Canvas c, double y, double lt, {double width = 260, double at = 1.3}) {
    final s = _pulse(lt, at);
    _at(c, Offset(_W / 2, y + 23), () {
      final r = Rect.fromCenter(center: Offset(_W / 2, y + 23), width: width, height: 46);
      c.drawShadow(Path()..addRRect(RRect.fromRectAndRadius(r, const Radius.circular(23))), Colors.black, 6, false);
      _pill(c, r, _waGreen);
      _chat(c, Offset(r.left + 26, r.center.dy), 10);
      final tp = _tp(info.reply, _st('Baloo', 17, Colors.white, weight: 800), maxW: width - 64);
      tp.paint(c, Offset(r.center.dx - tp.width / 2 + 10, r.center.dy - tp.height / 2));
    }, scale: s);
  }

  void _chat(Canvas c, Offset o, double r) {
    final p = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    c.drawCircle(o, r, p);
    c.drawLine(o + Offset(-r * 0.7, r * 0.7), o + Offset(-r * 1.0, r * 1.15), p);
  }

  /// Logo + brand name, top-left.
  void _brand(Canvas c, double x, double y, double a, {bool light = true}) {
    _fade(c, a, () {
      final logo = _img('logo') ?? _img('applogo');
      _disc(c, logo, Offset(x + 16, y + 16), 15, border: 2, borderColor: light ? Colors.white : info.dark);
      _textL(c, info.brand, _st('Baloo', 15, light ? Colors.white : info.dark, weight: 800, shadows: light ? _shadow : null),
          x + 38, y + 4,
          maxW: 230);
    });
  }

  Path _star(Offset o, double r, {int points = 12, double inner = 0.82}) {
    final path = Path();
    for (var k = 0; k < points * 2; k++) {
      final a = -math.pi / 2 + k * math.pi / points;
      final rr = k.isEven ? r : r * inner;
      final pt = o + Offset(math.cos(a) * rr, math.sin(a) * rr);
      if (k == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    return path..close();
  }

  void _sparkle(Canvas c, Offset o, double size, double a) {
    if (a <= 0) return;
    final p = Path()
      ..moveTo(o.dx, o.dy - size)
      ..quadraticBezierTo(o.dx, o.dy, o.dx + size, o.dy)
      ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy + size)
      ..quadraticBezierTo(o.dx, o.dy, o.dx - size, o.dy)
      ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy - size)
      ..close();
    c.drawPath(p, Paint()..color = Color.fromRGBO(255, 255, 255, a));
  }

  List<_Dot> _makeDots() {
    final r = math.Random(7);
    return List.generate(
        26, (_) => _Dot(r.nextDouble() * _W, r.nextDouble() * _H, 6.0 + r.nextDouble() * 16, 1.2 + r.nextDouble() * 2.4, r.nextDouble() * 6.28));
  }

  /// Floating pollen / grain dust.
  void _dust(Canvas c, double lt, {Color color = const Color(0xFFFFE6A0), double alpha = 0.7}) {
    for (final d in _dots) {
      final y = (d.y - d.speed * lt * 3 + _H) % _H;
      final x = d.x + math.sin(d.phase + lt * 1.4) * 8;
      final a = alpha * (0.45 + 0.55 * math.sin(d.phase + lt * 2).abs());
      c.drawCircle(Offset(x, y), d.size, Paint()..color = color.withOpacity(a.clamp(0.0, 1.0).toDouble()));
    }
  }

  /// Warm sun with a slow breathing glow and lens ghosts.
  void _sun(Canvas c, double lt, Offset o) {
    final r = 150.0 * (1 + 0.06 * math.sin(lt * 2.1));
    c.drawCircle(
        o,
        r,
        Paint()
          ..shader = ui.Gradient.radial(o, r, const [Color(0xCCFFF6D8), Color(0x55FFC768), Color(0x00FFB040)], const [0, 0.35, 1])
          ..blendMode = BlendMode.screen);
    final toC = const Offset(_W / 2, _H / 2) - o;
    for (final g in const [(0.55, 16.0, 0.12), (0.8, 26.0, 0.08), (1.15, 10.0, 0.14)]) {
      c.drawCircle(o + toC * g.$1, g.$2, Paint()..color = Color.fromRGBO(255, 230, 170, g.$3));
    }
  }

  /// A soft band of light sweeping across.
  void _sweep(Canvas c, double lt) {
    final x = -200.0 + (lt / _secs) * 760;
    c.drawRect(
        const Rect.fromLTWH(0, 0, _W, _H),
        Paint()
          ..shader = ui.Gradient.linear(Offset(x - 120, 0), Offset(x + 120, _H * 0.4),
              const [Color(0x00FFFFFF), Color(0x26FFFFFF), Color(0x00FFFFFF)], const [0, 0.5, 1])
          ..blendMode = BlendMode.screen);
  }

  /// Real leaves framing the picture, swaying a little.
  void _leaves(Canvas c, double lt, {double alpha = 1, double enter = 1}) {
    final img = _img('leaves');
    if (img == null) return;
    final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    final k = _out(enter);
    _fade(c, alpha * k, () {
      for (final left in [true, false]) {
        c.save();
        c.clipRect(left ? const Rect.fromLTWH(0, 0, _W / 2, _H) : const Rect.fromLTWH(_W / 2, 0, _W / 2, _H));
        final pivot = left ? const Offset(0, _H) : const Offset(_W, _H);
        final sway = (left ? 1.0 : -1.0) * 0.016 * math.sin(lt * (left ? 1.7 : 1.5) + (left ? 0.0 : 1.0));
        _at(c, pivot, () {
          c.drawImageRect(img, src, const Rect.fromLTWH(0, 0, _W, _H), Paint()..filterQuality = FilterQuality.medium);
        }, rot: sway, scale: 1 + 0.12 * (1 - k), shift: Offset((left ? -20.0 : 26.0) - (left ? 30.0 : -30.0) * (1 - k), 0));
        c.restore();
      }
    });
  }

  void _shade(Canvas c, double top, double bottom, double from, double to) => c.drawRect(
      Rect.fromLTRB(0, top, _W, bottom),
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, top), Offset(0, bottom),
            [Color.fromRGBO(0, 0, 0, from), Color.fromRGBO(0, 0, 0, to)]));

  ui.Image? _bg(ReelProduct p) => _img(_bgKey(p));
  ui.Image? _photo(ReelProduct p) => _img('photo:${p.id}');

  /// Small yellow chip with the offer line ("Today only!").
  void _extraChip(Canvas c, double cx, double y, double a) {
    final e = info.extra;
    if (e == null || e.isEmpty) return;
    _fade(c, a, () {
      final tp = _tp(e, _st('Baloo', 15, const Color(0xFF3B1E06), weight: 800), maxW: 290);
      final r = Rect.fromCenter(center: Offset(cx, y + tp.height / 2), width: tp.width + 26, height: tp.height + 8);
      _pill(c, r, const Color(0xFFFFD54A));
      tp.paint(c, Offset(r.center.dx - tp.width / 2, r.center.dy - tp.height / 2));
    });
  }

  /// Price + unit on one line ("₹43 / 500 g").
  TextPainter _priceTp(ReelProduct p, String family, double size, Color color, {Color? unitColor, double unitSize = 0}) {
    final key = 'price|${p.price}|${p.unit}|$family|$size|${color.hashCode}|${unitColor?.hashCode}|$unitSize';
    final hit = _texts[key];
    if (hit != null) return hit;
    final tp = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(children: [
        TextSpan(text: p.price, style: _st(family, size, color)),
        if (p.unit.isNotEmpty)
          TextSpan(
              text: '  / ${p.unit}',
              style: _st('Baloo', unitSize == 0 ? size * 0.36 : unitSize, unitColor ?? color, weight: 700)),
      ]),
    )..layout();
    _texts[key] = tp;
    return tp;
  }

  // ---------------- styles ----------------

  /// Fresh Farm: real field, sunlight, floating pollen, leaves frame.
  void _farm(Canvas c, ReelProduct p, double lt) {
    final k = lt / _secs;
    _cover(c, _bg(p) ?? _img('field'), const Rect.fromLTWH(0, 0, _W, _H),
        zoom: 1.06 + 0.1 * k, pan: Offset(0, -0.012 * k));
    _sun(c, lt, const Offset(300, 70));
    _sweep(c, lt);
    _shade(c, 300, _H, 0, 0.6);
    _leaves(c, lt, enter: _p(lt, 0, 0.6));
    _dust(c, lt);
    _brand(c, 18, 40, _p(lt, 0.05, 0.35));
    _extraChip(c, _W / 2, 120, _p(lt, 0.8, 1.1));
    final pop = _p(lt, 0.15, 0.55);
    _fade(c, pop, () {
      _at(c, const Offset(180, 245), () => _disc(c, _photo(p), const Offset(180, 245), 86, border: 6),
          scale: 0.6 + 0.4 * _back(pop));
    });
    final a1 = _p(lt, 0.35, 0.7);
    _fade(c, a1, () {
      _textC(c, p.name, _st('Pacifico', 38, Colors.white, shadows: _shadow), _W / 2, 345 + 20 * (1 - _out(a1)), maxW: 320);
    });
    final a2 = _p(lt, 0.45, 0.8);
    _fade(c, a2, () {
      _textC(c, p.otherName, _st('Baloo', 24, const Color(0xFFFFF3C4), weight: 800, shadows: _shadow), _W / 2,
          400 + 16 * (1 - _out(a2)));
    });
    final a3 = _p(lt, 0.6, 0.85);
    _fade(c, a3, () {
      final tp = _priceTp(p, 'Anton', 34, info.dark, unitColor: const Color(0xFF4A5A44), unitSize: 15);
      final r = Rect.fromCenter(center: const Offset(_W / 2, 468), width: tp.width + 40, height: 56);
      _at(c, r.center, () {
        c.drawShadow(Path()..addRRect(RRect.fromRectAndRadius(r, const Radius.circular(28))), Colors.black, 8, false);
        _pill(c, r, Colors.white);
        tp.paint(c, Offset(r.center.dx - tp.width / 2, r.center.dy - tp.height / 2));
      }, scale: 1.6 - 0.6 * _back(a3));
    });
    _fade(c, _p(lt, 1.0, 1.3), () {
      _textC(c, '${info.reply}  ·  ${info.site}', _st('Baloo', 14, Colors.white, weight: 700, shadows: _shadow), _W / 2, 512);
    });
  }

  /// Glow Spotlight: blurred grains, colour ring, price sticker.
  void _spotlight(Canvas c, ReelProduct p, double lt) {
    final bg = _bg(p);
    if (bg != null) {
      _cover(c, bg, const Rect.fromLTWH(0, 0, _W, _H), zoom: 1.1, blur: 6, dim: 0.45);
    } else {
      _cover(c, _photo(p), const Rect.fromLTWH(0, 0, _W, _H), zoom: 1.4, blur: 18, dim: 0.5);
    }
    _dust(c, lt, alpha: 0.35);
    _brand(c, 18, 36, _p(lt, 0, 0.3));
    const o = Offset(180, 270);
    _fade(c, _p(lt, 0, 0.3), () {
      _at(c, o, () {
        c.drawCircle(
            o,
            130,
            Paint()
              ..shader = ui.Gradient.sweep(o, const [
                Color(0xFFFFD54A),
                Color(0xFFFF7A2F),
                Color(0xFFFFD54A),
                Color(0xFF7CE38B),
                Color(0xFFFFD54A),
              ], const [0, 0.25, 0.5, 0.75, 1]));
      }, rot: lt * 1.1);
    });
    _disc(c, _photo(p), o, 118 * _out(_p(lt, 0.1, 0.5)), border: _p(lt, 0.45, 0.5) * 4);
    final a1 = _p(lt, 0, 0.35);
    _fade(c, a1, () {
      _textC(c, p.name, _st('Pacifico', 40, Colors.white, shadows: _shadow), _W / 2, 80 + 24 * (1 - _out(a1)));
    });
    final a2 = _p(lt, 0.4, 0.75);
    _fade(c, a2, () {
      _textC(c, p.otherName, _st('Baloo', 30, const Color(0xFFFFE27A), weight: 800, shadows: _shadow), _W / 2,
          414 + 20 * (1 - _out(a2)));
    });
    _extraChip(c, _W / 2, 462, _p(lt, 0.8, 1.1));
    final s = _p(lt, 0.3, 0.6);
    if (s > 0) {
      const so = Offset(286, 372);
      _at(c, so, () {
        c.drawShadow(_star(so, 64), Colors.black, 8, false);
        c.drawPath(_star(so, 64), Paint()..color = const Color(0xFFFFD54A));
        final pr = _tp(p.price, _st('Anton', 30, const Color(0xFF2B1606)), maxW: 100);
        final un = _tp(p.unit, _st('Baloo', 12, const Color(0xFF2B1606), weight: 800), maxW: 90);
        pr.paint(c, Offset(so.dx - pr.width / 2, so.dy - pr.height / 2 - 6));
        un.paint(c, Offset(so.dx - un.width / 2, so.dy + pr.height / 2 - 10));
      }, scale: _back(s), rot: -0.3 * (1 - s));
    }
    _fade(c, _p(lt, 0.9, 1.2), () => _reply(c, 492, lt));
  }

  /// Price Slam: photo zooms, price lands hard on a yellow band.
  void _slam(Canvas c, ReelProduct p, double lt) {
    final k = _out(lt / _secs);
    _cover(c, _photo(p) ?? _bg(p), const Rect.fromLTWH(0, 0, _W, _H),
        zoom: 1.05 + 0.2 * k, pan: Offset(-0.03 * k, -0.02 * k));
    _shade(c, 0, 230, 0.45, 0);
    _shade(c, 330, _H, 0, 0.78);
    final a = _out(_p(lt, 0.05, 0.35));
    if (a > 0) {
      final st = info.tamil
          ? _st('Baloo', 22, Colors.white, weight: 800)
          : _st('Bebas', 32, Colors.white, spacing: 1.5);
      final tp = _tp(info.extra?.isNotEmpty == true ? info.extra! : info.todayPrice, st, maxW: 300);
      final r = Rect.fromLTWH(16 - (1 - a) * 340, 52, tp.width + 24, tp.height + 6);
      c.drawRect(r, Paint()..color = const Color(0xFFE5322D));
      tp.paint(c, Offset(r.left + 12, r.top + 3));
    }
    _brand(c, 16, 100, _p(lt, 0.2, 0.5));
    final b = _out(_p(lt, 0.15, 0.45));
    if (b > 0) {
      _at(c, const Offset(180, 365), () {
        c.drawRect(Rect.fromLTWH(-60 - (1 - b) * 520, 300, 480, 130), Paint()..color = const Color(0xFFFFE14D));
      }, rot: -0.105);
    }
    final s = _p(lt, 0.45, 0.7);
    if (s > 0) {
      final scale = s < 0.6 ? 2.6 - 1.68 * (s / 0.6) : 0.92 + 0.08 * ((s - 0.6) / 0.4);
      final shake = lt > 0.7 && lt < 0.95 ? math.sin(lt * 90) * 3 * (1 - _p(lt, 0.7, 0.95)) : 0.0;
      final tp = _priceTp(p, 'Anton', 86, const Color(0xFF141414), unitSize: 24);
      _fade(c, math.min(1.0, s * 3), () {
        _at(c, const Offset(180, 365), () {
          tp.paint(c, Offset(180 - tp.width / 2, 365 - tp.height / 2));
        }, scale: scale, rot: -0.105, shift: Offset(shake, 0));
      });
    }
    final n = _p(lt, 0.6, 0.9);
    _fade(c, n, () {
      final y = 446 + 16 * (1 - _out(n));
      final h = _textL(c, p.name, _st('Bebas', 46, Colors.white, shadows: _shadow), 20, y, maxW: 320);
      _textL(c, p.otherName, _st('Baloo', 21, const Color(0xFFFFE14D), weight: 800), 20, y + h - 6, maxW: 320);
    });
    _fade(c, _p(lt, 0.9, 1.2), () {
      _textL(c, '${info.site}  ·  ${info.reply}', _st('Baloo', 14, Colors.white, weight: 700, shadows: _shadow), 20, 524,
          maxW: 320);
    });
  }

  /// Pack Float: packed product on warm sun rays.
  void _pack(Canvas c, ReelProduct p, double lt) {
    final bg = _bg(p);
    const o = Offset(180, 260);
    if (bg != null) {
      _cover(c, bg, const Rect.fromLTWH(0, 0, _W, _H), zoom: 1.1, blur: 5);
      c.drawRect(const Rect.fromLTWH(0, 0, _W, _H), Paint()..color = const Color(0x66F5C877));
    } else {
      c.drawRect(
          const Rect.fromLTWH(0, 0, _W, _H),
          Paint()
            ..shader = ui.Gradient.radial(
                o, 420, const [Color(0xFFFFF4D2), Color(0xFFF5C877), Color(0xFFC9862F)], const [0, 0.45, 1]));
    }
    _at(c, o, () {
      final ray = Paint()..color = const Color(0x38FFFFFF);
      for (var k = 0; k < 18; k++) {
        final a = k * math.pi / 9;
        c.drawPath(
            Path()
              ..moveTo(o.dx, o.dy)
              ..lineTo(o.dx + math.cos(a - 0.07) * 700, o.dy + math.sin(a - 0.07) * 700)
              ..lineTo(o.dx + math.cos(a + 0.07) * 700, o.dy + math.sin(a + 0.07) * 700)
              ..close(),
            ray);
      }
    }, rot: lt * 0.35);
    _brand(c, 18, 36, _p(lt, 0, 0.3), light: false);
    final e = _out(_p(lt, 0, 0.5));
    final r = RRect.fromRectAndRadius(Rect.fromCenter(center: const Offset(180, 245), width: 220, height: 240), const Radius.circular(14));
    _fade(c, e, () {
      _at(c, r.center, () {
        _round(c, _photo(p), r);
        c.save();
        c.clipRRect(r);
        _at(c, r.outerRect.topLeft + const Offset(46, 46), () {
          final band = Rect.fromCenter(center: r.outerRect.topLeft + const Offset(46, 46), width: 200, height: 26);
          c.drawRect(band, Paint()..color = const Color(0xFFC62828));
          final tp = _tp(info.brand.toUpperCase(), _st('Bebas', 16, Colors.white, spacing: 1.2), maxW: 120);
          tp.paint(c, Offset(band.center.dx - tp.width / 2, band.center.dy - tp.height / 2));
        }, rot: -math.pi / 4);
        c.restore();
      },
          shift: Offset(0, 60 * (1 - e) - 6 * math.sin(lt * 2.2) * e),
          rot: -0.1 * (1 - e) + 0.035 * math.sin(lt * 1.8) - 0.02);
    });
    for (final s in const [(40.0, 120.0, 0.0), (320.0, 170.0, 0.6), (50.0, 360.0, 1.1), (318.0, 330.0, 0.3), (180.0, 96.0, 0.9)]) {
      final x = ((lt - s.$3) % 1.6) / 1.6;
      _sparkle(c, Offset(s.$1, s.$2), 9 * math.sin(x * math.pi), math.sin(x * math.pi) * 0.95);
    }
    final a1 = _p(lt, 0.35, 0.7);
    _fade(c, a1, () {
      _textC(c, p.name, _st('Kaushan', 34, const Color(0xFF3B1E06)), _W / 2, 384 + 14 * (1 - _out(a1)));
      _textC(c, p.otherName, _st('Baloo', 21, const Color(0xFF6B2E0A), weight: 800), _W / 2, 428 + 14 * (1 - _out(a1)));
    });
    final a2 = _p(lt, 0.55, 0.85);
    if (a2 > 0) {
      final tp = _priceTp(p, 'Anton', 30, const Color(0xFFFFE7A8), unitSize: 15);
      final rr = Rect.fromCenter(center: const Offset(_W / 2, 486), width: tp.width + 34, height: 50);
      _at(c, rr.center, () {
        _pill(c, rr, const Color(0xFF3B1E06), radius: 14);
        tp.paint(c, Offset(rr.center.dx - tp.width / 2, rr.center.dy - tp.height / 2));
      }, scale: _back(a2));
    }
    _fade(c, _p(lt, 0.9, 1.2), () {
      _textC(c, '${info.site}  ·  ${info.reply}', _st('Baloo', 13.5, const Color(0xFF3B1E06), weight: 800), _W / 2, 522);
    });
  }

  /// Pack Podium: the pack drops onto a gold stage under a spotlight.
  void _podium(Canvas c, ReelProduct p, double lt) {
    const full = Rect.fromLTWH(0, 0, _W, _H);
    final bg = _bg(p);
    if (bg != null) {
      _cover(c, bg, full, zoom: 1.1, blur: 4, dim: 0.62);
    } else {
      c.drawRect(full,
          Paint()..shader = ui.Gradient.radial(const Offset(180, 200), 460, const [Color(0xFF2F6B3A), Color(0xFF0E2A15)]));
    }
    _fade(c, _p(lt, 0, 0.3), () {
      c.drawPath(
          Path()
            ..moveTo(150, -10)
            ..lineTo(210, -10)
            ..lineTo(340, 480)
            ..lineTo(20, 480)
            ..close(),
          Paint()
            ..shader = ui.Gradient.linear(const Offset(0, 0), const Offset(0, 480),
                const [Color(0x88FFECAA), Color(0x00FFECAA)]));
    });
    _dust(c, lt, alpha: 0.45);
    final a = _p(lt, 0.1, 0.4);
    _fade(c, a, () {
      _textC(c, p.name, _st('Kaushan', 34, const Color(0xFFFFE7A8), shadows: _shadow), _W / 2, 58);
      _textC(c, p.otherName, _st('Baloo', 19, Colors.white, weight: 800), _W / 2, 104);
    });
    // stage
    _fade(c, _p(lt, 0, 0.25), () {
      c.drawRect(const Rect.fromLTWH(70, 452, 220, 22), Paint()..color = const Color(0xFF7E5B1A));
      c.drawOval(const Rect.fromLTWH(70, 462, 220, 24), Paint()..color = const Color(0xFF7E5B1A));
      c.drawOval(
          const Rect.fromLTWH(70, 440, 220, 26),
          Paint()
            ..shader = ui.Gradient.linear(const Offset(70, 440), const Offset(290, 466),
                const [Color(0xFFF3D27A), Color(0xFFB8862C)]));
    });
    final d = _p(lt, 0.1, 0.65);
    if (d > 0) {
      final y = -480 * (1 - _bounce(d));
      _round(c, _photo(p), RRect.fromRectAndRadius(Rect.fromLTWH(95, 262 + y, 170, 190), const Radius.circular(10)));
    }
    final u = _out(_p(lt, 0.65, 0.95));
    if (u > 0) {
      final tp = _priceTp(p, 'Anton', 28, Colors.white, unitSize: 14);
      final r = Rect.fromCenter(center: const Offset(180, 512), width: math.max(220.0, tp.width + 70), height: 46);
      c.save();
      c.translate(r.center.dx, r.center.dy);
      c.scale(u, 1);
      c.translate(-r.center.dx, -r.center.dy);
      {
        c.drawPath(
            Path()
              ..moveTo(r.left, r.top)
              ..lineTo(r.right, r.top)
              ..lineTo(r.right - 14, r.center.dy)
              ..lineTo(r.right, r.bottom)
              ..lineTo(r.left, r.bottom)
              ..lineTo(r.left + 14, r.center.dy)
              ..close(),
            Paint()..color = const Color(0xFFC62828));
        tp.paint(c, Offset(r.center.dx - tp.width / 2, r.center.dy - tp.height / 2));
      }
      c.restore();
    }
    _fade(c, _p(lt, 0.9, 1.2), () {
      _textC(c, '${info.site}  ·  ${info.reply}', _st('Baloo', 13, const Color(0xFFE9C46A), weight: 800), _W / 2, 140);
    });
  }

  /// Field Story: real scene that pans, with a frosted glass card.
  void _story(Canvas c, ReelProduct p, double lt) {
    const full = Rect.fromLTWH(0, 0, _W, _H);
    final pan = Offset(0.05 - 0.1 * (lt / _secs), 0);
    final bg = _bg(p) ?? _img('field');
    _cover(c, bg, full, zoom: 1.3, pan: pan);
    _shade(c, 0, 200, 0.45, 0);
    _dust(c, lt, alpha: 0.4);
    _typed(c, info.extra?.isNotEmpty == true ? info.extra! : info.headline,
        _st('Kavivanar', 28, Colors.white, shadows: _shadow), 20, 52, _p(lt, 0.1, 0.7),
        maxW: 320);
    _brand(c, 18, 100, _p(lt, 0.3, 0.6));
    final e = _out(_p(lt, 0.15, 0.5));
    if (e <= 0) return;
    final card = RRect.fromRectAndRadius(Rect.fromLTWH(16, 376 + 70 * (1 - e), 328, 156), const Radius.circular(26));
    _fade(c, e, () {
      c.drawShadow(Path()..addRRect(card), Colors.black, 10, false);
      c.save();
      c.clipRRect(card);
      _cover(c, bg, full, zoom: 1.3, pan: pan, blur: 14);
      c.drawRRect(card, Paint()..color = const Color(0xA6FFFFFF));
      c.restore();
      c.drawRRect(
          card,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = const Color(0xCCFFFFFF));
      final top = card.top;
      _round(c, _photo(p), RRect.fromRectAndRadius(Rect.fromLTWH(30, top + 18, 118, 118), const Radius.circular(18)),
          shadow: false);
      var y = top + 16;
      y += _textL(c, p.name, _st('Baloo', 23, const Color(0xFF1F2A1C), weight: 800), 162, y, maxW: 172) - 4;
      y += _textL(c, p.otherName, _st('Kavivanar', 19, const Color(0xFF2E6B2F)), 162, y, maxW: 172);
      final tp = _priceTp(p, 'Anton', 30, const Color(0xFF8A3B1E), unitColor: const Color(0xFF4A5A44), unitSize: 13);
      tp.paint(c, Offset(162, y));
      _textL(c, '${info.site} · ${info.reply}', _st('Baloo', 11.5, const Color(0xFF4A5A44), weight: 700), 162, top + 128,
          maxW: 172);
    });
  }

  /// Polaroid Drop: a photo print falls onto the scene, price circled by hand.
  void _polaroid(Canvas c, ReelProduct p, double lt) {
    const full = Rect.fromLTWH(0, 0, _W, _H);
    _cover(c, _bg(p) ?? _img('field'), full, zoom: 1.12 + 0.08 * (lt / _secs), dim: 0.18);
    _shade(c, 360, _H, 0, 0.55);
    _brand(c, 18, 38, _p(lt, 0, 0.3));
    final e = _p(lt, 0.05, 0.45);
    if (e > 0) {
      final k = _back(e);
      const frame = Rect.fromLTWH(55, 92, 250, 292);
      _at(c, frame.center, () {
        c.drawShadow(Path()..addRect(frame), Colors.black, 16, false);
        c.drawRect(frame, Paint()..color = const Color(0xFFFFFDF7));
        _cover(c, _photo(p), Rect.fromLTWH(frame.left + 12, frame.top + 12, 226, 226), fallback: info.dark);
        if (_photo(p) == null) _icon(c, Offset(frame.center.dx, frame.top + 125), 70);
        _textC(c, p.otherName.isNotEmpty ? p.otherName : p.name, _st('Kavivanar', 22, const Color(0xFF1F2A1C)),
            frame.center.dx, frame.top + 244,
            maxW: 230);
        _at(c, Offset(frame.center.dx, frame.top), () {
          c.drawRect(Rect.fromCenter(center: Offset(frame.center.dx, frame.top), width: 84, height: 24),
              Paint()..color = const Color(0xD9FFECAA));
        }, rot: 0.05);
      }, shift: Offset(0, -560 * (1 - k)), rot: -0.5 * (1 - k) - 0.07);
    }
    final n = _p(lt, 0.4, 0.7);
    _fade(c, n, () {
      _textL(c, p.name, _st('Bebas', 40, Colors.white, shadows: _shadow), 22, 400, maxW: 190);
    });
    final pr = _p(lt, 0.5, 0.75);
    if (pr > 0) {
      final tp = _tp(p.price, _st('Anton', 46, Colors.white, shadows: _shadow), maxW: 130);
      const o = Offset(272, 428);
      _at(c, o, () => tp.paint(c, Offset(o.dx - tp.width / 2, o.dy - tp.height / 2)), scale: _back(pr));
      _textC(c, p.unit, _st('Baloo', 13, Colors.white, weight: 800, shadows: _shadow), o.dx, o.dy + 30);
      final ring = Path()
        ..moveTo(o.dx + 10, o.dy - 40)
        ..cubicTo(o.dx - 70, o.dy - 44, o.dx - 76, o.dy + 40, o.dx - 4, o.dy + 46)
        ..cubicTo(o.dx + 66, o.dy + 50, o.dx + 82, o.dy - 30, o.dx - 18, o.dy - 36);
      final f = _p(lt, 0.6, 0.95);
      final out = Path();
      for (final m in ring.computeMetrics()) {
        out.addPath(m.extractPath(0, m.length * f), Offset.zero);
      }
      c.drawPath(
          out,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..strokeCap = StrokeCap.round
            ..color = const Color(0xFFFFD54A));
    }
    _fade(c, _p(lt, 0.8, 1.1), () {
      c.drawRect(const Rect.fromLTWH(0, 488, _W, 56), Paint()..color = const Color(0xEB123A1A));
      _textL(c, info.site, _st('Baloo', 15, Colors.white, weight: 800), 16, 503, maxW: 160);
      final tp = _tp(info.reply, _st('Baloo', 13, Colors.white, weight: 800), maxW: 160);
      final r = Rect.fromLTWH(_W - 16 - tp.width - 24, 500, tp.width + 24, 32);
      _pill(c, r, _waGreen);
      tp.paint(c, Offset(r.left + 12, r.center.dy - tp.height / 2));
    });
  }

  /// Split Scene: scene photo on top, clean product details below.
  void _split(Canvas c, ReelProduct p, double lt) {
    _cover(c, _bg(p) ?? _img('field'), const Rect.fromLTWH(0, 0, _W, 360),
        zoom: 1.25, pan: Offset(0.04 - 0.08 * (lt / _secs), 0));
    c.drawRect(const Rect.fromLTWH(0, 360, _W, 280), Paint()..color = const Color(0xFFFFF6E5));
    _dust(c, lt, alpha: 0.35);
    final h = _out(_p(lt, 0.05, 0.35));
    if (h > 0) {
      final tp = _tp(info.extra?.isNotEmpty == true ? info.extra! : info.fresh, _st('Baloo', 15, Colors.white, weight: 800),
          maxW: 300);
      final r = Rect.fromLTWH(16 - (1 - h) * 300, 46, tp.width + 26, tp.height + 8);
      _pill(c, r, info.dark);
      tp.paint(c, Offset(r.left + 13, r.top + 4));
    }
    _brand(c, 16, 92, _p(lt, 0.2, 0.5));
    final d = _p(lt, 0.2, 0.5);
    if (d > 0) {
      _at(c, const Offset(262, 360), () => _disc(c, _photo(p), const Offset(262, 360), 74, border: 6, borderColor: const Color(0xFFFFF6E5)),
          scale: _back(d));
    }
    final n = _p(lt, 0.35, 0.65);
    _fade(c, n, () {
      final y = 384 + 14 * (1 - _out(n));
      final hh = _textL(c, p.name, _st('Bebas', 44, const Color(0xFF1F2A1C)), 22, y, maxW: 160);
      _textL(c, p.otherName, _st('Kavivanar', 22, info.dark), 22, y + hh - 6, maxW: 170);
    });
    final pr = _p(lt, 0.5, 0.8);
    _fade(c, pr, () {
      final dash = Paint()
        ..color = const Color(0xFFD9C9A3)
        ..strokeWidth = 2;
      for (var x = 22.0; x < 338; x += 10) {
        c.drawLine(Offset(x, 470), Offset(x + 5, 470), dash);
      }
      final tp = _priceTp(p, 'Anton', 40, const Color(0xFF8A3B1E), unitColor: const Color(0xFF5E6B57), unitSize: 14);
      tp.paint(c, Offset(22, 474 + 10 * (1 - _out(pr))));
    });
    _fade(c, _p(lt, 0.8, 1.1), () {
      _textL(c, info.site, _st('Baloo', 13.5, const Color(0xFF1F2A1C), weight: 800), 22, 530, maxW: 160);
      final tp = _tp(info.reply, _st('Baloo', 13.5, const Color(0xFF0E7A5F), weight: 800), maxW: 160);
      tp.paint(c, Offset(_W - 22 - tp.width, 530));
    });
  }

  /// The shop's own photo with a caption.
  void _custom(Canvas c, ReelCustom s, double lt) {
    const full = Rect.fromLTWH(0, 0, _W, _H);
    _cover(c, _img('own:${s.path}'), full, zoom: 1.05 + 0.12 * (lt / _secs));
    _shade(c, 0, 160, 0.4, 0);
    _shade(c, 300, _H, 0, 0.7);
    _dust(c, lt, alpha: 0.35);
    _brand(c, 18, 40, _p(lt, 0.05, 0.35));
    final a = _p(lt, 0.3, 0.7);
    _fade(c, a, () {
      _textC(c, s.caption, _st('Baloo', 28, Colors.white, weight: 800, shadows: _shadow, height: 1.15), _W / 2,
          410 + 18 * (1 - _out(a)),
          maxW: 320, lines: 2);
    });
    _fade(c, _p(lt, 0.8, 1.1), () {
      _textC(c, '${info.site}  ·  ${info.reply}', _st('Baloo', 14, Colors.white, weight: 700, shadows: _shadow), _W / 2, 516);
    });
  }

  /// Last card: logo, web address, QR, Reply ORDER.
  void _end(Canvas c, double lt) {
    const full = Rect.fromLTWH(0, 0, _W, _H);
    _cover(c, _img('field'), full, zoom: 1.15 + 0.05 * (lt / _secs), dim: 0.2);
    c.drawRect(
        full,
        Paint()
          ..shader = ui.Gradient.linear(const Offset(0, 0), const Offset(0, _H),
              const [Color(0x8C123A1A), Color(0xD9123A1A), Color(0xF2123A1A)], const [0, 0.5, 1]));
    _leaves(c, lt, alpha: 0.95, enter: _p(lt, 0, 0.5));
    _dust(c, lt, alpha: 0.5);
    final l = _p(lt, 0.05, 0.4);
    if (l > 0) {
      final logo = _img('logo') ?? _img('applogo');
      _at(c, const Offset(180, 176), () => _disc(c, logo, const Offset(180, 176), 62, border: 4, borderColor: const Color(0xFFE9C46A)),
          scale: _back(l));
    }
    _fade(c, _p(lt, 0.25, 0.5), () {
      _textC(c, info.shop, _st('Baloo', 18, const Color(0xFFE9C46A), weight: 800), _W / 2, 250, maxW: 300);
    });
    _typed(c, info.site, _st('Baloo', 32, Colors.white, weight: 800, shadows: _shadow), _W / 2 - _tp(info.site, _st('Baloo', 32, Colors.white, weight: 800, shadows: _shadow), maxW: 320).width / 2,
        276, _p(lt, 0.3, 0.8));
    _fade(c, _p(lt, 0.5, 0.8), () {
      _textC(c, info.tagline, _st('Kaushan', 20, const Color(0xFFE9C46A)), _W / 2, 326, maxW: 320);
    });
    final q = _p(lt, 0.55, 0.85);
    final qr = _img('qr');
    if (q > 0 && qr != null) {
      _fade(c, q, () {
        final r = Rect.fromLTWH(122, 372 + 16 * (1 - _out(q)), 116, 116);
        c.drawRRect(RRect.fromRectAndRadius(r.inflate(6), const Radius.circular(10)), Paint()..color = Colors.white);
        c.drawImageRect(qr, Rect.fromLTWH(0, 0, qr.width.toDouble(), qr.height.toDouble()), r, Paint());
      });
    }
    _fade(c, _p(lt, 0.8, 1.1), () => _reply(c, 498, lt, width: 280, at: 1.4));
  }
}

class _Dot {
  final double x, y, speed, size, phase;
  const _Dot(this.x, this.y, this.speed, this.size, this.phase);
}

/// Live preview in the app (loops the whole video).
class ReelPainter extends CustomPainter {
  final ReelRenderer renderer;
  final Animation<double> time; // 0..1 of the whole video
  ReelPainter(this.renderer, this.time) : super(repaint: time);

  @override
  void paint(Canvas canvas, Size size) {
    if (!renderer.loaded) {
      canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF123A1A));
      return;
    }
    renderer.paint(canvas, size, time.value * renderer.duration);
  }

  @override
  bool shouldRepaint(ReelPainter old) => old.renderer != renderer;
}
