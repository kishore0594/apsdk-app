import 'package:flutter/material.dart';
import '../db/db_helper.dart';
import '../utils/formatters.dart';

class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key});

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  final _db = DBHelper.instance;
  List<Map<String, dynamic>> _suppliers = [];
  Map<int, double> _balances = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final suppliers = await _db.getSuppliers();
    final balances = <int, double>{};
    for (final s in suppliers) {
      balances[s['id'] as int] = await _db.getSupplierBalance(s['id'] as int);
    }
    setState(() {
      _suppliers = suppliers;
      _balances = balances;
    });
  }

  Future<void> _addSupplier() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final openingCtrl = TextEditingController(text: '0');

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Supplier'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
            TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Phone')),
            TextField(controller: addressCtrl, decoration: const InputDecoration(labelText: 'Address')),
            TextField(
              controller: openingCtrl,
              decoration: const InputDecoration(labelText: 'Opening balance owed to them'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );

    if (saved == true && nameCtrl.text.trim().isNotEmpty) {
      await _db.insertSupplier({
        'name': nameCtrl.text.trim(),
        'phone': phoneCtrl.text.trim(),
        'address': addressCtrl.text.trim(),
        'opening_balance': double.tryParse(openingCtrl.text) ?? 0,
        'created_at': DateTime.now().toIso8601String(),
      });
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalOwed = _balances.values.fold<double>(0, (sum, b) => sum + b);
    return Scaffold(
      appBar: AppBar(title: const Text('Suppliers')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Text('Total Owed to Suppliers: ${formatCurrency(totalOwed)}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: _suppliers.isEmpty
                ? const Center(child: Text('No suppliers yet. Tap + to add one.'))
                : ListView.builder(
                    itemCount: _suppliers.length,
                    itemBuilder: (_, i) {
                      final s = _suppliers[i];
                      final balance = _balances[s['id']] ?? 0;
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: ListTile(
                          leading: CircleAvatar(child: Text((s['name'] as String)[0].toUpperCase())),
                          title: Text(s['name'] as String),
                          subtitle: Text(s['phone'] as String? ?? ''),
                          trailing: Text(
                            formatCurrency(balance),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: balance > 0 ? Colors.red : Colors.green,
                            ),
                          ),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => SupplierDetailScreen(supplier: s)),
                            );
                            _load();
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(onPressed: _addSupplier, child: const Icon(Icons.add_business)),
    );
  }
}

class SupplierDetailScreen extends StatefulWidget {
  final Map<String, dynamic> supplier;
  const SupplierDetailScreen({super.key, required this.supplier});

  @override
  State<SupplierDetailScreen> createState() => _SupplierDetailScreenState();
}

class _SupplierDetailScreenState extends State<SupplierDetailScreen> {
  final _db = DBHelper.instance;
  List<Map<String, dynamic>> _transactions = [];
  double _balance = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final txns = await _db.getSupplierTransactions(widget.supplier['id'] as int);
    final balance = await _db.getSupplierBalance(widget.supplier['id'] as int);
    setState(() {
      _transactions = txns;
      _balance = balance;
    });
  }

  Future<void> _recordPayment() async {
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Record Payment Made'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount'),
              autofocus: true,
            ),
            TextField(
              controller: notesCtrl,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );

    final amount = double.tryParse(amountCtrl.text) ?? 0;
    if (saved == true && amount > 0) {
      await _db.addSupplierTransaction(
        supplierId: widget.supplier['id'] as int,
        type: 'PAYMENT',
        amount: amount,
        notes: notesCtrl.text.trim(),
      );
      _load();
    }
  }

  Future<void> _openNewPurchase() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NewPurchaseSheet(supplierId: widget.supplier['id'] as int),
    );
    if (result == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.supplier['name'] as String)),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: _balance > 0 ? Colors.red.shade50 : Colors.green.shade50,
            child: Column(
              children: [
                const Text('Amount Owed to Supplier'),
                Text(
                  formatCurrency(_balance),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: _balance > 0 ? Colors.red : Colors.green,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openNewPurchase,
                    icon: const Icon(Icons.local_shipping),
                    label: const Text('New Purchase'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _recordPayment,
                    icon: const Icon(Icons.payments),
                    label: const Text('Pay Supplier'),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Transaction History', style: Theme.of(context).textTheme.titleMedium),
            ),
          ),
          Expanded(
            child: _transactions.isEmpty
                ? const Center(child: Text('No transactions yet.'))
                : ListView.builder(
                    itemCount: _transactions.length,
                    itemBuilder: (_, i) => _SupplierTxnTile(txn: _transactions[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SupplierTxnTile extends StatelessWidget {
  final Map<String, dynamic> txn;
  const _SupplierTxnTile({required this.txn});

  @override
  Widget build(BuildContext context) {
    final isPurchase = txn['type'] == 'PURCHASE';
    final txnId = txn['id'] as int;

    final leadingIcon = Icon(
      isPurchase ? Icons.arrow_upward : Icons.arrow_downward,
      color: isPurchase ? Colors.red : Colors.green,
    );
    final titleText = Text('${isPurchase ? 'Purchase' : 'Payment made'}: ${formatCurrency(txn['amount'])}');
    final balanceText =
        Text('Bal: ${formatCurrency(txn['balance_after'])}', style: const TextStyle(fontSize: 12));

    if (!isPurchase) {
      return ListTile(
        leading: leadingIcon,
        title: titleText,
        subtitle: Text(
            '${formatDate(txn['date'] as String)}${(txn['notes'] as String?)?.isNotEmpty == true ? '\n${txn['notes']}' : ''}'),
        isThreeLine: (txn['notes'] as String?)?.isNotEmpty == true,
        trailing: balanceText,
      );
    }

    // Purchases show which products were received, at what cost.
    return ExpansionTile(
      leading: leadingIcon,
      title: titleText,
      subtitle: Text('${formatDate(txn['date'] as String)} • tap to view products'),
      trailing: balanceText,
      children: [
        FutureBuilder<List<Map<String, dynamic>>>(
          future: DBHelper.instance.getSupplierPurchaseItems(txnId),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator());
            }
            final items = snapshot.data!;
            if (items.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No product details recorded for this purchase.'),
              );
            }
            return Column(
              children: items
                  .map((it) => ListTile(
                        dense: true,
                        title: Text(it['product_name'] as String),
                        subtitle: Text('${it['quantity']} × ${formatCurrency(it['unit_cost'])}'),
                        trailing: Text(formatCurrency(it['subtotal'])),
                      ))
                  .toList(),
            );
          },
        ),
      ],
    );
  }
}

class _NewPurchaseSheet extends StatefulWidget {
  final int supplierId;
  const _NewPurchaseSheet({required this.supplierId});

  @override
  State<_NewPurchaseSheet> createState() => _NewPurchaseSheetState();
}

class _PurchaseLine {
  final Map<String, dynamic> product;
  double quantity;
  double unitCost;
  _PurchaseLine(this.product, this.quantity, this.unitCost);
}

class _NewPurchaseSheetState extends State<_NewPurchaseSheet> {
  final _db = DBHelper.instance;
  List<Map<String, dynamic>> _products = [];
  final List<_PurchaseLine> _lines = [];
  final _notesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    final products = await _db.getProducts();
    setState(() => _products = products);
  }

  double get _total => _lines.fold(0, (sum, l) => sum + l.quantity * l.unitCost);

  void _addProduct(Map<String, dynamic> product) {
    final existing = _lines.where((l) => l.product['id'] == product['id']);
    if (existing.isNotEmpty) {
      setState(() => existing.first.quantity += 1);
    } else {
      setState(() => _lines.add(
          _PurchaseLine(product, 1, (product['cost_price'] as num?)?.toDouble() ?? 0)));
    }
  }

  Future<void> _save() async {
    if (_lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add at least one product')));
      return;
    }
    await _db.addSupplierPurchase(
      supplierId: widget.supplierId,
      items: _lines
          .map((l) => {
                'product_id': l.product['id'],
                'product_name': l.product['name'],
                'quantity': l.quantity,
                'unit_cost': l.unitCost,
              })
          .toList(),
      notes: _notesCtrl.text.trim(),
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('New Purchase', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              const Text('Tap a product to add it, then set quantity and cost per unit.',
                  style: TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    ..._products.map((p) => ListTile(
                          dense: true,
                          title: Text(p['name'] as String),
                          subtitle: Text('${p['unit']} • current stock ${p['quantity']}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.add_circle),
                            onPressed: () => _addProduct(p),
                          ),
                        )),
                    const Divider(),
                    Text('Purchase items (${_lines.length})',
                        style: Theme.of(context).textTheme.titleSmall),
                    if (_lines.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('No products added yet.'),
                      )
                    else
                      ..._lines.map((l) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Expanded(flex: 3, child: Text(l.product['name'] as String)),
                                Expanded(
                                  flex: 2,
                                  child: TextFormField(
                                    key: ValueKey('qty-${l.product['id']}'),
                                    initialValue: l.quantity.toString(),
                                    decoration: InputDecoration(labelText: 'Qty (${l.product['unit']})', isDense: true),
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    onChanged: (v) => setState(() => l.quantity = double.tryParse(v) ?? l.quantity),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 2,
                                  child: TextFormField(
                                    key: ValueKey('cost-${l.product['id']}'),
                                    initialValue: l.unitCost.toString(),
                                    decoration: const InputDecoration(labelText: 'Cost/unit', isDense: true),
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    onChanged: (v) => setState(() => l.unitCost = double.tryParse(v) ?? l.unitCost),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  onPressed: () => setState(() => _lines.remove(l)),
                                ),
                              ],
                            ),
                          )),
                  ],
                ),
              ),
              const Divider(),
              TextField(
                controller: _notesCtrl,
                decoration: const InputDecoration(labelText: 'Notes (invoice no. etc.)'),
              ),
              const SizedBox(height: 8),
              Text('Total: ${formatCurrency(_total)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              FilledButton(onPressed: _save, child: const Text('Save Purchase')),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
