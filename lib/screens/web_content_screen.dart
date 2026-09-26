import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart' show FieldValue;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/web_store_service.dart';
import '../utils/app_theme.dart';
import '../utils/formatters.dart';
import '../utils/keyed_stream.dart';

/// Everything on the website that isn't a product: offer banners, the
/// delivery note, trust lines, the owner story and About text, contact
/// links and category photos. Saving publishes to the website within a
/// few seconds — no code changes needed.
class WebContentScreen extends StatefulWidget {
  final List<String> categories;
  const WebContentScreen({super.key, required this.categories});

  @override
  State<WebContentScreen> createState() => _WebContentScreenState();
}

const _defaultTrust = [
  {'text': 'Prepared with the utmost care', 'textLocal': 'மிகுந்த அக்கறையுடன் தயாரிக்கப்பட்டது'},
  {'text': 'Serving you with love, every day', 'textLocal': 'ஒவ்வொரு நாளும் அன்புடன் உங்கள் சேவையில்'},
];

class _WebContentScreenState extends State<WebContentScreen> {
  final _svc = WebStoreService.instance;
  final _settings = KeyedStream<Map<String, dynamic>>();
  bool _busy = false;

  Map<String, dynamic> _siteOf(Map<String, dynamic> settings) =>
      Map<String, dynamic>.from((settings['site'] as Map?) ?? const {});

  List<Map<String, dynamic>> _list(dynamic v) =>
      ((v as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  Future<String?> _pickPhoto(String key, {double maxWidth = 1000}) async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: maxWidth, imageQuality: 70);
    if (x == null) return null;
    setState(() => _busy = true);
    try {
      final b64 = base64Encode(await x.readAsBytes());
      return await _svc.uploadSiteImage(key, b64);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _saved() {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Saved — the website updates in a few seconds')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      appBar: AppBar(
        title: const Text('Website content'),
        bottom: _busy
            ? const PreferredSize(preferredSize: Size.fromHeight(3), child: LinearProgressIndicator(minHeight: 3))
            : null,
      ),
      body: StreamBuilder<Map<String, dynamic>>(
        stream: _settings.get(0, _svc.watchSettings),
        builder: (context, snap) {
          if (snap.hasError) return ErrorState(message: 'Could not load website content.\n${snap.error}');
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final site = _siteOf(snap.data!);
          final banners = _list(site['banners']);
          final trust = _list(site['trust']);
          final owner = Map<String, dynamic>.from((site['owner'] as Map?) ?? const {});
          final catImages = Map<String, dynamic>.from((site['categoryImages'] as Map?) ?? const {});
          String v(String k) => (site[k] ?? '').toString();
          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
            children: [
              _section(
                icon: Icons.title,
                title: 'Headline',
                summary: v('heroTitle').isEmpty
                    ? 'Automatic — lists the categories shown on the website'
                    : v('heroTitle'),
                onTap: () => _headlineEditor(site),
              ),
              _section(
                icon: Icons.local_shipping_outlined,
                title: 'Delivery note',
                summary: v('deliveryNote').isEmpty ? 'Not set — a line under the website header' : v('deliveryNote'),
                onTap: () => _editTwo('Delivery note', 'deliveryNote', site,
                    hint: 'Delivering in and around Pollachi · Every order confirmed on WhatsApp'),
              ),
              _section(
                icon: Icons.view_carousel_outlined,
                title: 'Offer banners',
                summary: banners.isEmpty
                    ? 'No banners — add one for your current offer'
                    : '${banners.length} banner(s): ${banners.map((b) => b['title']).join(', ')}',
                onTap: () => _bannerList(banners),
              ),
              _section(
                icon: Icons.verified_outlined,
                title: 'Trust lines',
                summary: trust.isEmpty ? 'Using suggested lines until you save your own' : trust.map((t) => t['text']).join(' · '),
                onTap: () => _trustList(trust.isEmpty ? _defaultTrust.map((m) => Map<String, dynamic>.from(m)).toList() : trust),
              ),
              _section(
                icon: Icons.person_outline,
                title: 'Owner and About us',
                summary: (owner['name'] ?? '').toString().isEmpty
                    ? 'Not set'
                    : '${owner['name']}${(owner['years'] ?? 0) != 0 ? ' · ${owner['years']} years' : ''}${(owner['image'] ?? '').toString().isEmpty ? '' : ' · photo added'}',
                onTap: () => _ownerEditor(site, owner),
              ),
              _section(
                icon: Icons.contact_phone_outlined,
                title: 'Contact and Instagram',
                summary: [
                  if (v('phone').isNotEmpty) v('phone'),
                  if (v('hours').isNotEmpty) v('hours'),
                  if (v('instagram').isNotEmpty) '@${v('instagram')}',
                  if (v('mapUrl').isNotEmpty) 'map link',
                ].join(' · ').ifEmpty('Phone, map link, shop hours, Instagram'),
                onTap: () => _contactEditor(site),
              ),
              _section(
                icon: Icons.photo_library_outlined,
                title: 'Category photos',
                summary: '${catImages.length} of ${widget.categories.length} categories have a photo',
                onTap: () => _categoryPhotos(catImages),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _section({required IconData icon, required String title, required String summary, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        onTap: _busy ? null : onTap,
        child: Row(
          children: [
            IconBadge(icon: icon, color: AppTheme.primary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                  const SizedBox(height: 2),
                  Text(summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.black38),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, {String? hint, int lines = 1, TextInputType? type}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          maxLines: lines,
          keyboardType: type,
          decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder()),
        ),
      );

  Future<bool> _dialog(String title, List<Widget> children) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: children)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    return ok == true;
  }

  // ---------------- Headline ----------------

  Future<void> _headlineEditor(Map<String, dynamic> site) async {
    String s(String k) => (site[k] ?? '').toString();
    final title = TextEditingController(text: s('heroTitle'));
    final titleTa = TextEditingController(text: s('heroTitleLocal'));
    final sub = TextEditingController(text: s('heroSub'));
    final subTa = TextEditingController(text: s('heroSubLocal'));
    if (!await _dialog('Headline', [
      const Text(
          'Leave the headline empty to build it automatically from the categories on the website — '
          'switching a category off removes it from the headline too.',
          style: TextStyle(fontSize: 12, color: Colors.black54)),
      const SizedBox(height: 10),
      _field(title, 'Headline', hint: 'Order millets, grains and rice online'),
      _field(titleTa, 'Headline in Tamil'),
      _field(sub, 'Line below it (optional)', hint: 'Empty = your shop tagline'),
      _field(subTa, 'Line below it in Tamil'),
    ])) return;
    await _svc.saveSite({
      'heroTitle': title.text.trim(),
      'heroTitleLocal': titleTa.text.trim(),
      'heroSub': sub.text.trim(),
      'heroSubLocal': subTa.text.trim(),
    });
    _saved();
  }

  // ---------------- Delivery note ----------------

  Future<void> _editTwo(String title, String key, Map<String, dynamic> site, {String? hint}) async {
    final en = TextEditingController(text: (site[key] ?? '').toString());
    final ta = TextEditingController(text: (site['${key}Local'] ?? '').toString());
    if (!await _dialog(title, [
      _field(en, 'English', hint: hint, lines: 2),
      _field(ta, 'தமிழ்', lines: 2),
      const Text('Leave both empty to hide it.', style: TextStyle(fontSize: 12, color: Colors.black54)),
    ])) return;
    await _svc.saveSite({key: en.text.trim(), '${key}Local': ta.text.trim()});
    _saved();
  }

  // ---------------- Banners ----------------

  Future<void> _bannerList(List<Map<String, dynamic>> start) async {
    var banners = [...start];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Future<void> save() async {
            await _svc.saveSite({'banners': banners});
            _saved();
          }

          return SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.75,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: Text('Customers swipe through banners at the top of the website. Tap one to edit.',
                      style: TextStyle(fontSize: 12.5, color: Colors.black54)),
                ),
                Expanded(
                  child: banners.isEmpty
                      ? const Center(child: Text('No banners yet'))
                      : ListView.builder(
                          itemCount: banners.length,
                          itemBuilder: (_, i) {
                            final b = banners[i];
                            final until = (b['until'] ?? '').toString();
                            final ended = until.isNotEmpty &&
                                until.compareTo(DateTime.now().toIso8601String().substring(0, 10)) < 0;
                            return ListTile(
                              title: Text((b['title'] ?? '').toString().isEmpty ? '(photo only)' : b['title'].toString()),
                              subtitle: Text([
                                if (b['active'] == false) 'Hidden',
                                if (ended) 'Ended',
                                if (until.isNotEmpty && !ended) 'Until ${formatDay(until)}',
                                if ((b['image'] ?? '').toString().isNotEmpty) 'Photo',
                                if ((b['category'] ?? '').toString().isNotEmpty) 'Opens ${b['category']}',
                              ].join(' · ')),
                              onTap: () async {
                                final edited = await _bannerEditor(b, i);
                                if (edited == null) return;
                                setSheet(() => edited.isEmpty ? banners.removeAt(i) : banners[i] = edited);
                                await save();
                              },
                              trailing: IconButton(
                                tooltip: 'Move up',
                                icon: const Icon(Icons.arrow_upward, size: 18),
                                onPressed: i == 0
                                    ? null
                                    : () async {
                                        setSheet(() {
                                          final t = banners[i - 1];
                                          banners[i - 1] = banners[i];
                                          banners[i] = t;
                                        });
                                        await save();
                                      },
                              ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: () async {
                      final created = await _bannerEditor({}, banners.length);
                      if (created == null || created.isEmpty) return;
                      setSheet(() => banners.add(created));
                      await save();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add banner'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Returns the edited banner, {} to delete it, or null if cancelled.
  Future<Map<String, dynamic>?> _bannerEditor(Map<String, dynamic> b, int index) async {
    final title = TextEditingController(text: (b['title'] ?? '').toString());
    final titleTa = TextEditingController(text: (b['titleLocal'] ?? '').toString());
    final sub = TextEditingController(text: (b['sub'] ?? '').toString());
    final subTa = TextEditingController(text: (b['subLocal'] ?? '').toString());
    String category = (b['category'] ?? '').toString();
    String until = (b['until'] ?? '').toString();
    String image = (b['image'] ?? '').toString();
    bool active = b['active'] != false;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(b.isEmpty ? 'New banner' : 'Edit banner'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _field(title, 'Headline', hint: 'Cattle feed offers'),
                _field(titleTa, 'Headline in Tamil'),
                _field(sub, 'Second line (optional)', hint: 'Save on 50 kg bags this month'),
                _field(subTa, 'Second line in Tamil'),
                DropdownButtonFormField<String>(
                  value: widget.categories.contains(category) ? category : '',
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Tapping it opens', border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('Nothing')),
                    for (final c in widget.categories) DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: (v) => setD(() => category = v ?? ''),
                ),
                const SizedBox(height: 6),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(until.isEmpty ? 'No end date' : 'Ends after ${formatDay(until)}'),
                  subtitle: const Text('Hides itself automatically after this date'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (until.isNotEmpty)
                      IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setD(() => until = '')),
                    IconButton(
                      icon: const Icon(Icons.event_outlined),
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: DateTime.now().add(const Duration(days: 7)),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 730)),
                        );
                        if (d != null) setD(() => until = d.toIso8601String().substring(0, 10));
                      },
                    ),
                  ]),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(image.isEmpty ? 'No photo (green background)' : 'Photo added'),
                  subtitle: const Text('Wide photos look best'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (image.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () async {
                          await _svc.deleteSiteImage(image);
                          setD(() => image = '');
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      onPressed: () async {
                        final ref = await _pickPhoto('site_banner_${DateTime.now().millisecondsSinceEpoch}',
                            maxWidth: 1400);
                        if (ref == null) return;
                        await _svc.deleteSiteImage(image);
                        setD(() => image = ref);
                      },
                    ),
                  ]),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: active,
                  title: const Text('Show on website'),
                  onChanged: (v) => setD(() => active = v),
                ),
              ],
            ),
          ),
          actions: [
            if (b.isNotEmpty)
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'delete'),
                style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
                child: const Text('Delete'),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (result == 'delete') {
      await _svc.deleteSiteImage(image);
      return {};
    }
    if (result != 'save') return null;
    if (title.text.trim().isEmpty && image.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Add a headline or a photo for the banner.')));
      }
      return null;
    }
    return {
      'title': title.text.trim(),
      'titleLocal': titleTa.text.trim(),
      'sub': sub.text.trim(),
      'subLocal': subTa.text.trim(),
      'category': category,
      'until': until,
      'image': image,
      'active': active,
    };
  }

  // ---------------- Trust lines ----------------

  Future<void> _trustList(List<Map<String, dynamic>> start) async {
    final rows = [
      for (final t in start)
        (TextEditingController(text: (t['text'] ?? '').toString()),
            TextEditingController(text: (t['textLocal'] ?? '').toString()))
    ];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Trust lines'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                const Text('Shown with a tick near the top of the website. Keep them short and true.',
                    style: TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 10),
                for (var i = 0; i < rows.length; i++) ...[
                  Row(children: [
                    Text('Line ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () => setD(() => rows.removeAt(i)),
                    ),
                  ]),
                  _field(rows[i].$1, 'English'),
                  _field(rows[i].$2, 'தமிழ்'),
                ],
                if (rows.length < 5)
                  TextButton.icon(
                    onPressed: () => setD(() => rows.add((TextEditingController(), TextEditingController()))),
                    icon: const Icon(Icons.add),
                    label: const Text('Add line'),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _svc.saveSite({
      'trust': [
        for (final r in rows)
          if (r.$1.text.trim().isNotEmpty) {'text': r.$1.text.trim(), 'textLocal': r.$2.text.trim()}
      ]
    });
    _saved();
  }

  // ---------------- Owner and About ----------------

  Future<void> _ownerEditor(Map<String, dynamic> site, Map<String, dynamic> owner) async {
    String s(String k, [String fallback = '']) {
      final v = (owner[k] ?? '').toString();
      return v.isEmpty ? fallback : v;
    }

    final name = TextEditingController(text: s('name', 'Mr. Subramaniyan'));
    final nameTa = TextEditingController(text: s('nameLocal', 'திரு. சுப்பிரமணியன்'));
    final years = TextEditingController(text: s('years', '20'));
    final msg = TextEditingController(text: s('message'));
    final msgTa = TextEditingController(text: s('messageLocal'));
    final about = TextEditingController(text: (site['about'] ?? '').toString());
    final aboutTa = TextEditingController(text: (site['aboutLocal'] ?? '').toString());
    String image = s('image');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Owner and About us'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _field(name, 'Name'),
                _field(nameTa, 'Name in Tamil'),
                _field(years, 'Years of service', type: TextInputType.number),
                _field(msg, 'Message to customers', lines: 3,
                    hint: 'Every bag that leaves our shop is one I would give my own family.'),
                _field(msgTa, 'Message in Tamil', lines: 3),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(image.isEmpty ? 'No photo' : 'Photo added'),
                  subtitle: const Text('A clear photo at the shop builds trust'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (image.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () async {
                          await _svc.deleteSiteImage(image);
                          setD(() => image = '');
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      onPressed: () async {
                        final ref = await _pickPhoto('site_owner_${DateTime.now().millisecondsSinceEpoch}', maxWidth: 700);
                        if (ref == null) return;
                        await _svc.deleteSiteImage(image);
                        setD(() => image = ref);
                      },
                    ),
                  ]),
                ),
                const Divider(),
                _field(about, 'About us', lines: 4),
                _field(aboutTa, 'About us in Tamil', lines: 4),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _svc.saveSite({
      'owner': {
        'name': name.text.trim(),
        'nameLocal': nameTa.text.trim(),
        'years': int.tryParse(years.text.trim()) ?? 0,
        'message': msg.text.trim(),
        'messageLocal': msgTa.text.trim(),
        'image': image,
      },
      'about': about.text.trim(),
      'aboutLocal': aboutTa.text.trim(),
    });
    _saved();
  }

  // ---------------- Contact ----------------

  Future<void> _contactEditor(Map<String, dynamic> site) async {
    String s(String k) => (site[k] ?? '').toString();
    final phone = TextEditingController(text: s('phone'));
    final map = TextEditingController(text: s('mapUrl'));
    final hours = TextEditingController(text: s('hours'));
    final hoursTa = TextEditingController(text: s('hoursLocal'));
    final insta = TextEditingController(text: s('instagram'));
    if (!await _dialog('Contact and Instagram', [
      _field(phone, 'Phone number for calls', type: TextInputType.phone),
      _field(map, 'Google Maps link', hint: 'https://maps.app.goo.gl/...'),
      _field(hours, 'Shop hours', hint: '8 AM – 8 PM, all days'),
      _field(hoursTa, 'Shop hours in Tamil'),
      _field(insta, 'Instagram username', hint: 'The name after @ on your profile'),
    ])) return;
    final mapUrl = map.text.trim();
    await _svc.saveSite({
      'phone': phone.text.trim(),
      'mapUrl': mapUrl.startsWith('https://') ? mapUrl : '',
      'hours': hours.text.trim(),
      'hoursLocal': hoursTa.text.trim(),
      'instagram': insta.text
          .trim()
          .replaceFirst(RegExp(r'^@'), '')
          .replaceFirst(RegExp(r'^https?://(www\.)?instagram\.com/', caseSensitive: false), '')
          .replaceFirst(RegExp(r'[/?#].*$'), ''),
    });
    if (mapUrl.isNotEmpty && !mapUrl.startsWith('https://') && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Map link must start with https:// — copy it from Google Maps > Share.')));
      return;
    }
    _saved();
  }

  // ---------------- Category photos ----------------

  Future<void> _categoryPhotos(Map<String, dynamic> start) async {
    final images = Map<String, dynamic>.from(start);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 20),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Shown on the category tiles at the top of the website. Square photos look best.',
                  style: TextStyle(fontSize: 12.5, color: Colors.black54)),
            ),
            for (final c in widget.categories)
              ListTile(
                title: Text(c),
                subtitle: Text((images[c] ?? '').toString().isEmpty ? 'Icon' : 'Photo added'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if ((images[c] ?? '').toString().isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () async {
                        await _svc.deleteSiteImage(images[c] as String);
                        await _svc.saveSite({
                          'categoryImages': {c: FieldValue.delete()}
                        });
                        setSheet(() => images.remove(c));
                      },
                    ),
                  IconButton(
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    onPressed: () async {
                      final ref = await _pickPhoto('site_cat_${DateTime.now().millisecondsSinceEpoch}', maxWidth: 500);
                      if (ref == null) return;
                      await _svc.deleteSiteImage(images[c] as String?);
                      await _svc.saveSite({
                        'categoryImages': {c: ref}
                      });
                      setSheet(() => images[c] = ref);
                    },
                  ),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
