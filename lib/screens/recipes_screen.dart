import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/recipe_library.dart';
import '../services/web_store_service.dart';
import '../utils/app_theme.dart';
import '../utils/keyed_stream.dart';
import '../utils/user_role.dart';

/// Recipes for the web store. The shop picks "Today's recipe" with the star;
/// each recipe can link products or combos (e.g. to promote a new launch).
class RecipesScreen extends StatefulWidget {
  const RecipesScreen({super.key});

  @override
  State<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends State<RecipesScreen> {
  final _svc = WebStoreService.instance;
  final _settings = KeyedStream<Map<String, dynamic>>();
  final _products = KeyedStream<List<Map<String, dynamic>>>();

  bool get _canEdit => UserRole.instance.isAdmin;

  Future<void> _saveRecipes(List<Map<String, dynamic>> recipes) => _svc.saveSettings({'recipes': recipes});

  void _done(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      appBar: AppBar(title: const Text('Recipes')),
      body: StreamBuilder<Map<String, dynamic>>(
        stream: _settings.get(0, _svc.watchSettings),
        builder: (context, sSnap) => StreamBuilder<List<Map<String, dynamic>>>(
          stream: _products.get(0, _svc.watchProducts),
          builder: (context, pSnap) {
            if (sSnap.hasError || pSnap.hasError) {
              return ErrorState(message: 'Could not load recipes.\n${sSnap.error ?? pSnap.error}');
            }
            if (!sSnap.hasData || !pSnap.hasData) return const Center(child: CircularProgressIndicator());
            final settings = sSnap.data!;
            final products = pSnap.data!;
            final recipes = WebStoreService.recipesOf(settings);
            final today = (settings['todayRecipe'] ?? '').toString();
            final todayName = recipes.where((r) => r['id'] == today).map((r) => r['name'].toString()).firstOrNull;
            return ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 90),
              children: [
                AppCard(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    const IconBadge(icon: Icons.restaurant_menu, color: Color(0xFFE36A06), size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(todayName == null ? "Today's recipe: not chosen" : "Today's recipe: $todayName",
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                        const SizedBox(height: 2),
                        Text('Tap ☆ on a recipe to show it on the website',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      ]),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
                if (recipes.isEmpty) ...[
                  const EmptyState(
                    icon: Icons.restaurant_menu,
                    title: 'No recipes yet',
                    message: 'Start with 15 traditional millet and gram recipes in English and Tamil — you can edit them.',
                  ),
                  if (_canEdit)
                    FilledButton.icon(
                      onPressed: () async {
                        await _saveRecipes(WebStoreService.starterRecipesFor(products, starterRecipes));
                        _done('15 recipes added and linked to your products');
                      },
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Add 15 starter recipes'),
                    ),
                ],
                for (final r in recipes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppCard(
                      padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
                      onTap: _canEdit ? () => _openEditor(settings, products, r) : null,
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text((r['name'] ?? '').toString(),
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                            const SizedBox(height: 2),
                            Text(
                              [
                                (r['nameLocal'] ?? '').toString(),
                                '${r['minutes'] ?? 0} min',
                                '${((r['products'] as List?) ?? const []).length} linked',
                                (r['photo'] ?? '').toString().isEmpty ? 'no photo' : 'photo ✓',
                              ].where((x) => x.isNotEmpty).join(' · '),
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ]),
                        ),
                        IconButton(
                          tooltip: "Show as today's recipe",
                          onPressed: _canEdit
                              ? () async {
                                  await _svc.saveSettings({'todayRecipe': r['id']});
                                  _done("Today's recipe: ${r['name']} — the website updates in a few seconds");
                                }
                              : null,
                          icon: Icon(r['id'] == today ? Icons.star : Icons.star_border,
                              color: r['id'] == today ? const Color(0xFFE0A11B) : Colors.black45),
                        ),
                      ]),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: _canEdit
          ? FloatingActionButton.extended(
              onPressed: () async {
                final settings = await _svc.settingsRef.get().then((s) => s.data() ?? <String, dynamic>{});
                final products = await _svc.watchProducts().first;
                if (mounted) _openEditor(settings, products, null);
              },
              icon: const Icon(Icons.add),
              label: const Text('New recipe'),
            )
          : null,
    );
  }

  Future<void> _openEditor(Map<String, dynamic> settings, List<Map<String, dynamic>> products, Map<String, dynamic>? recipe) async {
    final result = await Navigator.push<Object>(
      context,
      MaterialPageRoute(builder: (_) => _RecipeEditor(recipe: recipe, products: products, settings: settings)),
    );
    if (result == null) return;
    final fresh = await _svc.settingsRef.get().then((s) => s.data() ?? <String, dynamic>{});
    final all = WebStoreService.recipesOf(fresh);
    final i = recipe == null ? -1 : all.indexWhere((r) => r['id'] == recipe['id']);
    if (result == 'delete') {
      if (i >= 0) {
        await _svc.deleteSiteImage((all[i]['photo'] ?? '').toString());
        all.removeAt(i);
        await _saveRecipes(all);
        if (fresh['todayRecipe'] == recipe!['id']) await _svc.saveSettings({'todayRecipe': ''});
      }
    } else if (result is Map<String, dynamic>) {
      if (i >= 0) {
        all[i] = result;
      } else {
        all.add(result);
      }
      await _saveRecipes(all);
    }
    _done('Saved — the website updates in a few seconds');
  }
}

class _RecipeEditor extends StatefulWidget {
  final Map<String, dynamic>? recipe;
  final List<Map<String, dynamic>> products;
  final Map<String, dynamic> settings;
  const _RecipeEditor({required this.recipe, required this.products, required this.settings});

  @override
  State<_RecipeEditor> createState() => _RecipeEditorState();
}

class _RecipeEditorState extends State<_RecipeEditor> {
  final _svc = WebStoreService.instance;
  late final String _id = (widget.recipe?['id'] ?? 'r${DateTime.now().millisecondsSinceEpoch}').toString();
  late final Map<String, TextEditingController> _c = {
    for (final k in const ['name', 'nameLocal', 'minutes', 'serves', 'tip', 'tipLocal'])
      k: TextEditingController(text: (widget.recipe?[k] ?? '').toString()),
    for (final k in const ['ingredients', 'ingredientsLocal', 'steps', 'stepsLocal', 'benefits', 'benefitsLocal'])
      k: TextEditingController(text: ((widget.recipe?[k] as List?) ?? const []).join('\n')),
  };
  late String _photo = (widget.recipe?['photo'] ?? '').toString();
  final List<String> _oldPhotos = [];
  late final Set<String> _linked = {...((widget.recipe?['products'] as List?) ?? const []).map((x) => x.toString())};
  bool _busy = false;

  List<String> _lines(String k) =>
      _c[k]!.text.split('\n').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();

  Future<void> _pickPhoto() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 72);
    if (x == null) return;
    setState(() => _busy = true);
    try {
      final ref = await _svc.uploadSiteImage('recipe_${_id}_${DateTime.now().millisecondsSinceEpoch}', base64Encode(await x.readAsBytes()));
      if (_photo.isNotEmpty) _oldPhotos.add(_photo);
      setState(() => _photo = ref);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(String k, String label, {int lines = 1, TextInputType? type, String? help}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: _c[k],
          minLines: lines,
          maxLines: lines == 1 ? 1 : 12,
          keyboardType: type,
          decoration: InputDecoration(labelText: label, helperText: help, border: const OutlineInputBorder()),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final online = widget.products.where(WebStoreService.isOnline).toList()
      ..sort((a, b) => (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()));
    final combos = WebStoreService.combosOf(widget.settings).where((c) => c['active'] != false).toList();
    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      appBar: AppBar(
        title: Text(widget.recipe == null ? 'New recipe' : 'Edit recipe'),
        actions: [
          if (widget.recipe != null)
            IconButton(
              tooltip: 'Delete recipe',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Delete this recipe?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                    ],
                  ),
                );
                if (ok == true && context.mounted) Navigator.pop(context, 'delete');
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 110),
        children: [
          AppCard(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Icon(_photo.isEmpty ? Icons.add_photo_alternate_outlined : Icons.check_circle,
                  color: _photo.isEmpty ? Colors.black45 : AppTheme.profit),
              const SizedBox(width: 10),
              Expanded(
                child: Text(_photo.isEmpty ? 'Recipe photo (square or 4:3 looks best)' : 'Photo added',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              if (_photo.isNotEmpty)
                TextButton(
                  onPressed: _busy ? null : () => setState(() {
                    _oldPhotos.add(_photo);
                    _photo = '';
                  }),
                  child: const Text('Remove'),
                ),
              FilledButton(
                onPressed: _busy ? null : _pickPhoto,
                child: Text(_busy ? 'Uploading…' : (_photo.isEmpty ? 'Choose' : 'Replace')),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          _field('name', 'Recipe name (English)'),
          _field('nameLocal', 'Recipe name (Tamil)'),
          Row(children: [
            Expanded(child: _field('minutes', 'Time (minutes)', type: TextInputType.number)),
            const SizedBox(width: 10),
            Expanded(child: _field('serves', 'Serves', type: TextInputType.number)),
          ]),
          _field('ingredients', 'Ingredients (English)', lines: 4, help: 'One per line'),
          _field('ingredientsLocal', 'Ingredients (Tamil)', lines: 4, help: 'One per line'),
          _field('steps', 'Method (English)', lines: 5, help: 'One step per line'),
          _field('stepsLocal', 'Method (Tamil)', lines: 5, help: 'One step per line'),
          _field('benefits', 'Why it is good (English)', lines: 2, help: 'One point per line — no medical claims'),
          _field('benefitsLocal', 'Why it is good (Tamil)', lines: 2, help: 'One point per line'),
          _field('tip', 'Tip (English)', lines: 2),
          _field('tipLocal', 'Tip (Tamil)', lines: 2),
          const SizedBox(height: 6),
          const Text('Products in this recipe', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          Text('These show with "Add" and "Add all to cart" on the website. Pick a combo to promote it.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 6),
          if (combos.isNotEmpty) ...[
            const Padding(padding: EdgeInsets.only(top: 6, bottom: 2), child: Text('Combos', style: TextStyle(fontWeight: FontWeight.w600))),
            for (final c in combos)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _linked.contains('combo:${c['id']}'),
                title: Text((c['name'] ?? '').toString()),
                subtitle: const Text('Combo'),
                onChanged: (v) => setState(() => v == true ? _linked.add('combo:${c['id']}') : _linked.remove('combo:${c['id']}')),
              ),
          ],
          const Padding(padding: EdgeInsets.only(top: 6, bottom: 2), child: Text('Products', style: TextStyle(fontWeight: FontWeight.w600))),
          for (final p in online)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _linked.contains(p['id']),
              title: Text((p['name'] ?? '').toString()),
              onChanged: (v) => setState(() => v == true ? _linked.add(p['id'] as String) : _linked.remove(p['id'])),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _busy
                ? null
                : () async {
                    if (_c['name']!.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Give the recipe a name')));
                      return;
                    }
                    for (final old in _oldPhotos) {
                      if (old != _photo) await _svc.deleteSiteImage(old);
                    }
                    if (!context.mounted) return;
                    Navigator.pop(context, <String, dynamic>{
                      'id': _id,
                      'name': _c['name']!.text.trim(),
                      'nameLocal': _c['nameLocal']!.text.trim(),
                      'photo': _photo,
                      'minutes': int.tryParse(_c['minutes']!.text.trim()) ?? 0,
                      'serves': int.tryParse(_c['serves']!.text.trim()) ?? 0,
                      for (final k in const ['ingredients', 'ingredientsLocal', 'steps', 'stepsLocal', 'benefits', 'benefitsLocal'])
                        k: _lines(k),
                      'tip': _c['tip']!.text.trim(),
                      'tipLocal': _c['tipLocal']!.text.trim(),
                      'products': _linked.toList(),
                    });
                  },
            child: const Text('Save recipe'),
          ),
        ),
      ),
    );
  }
}
