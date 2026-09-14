import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import '../db/db_helper.dart';
import '../utils/csv_helper.dart';

class DataSyncScreen extends StatefulWidget {
  const DataSyncScreen({super.key});

  @override
  State<DataSyncScreen> createState() => _DataSyncScreenState();
}

class _DataSyncScreenState extends State<DataSyncScreen> {
  final _db = DBHelper.instance;
  bool _busy = false;
  String? _status;

  Future<void> _runBusy(Future<void> Function() task) async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await task();
    } catch (e) {
      setState(() => _status = 'Something went wrong: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<File> _writeCsv(Directory dir, String filename, String content) async {
    final file = File('${dir.path}/$filename');
    await file.writeAsString(content);
    return file;
  }

  Future<void> _exportAll() async {
    await _runBusy(() async {
      final dir = await getTemporaryDirectory();
      final files = <XFile>[];

      final products = await _db.getProducts();
      final suppliers = await _db.getSuppliers();
      final supplierNameById = {for (final s in suppliers) s['id'] as String: s['name'] as String};
      files.add(XFile((await _writeCsv(
        dir,
        'products.csv',
        encodeCsv(
          ['name', 'category', 'subcategory', 'unit', 'quantity', 'reorder_level', 'cost_price', 'selling_price', 'supplier_name'],
          products
              .map((p) => [
                    p['name'],
                    p['category'],
                    p['subcategory'],
                    p['unit'],
                    p['quantity'],
                    p['reorder_level'],
                    p['cost_price'],
                    p['selling_price'],
                    p['supplier_id'] != null ? (supplierNameById[p['supplier_id']] ?? '') : '',
                  ])
              .toList(),
        ),
      )).path));

      final vendors = await _db.getVendors();
      files.add(XFile((await _writeCsv(
        dir,
        'vendors.csv',
        encodeCsv(
          ['name', 'phone', 'address', 'opening_balance'],
          vendors.map((v) => [v['name'], v['phone'], v['address'], v['opening_balance']]).toList(),
        ),
      )).path));

      files.add(XFile((await _writeCsv(
        dir,
        'suppliers.csv',
        encodeCsv(
          ['name', 'phone', 'address', 'opening_balance'],
          suppliers.map((s) => [s['name'], s['phone'], s['address'], s['opening_balance']]).toList(),
        ),
      )).path));

      final sales = await _db.getAllSalesFlat();
      files.add(XFile((await _writeCsv(
        dir,
        'sales.csv',
        encodeCsv(
          ['id', 'date', 'status', 'payment_type', 'vendor_name', 'subtotal', 'discount', 'total_amount', 'paid_amount', 'notes'],
          sales
              .map((s) => [
                    s['id'], s['date'], s['status'] ?? 'confirmed', s['payment_type'], s['vendor_name'] ?? '',
                    s['subtotal'], s['discount'], s['total_amount'], s['paid_amount'], s['notes']
                  ])
              .toList(),
        ),
      )).path));

      final saleItems = await _db.getAllSaleItemsFlat();
      files.add(XFile((await _writeCsv(
        dir,
        'sale_items.csv',
        encodeCsv(
          ['sale_id', 'sale_date', 'status', 'product_name', 'quantity', 'unit_price', 'subtotal'],
          saleItems
              .map((i) => [i['sale_id'], i['sale_date'], i['status'] ?? 'confirmed', i['product_name'], i['quantity'], i['unit_price'], i['subtotal']])
              .toList(),
        ),
      )).path));

      final creditTxns = await _db.getAllCreditTransactions();
      files.add(XFile((await _writeCsv(
        dir,
        'credit_transactions.csv',
        encodeCsv(
          ['date', 'vendor_name', 'type', 'amount', 'balance_after', 'notes'],
          creditTxns
              .map((t) => [t['date'], t['vendor_name'], t['type'], t['amount'], t['balance_after'], t['notes']])
              .toList(),
        ),
      )).path));

      final supplierTxns = await _db.getAllSupplierTransactions();
      files.add(XFile((await _writeCsv(
        dir,
        'supplier_transactions.csv',
        encodeCsv(
          ['date', 'supplier_name', 'type', 'amount', 'balance_after', 'notes'],
          supplierTxns
              .map((t) => [t['date'], t['supplier_name'], t['type'], t['amount'], t['balance_after'], t['notes']])
              .toList(),
        ),
      )).path));

      final stockMoves = await _db.getAllStockMovements();
      files.add(XFile((await _writeCsv(
        dir,
        'stock_movements.csv',
        encodeCsv(
          ['date', 'product_name', 'type', 'quantity', 'reason', 'notes'],
          stockMoves
              .map((m) => [m['date'], m['product_name'], m['type'], m['quantity'], m['reason'], m['notes']])
              .toList(),
        ),
      )).path));

      final today = DateTime.now().toIso8601String().substring(0, 10);
      await Share.shareXFiles(files, subject: 'Madhura Agro Traders — data export $today');
      setState(() => _status = 'Export ready — pick where to send it (WhatsApp, email, Drive, etc.)');
    });
  }

  Future<String?> _pickCsvContent() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (result == null || result.files.single.path == null) return null;
    return File(result.files.single.path!).readAsString();
  }

  Future<void> _importProducts() async {
    await _runBusy(() async {
      final content = await _pickCsvContent();
      if (content == null) return;
      final rows = csvRowsToMaps(parseCsv(content));
      final suppliers = await _db.getSuppliers();
      final supplierIdByName = {
        for (final s in suppliers) (s['name'] as String).toLowerCase(): s['id'] as String
      };
      var updated = 0, added = 0, skipped = 0;
      for (final row in rows) {
        final name = row['name'] ?? '';
        if (name.isEmpty) {
          skipped++;
          continue;
        }
        final supplierName = (row['supplier_name'] ?? '').toLowerCase();
        final wasUpdate = await _db.upsertProductByName({
          'name': name,
          'category': row['category'] ?? '',
          'subcategory': row['subcategory'] ?? '',
          'unit': row['unit']?.isNotEmpty == true ? row['unit'] : 'Nos',
          'quantity': double.tryParse(row['quantity'] ?? '') ?? 0,
          'reorder_level': double.tryParse(row['reorder_level'] ?? '') ?? 0,
          'cost_price': double.tryParse(row['cost_price'] ?? '') ?? 0,
          'selling_price': double.tryParse(row['selling_price'] ?? '') ?? 0,
          'supplier_id': supplierName.isNotEmpty ? supplierIdByName[supplierName] : null,
        });
        wasUpdate ? updated++ : added++;
      }
      setState(() => _status =
          'Products: $added added, $updated updated${skipped > 0 ? ', $skipped skipped (no name)' : ''}.');
    });
  }

  Future<void> _importVendors() async {
    await _runBusy(() async {
      final content = await _pickCsvContent();
      if (content == null) return;
      final rows = csvRowsToMaps(parseCsv(content));
      var updated = 0, added = 0, skipped = 0;
      for (final row in rows) {
        final name = row['name'] ?? '';
        if (name.isEmpty) {
          skipped++;
          continue;
        }
        final wasUpdate = await _db.upsertVendorByName(
          name: name,
          phone: row['phone'],
          address: row['address'],
        );
        wasUpdate ? updated++ : added++;
      }
      setState(() => _status =
          'Vendors: $added added, $updated updated${skipped > 0 ? ', $skipped skipped (no name)' : ''}. Opening balances are not changed by import.');
    });
  }

  Future<void> _importSuppliers() async {
    await _runBusy(() async {
      final content = await _pickCsvContent();
      if (content == null) return;
      final rows = csvRowsToMaps(parseCsv(content));
      var updated = 0, added = 0, skipped = 0;
      for (final row in rows) {
        final name = row['name'] ?? '';
        if (name.isEmpty) {
          skipped++;
          continue;
        }
        final wasUpdate = await _db.upsertSupplierByName(
          name: name,
          phone: row['phone'],
          address: row['address'],
        );
        wasUpdate ? updated++ : added++;
      }
      setState(() => _status =
          'Suppliers: $added added, $updated updated${skipped > 0 ? ', $skipped skipped (no name)' : ''}. Opening balances are not changed by import.');
    });
  }

  Future<void> _importVendorCreditHistory() async {
    await _runBusy(() async {
      final content = await _pickCsvContent();
      if (content == null) return;
      final rows = csvRowsToMaps(parseCsv(content));
      final parsed = rows
          .map((r) => {
                'vendor_name': r['vendor_name'] ?? '',
                'type': r['type'] ?? '',
                'amount': double.tryParse(r['amount'] ?? '') ?? 0.0,
                'date': r['date'] ?? '',
                'notes': r['notes'] ?? '',
              })
          .toList();
      final result = await _db.importVendorCreditHistory(parsed);
      setState(() => _status =
          'Vendor credit history: ${result['imported']} entries imported, ${result['skipped']} skipped '
          '(vendor not found by name, or missing/invalid date, amount, or type).');
    });
  }

  Future<void> _importSupplierTransactionHistory() async {
    await _runBusy(() async {
      final content = await _pickCsvContent();
      if (content == null) return;
      final rows = csvRowsToMaps(parseCsv(content));
      final parsed = rows
          .map((r) => {
                'supplier_name': r['supplier_name'] ?? '',
                'type': r['type'] ?? '',
                'amount': double.tryParse(r['amount'] ?? '') ?? 0.0,
                'date': r['date'] ?? '',
                'notes': r['notes'] ?? '',
              })
          .toList();
      final result = await _db.importSupplierTransactionHistory(parsed);
      setState(() => _status =
          'Supplier transaction history: ${result['imported']} entries imported, ${result['skipped']} skipped '
          '(supplier not found by name, or missing/invalid date, amount, or type).');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Data Export & Import')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Colors.blue.shade50,
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'This is for sharing data between two phones — it is not live syncing. '
                'Each phone keeps its own copy of the data; export here and send the files '
                'to the other phone, then import there to bring the changes in.',
                style: TextStyle(fontSize: 12.5),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Export', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Creates a CSV file for every part of the app (products, vendors, suppliers, '
            'sales, credit and supplier ledgers, stock history) and opens the share menu '
            'so you can send them via WhatsApp, email, Google Drive, etc.',
            style: TextStyle(fontSize: 12.5, color: Colors.black54),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _busy ? null : _exportAll,
            icon: const Icon(Icons.upload_file),
            label: const Text('Export All Data (CSV)'),
          ),
          const SizedBox(height: 28),
          Text('Import', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Products, vendors, and suppliers update or add records by name. Vendor/supplier '
            'credit history can also be imported — each row (date, name, type, amount, notes) '
            'is replayed the same safe way as entering it by hand, so balances stay correct. '
            'Sales themselves are still export-only, since importing one back would double-count '
            'stock.',
            style: TextStyle(fontSize: 12.5, color: Colors.black54),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _importProducts,
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text('Import Products CSV'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _importVendors,
            icon: const Icon(Icons.people_outline),
            label: const Text('Import Vendors CSV'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _importSuppliers,
            icon: const Icon(Icons.local_shipping_outlined),
            label: const Text('Import Suppliers CSV'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _importVendorCreditHistory,
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('Import Vendor Credit History CSV'),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              'Columns: date, vendor_name, type (CREDIT or PAYMENT), amount, notes — '
              'same shape as the exported credit_transactions.csv.',
              style: TextStyle(fontSize: 11, color: Colors.black45),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _importSupplierTransactionHistory,
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('Import Supplier Transaction History CSV'),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              'Columns: date, supplier_name, type (PURCHASE or PAYMENT), amount, notes.',
              style: TextStyle(fontSize: 11, color: Colors.black45),
            ),
          ),
          if (_busy) ...[
            const SizedBox(height: 20),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_status != null) ...[
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_status!, style: const TextStyle(fontSize: 13)),
            ),
          ],
        ],
      ),
    );
  }
}
