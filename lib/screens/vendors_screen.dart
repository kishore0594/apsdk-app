import 'package:flutter/material.dart';
import '../db/db_helper.dart';
import '../utils/formatters.dart';
import '../utils/app_theme.dart';
import '../utils/app_strings.dart';

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
  String _searchQuery = '';
  late Future<Map<String, dynamic>> _insightsFuture;

  @override
  void initState() {
    super.initState();
    _insightsFuture = _db.getVendorInsightsSummary();
  }

  Future<void> _refreshInsights() async {
    final future = _db.getVendorInsightsSummary();
    setState(() => _insightsFuture = future);
    await future;
  }

  List<Map<String, dynamic>> _filteredVendors(List<Map<String, dynamic>> vendors) {
    if (_searchQuery.isEmpty) return vendors;
    final q = _searchQuery.toLowerCase();
    return vendors.where((v) => (v['name'] as String).toLowerCase().contains(q)).toList();
  }

  /// Groups vendors by their place/address, sorting each group A–Z by
  /// name — makes a long list (50+) scannable without needing to remember
  /// exact spelling, and pairs with the search bar rather than replacing
  /// it: search narrows the list first, then it's still shown grouped.
  Map<String, List<Map<String, dynamic>>> _groupByLocation(List<Map<String, dynamic>> vendors) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final v in vendors) {
      final place = (v['address'] as String? ?? '').trim();
      final key = place.isEmpty ? 'No location set' : place;
      groups.putIfAbsent(key, () => []).add(v);
    }
    for (final list in groups.values) {
      list.sort((a, b) => (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase()));
    }
    return groups;
  }

  List<String> _sortedLocationKeys(Map<String, List<Map<String, dynamic>>> groups) {
    final keys = groups.keys.toList()
      ..sort((a, b) {
        if (a == 'No location set') return 1;
        if (b == 'No location set') return -1;
        return a.compareTo(b);
      });
    return keys;
  }

  String _vendorSubtitle(Map<String, dynamic> v) {
    final phone = v['phone'] as String? ?? '';
    final place = v['address'] as String? ?? '';
    if (phone.isEmpty && place.isEmpty) return '';
    if (place.isEmpty) return phone;
    if (phone.isEmpty) return 'Place: $place';
    return '$phone • $place';
  }

  /// Existing values for one field (name/phone/address) across all current
  /// vendors — the suggestion source for _suggestField, so retyping "same
  /// place, different spelling" becomes picking from a list instead.
  List<String> _distinctValues(List<Map<String, dynamic>> vendors, String key) {
    return vendors
        .map((v) => (v[key] as String? ?? '').trim())
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  /// A text field that suggests existing values as you type. Uses the same
  /// controller-capture approach as the product search in New Sale — the
  /// captured controller is read directly when Save is pressed, rather
  /// than kept in sync via a listener (which Autocomplete's rebuild
  /// behavior can call repeatedly, risking duplicate listener registrations).
  Widget _suggestField({
    required String label,
    required String initialValue,
    required List<String> suggestions,
    required void Function(TextEditingController) captureController,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) => Autocomplete<String>(
        initialValue: TextEditingValue(text: initialValue),
        optionsBuilder: (value) {
          final q = value.text.trim().toLowerCase();
          if (q.isEmpty) return const Iterable<String>.empty();
          return suggestions.where((s) => s.toLowerCase().contains(q) && s.toLowerCase() != q);
        },
        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
          captureController(controller);
          return TextField(controller: controller, focusNode: focusNode, decoration: InputDecoration(labelText: label));
        },
        optionsViewBuilder: (context, onSelected, options) => Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: constraints.maxWidth,
              height: options.length > 3 ? 168 : options.length * 44.0,
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: options.length,
                itemBuilder: (context, i) {
                  final s = options.elementAt(i);
                  return ListTile(
                    dense: true,
                    title: Text(s, style: const TextStyle(fontSize: 13)),
                    onTap: () => onSelected(s),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _addVendor() async {
    final allVendors = await _db.getVendors();
    final nameSuggestions = _distinctValues(allVendors, 'name');
    final phoneSuggestions = _distinctValues(allVendors, 'phone');
    final placeSuggestions = _distinctValues(allVendors, 'address');
    TextEditingController? nameFieldCtrl;
    TextEditingController? phoneFieldCtrl;
    TextEditingController? placeFieldCtrl;
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
                _suggestField(
                  label: AppStrings.t('name'),
                  initialValue: '',
                  suggestions: nameSuggestions,
                  captureController: (c) => nameFieldCtrl = c,
                ),
                const SizedBox(height: 8),
                _suggestField(
                  label: AppStrings.t('phone'),
                  initialValue: '',
                  suggestions: phoneSuggestions,
                  captureController: (c) => phoneFieldCtrl = c,
                ),
                const SizedBox(height: 8),
                _suggestField(
                  label: AppStrings.t('place'),
                  initialValue: '',
                  suggestions: placeSuggestions,
                  captureController: (c) => placeFieldCtrl = c,
                ),
                const SizedBox(height: 8),
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

    final vendorName = nameFieldCtrl?.text.trim() ?? '';
    if (saved == true && vendorName.isNotEmpty) {
      final newVendorId = await _db.insertVendor({
        'name': vendorName,
        'phone': phoneFieldCtrl?.text.trim() ?? '',
        'address': placeFieldCtrl?.text.trim() ?? '',
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
    final allVendors = await _db.getVendors();
    final nameSuggestions = _distinctValues(allVendors, 'name');
    final phoneSuggestions = _distinctValues(allVendors, 'phone');
    final placeSuggestions = _distinctValues(allVendors, 'address');
    TextEditingController? nameFieldCtrl;
    TextEditingController? phoneFieldCtrl;
    TextEditingController? placeFieldCtrl;

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppStrings.t('edit_vendor')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _suggestField(
                label: AppStrings.t('name'),
                initialValue: vendor['name'] as String? ?? '',
                suggestions: nameSuggestions,
                captureController: (c) => nameFieldCtrl = c,
              ),
              const SizedBox(height: 8),
              _suggestField(
                label: AppStrings.t('phone'),
                initialValue: vendor['phone'] as String? ?? '',
                suggestions: phoneSuggestions,
                captureController: (c) => phoneFieldCtrl = c,
              ),
              const SizedBox(height: 8),
              _suggestField(
                label: AppStrings.t('place'),
                initialValue: vendor['address'] as String? ?? '',
                suggestions: placeSuggestions,
                captureController: (c) => placeFieldCtrl = c,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(AppStrings.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(AppStrings.t('save'))),
        ],
      ),
    );
    final newName = nameFieldCtrl?.text.trim() ?? '';
    if (saved != true || newName.isEmpty) return;
    try {
      await _db.updateVendor(
        vendor['id'] as String,
        name: newName,
        phone: phoneFieldCtrl?.text.trim() ?? '',
        address: placeFieldCtrl?.text.trim() ?? '',
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

  Widget _vendorCard(Map<String, dynamic> v, {double? trend}) {
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
                  backgroundColor: (owes ? AppTheme.danger : AppTheme.success).withOpacity(0.12),
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
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      if (subtitle.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(subtitle,
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              overflow: TextOverflow.ellipsis),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(AppStrings.t('outstanding'), style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
                        if (trend != null && trend.abs() > 0.01) ...[
                          const SizedBox(width: 3),
                          Tooltip(
                            message: trend > 0
                                ? 'Grown by ${formatCurrency(trend)} in the last 14 days'
                                : 'Paid down by ${formatCurrency(trend.abs())} in the last 14 days',
                            child: Icon(
                              trend > 0 ? Icons.trending_up : Icons.trending_down,
                              size: 13,
                              color: trend > 0 ? AppTheme.danger : AppTheme.success,
                            ),
                          ),
                        ],
                      ],
                    ),
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
                        MaterialPageRoute(builder: (_) => VendorDetailScreen(vendor: v)),
                      ),
                      icon: const Icon(Icons.menu_book_outlined, size: 16),
                      label: Text(AppStrings.t('ledger')),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busyVendorIds.contains(v['id'])
                          ? null
                          : () => _quickCollectPayment(v['id'] as String, v['name'] as String),
                      icon: _busyVendorIds.contains(v['id'])
                          ? const SizedBox(
                              height: 14,
                              width: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.payments_outlined, size: 16),
                      label: Text(AppStrings.t('payment')),
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10)),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _insightStat(IconData icon, String label, String value, Color color) {
    return Expanded(
      child: AppCard(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 6),
            Text(value,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 9.5, color: Colors.grey.shade600), maxLines: 2),
          ],
        ),
      ),
    );
  }

  Widget _insightsStrip(Map<String, dynamic> data) {
    final avgDays = (data['avg_days_outstanding'] as num).toDouble();
    final newThisMonth = data['new_this_month'] as int;
    final collected = (data['collected_this_week'] as num).toDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Row(
        children: [
          _insightStat(Icons.hourglass_bottom, 'Avg Days Outstanding', '${avgDays.round()}', AppTheme.warning),
          const SizedBox(width: 8),
          _insightStat(Icons.person_add_alt, 'New This Month', '$newThisMonth', AppTheme.accent),
          const SizedBox(width: 8),
          _insightStat(Icons.payments, 'Collected This Week', formatCurrency(collected), AppTheme.success),
        ],
      ),
    );
  }

  Widget _needsAttentionSection(List<Map<String, dynamic>> vendors) {
    if (vendors.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: EdgeInsets.zero,
          leading: const IconBadge(icon: Icons.priority_high, color: AppTheme.danger, size: 16),
          title: const Text('Needs Attention',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.danger)),
          subtitle: Text('${vendors.length} overdue 30+ days, no recent activity',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          children: vendors.map((v) => _vendorCard(v)).toList(),
        ),
      ),
    );
  }

  Widget _locationHeader(String place, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
      child: Row(
        children: [
          const Icon(Icons.place_outlined, size: 15, color: AppTheme.accent),
          const SizedBox(width: 6),
          Text(place, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: AppTheme.accent)),
          const SizedBox(width: 6),
          Text('($count)', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.t('vendor_credit')),
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

          return RefreshIndicator(
            onRefresh: _refreshInsights,
            child: Column(
              children: [
                SummaryBanner(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Total Outstanding',
                  value: formatCurrency(totalOutstanding),
                  color: totalOutstanding > 0 ? AppTheme.danger : AppTheme.success,
                  caption: '$owingCount of ${vendors.length} vendors owe money',
                ),
                if (vendors.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search by name',
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v.trim()),
                    ),
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
                      : FutureBuilder<Map<String, dynamic>>(
                          future: _insightsFuture,
                          builder: (context, insightsSnapshot) {
                            final insights = insightsSnapshot.data;
                            final trends = (insights?['trends'] as Map<String, dynamic>?) ?? {};
                            final needsAttention =
                                (insights?['needs_attention'] as List<Map<String, dynamic>>?) ?? [];

                            final filtered = _filteredVendors(vendors);
                            final grouped = _groupByLocation(filtered);
                            final locationKeys = _sortedLocationKeys(grouped);

                            return ListView(
                              padding: const EdgeInsets.fromLTRB(14, 4, 14, 90),
                              children: [
                                if (insights != null) ...[
                                  _insightsStrip(insights),
                                  _needsAttentionSection(needsAttention),
                                  const SizedBox(height: 6),
                                ],
                                if (filtered.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 40),
                                    child: EmptyState(
                                      icon: Icons.search_off,
                                      title: 'No vendors match "$_searchQuery"',
                                    ),
                                  )
                                else
                                  for (final place in locationKeys) ...[
                                    _locationHeader(place, grouped[place]!.length),
                                    for (final v in grouped[place]!)
                                      _vendorCard(v, trend: (trends[v['id']] as num?)?.toDouble()),
                                  ],
                              ],
                            );
                          },
                        ),
                ),
              ],
            ),
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
