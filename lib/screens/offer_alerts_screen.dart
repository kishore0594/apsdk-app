import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import '../utils/formatters.dart';

/// Short notification-bar alerts to customers who turned on "offer alerts"
/// on the website. The shop's server sends them (Blaze plan); this screen
/// only queues a campaign document — nothing is sent from the phone.
class OfferAlertsScreen extends StatefulWidget {
  final String title;
  final String body;
  const OfferAlertsScreen({super.key, this.title = '', this.body = ''});

  @override
  State<OfferAlertsScreen> createState() => _OfferAlertsScreenState();
}

class _OfferAlertsScreenState extends State<OfferAlertsScreen> {
  final _fs = FirebaseFirestore.instance;
  late final _title = TextEditingController(text: widget.title);
  late final _body = TextEditingController(text: widget.body);
  late final Future<int> _subscribers = _count();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _history =
      _fs.collection('push_campaigns').orderBy('created_at', descending: true).limit(20).snapshots();
  bool _sending = false;

  Future<int> _count() async {
    try {
      final c = await _fs.collection('push_subscribers').count().get().timeout(const Duration(seconds: 8));
      return c.count ?? 0;
    } catch (_) {
      return -1; // offline or not available
    }
  }

  Future<void> _send(int people) async {
    final title = _title.text.trim();
    final body = _body.text.trim();
    if (title.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send this alert?'),
        content: Text(people > 0
            ? 'It goes to $people customer${people == 1 ? '' : 's'} with offer alerts on. This can\'t be undone.'
            : 'It goes to every customer with offer alerts on. This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _sending = true);
    try {
      await _fs.collection('push_campaigns').add({
        'title': title.length > 60 ? title.substring(0, 60) : title,
        'body': body.length > 160 ? body.substring(0, 160) : body,
        'url': '/',
        'audience': 'all',
        'status': 'queued',
        'created_at': DateTime.now().toIso8601String(),
        'created_by': FirebaseAuth.instance.currentUser?.uid ?? '',
      }).timeout(const Duration(seconds: 8));
      if (!mounted) return;
      _title.clear();
      _body.clear();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sending — status updates below in a moment')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not send (are you online?): $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      appBar: AppBar(title: const Text('Offer notifications')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
        children: [
          FutureBuilder<int>(
            future: _subscribers,
            builder: (context, snap) {
              final n = snap.data;
              final text = n == null
                  ? 'Counting customers…'
                  : n < 0
                      ? 'Customer count unavailable offline'
                      : n == 0
                          ? 'No customers have turned on offer alerts yet'
                          : '$n customer${n == 1 ? '' : 's'} will receive your alerts';
              return AppCard(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  const IconBadge(icon: Icons.notifications_active_outlined, color: AppTheme.primary, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(height: 2),
                      Text('Customers turn alerts on after ordering, or from the website footer.',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ]),
                  ),
                ]),
              );
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            maxLength: 60,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
                labelText: 'Title', hintText: '🌾 New combo: Millet Starter Pack', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _body,
            maxLength: 160,
            maxLines: 3,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
                labelText: 'Message (short)',
                hintText: 'Ragi + Thinai + Samai, 250 g each — ₹75 only. Tap to order.',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          const Text('Preview', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [BoxShadow(blurRadius: 10, color: Colors.black12)]),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset('assets/logo.png', width: 36, height: 36, fit: BoxFit.cover)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_title.text.isEmpty ? 'Title' : _title.text,
                      style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(_body.text.isEmpty ? 'Your message' : _body.text,
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700), maxLines: 2, overflow: TextOverflow.ellipsis),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          FutureBuilder<int>(
            future: _subscribers,
            builder: (context, snap) => FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: (_sending || _title.text.trim().isEmpty || snap.data == 0) ? null : () => _send(snap.data ?? 0),
              icon: const Icon(Icons.send_outlined),
              label: Text(_sending ? 'Sending…' : 'Send alert'),
            ),
          ),
          const SizedBox(height: 22),
          const Text('Sent alerts', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 6),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _history,
            builder: (context, snap) {
              if (!snap.hasData) return const Padding(padding: EdgeInsets.all(12), child: Text('Loading…'));
              final docs = snap.data!.docs;
              if (docs.isEmpty) return Text('None yet', style: TextStyle(color: Colors.grey.shade600));
              return Column(children: [
                for (final d in docs)
                  () {
                    final c = d.data();
                    final status = (c['status'] ?? 'queued').toString();
                    final color = status == 'sent'
                        ? AppTheme.profit
                        : status == 'failed'
                            ? AppTheme.danger
                            : Colors.orange;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text((c['title'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text([
                        formatDay((c['created_at'] ?? '').toString()),
                        status == 'queued' ? 'Sending… (needs the server set up)' : status,
                        if (status == 'failed' && c['error'] != null) c['error'].toString(),
                      ].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: Icon(
                          status == 'sent'
                              ? Icons.check_circle
                              : status == 'failed'
                                  ? Icons.error_outline
                                  : Icons.schedule,
                          color: color),
                    );
                  }(),
              ]);
            },
          ),
        ],
      ),
    );
  }
}
