import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../db/db_helper.dart';
import '../services/customer_pattern.dart';
import '../utils/app_info.dart';
import '../utils/app_theme.dart';
import 'buying_pattern.dart' show PatternStore;

/// Sends a status picture (or several offer pages) or a status video to
/// chosen customers on WhatsApp, one chat after another. Customers are
/// picked by buying-pattern group (Late, Due this week, Lost …) and/or
/// category buyers. WhatsApp allows no automatic bulk sending, so each
/// customer is one tap; coming back to the app moves to the next one.
class SendToCustomersScreen extends StatefulWidget {
  final List<String> paths;
  final String mime; // image/png or video/mp4
  final String caption;
  const SendToCustomersScreen({super.key, required this.paths, required this.mime, required this.caption});

  bool get isVideo => mime.startsWith('video');

  @override
  State<SendToCustomersScreen> createState() => _SendToCustomersScreenState();
}

class _Person {
  final String id, name, phone, place;
  final CustPattern? p;
  _Person(this.id, this.name, this.phone, this.place, this.p);
}

class _SendToCustomersScreenState extends State<SendToCustomersScreen> with WidgetsBindingObserver {
  static const _wa = MethodChannel('madhura/whatsapp');
  late final TextEditingController _msg =
      TextEditingController(text: 'Vanakkam {name},\n\n${widget.caption}\n\n- ${AppInfo.appName}');
  CustomerPatterns? _p;
  List<_Person> _everyone = [];
  String? _error;
  CustGroup? _group = CustGroup.late; // null = everyone
  String _cat = '';
  final Set<String> _picked = {};
  // sending
  List<_Person> _queue = [];
  int _step = -1;
  final Set<String> _sent = {};
  bool _awaiting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _msg.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaiting && _step >= 0 && _step < _queue.length) {
      setState(() {
        _awaiting = false;
        _sent.add(_queue[_step].id);
        _step++;
      });
    }
  }

  static String _digits(String phone) {
    var d = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.length == 10) d = '91$d';
    return d;
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([PatternStore.load(), DBHelper.instance.getVendors()]);
      final p = r[0] as CustomerPatterns;
      final vendors = r[1] as List<Map<String, dynamic>>;
      final byId = {for (final c in p.all) c.id: c};
      final people = <_Person>[
        for (final v in vendors)
          if (_digits((v['phone'] ?? '').toString()).length >= 12)
            _Person(v['id'] as String, (v['name'] ?? '').toString(), (v['phone'] ?? '').toString(),
                (v['address'] ?? '').toString().trim(), byId[v['id']]),
      ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (!mounted) return;
      setState(() {
        _p = p;
        _everyone = people;
        if (_list().isEmpty) _group = null;
        _pickAll();
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load customers: $e');
    }
  }

  /// Customers in the chosen group/category who have a phone number, in
  /// the group's priority order.
  List<_Person> _list() {
    final p = _p;
    if (p == null) return const [];
    if (_group == null) {
      return _everyone.where((x) => _cat.isEmpty || (x.p?.boughtCategory(_cat) ?? false)).toList();
    }
    final byId = {for (final x in _everyone) x.id: x};
    return [
      for (final c in p.list(_group, category: _cat))
        if (byId[c.id] != null) byId[c.id]!,
    ];
  }

  void _pickAll() {
    _picked
      ..clear()
      ..addAll(_list().map((x) => x.id));
  }

  String _textFor(_Person x) => _msg.text.replaceAll('{name}', x.name);

  Future<void> _sendCurrent() async {
    final x = _queue[_step];
    try {
      _awaiting = true;
      final outcome = await _wa.invokeMethod<String>('sendImage', {
        'phone': _digits(x.phone),
        'text': _textFor(x),
        'path': widget.paths.first,
        'paths': widget.paths,
        'mime': widget.mime,
      });
      if (outcome == 'not_installed') {
        _awaiting = false;
        await Share.shareXFiles([for (final f in widget.paths) XFile(f, mimeType: widget.mime)], text: _textFor(x));
        if (mounted) {
          setState(() {
            _sent.add(x.id);
            _step++;
          });
        }
      }
    } on MissingPluginException {
      _awaiting = false;
      _snack('Sending needs the latest app build. Install the new app and try again.');
    } catch (e) {
      _awaiting = false;
      _snack('Could not open WhatsApp: $e');
    }
  }

  void _snack(String t) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      appBar: AppBar(title: Text(widget.isVideo ? 'Send video to customers' : 'Send picture to customers')),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
          : _p == null
              ? const Center(child: CircularProgressIndicator())
              : (_step >= 0 ? _sending() : _compose()),
    );
  }

  Widget _preview() {
    final first = widget.paths.first;
    return Row(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: widget.isVideo
            ? Container(
                width: 64,
                height: 96,
                color: Colors.black87,
                child: const Icon(Icons.play_circle_outline, color: Colors.white, size: 34),
              )
            : Image.file(File(first), width: 64, height: 96, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(width: 64, height: 96, color: Colors.black12)),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          widget.isVideo
              ? 'Status video (MP4)'
              : (widget.paths.length > 1 ? '${widget.paths.length} pictures' : 'Status picture'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    ]);
  }

  Widget _compose() {
    final p = _p!;
    final list = _list();
    final cats = p.categories.where((c) => c != 'Uncategorised').toList();
    final picked = list.where((x) => _picked.contains(x.id)).toList();
    final groups = <CustGroup?>[...CustGroup.values, null];
    int countOf(CustGroup? g) {
      final saved = _group;
      _group = g;
      final n = _list().length;
      _group = saved;
      return n;
    }

    return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 32), children: [
      _preview(),
      const SizedBox(height: 12),
      TextField(
        controller: _msg,
        minLines: 3,
        maxLines: 6,
        decoration: const InputDecoration(
          labelText: 'Message',
          helperText: '{name} is replaced with each customer\'s name',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 14),
      const Text('Who gets it', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        key: ValueKey('scat-$_cat'),
        value: _cat,
        isExpanded: true,
        decoration: const InputDecoration(
            labelText: 'Category buyers', prefixIcon: Icon(Icons.category_outlined), isDense: true, border: OutlineInputBorder()),
        items: [
          const DropdownMenuItem(value: '', child: Text('All categories')),
          for (final c in cats) DropdownMenuItem(value: c.toLowerCase(), child: Text('$c buyers')),
        ],
        onChanged: (v) => setState(() {
          _cat = v ?? '';
          _pickAll();
        }),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final g in groups)
          ChoiceChip(
            label: Text('${g == null ? 'Everyone' : custGroupNames[g]} ${countOf(g)}'),
            selected: _group == g,
            onSelected: (_) => setState(() {
              _group = g;
              _pickAll();
            }),
          ),
      ]),
      const SizedBox(height: 4),
      Row(children: [
        Text('${picked.length} of ${list.length} picked', style: const TextStyle(color: Colors.black54)),
        const Spacer(),
        TextButton(onPressed: () => setState(_pickAll), child: const Text('All')),
        TextButton(onPressed: () => setState(_picked.clear), child: const Text('None')),
      ]),
      if (list.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Nobody with a phone number in this group.', style: TextStyle(color: Colors.black54)),
        ),
      for (final x in list)
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: _picked.contains(x.id),
          onChanged: (v) => setState(() => v == true ? _picked.add(x.id) : _picked.remove(x.id)),
          title: Text(x.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text([if (x.place.isNotEmpty) x.place, x.phone].join(' · '), style: const TextStyle(fontSize: 12)),
        ),
      const SizedBox(height: 10),
      FilledButton.icon(
        onPressed: picked.isEmpty
            ? null
            : () => setState(() {
                  _queue = picked;
                  _step = 0;
                  _sent.clear();
                }),
        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366), minimumSize: const Size.fromHeight(50)),
        icon: const Icon(Icons.send),
        label: Text('Start sending to ${picked.length}'),
      ),
      const SizedBox(height: 6),
      const Text(
        'WhatsApp opens each customer\'s chat with the picture or video ready — tap send there, then come back. '
        'The next customer opens by itself.',
        style: TextStyle(fontSize: 12, color: Colors.black54, height: 1.35),
      ),
    ]);
  }

  Widget _sending() {
    final done = _step >= _queue.length;
    return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 32), children: [
      _preview(),
      const SizedBox(height: 12),
      LinearProgressIndicator(
        value: _queue.isEmpty ? 0 : (_step.clamp(0, _queue.length)) / _queue.length,
        minHeight: 8,
        borderRadius: BorderRadius.circular(4),
      ),
      const SizedBox(height: 6),
      Text(done ? 'Done — sent to ${_sent.length} of ${_queue.length}' : 'Customer ${_step + 1} of ${_queue.length}',
          style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      if (!done) ...[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_queue[_step].name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              Text([if (_queue[_step].place.isNotEmpty) _queue[_step].place, _queue[_step].phone].join(' · '),
                  style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _sendCurrent,
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366), minimumSize: const Size.fromHeight(48)),
                    icon: const Icon(Icons.send),
                    label: const Text('Open WhatsApp'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => setState(() {
                    _awaiting = false;
                    _step++;
                  }),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(80, 48)),
                  child: const Text('Skip'),
                ),
              ]),
            ]),
          ),
        ),
      ] else
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Finish')),
      const SizedBox(height: 12),
      for (var i = 0; i < _queue.length; i++)
        ListTile(
          dense: true,
          leading: Icon(
            _sent.contains(_queue[i].id)
                ? Icons.check_circle
                : (i < _step ? Icons.remove_circle_outline : Icons.radio_button_unchecked),
            color: _sent.contains(_queue[i].id) ? const Color(0xFF16A34A) : Colors.black38,
          ),
          title: Text(_queue[i].name),
        ),
    ]);
  }
}
