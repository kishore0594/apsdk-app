import 'package:flutter/material.dart';
import '../db/db_helper.dart';
import '../utils/formatters.dart';
import '../utils/app_theme.dart';
import '../utils/app_strings.dart';
import 'vendor_insights_screen.dart';

class VendorsScreen extends StatefulWidget {
  const VendorsScreen({super.key});

  @override
  State<VendorsScreen> createState() => _VendorsScreenState();
}

class _VendorsScreenState extends State<VendorsScreen> {
  final _db = DBHelper.instance;
  // Tracks which vendor(s) currently have a quick-payment save in flight,
  // so double-tapping "Payment" on the same vendor while it's still
  // saving can't create two payment records — the same class of bug
  // that caused a duplicate sale entry.
  final Set<String> _busyVendorIds = {};

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
          title: Text(AppStrings.t('add_vendor_credit_customer')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: InputDecoration(labelText: AppStrings.t('name'))),
                TextField(controller: phoneCtrl, decoration: InputDecoration(labelText: AppStrings.t('phone'))),
                TextField(controller: addressCtrl, decoration: InputDecoration(labelText: AppStrings.t('place'))),
                TextField(
                  controller: openingCtrl,
                  decoration: InputDecoration(labelText: AppStrings.t('opening_balance_owed')),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(AppStrings.t('credit_given_on'), style: const TextStyle(fontSize: 13)),
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
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(AppStrings.t('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(AppStrings.t('save'))),
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
    if (_busyVendorIds.contains(vendorId)) return;
    final amountCtrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${AppStrings.t('collect_payment')} — $vendorName'),
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
    setState(() => _busyVendorIds.add(vendorId));
    try {
      await _db.addCreditTransaction(vendorId: vendorId, type: 'PAYMENT', amount: amount).timeout(
            const Duration(seconds: 25),
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("${AppStrings.t('could_not_record_payment')}: $e")));
      }
    } finally {
      if (mounted) setState(() => _busyVendorIds.remove(vendorId));
    }
  }

  Future<void> _editVendor(Map<String, dynamic> vendor) async {
    final nameCtrl = TextEditingController(text: vendor['name'] as String? ?? '');
    final phoneCtrl = TextEditingController(text: vendor['phone'] as String? ?? '');
    final addressCtrl = TextEditingController(text: vendor['address'] as String? ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppStrings.t('edit_vendor')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: InputDecoration(labelText: AppStrings.t('name'))),
            TextField(controller: phoneCtrl, decoration: InputDecoration(labelText: AppStrings.t('phone'))),
            TextField(controller: addressCtrl, decoration: InputDecoration(labelText: AppStrings.t('place'))),
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
      await _db.updateVendor(
        vendor['id'] as String,
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

  Future<void> _deleteVendor(Map<String, dynamic> vendor) async {
    final balance = (vendor['balance'] as num?)?.toDouble() ?? 0;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("${AppStrings.t('delete')} ${vendor['name']}?"),
        content: Text(
          balance > 0
              ? 'This vendor still has an outstanding balance of ${formatCurrency(balance)}. '
                  'Deleting them removes the vendor from your list — their past transaction records '
                  'stay in your data exports, but the balance itself won\'t be tracked anywhere '
                  'once they\'re gone. This can\'t be undone.'
              : 'This can\'t be undone. Their past transaction records stay in your data exports.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(AppStrings.t('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppStrings.t('delete')),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _db.deleteVendor(vendor['id'] as String);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${AppStrings.t('could_not_delete')}: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.t('vendor_credit')),
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
                          label: Text(AppStrings.t('add_vendor')),
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
                                          Text(AppStrings.t('outstanding'),
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
                                              title: Text(AppStrings.t('delete'), style: const TextStyle(color: AppTheme.danger)),
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
                                            label: Text(AppStrings.t('ledger')),
                                            style: OutlinedButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(vertical: 10),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: FilledButton.icon(
                                            onPressed: _busyVendorIds.contains(v['id'])
                                                ? null
                                                : () => _quickCollectPayment(
                                                    v['id'] as String, v['name'] as String),
                                            icon: _busyVendorIds.contains(v['id'])
                                                ? const SizedBox(
                                                    height: 14,
                                                    width: 14,
                                                    child: CircularProgressIndicator(
                                                        strokeWidth: 2, color: Colors.white))
                                                : const Icon(Icons.payments_outlined, size: 16),
                                            label: Text(AppStrings.t('payment')),
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
        label: Text(AppStrings.t('add_vendor')),
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
  bool _saving = false;

  Future<void> _recordTransaction(String type) async {
    if (_saving) return;
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
                  decoration: InputDecoration(labelText: AppStrings.t('amount')),
                  autofocus: true,
                ),
                TextField(controller: notesCtrl, decoration: InputDecoration(labelText: AppStrings.t('notes_optional'))),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(AppStrings.t('date'), style: const TextStyle(fontSize: 13)),
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
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(AppStrings.t('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(AppStrings.t('save'))),
          ],
        ),
      ),
    );

    final amount = double.tryParse(amountCtrl.text) ?? 0;
    if (saved == true && amount > 0) {
      setState(() => _saving = true);
      try {
        await _db
            .addCreditTransaction(
              vendorId: widget.vendor['id'] as String,
              type: type,
              amount: amount,
              notes: notesCtrl.text.trim(),
              date: txnDate.toIso8601String(),
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
                    Text(AppStrings.t('current_balance')),
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
                        onPressed: _saving ? null : () => _recordTransaction('CREDIT'),
                        icon: const Icon(Icons.add),
                        label: Text(AppStrings.t('add_credit')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _saving ? null : () => _recordTransaction('PAYMENT'),
                        icon: _saving
                            ? const SizedBox(
                                height: 14,
                                width: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.payments),
                        label: Text(AppStrings.t('collect_payment')),
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
                  stream: _db.watchVendorTransactions(vendorId),
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
        Text("${isCredit ? AppStrings.t('credit_given') : AppStrings.t('payment_received')}: ${formatCurrency(txn['amount'])}");
    final balanceText =
        Text("${AppStrings.t('balance_abbr')}: ${formatCurrency(txn['balance_after'])}", style: const TextStyle(fontSize: 12));

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
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text(AppStrings.t('no_item_details')),
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
