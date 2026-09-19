import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../db/db_helper.dart';
import '../utils/formatters.dart';
import '../utils/app_theme.dart';
import '../utils/app_strings.dart';
import '../utils/app_info.dart';

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

  /// Opens WhatsApp with a pre-filled reminder message for this vendor —
  /// composed, never sent automatically. You review and hit send yourself,
  /// same as typing the message by hand, just without retyping it each
  /// time.
  Future<void> _sendWhatsAppReminder(Map<String, dynamic> v) async {
    final phone = (v['phone'] as String? ?? '').trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No phone number saved for this vendor')));
      return;
    }

    // Independent of the app's own display language — the vendor
    // receiving this may prefer a different one than whatever the store
    // owner currently has the app set to, so this is asked fresh each
    // time rather than reusing LocaleController's setting.
    final language = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Send reminder in'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.language),
              title: const Text('English'),
              onTap: () => Navigator.pop(context, 'en'),
            ),
            ListTile(
              leading: const Icon(Icons.language),
              title: const Text('தமிழ்'),
              onTap: () => Navigator.pop(context, 'ta'),
            ),
          ],
        ),
      ),
    );
    if (language == null) return;

    // wa.me expects digits only, with country code — assumes a 10-digit
    // Indian number if none was included, since that's what's typically
    // entered here; a number already starting with a country code is
    // left as-is.
    var digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 10) digits = '91$digits';
    final balance = (v['balance'] as num?)?.toDouble() ?? 0;
    // Fetched fresh each time so the reminder always states the real
    // current number, not whatever happened to be cached when the list
    // last loaded.
    final days = await _db.getVendorOutstandingDays(v['id'] as String);

    final String text;
    if (language == 'ta') {
      final daysLine = days != null ? ' இந்த தொகை $days நாட்களாக நிலுவையில் உள்ளது.' : '';
      text = 'அன்புள்ள ${v['name']},\n\n'
          'தங்களிடம் ${AppInfo.appName} கடையில் ${formatCurrency(balance)} நிலுவைத் தொகை '
          'உள்ளது என்பதை நினைவூட்ட விரும்புகிறோம்.$daysLine\n\n'
          'தயவுசெய்து விரைவில் செலுத்தி உதவவும். தங்கள் தொடர்ச்சியான ஆதரவிற்கு நன்றி.\n\n'
          '- ${AppInfo.appName}';
    } else {
      final daysLine = days != null ? ', pending for $days day${days == 1 ? '' : 's'}' : '';
      text = 'Dear ${v['name']},\n\n'
          'This is a reminder that you have an outstanding balance of ${formatCurrency(balance)} '
          'with ${AppInfo.appName}$daysLine.\n\n'
          'Kindly settle this at your earliest convenience. Thank you for your continued business.\n\n'
          '- ${AppInfo.appName}';
    }
    final message = Uri.encodeComponent(text);
    final url = Uri.parse('https://wa.me/$digits?text=$message');
    try {
      final launched = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not open WhatsApp')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not open WhatsApp: $e')));
      }
    }
  }

  Widget _vendorCard(Map<String, dynamic> v, {double? trend, int? daysOutstanding}) {
    final balance = (v['balance'] as num?)?.toDouble() ?? 0;
    final owes = balance > 0;
    final subtitle = _vendorSubtitle(v);
    final daysText = daysOutstanding != null
        ? 'Outstanding for $daysOutstanding day${daysOutstanding == 1 ? '' : 's'}'
        : null;
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
                      if (daysText != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(daysText,
                              style: const TextStyle(
                                  fontSize: 11.5, color: AppTheme.danger, fontWeight: FontWeight.w600)),
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
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Remind on WhatsApp',
                    onPressed: () => _sendWhatsAppReminder(v),
                    icon: const Icon(Icons.chat_outlined, size: 18),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366).withOpacity(0.12),
                      foregroundColor: const Color(0xFF128C7E),
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

  void _showHelpSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const Text('What each number means',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              _helpItem(
                Icons.account_balance_wallet_outlined,
                AppTheme.danger,
                'Total Outstanding',
                'The sum every vendor currently owes, added up right now. Updates live as you record sales, credit, and payments.',
              ),
              _helpItem(
                Icons.search,
                AppTheme.primary,
                'Search',
                'Filters the list by name as you type. Location groups still show below — search just narrows which vendors appear inside them.',
              ),
              _helpItem(
                Icons.hourglass_bottom,
                AppTheme.warning,
                'Avg Days Outstanding',
                'The average — across every vendor who currently owes something — of how many days their present balance has been unpaid. A vendor who\'s fully paid up isn\'t counted.',
              ),
              _helpItem(
                Icons.person_add_alt,
                AppTheme.accent,
                'New This Month',
                'How many vendors have been added since the 1st of this calendar month.',
              ),
              _helpItem(
                Icons.payments,
                AppTheme.success,
                'Collected This Week',
                'Money collected against existing vendor debt (payments, not new credit) — for the last 7 calendar days, midnight to midnight, including today. This is the same number Reports & Trends calls "Credit Payments Collected" for the Week period — they\'re kept identical on purpose.',
              ),
              _helpItem(
                Icons.priority_high,
                AppTheme.danger,
                'Needs Attention',
                'Two separate conditions, both true at once — not added together:\n'
                    '• The current balance has been unpaid for 30+ days (however old it actually is)\n'
                    '• Nothing has happened on the account — no new credit, no payment — in the last 14 days\n'
                    'A vendor with a 6-month-old balance qualifies too, as long as it\'s also been quiet for 2 weeks. It is not "30 days + 14 days = 45 days".',
              ),
              _helpItem(
                Icons.trending_up,
                AppTheme.danger,
                'Trend arrow (↑ / ↓)',
                'Only shown for vendors who currently owe money. Adds up every credit and payment in the last 14 days into one net number — red ↑ means their balance grew overall, green ↓ means it shrank overall, no arrow means barely any net movement. Long-press it for the exact amount.',
              ),
              _helpItem(
                Icons.place_outlined,
                AppTheme.accent,
                'Location groups',
                'Vendors are grouped by their recorded place, sorted A–Z within each group. Collapsed by default so 40+ vendors stay scannable — tap a group to open it. While you\'re searching, matching groups expand automatically so results aren\'t hidden.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _helpItem(IconData icon, Color color, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon: icon, color: color, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                Text(body, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700, height: 1.4)),
              ],
            ),
          ),
        ],
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
          children: vendors.map((v) => _vendorCard(v, daysOutstanding: v['days_outstanding'] as int?)).toList(),
        ),
      ),
    );
  }

  Widget _locationGroup(
    String place,
    List<Map<String, dynamic>> vendors,
    Map<String, dynamic> trends,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          // Collapsed by default for normal browsing — but expanded
          // automatically while a search is active, so a match doesn't
          // end up hidden behind a group you'd have to tap first.
          key: PageStorageKey(place),
          initiallyExpanded: _searchQuery.isNotEmpty,
          tilePadding: const EdgeInsets.symmetric(horizontal: 4),
          childrenPadding: EdgeInsets.zero,
          leading: const Icon(Icons.place_outlined, size: 15, color: AppTheme.accent),
          title: Text(place,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: AppTheme.accent)),
          subtitle: Text('${vendors.length} vendor${vendors.length == 1 ? '' : 's'}',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
          children: [
            for (final v in vendors) _vendorCard(v, trend: (trends[v['id']] as num?)?.toDouble()),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.t('vendor_credit')),
        actions: [
          IconButton(
            tooltip: 'What do these mean?',
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showHelpSheet(context),
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
                                  for (final place in locationKeys)
                                    _locationGroup(place, grouped[place]!, trends),
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
  late Future<int?> _daysOutstandingFuture;

  @override
  void initState() {
    super.initState();
    _daysOutstandingFuture = _db.getVendorOutstandingDays(widget.vendor['id'] as String);
  }

  void _refreshDaysOutstanding() {
    setState(() {
      _daysOutstandingFuture = _db.getVendorOutstandingDays(widget.vendor['id'] as String);
    });
  }

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
        _refreshDaysOutstanding();
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
                    if (balance > 0)
                      FutureBuilder<int?>(
                        future: _daysOutstandingFuture,
                        builder: (context, snap) {
                          if (!snap.hasData || snap.data == null) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Outstanding for ${snap.data} day${snap.data == 1 ? '' : 's'}',
                              style: const TextStyle(fontSize: 12.5, color: Colors.black54),
                            ),
                          );
                        },
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
