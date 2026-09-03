import 'package:flutter/material.dart';
import '../db/db_helper.dart';
import '../utils/formatters.dart';

// Units sold by weight/volume need decimal quantities (e.g. 0.75 Kgs).
// Count-based units (Nos, Box, Dozen, Packet...) stay whole numbers.
const _weightUnits = {
  'kg', 'kgs', 'g', 'gm', 'gms', 'gram', 'grams',
  'l', 'ltr', 'ltrs', 'litre', 'litres', 'liter', 'liters', 'ml',
};

bool _isWeightUnit(String unit) => _weightUnits.contains(unit.trim().toLowerCase());

double _stepFor(String unit) => _isWeightUnit(unit) ? 0.25 : 1;

String _formatQty(double v, String unit) {
  if (!_isWeightUnit(unit)) return v.toStringAsFixed(0);
  var s = v.toStringAsFixed(2);
  s = s.replaceFirst(RegExp(r'0+$'), '');
  s = s.replaceFirst(RegExp(r'\.$'), '');
  return s.isEmpty ? '0' : s;
}

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  final _db = DBHelper.instance;
  List<Map<String, dynamic>> _sales = [];
  bool _todayOnly = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final filter = _todayOnly ? DateTime.now().toIso8601String().substring(0, 10) : null;
    final sales = await _db.getSales(dateFilter: filter);
    setState(() => _sales = sales);
  }

  Future<void> _viewSale(Map<String, dynamic> sale) async {
    final items = await _db.getSaleItems(sale['id'] as int);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Sale #${sale['id']}', style: Theme.of(context).textTheme.titleLarge),
            Text(formatDate(sale['date'] as String)),
            const Divider(),
            ...items.map((i) => ListTile(
                  dense: true,
                  title: Text(i['product_name'] as String),
                  subtitle: Text('${i['quantity']} × ${formatCurrency(i['unit_price'])}'),
                  trailing: Text(formatCurrency(i['subtotal'])),
                )),
            const Divider(),
            ListTile(title: const Text('Subtotal'), trailing: Text(formatCurrency(sale['subtotal']))),
            if ((sale['discount'] as num) > 0)
              ListTile(title: const Text('Discount'), trailing: Text('- ${formatCurrency(sale['discount'])}')),
            ListTile(
              title: const Text('Total', style: TextStyle(fontWeight: FontWeight.bold)),
              trailing: Text(formatCurrency(sale['total_amount']),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            Chip(label: Text(sale['payment_type'] as String)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _sales.fold<double>(0, (sum, s) => sum + (s['total_amount'] as num));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales'),
        actions: [
          IconButton(
            icon: Icon(_todayOnly ? Icons.today : Icons.calendar_month),
            tooltip: _todayOnly ? 'Showing today — tap for all' : 'Showing all — tap for today',
            onPressed: () {
              setState(() => _todayOnly = !_todayOnly);
              _load();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Text(
              '${_todayOnly ? "Today's" : "Total"} Sales: ${formatCurrency(total)}  (${_sales.length} bills)',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: _sales.isEmpty
                ? const Center(child: Text('No sales recorded. Tap + to add a sale.'))
                : ListView.builder(
                    itemCount: _sales.length,
                    itemBuilder: (_, i) {
                      final s = _sales[i];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: s['payment_type'] == 'CASH'
                                ? Colors.green.shade100
                                : Colors.orange.shade100,
                            child: Icon(
                              s['payment_type'] == 'CASH' ? Icons.money : Icons.credit_card,
                              color: s['payment_type'] == 'CASH' ? Colors.green : Colors.orange,
                            ),
                          ),
                          title: Text(formatCurrency(s['total_amount'])),
                          subtitle: Text(formatDate(s['date'] as String)),
                          trailing: Text(s['payment_type'] as String),
                          onTap: () => _viewSale(s),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
              context, MaterialPageRoute(builder: (_) => const NewSaleScreen()));
          if (result == true) _load();
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class NewSaleScreen extends StatefulWidget {
  const NewSaleScreen({super.key});

  @override
  State<NewSaleScreen> createState() => _NewSaleScreenState();
}

class _CartLine {
  final Map<String, dynamic> product;
  double quantity;
  _CartLine(this.product, this.quantity);
}

class _NewSaleScreenState extends State<NewSaleScreen> {
  final _db = DBHelper.instance;
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _vendors = [];
  final List<_CartLine> _cart = [];

  String _paymentType = 'CASH';
  int? _vendorId;
  int? _pickerProductId;
  final _discountCtrl = TextEditingController(text: '0');
  final _paidCtrl = TextEditingController(text: '0');

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final products = await _db.getProducts();
    final vendors = await _db.getVendors();
    setState(() {
      _products = products;
      _vendors = vendors;
      _pickerProductId ??= products.isNotEmpty ? products.first['id'] as int : null;
    });
  }

  double get _subtotal =>
      _cart.fold(0, (sum, l) => sum + l.quantity * (l.product['selling_price'] as num));

  double get _discount => double.tryParse(_discountCtrl.text) ?? 0;
  double get _total => _subtotal - _discount;

  void _addProduct(Map<String, dynamic> product) {
    final existing = _cart.where((l) => l.product['id'] == product['id']);
    if (existing.isNotEmpty) {
      final step = _stepFor(product['unit'] as String? ?? 'pcs');
      setState(() => existing.first.quantity =
          double.parse((existing.first.quantity + step).toStringAsFixed(2)));
    } else {
      setState(() => _cart.add(_CartLine(product, 1)));
    }
  }

  Future<void> _editQuantity(_CartLine line) async {
    final unit = line.product['unit'] as String? ?? 'pcs';
    final ctrl = TextEditingController(text: _formatQty(line.quantity, unit));
    final value = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Quantity ($unit)'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Quantity'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Set')),
        ],
      ),
    );
    if (value == null) return;
    final parsed = double.tryParse(value);
    if (parsed == null) return;
    setState(() {
      if (parsed <= 0) {
        _cart.remove(line);
      } else {
        line.quantity = double.parse(parsed.toStringAsFixed(2));
      }
    });
  }

  Future<void> _checkout() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add at least one item')));
      return;
    }
    if (_paymentType != 'CASH' && _vendorId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a vendor for credit sales')));
      return;
    }
    final paid = _paymentType == 'CASH' ? _total : (double.tryParse(_paidCtrl.text) ?? 0);

    await _db.createSale(
      items: _cart
          .map((l) => {
                'product_id': l.product['id'],
                'product_name': l.product['name'],
                'quantity': l.quantity,
                'unit_price': l.product['selling_price'],
              })
          .toList(),
      discount: _discount,
      paymentType: _paymentType,
      vendorId: _vendorId,
      paidAmount: paid,
    );

    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Sale')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _pickerProductId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Product'),
                    items: _products
                        .map((p) => DropdownMenuItem(
                              value: p['id'] as int,
                              child: Text(
                                '${p['name']} — ${formatCurrency(p['selling_price'])}/${p['unit']}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _pickerProductId = v),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: FilledButton(
                    onPressed: _pickerProductId == null
                        ? null
                        : () => _addProduct(_products.firstWhere((p) => p['id'] == _pickerProductId)),
                    child: const Text('Add'),
                  ),
                ),
              ],
            ),
          ),
          if (_pickerProductId != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Builder(builder: (context) {
                final p = _products.firstWhere((p) => p['id'] == _pickerProductId,
                    orElse: () => <String, dynamic>{});
                if (p.isEmpty) return const SizedBox.shrink();
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'In stock: ${p['quantity']} ${p['unit']}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                );
              }),
            ),
          const Divider(height: 16),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Cart (${_cart.length})', style: Theme.of(context).textTheme.titleMedium),
                  Expanded(
                    child: _cart.isEmpty
                        ? const Center(child: Text('Tap products above to add them'))
                        : ListView.builder(
                            itemCount: _cart.length,
                            itemBuilder: (_, i) {
                              final line = _cart[i];
                              return ListTile(
                                dense: true,
                                title: Text(line.product['name'] as String),
                                subtitle: Text(formatCurrency(line.product['selling_price'])),
                                leading: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove),
                                      onPressed: () => setState(() {
                                        final step = _stepFor(line.product['unit'] as String? ?? 'pcs');
                                        line.quantity =
                                            double.parse((line.quantity - step).toStringAsFixed(2));
                                        if (line.quantity <= 0) _cart.removeAt(i);
                                      }),
                                    ),
                                    GestureDetector(
                                      onTap: () => _editQuantity(line),
                                      child: Text(
                                        '${_formatQty(line.quantity, line.product['unit'] as String? ?? 'pcs')} ${line.product['unit']}',
                                        style: const TextStyle(
                                          decoration: TextDecoration.underline,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.add),
                                      onPressed: () => setState(() {
                                        final step = _stepFor(line.product['unit'] as String? ?? 'pcs');
                                        line.quantity =
                                            double.parse((line.quantity + step).toStringAsFixed(2));
                                      }),
                                    ),
                                  ],
                                ),
                                trailing: Text(formatCurrency(line.quantity * line.product['selling_price'])),
                              );
                            },
                          ),
                  ),
                  const Divider(),
                  Row(
                    children: [
                      const Text('Discount:'),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _discountCtrl,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(isDense: true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Total: ${formatCurrency(_total)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'CASH', label: Text('Cash')),
                      ButtonSegment(value: 'CREDIT', label: Text('Full Credit')),
                      ButtonSegment(value: 'PARTIAL', label: Text('Partial')),
                    ],
                    selected: {_paymentType},
                    onSelectionChanged: (s) => setState(() => _paymentType = s.first),
                  ),
                  if (_paymentType != 'CASH') ...[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      value: _vendorId,
                      decoration: const InputDecoration(labelText: 'Vendor (credit customer)'),
                      items: _vendors
                          .map((v) => DropdownMenuItem(value: v['id'] as int, child: Text(v['name'] as String)))
                          .toList(),
                      onChanged: (v) => setState(() => _vendorId = v),
                    ),
                  ],
                  if (_paymentType == 'PARTIAL') ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _paidCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(labelText: 'Amount collected now'),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Outstanding after this sale: ${formatCurrency((_total - (double.tryParse(_paidCtrl.text) ?? 0)).clamp(0, double.infinity))}',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _checkout, child: const Text('Complete Sale')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
