import 'package:flutter/material.dart';
import '../db/db_helper.dart';
import '../utils/formatters.dart';
import '../utils/app_strings.dart';
import '../utils/app_theme.dart';

class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key});

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  final _db = DBHelper.instance;
  // Same double-submission guard as the Vendors quick-payment button.
  final Set<String> _busySupplierIds = {};

  Future<void> _quickPaySupplier(String supplierId, String supplierName) async {
    if (_busySupplierIds.contains(supplierId)) return;
    final amountCtrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${AppStrings.t('pay_supplier')} — $supplierName'),
        content: TextField(
          controller: amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: AppStrings.t('amount')),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(AppStrings.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(AppStrings.t('save'))),
        ],
      ),
    );
    final amount = double.tryParse(amountCtrl.text) ?? 0;
    if (saved != true || amount <= 0) return;
    setState(() => _busySupplierIds.add(supplierId));
    try {
      await _db
          .addSupplierTransaction(supplierId: supplierId, type: 'PAYMENT', amount: amount)
          .timeout(const Duration(seconds: 25));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("${AppStrings.t('could_not_save')}: $e")));
      }
    } finally {
      if (mounted) setState(() => _busySupplierIds.remove(supplierId));
    }
  }

  Future<void> _addSupplier() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final openingCtrl = TextEditingController(text: '0');

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppStrings.t('add_supplier')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: InputDecoration(labelText: AppStrings.t('name'))),
            TextField(controller: phoneCtrl, decoration: InputDecoration(labelText: AppStrings.t('phone'))),
            TextField(controller: addressCtrl, decoration: InputDecoration(labelText: AppStrings.t('address'))),
            TextField(
              controller: openingCtrl,
              decoration: InputDecoration(labelText: AppStrings.t('opening_balance_owed_them')),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(AppStrings.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(AppStrings.t('save'))),
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
      // Live stream below updates on its own — no manual refresh needed.
    }
  }

  Future<void> _editSupplier(Map<String, dynamic> supplier) async {
    final nameCtrl = TextEditingController(text: supplier['name'] as String? ?? '');
    final phoneCtrl = TextEditingController(text: supplier['phone'] as String? ?? '');
    final addressCtrl = TextEditingController(text: supplier['address'] as String? ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppStrings.t('edit_supplier')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: InputDecoration(labelText: AppStrings.t('name'))),
            TextField(controller: phoneCtrl, decoration: InputDecoration(labelText: AppStrings.t('phone'))),
            TextField(controller: addressCtrl, decoration: InputDecoration(labelText: AppStrings.t('address'))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(AppStrings.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(AppStrings.t('save'))),
        ],
      ),
    );
    if (saved != true || nameCtrl.text.trim().isEmpty) return;
    try {
      await _db.updateSupplier(
        supplier['id'] as String,
        name: nameCtrl.text.trim(),
        phone: phoneCtrl.text.trim(),
        address: addressCtrl.text.trim(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${AppStrings.t('could_not_save')}: $e")));
      }
    }
  }

  Future<void> _deleteSupplier(Map<String, dynamic> supplier) async {
    final balance = (supplier['balance'] as num?)?.toDouble() ?? 0;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("${AppStrings.t('delete')} ${supplier['name']}?"),
        content: Text(
          balance > 0
              ? 'You still owe this supplier ${formatCurrency(balance)}. Deleting them removes '
                  'the supplier from your list — their past transaction records stay in your data '
                  'exports, but the balance itself won\'t be tracked anywhere once they\'re gone. '
                  'This can\'t be undone.'
              : 'This can\'t be undone. Their past transaction records stay in your data exports.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(AppStrings.t('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppStrings.t('delete')),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _db.deleteSupplier(supplier['id'] as String);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${AppStrings.t('could_not_delete')}: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.t('suppliers_title'))),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _db.watchSuppliers(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text("${AppStrings.t('could_not_load_suppliers')}: ${snapshot.error}"));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final suppliers = snapshot.data!;
          final totalOwed = suppliers.fold<double>(
              0, (sum, s) => sum + ((s['balance'] as num?)?.toDouble() ?? 0));
          final owingCount =
              suppliers.where((s) => ((s['balance'] as num?)?.toDouble() ?? 0) > 0).length;

          return Column(
            children: [
              SummaryBanner(
                icon: Icons.local_shipping_outlined,
                label: AppStrings.t('total_owed_suppliers'),
                value: formatCurrency(totalOwed),
                color: totalOwed > 0 ? AppTheme.cost : AppTheme.success,
                caption: '$owingCount of ${suppliers.length}',
              ),
              Expanded(
                child: suppliers.isEmpty
                    ? EmptyState(
                        icon: Icons.local_shipping_outlined,
                        title: AppStrings.t('no_suppliers_tap_add'),
                        action: FilledButton.icon(
                          onPressed: _addSupplier,
                          icon: const Icon(Icons.add_business, size: 18),
                          label: Text(AppStrings.t('add_supplier')),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 90),
                        itemCount: suppliers.length,
                        itemBuilder: (_, i) {
                          final s = suppliers[i];
                          final balance = (s['balance'] as num?)?.toDouble() ?? 0;
                          final owes = balance > 0;
                          final busy = _busySupplierIds.contains(s['id']);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: AppCard(
                              padding: const EdgeInsets.all(14),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => SupplierDetailScreen(supplier: s)),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 21,
                                        backgroundColor:
                                            (owes ? AppTheme.cost : AppTheme.success).withOpacity(0.12),
                                        child: Text(
                                          (s['name'] as String)[0].toUpperCase(),
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 17,
                                            color: owes ? AppTheme.cost : AppTheme.success,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 13),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(s['name'] as String,
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.w600, fontSize: 15)),
                                            if ((s['phone'] as String?)?.isNotEmpty == true)
                                              Padding(
                                                padding: const EdgeInsets.only(top: 2),
                                                child: Text(s['phone'] as String,
                                                    style: TextStyle(
                                                        fontSize: 12, color: Colors.grey.shade600)),
                                              ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(formatCurrency(balance),
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                                color: owes ? AppTheme.cost : AppTheme.success,
                                              )),
                                        ],
                                      ),
                                      PopupMenuButton<String>(
                                        icon: Icon(Icons.more_vert, color: Colors.grey.shade500, size: 20),
                                        padding: EdgeInsets.zero,
                                        onSelected: (choice) {
                                          if (choice == 'edit') {
                                            _editSupplier(s);
                                          } else if (choice == 'delete') {
                                            _deleteSupplier(s);
                                          }
                                        },
                                        itemBuilder: (_) => [
                                          PopupMenuItem(
                                            value: 'edit',
                                            child: ListTile(
                                              leading: const Icon(Icons.edit_outlined),
                                              title: Text(AppStrings.t('edit')),
                                              contentPadding: EdgeInsets.zero,
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: ListTile(
                                              leading: const Icon(Icons.delete_outline, color: AppTheme.danger),
                                              title: Text(AppStrings.t('delete'),
                                                  style: const TextStyle(color: AppTheme.danger)),
                                              contentPadding: EdgeInsets.zero,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  if (owes) ...[
                                    const Divider(height: 22),
                                    SizedBox(
                                      width: double.infinity,
                                      child: FilledButton.icon(
                                        onPressed: busy
                                            ? null
                                            : () => _quickPaySupplier(s['id'] as String, s['name'] as String),
                                        icon: busy
                                            ? const SizedBox(
                                                height: 14,
                                                width: 14,
                                                child: CircularProgressIndicator(
                                                    strokeWidth: 2, color: Colors.white))
                                            : const Icon(Icons.payments_outlined, size: 16),
                                        label: Text(AppStrings.t('pay_supplier')),
                                        style: FilledButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
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
  bool _saving = false;

  Future<void> _recordPayment() async {
    if (_saving) return;
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppStrings.t('record_payment_made')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: AppStrings.t('amount')),
              autofocus: true,
            ),
            TextField(
              controller: notesCtrl,
              decoration: InputDecoration(labelText: AppStrings.t('notes_optional')),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(AppStrings.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(AppStrings.t('save'))),
        ],
      ),
    );

    final amount = double.tryParse(amountCtrl.text) ?? 0;
    if (saved == true && amount > 0) {
      setState(() => _saving = true);
      try {
        await _db
            .addSupplierTransaction(
              supplierId: widget.supplier['id'] as String,
              type: 'PAYMENT',
              amount: amount,
              notes: notesCtrl.text.trim(),
            )
            .timeout(const Duration(seconds: 25));
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text("${AppStrings.t('could_not_save')}: $e")));
        }
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    }
  }

  Future<void> _openNewPurchase() async {
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NewPurchaseSheet(supplierId: widget.supplier['id'] as String),
    );
  }

  @override
  Widget build(BuildContext context) {
    final supplierId = widget.supplier['id'] as String;
    return Scaffold(
      appBar: AppBar(title: Text(widget.supplier['name'] as String)),
      body: StreamBuilder<Map<String, dynamic>?>(
        stream: _db.watchSupplier(supplierId),
        builder: (context, supplierSnap) {
          final supplier = supplierSnap.data ?? widget.supplier;
          final balance = (supplier['balance'] as num?)?.toDouble() ?? 0;

          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                color: balance > 0 ? Colors.red.shade50 : Colors.green.shade50,
                child: Column(
                  children: [
                    Text(AppStrings.t('amount_owed_supplier')),
                    Text(
                      formatCurrency(balance),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: balance > 0 ? Colors.red : Colors.green,
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
                        label: Text(AppStrings.t('new_purchase')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _recordPayment,
                        icon: _saving
                            ? const SizedBox(
                                height: 14,
                                width: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.payments),
                        label: Text(AppStrings.t('pay_supplier')),
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
                  child: Text(AppStrings.t('transaction_history'), style: Theme.of(context).textTheme.titleMedium),
                ),
              ),
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _db.watchSupplierTransactions(supplierId),
                  builder: (context, txnSnap) {
                    if (txnSnap.hasError) {
                      return Center(child: Text("${AppStrings.t('could_not_load_history')}: ${txnSnap.error}"));
                    }
                    if (!txnSnap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final transactions = txnSnap.data!;
                    if (transactions.isEmpty) {
                      return Center(child: Text(AppStrings.t('no_transactions_yet')));
                    }
                    return ListView.builder(
                      itemCount: transactions.length,
                      itemBuilder: (_, i) => _SupplierTxnTile(txn: transactions[i]),
                    );
                  },
                ),
              ),
            ],
          );
        },
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
    final txnId = txn['id'] as String;

    final leadingIcon = Icon(
      isPurchase ? Icons.arrow_upward : Icons.arrow_downward,
      color: isPurchase ? Colors.red : Colors.green,
    );
    final titleText = Text("${isPurchase ? AppStrings.t('purchase') : AppStrings.t('payment_made')}: ${formatCurrency(txn['amount'])}");
    final balanceText =
        Text("${AppStrings.t('balance_abbr')}: ${formatCurrency(txn['balance_after'])}", style: const TextStyle(fontSize: 12));

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
      subtitle: Text("${formatDate(txn['date'] as String)} • ${AppStrings.t('tap_view_products')}"),
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
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text(AppStrings.t('no_product_details_purchase')),
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
  final String supplierId;
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
  bool _saving = false;

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
    if (_saving) return;
    if (_lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppStrings.t('add_at_least_one_product'))));
      return;
    }
    setState(() => _saving = true);
    try {
      await _db
          .addSupplierPurchase(
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
          )
          .timeout(const Duration(seconds: 25));
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("${AppStrings.t('could_not_save')}: $e")));
      }
      return;
    }
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
              Text(AppStrings.t('new_purchase'), style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              Text(AppStrings.t('tap_product_add_qty'),
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
                    Text('${AppStrings.t('purchase_items')} (${_lines.length})',
                        style: Theme.of(context).textTheme.titleSmall),
                    if (_lines.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(AppStrings.t('no_products_added_yet')),
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
                                    decoration: InputDecoration(labelText: "${AppStrings.t('qty')} (${l.product['unit']})", isDense: true),
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
                                    decoration: InputDecoration(labelText: AppStrings.t('cost_per_unit'), isDense: true),
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
                decoration: InputDecoration(labelText: AppStrings.t('notes_invoice')),
              ),
              const SizedBox(height: 8),
              Text('${AppStrings.t('total')}: ${formatCurrency(_total)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(AppStrings.t('save_purchase')),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppStrings.t('cancel')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
