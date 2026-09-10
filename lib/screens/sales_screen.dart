import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
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
  List<Map<String, dynamic>> _monthlyTrend = [];
  bool _todayOnly = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final filter = _todayOnly ? DateTime.now().toIso8601String().substring(0, 10) : null;
    final sales = await _db.getSales(dateFilter: filter);
    final trend = await _db.getSalesSummaryByDay(days: 30);
    setState(() {
      _sales = sales;
      _monthlyTrend = trend.reversed.toList();
    });
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
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: const Text('Monthly Sales Trend', style: TextStyle(fontSize: 14)),
              subtitle: const Text('Last 30 days', style: TextStyle(fontSize: 11)),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: SizedBox(height: 160, child: _MonthlyTrendChart(data: _monthlyTrend)),
                ),
              ],
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
        title: const Text('Add Vendor (Credit Customer)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name'), autofocus: true),
            TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Phone')),
            TextField(controller: placeCtrl, decoration: const InputDecoration(labelText: 'Place')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
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
      appBar: AppBar(
        title: const Text('New Sale'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
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
                    decoration: const InputDecoration(
                      labelText: 'Type a product name to search',
                      prefixIcon: Icon(Icons.search),
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
                          return ListTile(
                            dense: true,
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
                        ? const Center(child: Text('Search a product above and tap it to add'))
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
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: _vendorId,
                            decoration: const InputDecoration(labelText: 'Vendor (credit customer)'),
                            items: _vendors
                                .map((v) =>
                                    DropdownMenuItem(value: v['id'] as int, child: Text(v['name'] as String)))
                                .toList(),
                            onChanged: (v) => setState(() => _vendorId = v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Add new vendor',
                          onPressed: _quickAddVendor,
                          icon: const Icon(Icons.person_add),
                        ),
                      ],
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

class _MonthlyTrendChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  const _MonthlyTrendChart({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Center(child: Text('No sales recorded yet.'));
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
