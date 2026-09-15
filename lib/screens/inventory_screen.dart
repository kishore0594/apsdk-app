import 'package:flutter/material.dart';
import '../db/db_helper.dart';
import '../utils/formatters.dart';
import '../utils/app_strings.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _db = DBHelper.instance;
  // Created once — search/category filtering happens client-side on
  // whatever this stream last emitted, so typing in the search box never
  // triggers a new Firestore subscription.
  late final Stream<List<Map<String, dynamic>>> _productsStream = _db.watchProducts();
  String _search = '';
  String _categoryFilter = 'All';
  String _subcategoryFilter = 'All';

  List<String> _categoryChips(List<Map<String, dynamic>> products) {
    final cats = products
        .map((p) => (p['category'] as String? ?? '').trim())
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return ['All', ...cats, 'Low Stock'];
  }

  /// Subcategories that exist *within the currently selected category* —
  /// empty when "All" or "Low Stock" is selected, since subcategory only
  /// makes sense once you've narrowed to one category.
  List<String> _subcategoryChips(List<Map<String, dynamic>> products) {
    if (_categoryFilter == 'All' || _categoryFilter == 'Low Stock') return [];
    final subs = products
        .where((p) => (p['category'] as String? ?? '') == _categoryFilter)
        .map((p) => (p['subcategory'] as String? ?? '').trim())
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    if (subs.isEmpty) return [];
    return ['All', ...subs];
  }

  List<Map<String, dynamic>> _filteredProducts(List<Map<String, dynamic>> products) {
    var list = products;
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((p) => (p['name'] as String).toLowerCase().contains(q)).toList();
    }
    if (_categoryFilter == 'Low Stock') {
      return list.where((p) {
        final qty = (p['quantity'] as num).toDouble();
        final reorder = (p['reorder_level'] as num).toDouble();
        return qty <= reorder;
      }).toList();
    }
    if (_categoryFilter != 'All') {
      list = list.where((p) => (p['category'] as String? ?? '') == _categoryFilter).toList();
      if (_subcategoryFilter != 'All') {
        list = list.where((p) => (p['subcategory'] as String? ?? '') == _subcategoryFilter).toList();
      }
    }
    return list;
  }

  String _productSubtitle(Map<String, dynamic> p) {
    final category = p['category'] as String? ?? '';
    final subcategory = p['subcategory'] as String? ?? '';
    final catPart = subcategory.isNotEmpty && category.isNotEmpty
        ? '$category › $subcategory'
        : (category.isNotEmpty ? category : (subcategory.isNotEmpty ? subcategory : '—'));
    return '$catPart  •  ${formatCurrency(p['selling_price'])} / ${p['unit']}';
  }

  Future<void> _openProductForm({Map<String, dynamic>? product}) async {
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProductForm(product: product),
    );
    // No manual refresh needed — the list below is a live stream.
  }

  Future<void> _openStockHistory(Map<String, dynamic> product) async {
    final history = await _db.getStockHistory(product['id'] as String);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        expand: false,
        builder: (_, scrollController) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${product['name']} — Stock History',
                  style: Theme.of(context).textTheme.titleMedium),
              const Divider(),
              Expanded(
                child: history.isEmpty
                    ? Center(child: Text(AppStrings.t('no_movements_yet')))
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: history.length,
                        itemBuilder: (_, i) {
                          final m = history[i];
                          final isIn = m['type'] == 'IN';
                          return ListTile(
                            leading: Icon(
                              isIn ? Icons.arrow_downward : Icons.arrow_upward,
                              color: isIn ? Colors.green : Colors.red,
                            ),
                            title: Text('${isIn ? '+' : '-'}${m['quantity']} ${product['unit']}  (${m['reason']})'),
                            subtitle: Text(formatDate(m['date'] as String)),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.t('inventory_title'))),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _productsStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text("${AppStrings.t('could_not_load_inventory')}: ${snapshot.error}"));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final products = snapshot.data!;
          final filtered = _filteredProducts(products);

          return Column(
            children: [
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: _categoryChips(products).map((cat) {
                    final selected = _categoryFilter == cat;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(cat),
                        selected: selected,
                        onSelected: (_) => setState(() {
                          _categoryFilter = cat;
                          _subcategoryFilter = 'All'; // reset — subcategories differ per category
                        }),
                      ),
                    );
                  }).toList(),
                ),
              ),
              if (_subcategoryChips(products).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: SizedBox(
                    height: 38,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: _subcategoryChips(products).map((sub) {
                        final selected = _subcategoryFilter == sub;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            visualDensity: VisualDensity.compact,
                            label: Text(sub, style: const TextStyle(fontSize: 12)),
                            selected: selected,
                            onSelected: (_) => setState(() => _subcategoryFilter = sub),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: AppStrings.t('search_products'),
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? Center(child: Text(AppStrings.t('no_products_tap_add')))
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final p = filtered[i];
                          final qty = (p['quantity'] as num).toDouble();
                          final reorder = (p['reorder_level'] as num).toDouble();
                          final low = qty <= reorder;
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            child: ListTile(
                              title: Text(p['name'] as String),
                              subtitle: Text(_productSubtitle(p)),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('$qty ${p['unit']}',
                                      style: TextStyle(
                                          color: low ? Colors.red : Colors.black87,
                                          fontWeight: FontWeight.bold)),
                                  if (low)
                                    Text(AppStrings.t('low_stock'),
                                        style: TextStyle(color: Colors.red, fontSize: 11)),
                                ],
                              ),
                              onTap: () => _openProductForm(product: p),
                              onLongPress: () => _openStockHistory(p),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openProductForm(),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _ProductForm extends StatefulWidget {
  final Map<String, dynamic>? product;
  const _ProductForm({this.product});

  @override
  State<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<_ProductForm> {
  final _formKey = GlobalKey<FormState>();
  final _db = DBHelper.instance;

  static const _unitOptions = ['Nos', 'Kgs', 'Gms', 'Ltr', 'Ml', 'Box', 'Dozen', 'Packet'];

  late final TextEditingController _name;
  late final TextEditingController _category;
  late final TextEditingController _subcategory;
  late String _unit;
  late final TextEditingController _quantity;
  late final TextEditingController _reorderLevel;
  late final TextEditingController _costPrice;
  late final TextEditingController _sellingPrice;
  String? _supplierId;
  List<Map<String, dynamic>> _suppliers = [];

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _name = TextEditingController(text: p?['name'] as String? ?? '');
    _category = TextEditingController(text: p?['category'] as String? ?? '');
    _subcategory = TextEditingController(text: p?['subcategory'] as String? ?? '');
    final existingUnit = p?['unit'] as String?;
    _unit = _unitOptions.contains(existingUnit) ? existingUnit! : _unitOptions.first;
    _quantity = TextEditingController(text: (p?['quantity'] ?? 0).toString());
    _reorderLevel = TextEditingController(text: (p?['reorder_level'] ?? 0).toString());
    _costPrice = TextEditingController(text: (p?['cost_price'] ?? 0).toString());
    _sellingPrice = TextEditingController(text: (p?['selling_price'] ?? 0).toString());
    _supplierId = p?['supplier_id'] as String?;
    _loadSuppliers();
  }

  Future<void> _loadSuppliers() async {
    final s = await _db.getSuppliers();
    setState(() => _suppliers = s);
  }

  Future<void> _quickAddSupplier() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppStrings.t('new_supplier')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: InputDecoration(labelText: AppStrings.t('name')), autofocus: true),
            TextField(controller: phoneCtrl, decoration: InputDecoration(labelText: AppStrings.t('phone'))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(AppStrings.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(AppStrings.t('save'))),
        ],
      ),
    );
    if (saved == true && nameCtrl.text.trim().isNotEmpty) {
      final newId = await _db.insertSupplier({
        'name': nameCtrl.text.trim(),
        'phone': phoneCtrl.text.trim(),
        'address': '',
        'opening_balance': 0,
        'created_at': DateTime.now().toIso8601String(),
      });
      await _loadSuppliers();
      setState(() => _supplierId = newId);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final now = DateTime.now().toIso8601String();
    final data = {
      'name': _name.text.trim(),
      'category': _category.text.trim(),
      'subcategory': _subcategory.text.trim(),
      'unit': _unit,
      'quantity': double.tryParse(_quantity.text) ?? 0,
      'reorder_level': double.tryParse(_reorderLevel.text) ?? 0,
      'cost_price': double.tryParse(_costPrice.text) ?? 0,
      'selling_price': double.tryParse(_sellingPrice.text) ?? 0,
      'supplier_id': _supplierId,
      'updated_at': now,
    };
    if (widget.product == null) {
      data['created_at'] = now;
      await _db.insertProduct(data);
    } else {
      await _db.updateProduct(widget.product!['id'] as String, data);
    }
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    await _db.deleteProduct(widget.product!['id'] as String);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.product == null ? 'Add Product' : 'Edit Product',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                decoration: InputDecoration(labelText: AppStrings.t('product_name')),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _category,
                decoration: InputDecoration(labelText: AppStrings.t('category')),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _subcategory,
                decoration: InputDecoration(labelText: AppStrings.t('sub_category')),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _unit,
                      decoration: InputDecoration(labelText: AppStrings.t('unit')),
                      items: _unitOptions
                          .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                          .toList(),
                      onChanged: (v) => setState(() => _unit = v ?? _unit),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _quantity,
                      decoration: InputDecoration(labelText: AppStrings.t('current_quantity')),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _reorderLevel,
                decoration: InputDecoration(labelText: AppStrings.t('reorder_level')),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _costPrice,
                      decoration: InputDecoration(labelText: AppStrings.t('cost_price')),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _sellingPrice,
                      decoration: InputDecoration(labelText: AppStrings.t('selling_price')),
                      keyboardType: TextInputType.number,
                      validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _supplierId,
                      decoration: InputDecoration(labelText: AppStrings.t('supplier_optional')),
                      items: _suppliers
                          .map((s) => DropdownMenuItem(value: s['id'] as String, child: Text(s['name'] as String)))
                          .toList(),
                      onChanged: (v) => setState(() => _supplierId = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Add new supplier',
                    onPressed: _quickAddSupplier,
                    icon: const Icon(Icons.add_business),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: _save, child: Text(AppStrings.t('save_product'))),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppStrings.t('cancel')),
              ),
              if (widget.product != null) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _delete,
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  child: Text(AppStrings.t('delete_product')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
