import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:convert';
import '../db/db_helper.dart';
import '../utils/formatters.dart';
import '../utils/app_strings.dart';
import '../utils/app_theme.dart';
import '../utils/user_role.dart';

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
  List<Map<String, dynamic>> _monthlyTrend = [];
  bool _todayOnly = true;

  @override
  void initState() {
    super.initState();
    _loadTrend();
  }

  Future<void> _loadTrend() async {
    final trend = await _db.getSalesSummaryByDay(days: 30);
    if (mounted) setState(() => _monthlyTrend = trend.reversed.toList());
  }

  Future<void> _cancelSale(String saleId, {bool closeSheet = true}) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppStrings.t('cancel_sale_confirm')),
        content: const Text(
            'This restores the stock it used and reverses any credit posted to the vendor. '
            'The sale stays visible for the record, marked as cancelled.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(AppStrings.t('no_keep_it'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppStrings.t('cancel_sale')),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _db.cancelSale(saleId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("${AppStrings.t('could_not_cancel_sale')}: $e")));
      }
      return;
    }
    if (closeSheet && mounted) Navigator.pop(context); // close the sale detail sheet
    _loadTrend(); // the sales list itself is a live stream and updates on its own
  }

  Future<void> _modifySale(Map<String, dynamic> sale, List<Map<String, dynamic>> items,
      {bool closeSheet = true}) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppStrings.t('modify_sale_confirm')),
        content: const Text(
            'This cancels the original sale (restoring stock and reversing any credit) and opens '
            'a new sale pre-filled with the same items, so you can adjust and re-enter it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(AppStrings.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(AppStrings.t('continue_label'))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _db.cancelSale(sale['id'] as String);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("${AppStrings.t('could_not_modify_sale')}: $e")));
      }
      return;
    }
    if (closeSheet && mounted) Navigator.pop(context); // close the sale detail sheet
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NewSaleScreen(
          prefillItems: items,
          prefillDiscount: (sale['discount'] as num?)?.toDouble() ?? 0,
          prefillPaymentType: sale['payment_type'] as String? ?? 'CASH',
          prefillVendorId: sale['vendor_id'] as String?,
          prefillPaidAmount: (sale['paid_amount'] as num?)?.toDouble() ?? 0,
          prefillDate: sale['date'] as String?,
          prefillDueDate: sale['due_date'] as String?,
        ),
      ),
    );
    // The list is a live stream now — it'll reflect both the cancellation
    // and the new re-entered sale on its own. Just refresh the trend chart.
    _loadTrend();
  }

  /// Long-press quick menu: Modify / Delete without needing to open the
  /// full sale detail view first.
  Future<void> _showSaleActions(Map<String, dynamic> sale) async {
    if (sale['status'] == 'cancelled') return;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: Text(AppStrings.t('modify')),
              onTap: () => Navigator.pop(context, 'modify'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: Text(AppStrings.t('delete_cancel_sale'), style: const TextStyle(color: Colors.red)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'modify') {
      final items = await _db.getSaleItems(sale['id'] as String);
      if (mounted) _modifySale(sale, items, closeSheet: false);
    } else if (action == 'delete') {
      _cancelSale(sale['id'] as String, closeSheet: false);
    }
  }

  Future<void> _viewSale(Map<String, dynamic> sale) async {
    final items = await _db.getSaleItems(sale['id'] as String);
    final isCancelled = sale['status'] == 'cancelled';
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
            Row(
              children: [
                Expanded(
                  child: Text('${AppStrings.t('sale_hash')}${(sale['id'] as String).substring(0, 6)}',
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                if (isCancelled)
                  Chip(
                    label: Text(AppStrings.t('cancelled'), style: const TextStyle(fontSize: 11, color: Colors.white)),
                    backgroundColor: Colors.red,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            Text(formatDate(sale['date'] as String)),
            const Divider(),
            ...items.map((i) => ListTile(
                  dense: true,
                  title: Text(i['product_name'] as String),
                  subtitle: Text('${i['quantity']} × ${formatCurrency(i['unit_price'])}'),
                  trailing: Text(formatCurrency(i['subtotal'])),
                )),
            const Divider(),
            ListTile(title: Text(AppStrings.t('subtotal')), trailing: Text(formatCurrency(sale['subtotal']))),
            if ((sale['discount'] as num) > 0)
              ListTile(title: Text(AppStrings.t('discount')), trailing: Text('- ${formatCurrency(sale['discount'])}')),
            ListTile(
              title: Text(AppStrings.t('total'), style: const TextStyle(fontWeight: FontWeight.bold)),
              trailing: Text(formatCurrency(sale['total_amount']),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            Chip(label: Text(sale['payment_type'] as String)),
            if (sale['due_date'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Builder(builder: (context) {
                  final due = DateTime.tryParse(sale['due_date'] as String);
                  final overdue = due != null && !isCancelled && due.isBefore(DateTime.now());
                  return Text(
                    'Credit due · ${formatDay(sale['due_date'] as String)}',
                    style: TextStyle(
                        color: overdue ? Colors.red : Colors.black54,
                        fontWeight: overdue ? FontWeight.bold : FontWeight.normal),
                  );
                }),
              ),
            if (!isCancelled && UserRole.instance.isAdmin) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _modifySale(sale, items),
                      icon: const Icon(Icons.edit),
                      label: Text(AppStrings.t('modify')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                      onPressed: () => _cancelSale(sale['id'] as String),
                      icon: const Icon(Icons.cancel_outlined),
                      label: Text(AppStrings.t('cancel_sale')),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.t('sales_title')),
        actions: [
          IconButton(
            icon: Icon(_todayOnly ? Icons.today : Icons.calendar_month),
            tooltip: _todayOnly ? 'Showing today — tap for all' : 'Showing all — tap for today',
            onPressed: () {
              setState(() => _todayOnly = !_todayOnly);
            },
          ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _db.watchSales(
            dateFilter: _todayOnly ? DateTime.now().toIso8601String().substring(0, 10) : null),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text("${AppStrings.t('could_not_load_sales')}: ${snapshot.error}"));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final sales = snapshot.data!;
          final total = sales.fold<double>(
              0, (sum, s) => s['status'] == 'cancelled' ? sum : sum + (s['total_amount'] as num));
          final activeCount = sales.where((s) => s['status'] != 'cancelled').length;

          return Column(
            children: [
              SummaryBanner(
                icon: Icons.receipt_long_outlined,
                label: _todayOnly ? AppStrings.t('todays_sales') : AppStrings.t('total'),
                value: formatCurrency(total),
                color: AppTheme.revenue,
                caption: '$activeCount bills',
              ),
              const SizedBox(height: 6),
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  leading: const IconBadge(icon: Icons.show_chart, color: AppTheme.accent, size: 16),
                  title: Text(AppStrings.t('monthly_sales_trend'),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: Text(AppStrings.t('last_30_days'), style: const TextStyle(fontSize: 11)),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: SizedBox(height: 160, child: _MonthlyTrendChart(data: _monthlyTrend)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: sales.isEmpty
                    ? EmptyState(icon: Icons.point_of_sale_outlined, title: AppStrings.t('no_sales_tap_add'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 6, 14, 90),
                        itemCount: sales.length,
                        itemBuilder: (_, i) {
                          final s = sales[i];
                          final isCancelled = s['status'] == 'cancelled';
                          final payType = s['payment_type'] as String;
                          final payColor = isCancelled
                              ? Colors.grey
                              : payType == 'CASH'
                                  ? AppTheme.success
                                  : payType == 'PARTIAL'
                                      ? AppTheme.warning
                                      : AppTheme.danger;
                          final payLabel = payType == 'CASH'
                              ? AppStrings.t('cash')
                              : payType == 'PARTIAL'
                                  ? AppStrings.t('partial')
                                  : AppStrings.t('full_credit');
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: AppCard(
                              padding: const EdgeInsets.all(14),
                              background: isCancelled ? Colors.grey.shade50 : null,
                              onTap: () => _viewSale(s),
                              onLongPress: () => _showSaleActions(s),
                              child: Row(
                                children: [
                                  IconBadge(
                                    icon: isCancelled
                                        ? Icons.block
                                        : (payType == 'CASH' ? Icons.money : Icons.credit_card),
                                    color: payColor,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 13),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          formatCurrency(s['total_amount']),
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            decoration: isCancelled ? TextDecoration.lineThrough : null,
                                            color: isCancelled ? Colors.grey : null,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          isCancelled
                                              ? formatDate(s['date'] as String)
                                              : s['due_date'] != null
                                                  ? '${formatDate(s['date'] as String)} • Due ${formatDay(s['due_date'] as String)}'
                                                  : formatDate(s['date'] as String),
                                          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  StatusPill(
                                    label: isCancelled ? AppStrings.t('cancelled') : payLabel,
                                    color: payColor,
                                  ),
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
      floatingActionButton: UserRole.instance.isAdmin
          ? FloatingActionButton(
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const NewSaleScreen()));
                _loadTrend();
              },
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

class NewSaleScreen extends StatefulWidget {
  final List<Map<String, dynamic>>? prefillItems;
  final double? prefillDiscount;
  final String? prefillPaymentType;
  final String? prefillVendorId;
  final double? prefillPaidAmount;
  final String? prefillDate;
  final String? prefillDueDate;

  const NewSaleScreen({
    super.key,
    this.prefillItems,
    this.prefillDiscount,
    this.prefillPaymentType,
    this.prefillVendorId,
    this.prefillPaidAmount,
    this.prefillDate,
    this.prefillDueDate,
  });

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
  bool _saving = false;

  String _paymentType = 'CASH';
  String? _vendorId;
  DateTime _saleDate = DateTime.now();
  DateTime? _dueDate;
  TextEditingController? _pickerController;
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
    });
    _applyPrefill();
  }

  void _applyPrefill() {
    final items = widget.prefillItems;
    if (items == null || items.isEmpty || _cart.isNotEmpty) return;
    setState(() {
      for (final item in items) {
        final pid = item['product_id'] as String?;
        final qty = (item['quantity'] as num?)?.toDouble() ?? 1;
        Map<String, dynamic>? liveProduct;
        if (pid != null) {
          final matches = _products.where((p) => p['id'] == pid);
          if (matches.isNotEmpty) liveProduct = matches.first;
        }
        final product = liveProduct ??
            {
              'id': null,
              'name': item['product_name'],
              'unit': 'Nos',
              'selling_price': item['unit_price'],
              'quantity': 0,
            };
        _cart.add(_CartLine(product, qty));
      }
      if (widget.prefillDiscount != null) {
        _discountCtrl.text = widget.prefillDiscount!.toStringAsFixed(2);
      }
      if (widget.prefillPaymentType != null) {
        _paymentType = widget.prefillPaymentType!;
      }
      if (widget.prefillVendorId != null) {
        _vendorId = widget.prefillVendorId;
      }
      if (widget.prefillPaidAmount != null) {
        _paidCtrl.text = widget.prefillPaidAmount!.toStringAsFixed(2);
      }
      if (widget.prefillDate != null) {
        final parsed = DateTime.tryParse(widget.prefillDate!);
        if (parsed != null) _saleDate = parsed;
      }
      if (widget.prefillDueDate != null) {
        _dueDate = DateTime.tryParse(widget.prefillDueDate!);
      }
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

  Future<void> _quickAddVendor() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final placeCtrl = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppStrings.t('add_vendor_credit_customer')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: InputDecoration(labelText: AppStrings.t('name')), autofocus: true),
            TextField(controller: phoneCtrl, decoration: InputDecoration(labelText: AppStrings.t('phone'))),
            TextField(controller: placeCtrl, decoration: InputDecoration(labelText: AppStrings.t('place'))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(AppStrings.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(AppStrings.t('save'))),
        ],
      ),
    );

    if (saved == true && nameCtrl.text.trim().isNotEmpty) {
      final newId = await _db.insertVendor({
        'name': nameCtrl.text.trim(),
        'phone': phoneCtrl.text.trim(),
        'address': placeCtrl.text.trim(),
        'opening_balance': 0,
        'created_at': DateTime.now().toIso8601String(),
      });
      final vendors = await _db.getVendors();
      setState(() {
        _vendors = vendors;
        _vendorId = newId;
      });
    }
  }

  Future<void> _editQuantity(_CartLine line) async {
    final unit = line.product['unit'] as String? ?? 'pcs';
    final ctrl = TextEditingController(text: _formatQty(line.quantity, unit));
    final value = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${AppStrings.t('quantity')} ($unit)'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: AppStrings.t('quantity')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(AppStrings.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text), child: Text(AppStrings.t('set_label'))),
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
    // Guards against exactly the bug that was reported: if this runs
    // twice in quick succession (a double-tap, or a tap that lands again
    // after the screen freezes/redraws), the second call does nothing
    // instead of creating a second sale.
    if (_saving) return;

    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppStrings.t('add_at_least_one_item'))));
      return;
    }
    if (_paymentType != 'CASH' && _vendorId == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppStrings.t('select_vendor_credit'))));
      return;
    }
    final paid = _paymentType == 'CASH' ? _total : (double.tryParse(_paidCtrl.text) ?? 0);

    setState(() => _saving = true);
    try {
      await _db
          .createSale(
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
            saleDate: _saleDate.toIso8601String(),
            dueDate: _dueDate?.toIso8601String(),
          )
          // A save should never hang forever — if something is badly stuck
          // (e.g. a flaky connection Firestore keeps retrying on rather
          // than falling back to the local queue), this guarantees the
          // button re-enables and you get a clear error instead of an
          // unresponsive screen.
          .timeout(const Duration(seconds: 25));
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("${AppStrings.t('could_not_save_sale')}: $e")));
      }
      return;
    }

    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.prefillItems != null ? AppStrings.t('re_enter_sale') : AppStrings.t('new_sale')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppStrings.t('cancel'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => Autocomplete<Map<String, dynamic>>(
                      displayStringForOption: (p) => p['name'] as String,
                      optionsBuilder: (value) {
                        if (value.text.trim().isEmpty) return const Iterable<Map<String, dynamic>>.empty();
                        final q = value.text.toLowerCase();
                        return _products.where((p) => (p['name'] as String).toLowerCase().contains(q));
                      },
                      onSelected: (p) {
                        _addProduct(p);
                        _pickerController?.clear();
                      },
                      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                        _pickerController = controller;
                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
                          decoration: InputDecoration(
                            labelText: AppStrings.t('type_product_search'),
                            prefixIcon: const Icon(Icons.search),
                          ),
                        );
                      },
                      optionsViewBuilder: (context, onSelected, options) => Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 4,
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: constraints.maxWidth,
                            height: options.length > 4 ? 260 : options.length * 64.0,
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              itemCount: options.length,
                              itemBuilder: (context, i) {
                                final p = options.elementAt(i);
                                final photo = p['photo'] as String?;
                                return ListTile(
                                  dense: true,
                                  leading: photo != null
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(6),
                                          child: Image.memory(base64Decode(photo),
                                              width: 32, height: 32, fit: BoxFit.cover),
                                        )
                                      : null,
                                  title: Text(p['name'] as String),
                                  subtitle: Text(
                                      '${formatCurrency(p['selling_price'])}/${p['unit']} • stock ${p['quantity']}'),
                                  onTap: () => onSelected(p),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _saleDate,
                        firstDate: DateTime(2015),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) setState(() => _saleDate = picked);
                    },
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(formatDay(_saleDate.toIso8601String())),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 16),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('${AppStrings.t('cart')} (${_cart.length})', style: Theme.of(context).textTheme.titleMedium),
                  Expanded(
                    child: _cart.isEmpty
                        ? Center(child: Text(AppStrings.t('search_product_add')))
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
                      Text('${AppStrings.t('discount')}:'),
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
                  Text('${AppStrings.t('total')}: ${formatCurrency(_total)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(value: 'CASH', label: Text(AppStrings.t('cash'))),
                      ButtonSegment(value: 'CREDIT', label: Text(AppStrings.t('full_credit'))),
                      ButtonSegment(value: 'PARTIAL', label: Text(AppStrings.t('partial'))),
                    ],
                    selected: {_paymentType},
                    onSelectionChanged: (s) => setState(() => _paymentType = s.first),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _vendorId,
                          decoration: InputDecoration(
                            labelText: _paymentType == 'CASH'
                                ? 'Customer (optional)'
                                : 'Vendor (credit customer)',
                          ),
                          items: _vendors
                              .map((v) =>
                                  DropdownMenuItem(value: v['id'] as String, child: Text(v['name'] as String)))
                              .toList(),
                          onChanged: (v) => setState(() => _vendorId = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: AppStrings.t('add_vendor'),
                        onPressed: _quickAddVendor,
                        icon: const Icon(Icons.person_add),
                      ),
                    ],
                  ),
                  if (_paymentType != 'CASH') ...[
                    const SizedBox(height: 8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(AppStrings.t('payment_due_by'), style: const TextStyle(fontSize: 13)),
                      subtitle: Text(_dueDate != null ? formatDay(_dueDate!.toIso8601String()) : 'Not set'),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          if (_dueDate != null)
                            IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () => setState(() => _dueDate = null),
                            ),
                          IconButton(
                            icon: const Icon(Icons.calendar_today, size: 18),
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _dueDate ?? _saleDate.add(const Duration(days: 30)),
                                firstDate: _saleDate,
                                lastDate: DateTime(2035),
                              );
                              if (picked != null) setState(() => _dueDate = picked);
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_paymentType == 'PARTIAL') ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _paidCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(labelText: AppStrings.t('amount_collected_now')),
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
                  FilledButton(
                    onPressed: _saving ? null : _checkout,
                    child: _saving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(AppStrings.t('complete_sale')),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthlyTrendChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  const _MonthlyTrendChart({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Center(child: Text(AppStrings.t('no_sales_recorded_yet')));
    }
    final spots = <FlSpot>[];
    for (var i = 0; i < data.length; i++) {
      final total = (data[i]['total'] as num?)?.toDouble() ?? 0;
      spots.add(FlSpot(i.toDouble(), total));
    }
    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: (data.length / 5).clamp(1, data.length).toDouble(),
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= data.length) return const SizedBox.shrink();
                final day = data[i]['day'] as String? ?? '';
                final label = day.length >= 10 ? day.substring(8, 10) : day;
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(label, style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: Theme.of(context).colorScheme.primary,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
            ),
          ),
        ],
      ),
    );
  }
}
