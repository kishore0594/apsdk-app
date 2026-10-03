import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/app_theme.dart';
import '../utils/formatters.dart';
import '../utils/user_role.dart';

/// Messages from the website footer and "couldn't find it" searches:
/// what customers want that the shop may not stock yet.
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

/// Latest messages, newest first (shared with the Web Store card count).
Stream<List<Map<String, dynamic>>> watchFeedback() => FirebaseFirestore.instance
    .collection('feedback')
    .orderBy('createdAt', descending: true)
    .limit(150)
    .snapshots()
    .map((s) => s.docs.map((d) => <String, dynamic>{...d.data(), 'id': d.id}).toList());

class _FeedbackScreenState extends State<FeedbackScreen> {
  late final Stream<List<Map<String, dynamic>>> _stream = watchFeedback();
  bool _showDone = false;

  Future<void> _markDone(String id, bool done) async {
    final op = FirebaseFirestore.instance.collection('feedback').doc(id).update({'done': done});
    try {
      await op.timeout(const Duration(seconds: 3));
    } catch (_) {/* saved offline; syncs later */}
  }

  Future<void> _reply(Map<String, dynamic> f) async {
    final phone = (f['phone'] ?? '').toString();
    final name = (f['name'] ?? '').toString();
    final msg = Uri.encodeComponent('Hello${name.isEmpty ? '' : ' $name'}, thank you for your message to Sri Madhura Agro Traders. ');
    try {
      await launchUrl(Uri.parse('https://wa.me/91$phone?text=$msg'), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open WhatsApp')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = UserRole.instance.isAdmin;
    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      appBar: AppBar(
        title: const Text('Customer feedback'),
        actions: [
          TextButton(
            onPressed: () => setState(() => _showDone = !_showDone),
            child: Text(_showDone ? 'Hide done' : 'Show done'),
          ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) return ErrorState(message: 'Could not load feedback.\n${snap.error}');
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final list = snap.data!.where((f) => _showDone || f['done'] != true).toList();
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.forum_outlined,
              title: 'No new messages',
              message: 'Customers can send feedback or tell you what they were looking for from the website.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(14),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final f = list[i];
              final ts = f['createdAt'];
              final when = ts is Timestamp ? formatDay(ts.toDate().toIso8601String()) : '';
              final phone = (f['phone'] ?? '').toString();
              final query = (f['query'] ?? '').toString();
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (query.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color: const Color(0xFFE36A06).withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
                        child: Text('Searched: "$query"',
                            style: const TextStyle(fontSize: 11.5, color: Color(0xFFE36A06), fontWeight: FontWeight.w600)),
                      ),
                    Text((f['text'] ?? '').toString(), style: const TextStyle(fontSize: 14.5, height: 1.4)),
                    const SizedBox(height: 6),
                    Text(
                      [
                        (f['name'] ?? '').toString().isEmpty ? 'Customer' : f['name'].toString(),
                        if (phone.isNotEmpty) phone,
                        if (when.isNotEmpty) when,
                        if (f['done'] == true) 'done ✓',
                      ].join(' · '),
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    if (canEdit) ...[
                      const SizedBox(height: 6),
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        if (phone.isNotEmpty)
                          TextButton.icon(
                            onPressed: () => _reply(f),
                            icon: const Icon(Icons.chat_outlined, size: 18),
                            label: const Text('Reply on WhatsApp'),
                          ),
                        TextButton(
                          onPressed: () => _markDone(f['id'] as String, f['done'] != true),
                          child: Text(f['done'] == true ? 'Mark new' : 'Mark done'),
                        ),
                      ]),
                    ],
                  ]),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
