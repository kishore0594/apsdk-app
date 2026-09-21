import 'package:flutter/material.dart';
import '../db/db_helper.dart';
import '../utils/app_theme.dart';
import '../utils/formatters.dart';

class ProductMarginsScreen extends StatefulWidget {
  const ProductMarginsScreen({super.key});

  @override
  State<ProductMarginsScreen> createState() => _ProductMarginsScreenState();
}

class _ProductMarginsScreenState extends State<ProductMarginsScreen> {
  final _db = DBHelper.instance;
  List<Map<String, dynamic>> _products = [];
  bool _loading = true;
  String _searchQuery = '';
  // 'margin_asc' surfaces the worst performers first by default — the
  // more actionable view for deciding what to reprice, since a healthy
  // margin rarely needs attention but a thin or negative one does.
  String _sort = 'margin_asc';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final products = await _db.getProducts();
    if (mounted) setState(() { _products = products; _loading = false; });
  }

  double _costOf(Map<String, dynamic> p) => (p['cost_price'] as num?)?.toDouble() ?? 0;
  double _priceOf(Map<String, dynamic> p) => (p['selling_price'] as num?)?.toDouble() ?? 0;
  double _marginPercentOf(Map<String, dynamic> p) {
    final price = _priceOf(p);
    if (price <= 0) return 0;
    return ((price - _costOf(p)) / price) * 100;
  }

  List<Map<String, dynamic>> get _filtered {
    var list = _products.where((p) {
      if (_searchQuery.isEmpty) return true;
      return (p['name'] as String? ?? '').toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
    switch (_sort) {
      case 'margin_asc':
        list.sort((a, b) => _marginPercentOf(a).compareTo(_marginPercentOf(b)));
        break;
      case 'margin_desc':
        list.sort((a, b) => _marginPercentOf(b).compareTo(_marginPercentOf(a)));
        break;
      case 'name':
        list.sort((a, b) => (a['name'] as String? ?? '').compareTo(b['name'] as String? ?? ''));
        break;
    }
    return list;
  }

  Color _colorFor(double margin, bool costMissing) {
    if (costMissing) return Colors.grey;
    if (margin < 0) return AppTheme.danger;
    if (margin < 15) return Colors.orange;
    return AppTheme.profit;
  }

  @override
  Widget build(BuildContext context) {
    final withCost = _products.where((p) => _costOf(p) > 0).toList();
    final missingCostCount = _products.length - withCost.length;
    final avgMargin = withCost.isEmpty
        ? 0.0
        : withCost.fold<double>(0, (sum, p) => sum + _marginPercentOf(p)) / withCost.length;

    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      appBar: AppBar(
        title: const Text('Profit Margins'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => showModalBottomSheet(
              context: context,
              showDragHandle: true,
              builder: (_) => Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('About this page',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    const Text(
                      'Margin here is per unit, at the current cost and selling price on file for each '
                      'product — not tied to any particular sale. For the margin on a specific sale as '
                      'you apply a discount, that shows on the New Sale screen itself.',
                      style: TextStyle(fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'A product with no cost price on file shows as unknown, in grey, rather than as a '
                      'misleadingly high margin — fill in its cost on the Inventory screen to see a real '
                      'number.',
                      style: TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AppCard(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${avgMargin.toStringAsFixed(1)}%',
                                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                              Text('Avg. margin', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                            ],
                          ),
                        ),
                      ),
                      if (missingCostCount > 0) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: AppCard(
                            padding: const EdgeInsets.all(14),
                            background: Colors.grey.withOpacity(0.1),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('$missingCostCount',
                                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                                Text('Missing cost price',
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search products',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v.trim()),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'margin_asc', label: Text('Lowest first', style: TextStyle(fontSize: 11.5))),
                      ButtonSegment(value: 'margin_desc', label: Text('Highest first', style: TextStyle(fontSize: 11.5))),
                      ButtonSegment(value: 'name', label: Text('Name', style: TextStyle(fontSize: 11.5))),
                    ],
                    selected: {_sort},
                    onSelectionChanged: (s) => setState(() => _sort = s.first),
                  ),
                  const SizedBox(height: 14),
                  if (_filtered.isEmpty)
                    const EmptyState(icon: Icons.inventory_2_outlined, title: 'No products found')
                  else
                    for (final p in _filtered)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: AppCard(
                          padding: const EdgeInsets.all(14),
                          child: Builder(builder: (context) {
                            final cost = _costOf(p);
                            final price = _priceOf(p);
                            final costMissing = cost <= 0;
                            final margin = _marginPercentOf(p);
                            final color = _colorFor(margin, costMissing);
                            return Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(p['name'] as String? ?? '',
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                      const SizedBox(height: 3),
                                      Text(
                                        'Cost ${costMissing ? "—" : formatCurrency(cost)}  •  Price ${formatCurrency(price)}',
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      costMissing ? 'Unknown' : '${margin.toStringAsFixed(1)}%',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: color),
                                    ),
                                    if (!costMissing)
                                      Text(formatCurrency(price - cost),
                                          style: TextStyle(fontSize: 11.5, color: color)),
                                  ],
                                ),
                              ],
                            );
                          }),
                        ),
                      ),
                ],
              ),
            ),
    );
  }
}
