import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import '../db/db_helper.dart';
import '../utils/csv_helper.dart';
import '../utils/app_strings.dart';
import '../utils/app_theme.dart';

class DataSyncScreen extends StatefulWidget {
  const DataSyncScreen({super.key});

  @override
  State<DataSyncScreen> createState() => _DataSyncScreenState();
}

class _DataSyncScreenState extends State<DataSyncScreen> {
  final _db = DBHelper.instance;
  bool _busy = false;
  String? _status;
  bool _statusIsError = false;

  Future<void> _runBusy(Future<void> Function() task) async {
    setState(() {
      _busy = true;
      _status = null;
      _statusIsError = false;
    });
    try {
      await task();
    } catch (e) {
      setState(() {
        _status = 'Something went wrong: $e';
        _statusIsError = true;
      });
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
      backgroundColor: AppTheme.scaffold,
      appBar: AppBar(title: Text(AppStrings.t('data_export_import'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppCard(
            background: AppTheme.primaryLight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const IconBadge(icon: Icons.info_outline, color: AppTheme.primary, size: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(AppStrings.t('sync_explanation'), style: const TextStyle(fontSize: 12.5, height: 1.4)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const IconBadge(icon: Icons.upload_file, color: AppTheme.revenue, size: 18),
                    const SizedBox(width: 10),
                    Text(AppStrings.t('export'),
                        style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(AppStrings.t('export_explanation'), style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _exportAll,
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.revenue),
                    icon: const Icon(Icons.upload_file),
                    label: Text(AppStrings.t('export_all_data')),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const IconBadge(icon: Icons.download, color: AppTheme.profit, size: 18),
                    const SizedBox(width: 10),
                    Text(AppStrings.t('import'),
                        style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(AppStrings.t('import_explanation'), style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _importProducts,
                  icon: const Icon(Icons.inventory_2_outlined, color: AppTheme.accent),
                  label: Text(AppStrings.t('import_products_csv')),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _importVendors,
                  icon: const Icon(Icons.people_outline, color: AppTheme.danger),
                  label: Text(AppStrings.t('import_vendors_csv')),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _importSuppliers,
                  icon: const Icon(Icons.local_shipping_outlined, color: AppTheme.cost),
                  label: Text(AppStrings.t('import_suppliers_csv')),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _importVendorCreditHistory,
                  icon: const Icon(Icons.receipt_long_outlined, color: AppTheme.danger),
                  label: Text(AppStrings.t('import_vendor_credit_history')),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 4, top: 4),
                  child: Text(
                    AppStrings.t('vendor_credit_csv_columns'),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _importSupplierTransactionHistory,
                  icon: const Icon(Icons.receipt_long_outlined, color: AppTheme.cost),
                  label: Text(AppStrings.t('import_supplier_txn_history')),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 4, top: 4),
                  child: Text(
                    AppStrings.t('supplier_txn_csv_columns'),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ),
              ],
            ),
          ),
          if (_busy) ...[
            const SizedBox(height: 20),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_status != null) ...[
            const SizedBox(height: 16),
            AppCard(
              background: (_statusIsError ? AppTheme.danger : AppTheme.success).withOpacity(0.08),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconBadge(
                    icon: _statusIsError ? Icons.error_outline : Icons.check_circle_outline,
                    color: _statusIsError ? AppTheme.danger : AppTheme.success,
                    size: 18,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_status!, style: const TextStyle(fontSize: 13))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
