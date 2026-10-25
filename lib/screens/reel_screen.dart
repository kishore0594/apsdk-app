import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/app_theme.dart';
import 'reel_styles.dart';
import 'send_to_customers.dart';

/// Makes one Status / Reels video (MP4, 1080 × 1920): 3 seconds per
/// product, each in its own style and background, optional own photos,
/// then the shop card. Made on the phone by the app's own encoder.
class ReelScreen extends StatefulWidget {
  final List<ReelProduct> products;
  final ReelInfo info;
  final String caption; // text sent with the video (has the order link)
  const ReelScreen({super.key, required this.products, required this.info, required this.caption});

  @override
  State<ReelScreen> createState() => _ReelScreenState();
}

class _ReelScreenState extends State<ReelScreen> with SingleTickerProviderStateMixin {
  late final List<ReelProduct> _products = widget.products;
  final List<ReelCustom> _customs = [];
  final Map<ReelCustom, TextEditingController> _captions = {};
  bool _ownFirst = true;
  ReelRenderer? _renderer;
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(seconds: 6));
  int _gen = 0;
  double? _progress; // making the video
  String? _video; // last made video file
  bool _paused = false;

  static const _wa = Color(0xFF128C7E);

  List<ReelSlide> get _slides => [
        if (_ownFirst) ..._customs.map((c) => ReelSlide.custom(c)),
        ..._products.map((p) => ReelSlide.product(p)),
        if (!_ownFirst) ..._customs.map((c) => ReelSlide.custom(c)),
      ];

  @override
  void initState() {
    super.initState();
    _rebuild();
  }

  @override
  void dispose() {
    _anim.dispose();
    _renderer?.dispose();
    for (final c in _captions.values) {
      c.dispose();
    }
    super.dispose();
  }

  static Future<Uint8List?> _readFile(String path) async {
    try {
      return await File(path).readAsBytes();
    } catch (_) {
      return null;
    }
  }

  /// New drawing set-up after a style, background or photo change.
  Future<void> _rebuild() async {
    final gen = ++_gen;
    _video = null;
    final r = ReelRenderer(_slides, widget.info);
    await r.load(_readFile);
    if (!mounted || gen != _gen) {
      r.dispose();
      return;
    }
    final old = _renderer;
    setState(() => _renderer = r);
    old?.dispose();
    _anim.duration = Duration(milliseconds: (r.duration * 1000).round());
    if (!_paused && _progress == null) _anim.repeat();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // ---------------- own photos ----------------

  Future<Directory> _photoDir() async {
    final d = Directory('${(await getApplicationDocumentsDirectory()).path}/reel_photos');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<List<File>> _recent() async {
    try {
      final files = (await _photoDir()).listSync().whereType<File>().toList()
        ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      return files;
    } catch (_) {
      return [];
    }
  }

  /// Gallery or one of the last 10 photos used. Returns a file path.
  Future<String?> _pickOwn() async {
    final recent = await _recent();
    if (!mounted) return null;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              subtitle: const Text('Shop, field, harvest, delivery — upright photos look best'),
              onTap: () => Navigator.pop(ctx, '#gallery'),
            ),
            if (recent.isNotEmpty) ...[
              const SizedBox(height: 4),
              const Text('Used before', style: TextStyle(fontSize: 12.5, color: Colors.black54)),
              const SizedBox(height: 6),
              SizedBox(
                height: 104,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: recent.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => GestureDetector(
                    onTap: () => Navigator.pop(ctx, recent[i].path),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(recent[i], width: 60, height: 104, fit: BoxFit.cover, cacheWidth: 160),
                    ),
                  ),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
    if (choice == null) return null;
    if (choice != '#gallery') return choice;
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
    if (x == null) return null;
    final dir = await _photoDir();
    final path = '${dir.path}/own_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(path).writeAsBytes(await x.readAsBytes());
    // keep the last 10 only (but never one still in use)
    final all = await _recent();
    final inUse = {..._customs.map((c) => c.path), ..._products.map((p) => p.ownBg).whereType<String>(), path};
    for (final f in all.skip(10)) {
      if (!inUse.contains(f.path)) {
        try {
          await f.delete();
        } catch (_) {/* fine */}
      }
    }
    return path;
  }

  Future<void> _addCustom() async {
    if (_customs.length >= 3) return _snack('Up to 3 own photos in one video.');
    final path = await _pickOwn();
    if (path == null) return;
    final c = ReelCustom(path, widget.info.tamil ? 'நம்ம கடையிலிருந்து புதிதாக' : 'Fresh from our shop today');
    _captions[c] = TextEditingController(text: c.caption);
    setState(() => _customs.add(c));
    _rebuild();
  }

  void _removeCustom(ReelCustom c) {
    _captions.remove(c)?.dispose();
    setState(() => _customs.remove(c));
    _rebuild();
  }

  // ---------------- styles ----------------

  void _mix() {
    for (var i = 0; i < _products.length; i++) {
      _products[i].style = reelMixOrder[i % reelMixOrder.length];
      _products[i].bg = ReelBg.auto;
    }
    _rebuild();
  }

  void _sameForAll() {
    if (_products.isEmpty) return;
    final f = _products.first;
    for (final p in _products.skip(1)) {
      p.style = f.style;
      p.bg = f.bg;
      p.ownBg = f.ownBg;
    }
    _rebuild();
  }

  Future<void> _setBg(ReelProduct p, ReelBg b) async {
    if (b == ReelBg.own) {
      final path = await _pickOwn();
      if (path == null) return;
      p.ownBg = path;
    }
    p.bg = b;
    _rebuild();
  }

  // ---------------- make / share ----------------

  Future<void> _make() async {
    final r = _renderer;
    if (r == null || !r.loaded || _progress != null) return;
    _anim.stop();
    setState(() => _progress = 0);
    try {
      final path = await ReelVideo.make(r, (p) {
        if (mounted) setState(() => _progress = p);
      });
      if (!mounted) return;
      setState(() {
        _video = path;
        _progress = null;
      });
      await _share();
    } on MissingPluginException {
      _snack('Videos need the latest app build. Install the new app and try again.');
    } catch (e) {
      _snack('Could not make the video: $e');
    } finally {
      if (mounted) {
        setState(() => _progress = null);
        if (!_paused) _anim.repeat();
      }
    }
  }

  Future<void> _share() async {
    final v = _video;
    if (v == null) return;
    await Share.shareXFiles([XFile(v, mimeType: 'video/mp4')], text: widget.caption);
  }

  Future<void> _save() async {
    final v = _video;
    if (v == null) return;
    try {
      final ok = await ReelVideo.save(v);
      _snack(ok ? 'Saved to Movies › Madhura on this phone' : 'Could not save — use Share instead.');
    } catch (_) {
      _snack('Could not save on this phone — use Share and pick Files or Drive.');
    }
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final r = _renderer;
    final secs = (_slides.length + 1) * 3;
    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      appBar: AppBar(title: const Text('Status video')),
      body: AbsorbPointer(
        absorbing: _progress != null,
        child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
        children: [
          Center(
            child: GestureDetector(
              onTap: () => setState(() {
                _paused = !_paused;
                if (_paused) {
                  _anim.stop();
                } else {
                  _anim.repeat();
                }
              }),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: 252,
                  height: 448,
                  child: r == null
                      ? const ColoredBox(color: Color(0xFF123A1A), child: Center(child: CircularProgressIndicator()))
                      : CustomPaint(painter: ReelPainter(r, _anim)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$secs seconds · ${_products.length} product${_products.length == 1 ? '' : 's'}'
            '${_customs.isEmpty ? '' : ' + ${_customs.length} own photo${_customs.length == 1 ? '' : 's'}'} · tap to ${_paused ? 'play' : 'pause'}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          if (_progress != null) ...[
            LinearProgressIndicator(value: _progress, minHeight: 8, borderRadius: BorderRadius.circular(4)),
            const SizedBox(height: 6),
            Text('Making the video… ${((_progress ?? 0) * 100).round()}%  (keep this screen open)',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
          ] else if (_video == null)
            FilledButton.icon(
              onPressed: r == null ? null : _make,
              style: FilledButton.styleFrom(backgroundColor: _wa, minimumSize: const Size.fromHeight(50)),
              icon: const Icon(Icons.movie_creation_outlined),
              label: const Text('Make video'),
            )
          else
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _share,
                  style: FilledButton.styleFrom(backgroundColor: _wa, minimumSize: const Size.fromHeight(50)),
                  icon: const Icon(Icons.share),
                  label: const Text('Share video'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _save,
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  icon: const Icon(Icons.download),
                  label: const Text('Save to phone'),
                ),
              ),
            ]),
          if (_video != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => SendToCustomersScreen(paths: [_video!], mime: 'video/mp4', caption: widget.caption)),
              ),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
              icon: const Icon(Icons.groups_outlined),
              label: const Text('Send to customers (late, due, category buyers…)'),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'One MP4 file, ready for WhatsApp Status, Instagram Reels and Facebook. In WhatsApp, pick "My status"; '
            'the order link goes with it as the caption.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.35),
          ),
          const SizedBox(height: 16),
          Row(children: [
            const Expanded(
                child: Text('Style for each product', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
            TextButton(onPressed: _mix, child: const Text('Mix for me')),
            TextButton(onPressed: _products.length > 1 ? _sameForAll : null, child: const Text('Same for all')),
          ]),
          for (var i = 0; i < _products.length; i++) _productCard(i, _products[i]),
          const SizedBox(height: 14),
          Row(children: [
            const Expanded(
                child: Text('My own photos', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
            TextButton.icon(
              onPressed: _customs.length >= 3 ? null : _addCustom,
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: const Text('Add photo'),
            ),
          ]),
          if (_customs.isEmpty)
            const Text('Add your shop, field or delivery photo as its own 3-second scene (up to 3).',
                style: TextStyle(fontSize: 12.5, color: Colors.black54)),
          for (final c in _customs) _customCard(c),
          if (_customs.isNotEmpty)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Show my photos before the products'),
              value: _ownFirst,
              onChanged: (v) {
                setState(() => _ownFirst = v);
                _rebuild();
              },
            ),
        ],
      ),
      ),
    );
  }

  Widget _productCard(int i, ReelProduct p) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
        child: Column(children: [
          Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 40,
                height: 40,
                child: p.photo == null
                    ? const ColoredBox(color: Color(0xFFE8E2D0), child: Icon(Icons.grass, size: 20))
                    : Image.memory(p.photo!, fit: BoxFit.cover, cacheWidth: 120),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text('${i + 1}. ${p.name}  ·  ${p.price}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<ReelStyle>(
                value: p.style,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Style', border: OutlineInputBorder(), isDense: true),
                items: [
                  for (final e in reelStyleNames.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  p.style = v;
                  _rebuild();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<ReelBg>(
                value: p.bg,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Background', border: OutlineInputBorder(), isDense: true),
                items: [
                  for (final b in ReelBg.values)
                    DropdownMenuItem(
                      value: b,
                      child: Row(children: [
                        _bgThumb(b, p),
                        const SizedBox(width: 6),
                        Expanded(child: Text(reelBgNames[b]!, overflow: TextOverflow.ellipsis)),
                      ]),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) _setBg(p, v);
                },
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _bgThumb(ReelBg b, ReelProduct p) {
    final asset = reelBgAsset(b);
    Widget child;
    if (asset != null) {
      child = Image.asset(asset, fit: BoxFit.cover, cacheWidth: 60);
    } else if (b == ReelBg.own && p.ownBg != null) {
      child = Image.file(File(p.ownBg!), fit: BoxFit.cover, cacheWidth: 60);
    } else {
      child = ColoredBox(
          color: const Color(0xFFE8E2D0),
          child: Icon(b == ReelBg.own ? Icons.add_photo_alternate_outlined : Icons.auto_awesome, size: 14));
    }
    return ClipRRect(borderRadius: BorderRadius.circular(4), child: SizedBox(width: 22, height: 32, child: child));
  }

  Widget _customCard(ReelCustom c) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(File(c.path), width: 48, height: 72, fit: BoxFit.cover, cacheWidth: 140),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _captions[c],
              maxLength: 50,
              decoration: const InputDecoration(labelText: 'Words on the photo', isDense: true),
              onChanged: (v) => setState(() {
                c.caption = v.trim();
                _video = null;
              }),
            ),
          ),
          IconButton(onPressed: () => _removeCustom(c), icon: const Icon(Icons.delete_outline)),
        ]),
      ),
    );
  }
}

/// Talks to the phone's own video encoder (MainActivity "madhura/video").
class ReelVideo {
  static const _ch = MethodChannel('madhura/video');
  static const fps = 30;

  static Future<String> make(ReelRenderer r, void Function(double) onProgress) async {
    final dir = await getTemporaryDirectory();
    try {
      for (final f in dir.listSync()) {
        if (f is File && f.path.contains('madhura_reel_')) f.deleteSync();
      }
    } catch (_) {/* old files only */}
    final path = '${dir.path}/madhura_reel_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final size = await _ch.invokeMapMethod<String, dynamic>('start', {'path': path, 'fps': fps, 'bitrate': 8000000});
    final w = (size?['width'] as num?)?.toInt() ?? 1080;
    final h = (size?['height'] as num?)?.toInt() ?? 1920;
    final total = (r.duration * fps).round();
    try {
      for (var f = 0; f < total; f++) {
        final rec = ui.PictureRecorder();
        final canvas = Canvas(rec);
        r.paint(canvas, Size(w.toDouble(), h.toDouble()), f / fps);
        final pic = rec.endRecording();
        final img = await pic.toImage(w, h);
        pic.dispose();
        final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
        img.dispose();
        if (data == null) throw StateError('Frame ${f + 1} could not be drawn');
        await _ch.invokeMethod('frame', {'rgba': data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes)});
        onProgress((f + 1) / total);
      }
      await _ch.invokeMethod('finish');
    } catch (e) {
      try {
        await _ch.invokeMethod('cancel');
      } catch (_) {/* already stopped */}
      rethrow;
    }
    return path;
  }

  static Future<bool> save(String path) async =>
      await _ch.invokeMethod<bool>('save', {'path': path, 'name': 'madhura_${DateTime.now().millisecondsSinceEpoch}.mp4'}) ??
      false;
}
