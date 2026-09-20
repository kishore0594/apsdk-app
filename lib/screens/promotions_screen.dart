import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:url_launcher/url_launcher.dart';
import '../db/db_helper.dart';
import '../utils/app_theme.dart';
import '../utils/app_info.dart';

class PromotionsScreen extends StatefulWidget {
  const PromotionsScreen({super.key});

  @override
  State<PromotionsScreen> createState() => _PromotionsScreenState();
}

class _PromotionsScreenState extends State<PromotionsScreen> {
  final _db = DBHelper.instance;
  final _messageEnCtrl = TextEditingController();
  final _messageTaCtrl = TextEditingController();
  Map<String, dynamic>? _selectedProduct;
  List<Map<String, dynamic>> _selectedVendors = [];
  int _stepIndex = -1; // -1 = still composing; >=0 = stepping through recipients
  final Set<String> _sentTo = {};

  void _showHelpSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.85,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const Text('Why two buttons?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              const Text(
                'WhatsApp has no single method that attaches a photo directly into a specific chat — '
                'attaching still needs one manual step, but both buttons open the right vendor\'s chat '
                'for you first.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 16),
              const Text('Send Text', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
              const SizedBox(height: 4),
              const Text(
                'Opens WhatsApp already set to that vendor, with your message pre-filled. No photo — fastest '
                'option for a plain update.',
                style: TextStyle(fontSize: 12.5, color: Colors.black54, height: 1.4),
              ),
              const SizedBox(height: 14),
              const Text('Share with Photo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
              const SizedBox(height: 4),
              const Text(
                'Saves the product photo to your gallery, then opens WhatsApp on that vendor\'s chat — same '
                'as Send Text. Tap the attach button in the chat and the photo will be right there as the '
                'newest one.',
                style: TextStyle(fontSize: 12.5, color: Colors.black54, height: 1.4),
              ),
              const SizedBox(height: 14),
              const Text(
                'Either way, nothing sends automatically — you review and tap send yourself for every message.',
                style: TextStyle(fontSize: 12.5, color: Colors.black54, height: 1.4, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickProduct() async {
    final product = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const _ProductPickerScreen()),
    );
    if (product != null) setState(() => _selectedProduct = product);
  }

  Future<void> _pickVendors() async {
    final vendors = await Navigator.push<List<Map<String, dynamic>>>(
      context,
      MaterialPageRoute(builder: (_) => _VendorMultiPickerScreen(initiallySelected: _selectedVendors)),
    );
    if (vendors != null) setState(() => _selectedVendors = vendors);
  }

  String _composedMessage(String language) {
    final en = _messageEnCtrl.text.trim();
    final ta = _messageTaCtrl.text.trim();
    if (language == 'ta') {
      // Falls back to the English box if the Tamil one was left empty —
      // sends something sensible rather than a blank message.
      final text = ta.isNotEmpty ? ta : en;
      return 'வணக்கம்,\n\n$text\n\n- ${AppInfo.appName}';
    }
    final text = en.isNotEmpty ? en : ta;
    return 'Hello,\n\n$text\n\n- ${AppInfo.appName}';
  }

  Future<String?> _askLanguage() {
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Send in'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.language),
              title: const Text('English'),
              onTap: () => Navigator.pop(context, 'en'),
            ),
            ListTile(
              leading: const Icon(Icons.language),
              title: const Text('தமிழ்'),
              onTap: () => Navigator.pop(context, 'ta'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendText(Map<String, dynamic> vendor) async {
    final language = await _askLanguage();
    if (language == null) return;
    final phone = (vendor['phone'] as String? ?? '').trim();
    if (phone.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('No phone number saved for this vendor')));
      }
      return;
    }
    var digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 10) digits = '91$digits';
    final message = Uri.encodeComponent(_composedMessage(language));
    final url = Uri.parse('https://wa.me/$digits?text=$message');
    try {
      final launched = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (launched && mounted) setState(() => _sentTo.add(vendor['id'] as String));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not open WhatsApp: $e')));
      }
    }
  }

  Future<void> _shareWithPhoto(Map<String, dynamic> vendor) async {
    final language = await _askLanguage();
    if (language == null) return;
    final photo = _selectedProduct?['photo'] as String?;
    if (photo == null) return;
    final phone = (vendor['phone'] as String? ?? '').trim();
    if (phone.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('No phone number saved for this vendor')));
      }
      return;
    }
    try {
      // Saved to the gallery rather than shared via the OS share sheet —
      // wa.me (below) already redirects straight to this vendor's chat,
      // matching the text flow. Saving to the gallery means the photo
      // shows up as the newest item when you tap the attach button
      // inside that now-open, already-correct chat — one tap instead of
      // hunting for the right contact in a blind share sheet.
      final bytes = base64Decode(photo);
      await Gal.putImageBytes(bytes);
    } on GalException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save photo: ${e.type.message}')));
      }
      return;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save photo: $e')));
      }
      return;
    }

    var digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 10) digits = '91$digits';
    final message = Uri.encodeComponent(_composedMessage(language));
    final url = Uri.parse('https://wa.me/$digits?text=$message');
    try {
      final launched = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (launched && mounted) {
        setState(() => _sentTo.add(vendor['id'] as String));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Photo saved — tap the attach button in the chat to add it'),
          duration: Duration(seconds: 4),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not open WhatsApp: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      appBar: AppBar(
        title: const Text('Promotions'),
        actions: [
          IconButton(
            tooltip: 'How this works',
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showHelpSheet(context),
          ),
        ],
      ),
      body: _stepIndex < 0 ? _buildComposer() : _buildStepper(),
    );
  }

  Widget _buildComposer() {
    final photo = _selectedProduct?['photo'] as String?;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Message', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 4),
        const Text(
          'Write it in whichever language(s) you\'ll actually send — leaving one blank falls back '
          'to the other when you pick a language to send in.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 10),
        const Text('English', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
        const SizedBox(height: 4),
        TextField(
          controller: _messageEnCtrl,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'e.g. New stock of premium cattle feed just arrived — 5% off this week!',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        const Text('தமிழ்', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
        const SizedBox(height: 4),
        TextField(
          controller: _messageTaCtrl,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'e.g. புதிய கால்நடை தீவனம் வந்துள்ளது — இந்த வாரம் 5% தள்ளுபடி!',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 20),
        const Text('Product (optional)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 4),
        const Text(
          'Attach a product so its photo can go along with the message.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 8),
        AppCard(
          onTap: _pickProduct,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              if (photo != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(base64Decode(photo), width: 44, height: 44, fit: BoxFit.cover),
                )
              else
                const IconBadge(icon: Icons.inventory_2_outlined, color: AppTheme.accent, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _selectedProduct != null ? _selectedProduct!['name'] as String : 'Tap to pick a product',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              if (_selectedProduct != null)
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => _selectedProduct = null),
                ),
              const Icon(Icons.chevron_right, color: Colors.black38),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text('Send to', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        AppCard(
          onTap: _pickVendors,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const IconBadge(icon: Icons.people_outline, color: AppTheme.primary, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _selectedVendors.isEmpty
                      ? 'Tap to pick vendors'
                      : '${_selectedVendors.length} vendor${_selectedVendors.length == 1 ? '' : 's'} selected',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black38),
            ],
          ),
        ),
        const SizedBox(height: 28),
        FilledButton.icon(
          onPressed: ((_messageEnCtrl.text.trim().isNotEmpty || _messageTaCtrl.text.trim().isNotEmpty) &&
                  _selectedVendors.isNotEmpty)
              ? () => setState(() {
                    _stepIndex = 0;
                    _sentTo.clear();
                  })
              : null,
          icon: const Icon(Icons.send_outlined, size: 18),
          label: const Text('Start Sending'),
        ),
      ],
    );
  }

  Widget _buildStepper() {
    if (_stepIndex >= _selectedVendors.length) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline, color: AppTheme.success, size: 48),
              const SizedBox(height: 12),
              Text('Done — sent to ${_sentTo.length} of ${_selectedVendors.length} vendors',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => setState(() => _stepIndex = -1),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      );
    }

    final vendor = _selectedVendors[_stepIndex];
    final hasPhoto = _selectedProduct?['photo'] != null;
    final alreadySent = _sentTo.contains(vendor['id']);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text('${_stepIndex + 1} of ${_selectedVendors.length}',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
          const SizedBox(height: 20),
          CircleAvatar(
            radius: 32,
            backgroundColor: AppTheme.primary.withOpacity(0.12),
            child: Text((vendor['name'] as String)[0].toUpperCase(),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.primary)),
          ),
          const SizedBox(height: 12),
          Text(vendor['name'] as String, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text(vendor['phone'] as String? ?? '', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          if (alreadySent) ...[
            const SizedBox(height: 8),
            const Chip(label: Text('Sent', style: TextStyle(fontSize: 11)), backgroundColor: Color(0xFFDCFCE7)),
          ],
          const Spacer(),
          OutlinedButton.icon(
            onPressed: () => _sendText(vendor),
            icon: const Icon(Icons.message_outlined, size: 18),
            label: const Text('Send Text'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
          if (hasPhoto) ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () => _shareWithPhoto(vendor),
              icon: const Icon(Icons.image_outlined, size: 18),
              label: const Text('Share with Photo'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
          ],
          const SizedBox(height: 20),
          TextButton(
            onPressed: () => setState(() => _stepIndex++),
            child: Text(_stepIndex == _selectedVendors.length - 1 ? 'Finish' : 'Next vendor'),
          ),
        ],
      ),
    );
  }
}

class _ProductPickerScreen extends StatefulWidget {
  const _ProductPickerScreen();

  @override
  State<_ProductPickerScreen> createState() => _ProductPickerScreenState();
}

class _ProductPickerScreenState extends State<_ProductPickerScreen> {
  final _db = DBHelper.instance;
  String _search = '';
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _db.getProducts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pick a Product')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: TextField(
              decoration: const InputDecoration(hintText: 'Search products', prefixIcon: Icon(Icons.search)),
              onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _future,
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final products = snap.data!
                    .where((p) => (p['name'] as String).toLowerCase().contains(_search))
                    .toList();
                return ListView.builder(
                  itemCount: products.length,
                  itemBuilder: (_, i) {
                    final p = products[i];
                    final photo = p['photo'] as String?;
                    return ListTile(
                      leading: photo != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.memory(base64Decode(photo), width: 40, height: 40, fit: BoxFit.cover),
                            )
                          : const Icon(Icons.inventory_2_outlined),
                      title: Text(p['name'] as String),
                      onTap: () => Navigator.pop(context, p),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _VendorMultiPickerScreen extends StatefulWidget {
  final List<Map<String, dynamic>> initiallySelected;
  const _VendorMultiPickerScreen({required this.initiallySelected});

  @override
  State<_VendorMultiPickerScreen> createState() => _VendorMultiPickerScreenState();
}

class _VendorMultiPickerScreenState extends State<_VendorMultiPickerScreen> {
  final _db = DBHelper.instance;
  String _search = '';
  late Future<List<Map<String, dynamic>>> _future;
  late Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _future = _db.getVendors();
    _selectedIds = widget.initiallySelected.map((v) => v['id'] as String).toSet();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick Vendors'),
        actions: [
          TextButton(
            onPressed: () async {
              final all = await _future;
              Navigator.pop(context, all.where((v) => _selectedIds.contains(v['id'])).toList());
            },
            child: Text('Done (${_selectedIds.length})', style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: TextField(
              decoration: const InputDecoration(hintText: 'Search vendors', prefixIcon: Icon(Icons.search)),
              onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _future,
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final vendors = [...snap.data!]
                  ..sort((a, b) =>
                      (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase()));
                final filtered =
                    vendors.where((v) => (v['name'] as String).toLowerCase().contains(_search)).toList();
                return ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final v = filtered[i];
                    final id = v['id'] as String;
                    return CheckboxListTile(
                      value: _selectedIds.contains(id),
                      title: Text(v['name'] as String),
                      subtitle: Text(v['phone'] as String? ?? ''),
                      onChanged: (checked) => setState(() {
                        if (checked == true) {
                          _selectedIds.add(id);
                        } else {
                          _selectedIds.remove(id);
                        }
                      }),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
