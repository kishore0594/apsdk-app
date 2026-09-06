import 'package:flutter/material.dart';
import '../db/db_helper.dart';
import '../utils/formatters.dart';

class VendorsScreen extends StatefulWidget {
  const VendorsScreen({super.key});

  @override
  State<VendorsScreen> createState() => _VendorsScreenState();
}

class _VendorsScreenState extends State<VendorsScreen> {
  final _db = DBHelper.instance;
  List<Map<String, dynamic>> _vendors = [];
  Map<int, double> _balances = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final vendors = await _db.getVendors();
    final balances = <int, double>{};
    for (final v in vendors) {
      balances[v['id'] as int] = await _db.getVendorBalance(v['id'] as int);
    }
    setState(() {
      _vendors = vendors;
      _balances = balances;
    });
  }

  String _vendorSubtitle(Map<String, dynamic> v) {
    final phone = v['phone'] as String? ?? '';
    final place = v['address'] as String? ?? '';
    if (phone.isEmpty && place.isEmpty) return '';
    if (place.isEmpty) return phone;
    if (phone.isEmpty) return 'Place: $place';
    return '$phone • $place';
  }

  Future<void> _addVendor() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final openingCtrl = TextEditingController(text: '0');

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Vendor (Credit Customer)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
            TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Phone')),
            TextField(controller: addressCtrl, decoration: const InputDecoration(labelText: 'Place')),
            TextField(
              controller: openingCtrl,
              decoration: const InputDecoration(labelText: 'Opening balance owed'),
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
      await _db.insertVendor({
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
    final totalOutstanding = _balances.values.fold<double>(0, (sum, b) => sum + b);
    return Scaffold(
      appBar: AppBar(title: const Text('Vendor Credit')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Text('Total Outstanding: ${formatCurrency(totalOutstanding)}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: _vendors.isEmpty
                ? const Center(child: Text('No vendors yet. Tap + to add one.'))
                : ListView.builder(
                    itemCount: _vendors.length,
                    itemBuilder: (_, i) {
                      final v = _vendors[i];
                      final balance = _balances[v['id']] ?? 0;
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: ListTile(
                          leading: CircleAvatar(child: Text((v['name'] as String)[0].toUpperCase())),
                          title: Text(v['name'] as String),
                          subtitle: Text(_vendorSubtitle(v)),
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
                              MaterialPageRoute(builder: (_) => VendorDetailScreen(vendor: v)),
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
      floatingActionButton: FloatingActionButton(onPressed: _addVendor, child: const Icon(Icons.person_add)),
    );
  }
}

class VendorDetailScreen extends StatefulWidget {
  final Map<String, dynamic> vendor;
  const VendorDetailScreen({super.key, required this.vendor});

  @override
  State<VendorDetailScreen> createState() => _VendorDetailScreenState();
}

class _VendorDetailScreenState extends State<VendorDetailScreen> {
  final _db = DBHelper.instance;
  List<Map<String, dynamic>> _transactions = [];
  double _balance = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final txns = await _db.getVendorTransactions(widget.vendor['id'] as int);
    final balance = await _db.getVendorBalance(widget.vendor['id'] as int);
    setState(() {
      _transactions = txns;
      _balance = balance;
    });
  }

  Future<void> _recordTransaction(String type) async {
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(type == 'CREDIT' ? 'Record Credit Given' : 'Record Payment Collected'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Amount'),
              autofocus: true,
            ),
            TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notes (optional)')),
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
      await _db.addCreditTransaction(
        vendorId: widget.vendor['id'] as int,
        type: type,
        amount: amount,
        notes: notesCtrl.text.trim(),
      );
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.vendor['name'] as String)),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: _balance > 0 ? Colors.red.shade50 : Colors.green.shade50,
            child: Column(
              children: [
                if ((widget.vendor['address'] as String?)?.isNotEmpty == true ||
                    (widget.vendor['phone'] as String?)?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      [
                        if ((widget.vendor['phone'] as String?)?.isNotEmpty == true) widget.vendor['phone'],
                        if ((widget.vendor['address'] as String?)?.isNotEmpty == true)
                          'Place: ${widget.vendor['address']}',
                      ].join('  •  '),
                      style: const TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                  ),
                const Text('Current Balance'),
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
                    onPressed: () => _recordTransaction('CREDIT'),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Credit'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _recordTransaction('PAYMENT'),
                    icon: const Icon(Icons.payments),
                    label: const Text('Collect Payment'),
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
                    itemBuilder: (_, i) => _TransactionTile(txn: _transactions[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final Map<String, dynamic> txn;
  const _TransactionTile({required this.txn});

  @override
  Widget build(BuildContext context) {
    final isCredit = txn['type'] == 'CREDIT';
    final saleId = txn['sale_id'] as int?;

    final leadingIcon = Icon(
      isCredit ? Icons.arrow_upward : Icons.arrow_downward,
      color: isCredit ? Colors.red : Colors.green,
    );
    final titleText =
        Text('${isCredit ? 'Credit given' : 'Payment received'}: ${formatCurrency(txn['amount'])}');
    final balanceText =
        Text('Bal: ${formatCurrency(txn['balance_after'])}', style: const TextStyle(fontSize: 12));

    if (saleId == null) {
      return ListTile(
        leading: leadingIcon,
        title: titleText,
        subtitle: Text(
            '${formatDate(txn['date'] as String)}${(txn['notes'] as String?)?.isNotEmpty == true ? '\n${txn['notes']}' : ''}'),
        isThreeLine: (txn['notes'] as String?)?.isNotEmpty == true,
        trailing: balanceText,
      );
    }

    // Credit that came from a sale — show which products were purchased.
    return ExpansionTile(
      title: titleText,
      subtitle: Text(
          '${formatDate(txn['date'] as String)} • tap to view items purchased'),
      leading: leadingIcon,
      trailing: balanceText,
      children: [
        FutureBuilder<List<Map<String, dynamic>>>(
          future: DBHelper.instance.getSaleItems(saleId),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: LinearProgressIndicator(),
              );
            }
            final items = snapshot.data!;
            if (items.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No item details recorded for this sale.'),
              );
            }
            return Column(
              children: items
                  .map((it) => ListTile(
                        dense: true,
                        title: Text(it['product_name'] as String),
                        subtitle: Text('${it['quantity']} × ${formatCurrency(it['unit_price'])}'),
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
