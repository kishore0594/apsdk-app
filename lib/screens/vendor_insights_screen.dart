import 'package:flutter/material.dart';
import '../db/db_helper.dart';
import '../utils/formatters.dart';
import '../utils/app_theme.dart';
import 'vendors_screen.dart';

class VendorInsightsScreen extends StatefulWidget {
  const VendorInsightsScreen({super.key});

  @override
  State<VendorInsightsScreen> createState() => _VendorInsightsScreenState();
}

enum _View { location, frequency, outstanding, pending }

class _VendorInsightsScreenState extends State<VendorInsightsScreen> {
  final _db = DBHelper.instance;
  _View _view = _View.location;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _vendors = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _db.getVendorAnalytics();
      setState(() {
        _vendors = data;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Could not load vendor insights: $e';
      });
    }
  }

  void _openVendor(Map<String, dynamic> v) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => VendorDetailScreen(vendor: v)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      appBar: AppBar(title: const Text('Vendor Insights')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _ViewChip(
                              label: 'Location',
                              icon: Icons.place_outlined,
                              selected: _view == _View.location,
                              onTap: () => setState(() => _view = _View.location),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _ViewChip(
                              label: 'Frequency',
                              icon: Icons.repeat,
                              selected: _view == _View.frequency,
                              onTap: () => setState(() => _view = _View.frequency),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _ViewChip(
                              label: 'Outstanding',
                              icon: Icons.account_balance_wallet_outlined,
                              selected: _view == _View.outstanding,
                              onTap: () => setState(() => _view = _View.outstanding),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _ViewChip(
                              label: 'Long Pending',
                              icon: Icons.hourglass_bottom,
                              selected: _view == _View.pending,
                              onTap: () => setState(() => _view = _View.pending),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      switch (_view) {
                        _View.location => _byLocation(),
                        _View.frequency => _byFrequency(),
                        _View.outstanding => _byOutstanding(),
                        _View.pending => _longPending(),
                      },
                    ],
                  ),
                ),
    );
  }

  // ---------------- BY LOCATION ----------------

  Widget _byLocation() {
    if (_vendors.isEmpty) return _emptyMessage('No vendors yet.');
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final v in _vendors) {
      final place = (v['address'] as String? ?? '').trim();
      final key = place.isEmpty ? 'No location set' : place;
      groups.putIfAbsent(key, () => []).add(v);
    }
    final sortedKeys = groups.keys.toList()
      ..sort((a, b) {
        if (a == 'No location set') return 1;
        if (b == 'No location set') return -1;
        return a.compareTo(b);
      });

    return Column(
      children: sortedKeys.map((place) {
        final vendorsHere = groups[place]!;
        final totalOutstanding =
            vendorsHere.fold<double>(0, (sum, v) => sum + (v['balance'] as num));
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                leading: const IconBadge(icon: Icons.place_outlined, color: AppTheme.accent, size: 16),
                title: Text(place, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: Text(
                  '${vendorsHere.length} vendor${vendorsHere.length == 1 ? '' : 's'}'
                  '${totalOutstanding > 0 ? '  •  ${formatCurrency(totalOutstanding)} outstanding' : ''}',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                ),
                children: vendorsHere.map((v) => _vendorRow(v)).toList(),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ---------------- BY PURCHASE FREQUENCY ----------------

  Widget _byFrequency() {
    if (_vendors.isEmpty) return _emptyMessage('No vendors yet.');
    final sorted = [..._vendors]
      ..sort((a, b) => (b['purchase_count'] as int).compareTo(a['purchase_count'] as int));

    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(children: sorted.map((v) => _vendorRow(v, showFrequency: true)).toList()),
    );
  }

  // ---------------- BY OUTSTANDING AMOUNT ----------------

  Widget _byOutstanding() {
    if (_vendors.isEmpty) return _emptyMessage('No vendors yet.');
    final sorted = [..._vendors]..sort((a, b) => (b['balance'] as num).compareTo(a['balance'] as num));

    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(children: sorted.map((v) => _vendorRow(v)).toList()),
    );
  }

  // ---------------- LONG PENDING (AGING BUCKETS) ----------------

  Widget _longPending() {
    final pending = _vendors.where((v) => v['days_outstanding'] != null).toList();
    if (pending.isEmpty) {
      return _emptyMessage('Nobody has an outstanding balance right now — nothing pending.');
    }

    final buckets = <String, List<Map<String, dynamic>>>{
      '90+ days': [],
      '61–90 days': [],
      '31–60 days': [],
      '0–30 days': [],
    };
    for (final v in pending) {
      final days = v['days_outstanding'] as int;
      if (days > 90) {
        buckets['90+ days']!.add(v);
      } else if (days > 60) {
        buckets['61–90 days']!.add(v);
      } else if (days > 30) {
        buckets['31–60 days']!.add(v);
      } else {
        buckets['0–30 days']!.add(v);
      }
    }
    final bucketColors = {
      '90+ days': AppTheme.danger,
      '61–90 days': const Color(0xFFEA580C),
      '31–60 days': AppTheme.warning,
      '0–30 days': AppTheme.success,
    };

    return Column(
      children: buckets.entries.where((e) => e.value.isNotEmpty).map((entry) {
        final color = bucketColors[entry.key]!;
        final total = entry.value.fold<double>(0, (sum, v) => sum + (v['balance'] as num));
        entry.value.sort((a, b) => (b['days_outstanding'] as int).compareTo(a['days_outstanding'] as int));
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: entry.key == '90+ days' || entry.key == '61–90 days',
                leading: IconBadge(icon: Icons.hourglass_bottom, color: color, size: 16),
                title: Text(entry.key, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color)),
                subtitle: Text(
                  '${entry.value.length} vendor${entry.value.length == 1 ? '' : 's'}  •  ${formatCurrency(total)}',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                ),
                children: entry.value.map((v) => _vendorRow(v, showDays: true)).toList(),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ---------------- SHARED ROW ----------------

  Widget _vendorRow(Map<String, dynamic> v, {bool showFrequency = false, bool showDays = false}) {
    final balance = (v['balance'] as num?)?.toDouble() ?? 0;
    final purchaseCount = v['purchase_count'] as int? ?? 0;
    final lastPurchase = v['last_purchase_date'] as String?;
    final days = v['days_outstanding'] as int?;

    String subtitle;
    if (showFrequency) {
      subtitle = purchaseCount == 0
          ? 'No purchases yet'
          : '$purchaseCount purchase${purchaseCount == 1 ? '' : 's'}'
              '${lastPurchase != null ? '  •  last ${formatDay(lastPurchase)}' : ''}';
    } else if (showDays && days != null) {
      subtitle = 'Outstanding $days days';
    } else {
      final place = (v['address'] as String? ?? '').trim();
      subtitle = place.isNotEmpty ? place : '$purchaseCount purchase${purchaseCount == 1 ? '' : 's'}';
    }

    return ListTile(
      title: Text(v['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
      trailing: Text(
        formatCurrency(balance),
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: balance > 0 ? AppTheme.danger : AppTheme.success,
        ),
      ),
      onTap: () => _openVendor(v),
    );
  }

  Widget _emptyMessage(String message) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(child: Text(message, style: TextStyle(color: Colors.grey.shade600))),
      );
}

class _ViewChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _ViewChip({required this.label, required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          border: Border.all(color: selected ? AppTheme.primary : AppTheme.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: selected ? Colors.white : Colors.black54),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                  fontSize: 12.5,
                  color: selected ? Colors.white : Colors.black87,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                )),
          ],
        ),
      ),
    );
  }
}
