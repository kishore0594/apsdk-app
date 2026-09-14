import 'package:flutter/material.dart';
import '../db/db_helper.dart';
import '../utils/formatters.dart';
import '../utils/app_theme.dart';
import 'vendor_insights_screen.dart';

class VendorsScreen extends StatefulWidget {
  const VendorsScreen({super.key});

  @override
  State<VendorsScreen> createState() => _VendorsScreenState();
}

class _VendorsScreenState extends State<VendorsScreen> {
  final _db = DBHelper.instance;

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
    DateTime creditDate = DateTime.now();

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Vendor (Credit Customer)'),
          content: SingleChildScrollView(
            child: Column(
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
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Credit given on', style: TextStyle(fontSize: 13)),
                  subtitle: Text(formatDay(creditDate.toIso8601String())),
                  trailing: const Icon(Icons.calendar_today, size: 18),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: creditDate,
                      firstDate: DateTime(2015),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setDialogState(() => creditDate = picked);
                  },
                ),
                const Text(
                  'Only matters if there\'s an opening balance — sets when that old credit '
                  'actually started, so day-tracking is accurate from the start.',
                  style: TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );

    if (saved == true && nameCtrl.text.trim().isNotEmpty) {
      final newVendorId = await _db.insertVendor({
        'name': nameCtrl.text.trim(),
        'phone': phoneCtrl.text.trim(),
        'address': addressCtrl.text.trim(),
        'opening_balance': 0,
        'created_at': DateTime.now().toIso8601String(),
      });
      final openingAmount = double.tryParse(openingCtrl.text) ?? 0;
      if (openingAmount > 0) {
        await _db.addCreditTransaction(
          vendorId: newVendorId,
          type: 'CREDIT',
          amount: openingAmount,
          notes: 'Opening balance',
          date: creditDate.toIso8601String(),
        );
      }
      // No manual refresh needed — the list below is a live stream, so it
      // (and the phone this vendor was added on, even if it was offline a
      // moment ago) updates on its own the instant this write lands.
    }
  }

  Future<void> _quickCollectPayment(String vendorId, String vendorName) async {
    final amountCtrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Collect Payment — $vendorName'),
        content: TextField(
          controller: amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Amount'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    final amount = double.tryParse(amountCtrl.text) ?? 0;
    if (saved != true || amount <= 0) return;
    try {
      await _db.addCreditTransaction(vendorId: vendorId, type: 'PAYMENT', amount: amount);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not record payment: $e')));
      }
    }
  }

  Future<void> _editVendor(Map<String, dynamic> vendor) async {
    final nameCtrl = TextEditingController(text: vendor['name'] as String? ?? '');
    final phoneCtrl = TextEditingController(text: vendor['phone'] as String? ?? '');
    final addressCtrl = TextEditingController(text: vendor['address'] as String? ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit Vendor'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
            TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Phone')),
            TextField(controller: addressCtrl, decoration: const InputDecoration(labelText: 'Place')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved != true || nameCtrl.text.trim().isEmpty) return;
    try {
      await _db.updateVendor(
        vendor['id'] as String,
        name: nameCtrl.text.trim(),
        phone: phoneCtrl.text.trim(),
        address: addressCtrl.text.trim(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    }
  }

  Future<void> _deleteVendor(Map<String, dynamic> vendor) async {
    final balance = (vendor['balance'] as num?)?.toDouble() ?? 0;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete ${vendor['name']}?'),
        content: Text(
          balance > 0
              ? 'This vendor still has an outstanding balance of ${formatCurrency(balance)}. '
                  'Deleting them removes the vendor from your list — their past transaction records '
                  'stay in your data exports, but the balance itself won\'t be tracked anywhere '
                  'once they\'re gone. This can\'t be undone.'
              : 'This can\'t be undone. Their past transaction records stay in your data exports.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _db.deleteVendor(vendor['id'] as String);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not delete: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vendor Credit'),
        actions: [
          IconButton(
            tooltip: 'Vendor Insights',
            icon: const Icon(Icons.insights_outlined),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const VendorInsightsScreen())),
          ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _db.watchVendors(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(message: 'Could not load vendors.\n${snapshot.error}');
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final vendors = snapshot.data!;
          final totalOutstanding = vendors.fold<double>(
              0, (sum, v) => sum + ((v['balance'] as num?)?.toDouble() ?? 0));
          final owingCount = vendors.where((v) => ((v['balance'] as num?)?.toDouble() ?? 0) > 0).length;

          return Column(
            children: [
              SummaryBanner(
                icon: Icons.account_balance_wallet_outlined,
                label: 'Total Outstanding',
                value: formatCurrency(totalOutstanding),
                color: totalOutstanding > 0 ? AppTheme.danger : AppTheme.success,
                caption: '$owingCount of ${vendors.length} vendors owe money',
              ),
              Expanded(
                child: vendors.isEmpty
                    ? EmptyState(
                        icon: Icons.people_outline,
                        title: 'No credit customers yet',
                        message: 'Add a vendor to start tracking what they owe.',
                        action: FilledButton.icon(
                          onPressed: _addVendor,
                          icon: const Icon(Icons.person_add, size: 18),
                          label: const Text('Add Vendor'),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 90),
                        itemCount: vendors.length,
                        itemBuilder: (_, i) {
                          final v = vendors[i];
                          final balance = (v['balance'] as num?)?.toDouble() ?? 0;
                          final owes = balance > 0;
                          final subtitle = _vendorSubtitle(v);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: AppCard(
                              padding: const EdgeInsets.all(14),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => VendorDetailScreen(vendor: v)),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 21,
                                        backgroundColor:
                                            (owes ? AppTheme.danger : AppTheme.success).withOpacity(0.12),
                                        child: Text(
                                          (v['name'] as String)[0].toUpperCase(),
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 17,
                                            color: owes ? AppTheme.danger : AppTheme.success,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 13),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(v['name'] as String,
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.w600, fontSize: 15)),
                                            if (subtitle.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(top: 2),
                                                child: Text(subtitle,
                                                    style: TextStyle(
                                                        fontSize: 12, color: Colors.grey.shade600),
                                                    overflow: TextOverflow.ellipsis),
                                              ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text('Outstanding',
                                              style: TextStyle(
                                                  fontSize: 10.5, color: Colors.grey.shade600)),
                                          const SizedBox(height: 1),
                                          Text(
                                            formatCurrency(balance),
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                              color: owes ? AppTheme.danger : AppTheme.success,
                                            ),
                                          ),
                                        ],
                                      ),
                                      PopupMenuButton<String>(
                                        icon: Icon(Icons.more_vert, color: Colors.grey.shade500, size: 20),
                                        padding: EdgeInsets.zero,
                                        onSelected: (choice) {
                                          if (choice == 'edit') {
                                            _editVendor(v);
                                          } else if (choice == 'delete') {
                                            _deleteVendor(v);
                                          }
                                        },
                                        itemBuilder: (_) => const [
                                          PopupMenuItem(
                                            value: 'edit',
                                            child: ListTile(
                                              leading: Icon(Icons.edit_outlined),
                                              title: Text('Edit'),
                                              contentPadding: EdgeInsets.zero,
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: ListTile(
                                              leading: Icon(Icons.delete_outline, color: AppTheme.danger),
                                              title: Text('Delete', style: TextStyle(color: AppTheme.danger)),
                                              contentPadding: EdgeInsets.zero,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  if (owes) ...[
                                    const Divider(height: 22),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () => Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                  builder: (_) => VendorDetailScreen(vendor: v)),
                                            ),
                                            icon: const Icon(Icons.menu_book_outlined, size: 16),
                                            label: const Text('Ledger'),
                                            style: OutlinedButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(vertical: 10),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: FilledButton.icon(
                                            onPressed: () => _quickCollectPayment(
                                                v['id'] as String, v['name'] as String),
                                            icon: const Icon(Icons.payments_outlined, size: 16),
                                            label: const Text('Payment'),
                                            style: FilledButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(vertical: 10),
                                            ),
                                          ),
                                        ),
                                      ],
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addVendor,
        icon: const Icon(Icons.person_add),
        label: const Text('Add Vendor'),
      ),
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

  Future<void> _recordTransaction(String type) async {
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    DateTime txnDate = DateTime.now();

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(type == 'CREDIT' ? 'Record Credit Given' : 'Record Payment Collected'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Amount'),
                  autofocus: true,
                ),
                TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notes (optional)')),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Date', style: TextStyle(fontSize: 13)),
                  subtitle: Text(formatDay(txnDate.toIso8601String())),
                  trailing: const Icon(Icons.calendar_today, size: 18),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: txnDate,
                      firstDate: DateTime(2015),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setDialogState(() => txnDate = picked);
                  },
                ),
                if (type == 'CREDIT')
                  const Text(
                    'Backdate this if you\'re entering old credit history — keeps '
                    'day-outstanding tracking accurate.',
                    style: TextStyle(fontSize: 11, color: Colors.black54),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );

    final amount = double.tryParse(amountCtrl.text) ?? 0;
    if (saved == true && amount > 0) {
      await _db.addCreditTransaction(
        vendorId: widget.vendor['id'] as String,
        type: type,
        amount: amount,
        notes: notesCtrl.text.trim(),
        date: txnDate.toIso8601String(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final vendorId = widget.vendor['id'] as String;
    return Scaffold(
      appBar: AppBar(title: Text(widget.vendor['name'] as String)),
      body: StreamBuilder<Map<String, dynamic>?>(
        stream: _db.watchVendor(vendorId),
        builder: (context, vendorSnap) {
          // Fall back to the vendor map we were opened with until the
          // live one arrives, so the screen never looks empty.
          final vendor = vendorSnap.data ?? widget.vendor;
          final balance = (vendor['balance'] as num?)?.toDouble() ?? 0;

          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                color: balance > 0 ? Colors.red.shade50 : Colors.green.shade50,
                child: Column(
                  children: [
                    if ((vendor['address'] as String?)?.isNotEmpty == true ||
                        (vendor['phone'] as String?)?.isNotEmpty == true)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          [
                            if ((vendor['phone'] as String?)?.isNotEmpty == true) vendor['phone'],
                            if ((vendor['address'] as String?)?.isNotEmpty == true)
                              'Place: ${vendor['address']}',
                          ].join('  •  '),
                          style: const TextStyle(color: Colors.black54, fontSize: 12),
                        ),
                      ),
                    const Text('Current Balance'),
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
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _db.watchVendorTransactions(vendorId),
                  builder: (context, txnSnap) {
                    if (txnSnap.hasError) {
                      return Center(child: Text('Could not load history: ${txnSnap.error}'));
                    }
                    if (!txnSnap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final transactions = txnSnap.data!;
                    if (transactions.isEmpty) {
                      return const Center(child: Text('No transactions yet.'));
                    }
                    return ListView.builder(
                      itemCount: transactions.length,
                      itemBuilder: (_, i) => _TransactionTile(txn: transactions[i]),
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

class _TransactionTile extends StatelessWidget {
  final Map<String, dynamic> txn;
  const _TransactionTile({required this.txn});

  @override
  Widget build(BuildContext context) {
    final isCredit = txn['type'] == 'CREDIT';
    final saleId = txn['sale_id'] as String?;

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
