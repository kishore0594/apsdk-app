import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/web_store_service.dart';
import '../utils/app_theme.dart';
import '../utils/formatters.dart';
import '../utils/user_role.dart';

/// Words customers typed in the website search box (no names or phone
/// numbers are saved). Most searched first. Words that found nothing show
/// what to stock next — or a name to add as "Also called" so the search
/// finds the product next time.
class SearchWordsScreen extends StatefulWidget {
  const SearchWordsScreen({super.key});

  @override
  State<SearchWordsScreen> createState() => _SearchWordsScreenState();
}

class _Word {
  final String q;
  int count = 0;
  int found = 0; // searches that showed at least one product
  DateTime? last;
  _Word(this.q);
  bool get nothing => found == 0;
}

class _SearchWordsScreenState extends State<SearchWordsScreen> {
  final _fs = FirebaseFirestore.instance;
  int _days = 30;
  bool _onlyNothing = false;
  late Future<List<_Word>> _future = _load();

  Future<List<_Word>> _load() async {
    final since = DateTime.now().subtract(Duration(days: _days));
    final snap = await _fs
        .collection('search_log')
        .where('createdAt', isGreaterThan: Timestamp.fromDate(since))
        .orderBy('createdAt', descending: true)
        .limit(2000)
        .get()
        .timeout(const Duration(seconds: 20));
    final byWord = <String, _Word>{};
    for (final d in snap.docs) {
      final m = d.data();
      final q = (m['q'] ?? '').toString().trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      if (q.length < 2) continue;
      final w = byWord.putIfAbsent(q, () => _Word(q));
      w.count++;
      if (((m['hits'] as num?) ?? 0) > 0) w.found++;
      final ts = m['createdAt'];
      if (ts is Timestamp && (w.last == null || ts.toDate().isAfter(w.last!))) w.last = ts.toDate();
    }
    return byWord.values.toList()..sort((a, b) => b.count.compareTo(a.count));
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _copy(String q) async {
    await Clipboard.setData(ClipboardData(text: q));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied "$q"')));
  }

  /// Add the word as an "Also called" name of one product.
  Future<void> _addAsName(String q) async {
    List<Map<String, dynamic>> products;
    try {
      final snap = await _fs.collection('products').get().timeout(const Duration(seconds: 15));
      products = snap.docs.map((d) => <String, dynamic>{...d.data(), 'id': d.id}).where(WebStoreService.isOnline).toList()
        ..sort((a, b) => (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load products: $e')));
      return;
    }
    if (!mounted) return;
    var filter = '';
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final shown = products
              .where((p) => (p['name'] ?? '').toString().toLowerCase().contains(filter.toLowerCase()))
              .toList();
          return SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.75,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Which product is "$q"?',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  decoration: const InputDecoration(
                      hintText: 'Search products', prefixIcon: Icon(Icons.search), isDense: true, border: OutlineInputBorder()),
                  onChanged: (v) => setSheet(() => filter = v.trim()),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (_, i) {
                    final p = shown[i];
                    final names = WebStoreService.aliasesOf(p);
                    return ListTile(
                      title: Text((p['name'] ?? '').toString()),
                      subtitle: names.isEmpty ? null : Text('Also called: ${names.join(', ')}', maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.pop(ctx, p),
                    );
                  },
                ),
              ),
            ]),
          );
        },
      ),
    );
    if (picked == null) return;
    await WebStoreService.instance.addAlias(picked, q);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Added "$q" to ${picked['name']} — the website search finds it in a few seconds')));
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = UserRole.instance.isAdmin;
    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      appBar: AppBar(
        title: const Text('What customers searched'),
        actions: [
          PopupMenuButton<int>(
            tooltip: 'Period',
            initialValue: _days,
            onSelected: (d) {
              _days = d;
              _reload();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 7, child: Text('Last 7 days')),
              PopupMenuItem(value: 30, child: Text('Last 30 days')),
              PopupMenuItem(value: 90, child: Text('Last 90 days')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [Text('$_days days'), const Icon(Icons.arrow_drop_down)]),
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<_Word>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return ErrorState(message: 'Could not load searches (are you online?)\n${snap.error}');
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final all = snap.data!;
          if (all.isEmpty) {
            return const EmptyState(
              icon: Icons.manage_search,
              title: 'No searches yet',
              message: 'When customers type in the search box on your website, the words appear here.',
            );
          }
          final total = all.fold<int>(0, (s, w) => s + w.count);
          final nothing = all.where((w) => w.nothing).length;
          final list = _onlyNothing ? all.where((w) => w.nothing).toList() : all;
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
              children: [
                AppCard(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    const IconBadge(icon: Icons.manage_search, color: AppTheme.primary, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('$total searches · ${all.length} different words',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        const SizedBox(height: 2),
                        Text(
                          nothing == 0 ? 'Every search found products' : '$nothing word(s) found nothing — see below',
                          style: TextStyle(fontSize: 12, color: nothing == 0 ? Colors.grey.shade600 : AppTheme.danger),
                        ),
                      ]),
                    ),
                  ]),
                ),
                const SizedBox(height: 10),
                Wrap(spacing: 8, children: [
                  ChoiceChip(
                      label: const Text('All words'),
                      selected: !_onlyNothing,
                      onSelected: (_) => setState(() => _onlyNothing = false)),
                  ChoiceChip(
                      label: Text('Found nothing ($nothing)'),
                      selected: _onlyNothing,
                      onSelected: (_) => setState(() => _onlyNothing = true)),
                ]),
                const SizedBox(height: 8),
                for (final w in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(w.q, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                            const SizedBox(height: 2),
                            Text(
                              [
                                '${w.count} search${w.count == 1 ? '' : 'es'}',
                                if (w.last != null) 'last ${formatDay(w.last!.toIso8601String())}',
                                if (w.nothing) 'found nothing',
                              ].join(' · '),
                              style: TextStyle(fontSize: 12, color: w.nothing ? AppTheme.danger : Colors.grey.shade600),
                            ),
                          ]),
                        ),
                        PopupMenuButton<String>(
                          onSelected: (a) => a == 'name' ? _addAsName(w.q) : _copy(w.q),
                          itemBuilder: (_) => [
                            if (canEdit)
                              const PopupMenuItem(value: 'name', child: Text('Add as a name of a product')),
                            const PopupMenuItem(value: 'copy', child: Text('Copy word')),
                          ],
                        ),
                      ]),
                    ),
                  ),
                const SizedBox(height: 10),
                Text(
                  'Found nothing? Either you do not sell it yet (a product to stock), or customers call it by another '
                  'name — tap ⋮ → "Add as a name of a product" and the search will find it. '
                  'Only the words are saved: no names or phone numbers.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.4),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
