import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Singleton SQLite helper for APSDK.
/// Handles schema creation and all read/write access to the store's data.
class DBHelper {
  DBHelper._internal();
  static final DBHelper instance = DBHelper._internal();

  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'apsdk.db');
    return openDatabase(
      path,
      version: 2,
      onCreate: _createSchema,
      // NOTE: this is a destructive upgrade (drops and recreates everything).
      // Fine while the app is still in development / not yet holding real
      // store data. Before a production release, replace this with proper
      // column-by-column ALTER TABLE migrations so upgrades don't wipe data.
      onUpgrade: (db, oldVersion, newVersion) async {
        const tables = [
          'sale_items',
          'sales',
          'credit_transactions',
          'vendors',
          'stock_movements',
          'supplier_purchase_items',
          'supplier_transactions',
          'products',
          'suppliers',
        ];
        for (final t in tables) {
          await db.execute('DROP TABLE IF EXISTS $t');
        }
        await _createSchema(db, newVersion);
      },
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
    );
  }

  Future<void> _createSchema(Database db, int version) async {
    // Suppliers who supply stock to the store
    await db.execute('''
      CREATE TABLE suppliers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT,
        opening_balance REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    // Ledger of purchases from / payments to suppliers
    await db.execute('''
      CREATE TABLE supplier_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplier_id INTEGER NOT NULL,
        date TEXT NOT NULL,
        type TEXT NOT NULL, -- PURCHASE or PAYMENT
        amount REAL NOT NULL,
        balance_after REAL NOT NULL,
        notes TEXT,
        FOREIGN KEY (supplier_id) REFERENCES suppliers (id) ON DELETE CASCADE
      )
    ''');

    // Line items for a PURCHASE-type supplier transaction: which products,
    // how much, and at what cost — so a purchase isn't just a lump sum.
    await db.execute('''
      CREATE TABLE supplier_purchase_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplier_transaction_id INTEGER NOT NULL,
        product_id INTEGER,
        product_name TEXT NOT NULL,
        quantity REAL NOT NULL,
        unit_cost REAL NOT NULL,
        subtotal REAL NOT NULL,
        FOREIGN KEY (supplier_transaction_id) REFERENCES supplier_transactions (id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE SET NULL
      )
    ''');

    // Products in inventory
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        category TEXT,
        subcategory TEXT,
        unit TEXT NOT NULL DEFAULT 'Nos',
        quantity REAL NOT NULL DEFAULT 0,
        reorder_level REAL NOT NULL DEFAULT 0,
        cost_price REAL NOT NULL DEFAULT 0,
        selling_price REAL NOT NULL DEFAULT 0,
        supplier_id INTEGER,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (supplier_id) REFERENCES suppliers (id) ON DELETE SET NULL
      )
    ''');

    // Audit trail of every stock change (sale, purchase, manual adjustment)
    await db.execute('''
      CREATE TABLE stock_movements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        date TEXT NOT NULL,
        type TEXT NOT NULL, -- IN or OUT
        quantity REAL NOT NULL,
        reason TEXT NOT NULL, -- SALE, PURCHASE, ADJUSTMENT
        notes TEXT,
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
      )
    ''');

    // Credit customers ("vendors" in store-owner terminology)
    await db.execute('''
      CREATE TABLE vendors (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT,
        opening_balance REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    // Ledger of credit given / payments collected per vendor
    await db.execute('''
      CREATE TABLE credit_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        vendor_id INTEGER NOT NULL,
        date TEXT NOT NULL,
        type TEXT NOT NULL, -- CREDIT or PAYMENT
        amount REAL NOT NULL,
        balance_after REAL NOT NULL,
        notes TEXT,
        sale_id INTEGER,
        FOREIGN KEY (vendor_id) REFERENCES vendors (id) ON DELETE CASCADE,
        FOREIGN KEY (sale_id) REFERENCES sales (id) ON DELETE SET NULL
      )
    ''');

    // Daily sales header
    await db.execute('''
      CREATE TABLE sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        subtotal REAL NOT NULL,
        discount REAL NOT NULL DEFAULT 0,
        total_amount REAL NOT NULL,
        payment_type TEXT NOT NULL, -- CASH, CREDIT, PARTIAL
        vendor_id INTEGER,
        paid_amount REAL NOT NULL DEFAULT 0,
        notes TEXT,
        FOREIGN KEY (vendor_id) REFERENCES vendors (id) ON DELETE SET NULL
      )
    ''');

    // Line items per sale
    await db.execute('''
      CREATE TABLE sale_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL,
        product_id INTEGER,
        product_name TEXT NOT NULL,
        quantity REAL NOT NULL,
        unit_price REAL NOT NULL,
        subtotal REAL NOT NULL,
        FOREIGN KEY (sale_id) REFERENCES sales (id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE SET NULL
      )
    ''');

    await db.execute('CREATE INDEX idx_sales_date ON sales(date)');
    await db.execute('CREATE INDEX idx_credit_vendor ON credit_transactions(vendor_id, date)');
    await db.execute('CREATE INDEX idx_supplier_txn ON supplier_transactions(supplier_id, date)');
    await db.execute('CREATE INDEX idx_stock_product ON stock_movements(product_id, date)');
    await db.execute('CREATE INDEX idx_purchase_items ON supplier_purchase_items(supplier_transaction_id)');

    await _seedInitialInventory(db);
  }

  /// One-time seed of the store's existing inventory (imported from the
  /// owner's spreadsheet on 01-Sep-2026) so the app isn't empty on first
  /// run. Runs once when the database is first created (and again on a
  /// dev-time schema upgrade, since that currently rebuilds the tables —
  /// see the onUpgrade note above). Cost price wasn't in the source sheet,
  /// so it's left at 0 for the incharge to fill in; selling price and
  /// current stock are taken directly from the sheet.
  Future<void> _seedInitialInventory(Database db) async {
    final now = DateTime.now().toIso8601String();
    final items = <Map<String, dynamic>>[
      {'name': 'Ragi (Finger millet)', 'category': 'Human', 'subcategory': 'Millets & Grams', 'unit': 'Kgs', 'quantity': 34.0, 'reorder_level': 10.0, 'cost_price': 0.0, 'selling_price': 50.0},
      {'name': 'Kambu (Pearl millet IR8)', 'category': 'Human', 'subcategory': 'Millets & Grams', 'unit': 'Kgs', 'quantity': 50.0, 'reorder_level': 10.0, 'cost_price': 0.0, 'selling_price': 50.0},
      {'name': 'Kambu (Pearl millet traditional)', 'category': 'Human', 'subcategory': 'Millets & Grams', 'unit': 'Kgs', 'quantity': 30.0, 'reorder_level': 10.0, 'cost_price': 0.0, 'selling_price': 60.0},
      {'name': 'Sorghum (white)', 'category': 'Human', 'subcategory': 'Millets & Grams', 'unit': 'Kgs', 'quantity': 50.0, 'reorder_level': 10.0, 'cost_price': 0.0, 'selling_price': 70.0},
      {'name': 'Sorghum (Red)', 'category': 'Human', 'subcategory': 'Millets & Grams', 'unit': 'Kgs', 'quantity': 50.0, 'reorder_level': 10.0, 'cost_price': 0.0, 'selling_price': 80.0},
      {'name': 'Thinai (Fox tail millet)', 'category': 'Human', 'subcategory': 'Millets & Grams', 'unit': 'Kgs', 'quantity': 50.0, 'reorder_level': 10.0, 'cost_price': 0.0, 'selling_price': 90.0},
      {'name': 'Mochai (Bean)', 'category': 'Human', 'subcategory': 'Millets & Grams', 'unit': 'Kgs', 'quantity': 50.0, 'reorder_level': 10.0, 'cost_price': 0.0, 'selling_price': 0.0},
      {'name': 'Kollu (horsegram)', 'category': 'Human', 'subcategory': 'Millets & Grams', 'unit': 'Kgs', 'quantity': 50.0, 'reorder_level': 10.0, 'cost_price': 0.0, 'selling_price': 100.0},
      {'name': 'PBT', 'category': 'Human', 'subcategory': 'Rice', 'unit': 'Nos', 'quantity': 9.0, 'reorder_level': 5.0, 'cost_price': 0.0, 'selling_price': 800.0},
      {'name': 'RNR', 'category': 'Human', 'subcategory': 'Rice', 'unit': 'Nos', 'quantity': 10.0, 'reorder_level': 5.0, 'cost_price': 0.0, 'selling_price': 0.0},
      {'name': 'Ponni', 'category': 'Human', 'subcategory': 'Rice', 'unit': 'Nos', 'quantity': 10.0, 'reorder_level': 5.0, 'cost_price': 0.0, 'selling_price': 0.0},
      {'name': 'Basmati', 'category': 'Human', 'subcategory': 'Rice', 'unit': 'Nos', 'quantity': 10.0, 'reorder_level': 5.0, 'cost_price': 0.0, 'selling_price': 0.0},
      {'name': 'Idly rice', 'category': 'Human', 'subcategory': 'Rice', 'unit': 'Nos', 'quantity': 10.0, 'reorder_level': 5.0, 'cost_price': 0.0, 'selling_price': 0.0},
      {'name': 'Groundnut seedcake- Chekku', 'category': 'Cattle', 'subcategory': 'Oil cakes', 'unit': 'Kgs', 'quantity': 70.0, 'reorder_level': 14.0, 'cost_price': 0.0, 'selling_price': 0.0},
      {'name': 'Groundnut seedcake- Lottery', 'category': 'Cattle', 'subcategory': 'Oil cakes', 'unit': 'Kgs', 'quantity': 70.0, 'reorder_level': 14.0, 'cost_price': 0.0, 'selling_price': 0.0},
      {'name': 'Groundnut seedcake- Explorer', 'category': 'Cattle', 'subcategory': 'Oil cakes', 'unit': 'Kgs', 'quantity': 70.0, 'reorder_level': 14.0, 'cost_price': 0.0, 'selling_price': 0.0},
      {'name': 'Sesame seedcake', 'category': 'Cattle', 'subcategory': 'Oil cakes', 'unit': 'Kgs', 'quantity': 70.0, 'reorder_level': 14.0, 'cost_price': 0.0, 'selling_price': 0.0},
      {'name': 'cotton seedcake', 'category': 'Cattle', 'subcategory': 'Oil cakes', 'unit': 'Kgs', 'quantity': 70.0, 'reorder_level': 14.0, 'cost_price': 0.0, 'selling_price': 0.0},
      {'name': 'Toor dal husk', 'category': 'Cattle', 'subcategory': 'Husks', 'unit': 'Kgs', 'quantity': 30.0, 'reorder_level': 6.0, 'cost_price': 0.0, 'selling_price': 0.0},
      {'name': 'Balck gram husk', 'category': 'Cattle', 'subcategory': 'Husks', 'unit': 'Kgs', 'quantity': 30.0, 'reorder_level': 6.0, 'cost_price': 0.0, 'selling_price': 0.0},
      {'name': 'Theevanam', 'category': 'Cattle', 'subcategory': 'Pellets', 'unit': 'Kgs', 'quantity': 25.0, 'reorder_level': 5.0, 'cost_price': 0.0, 'selling_price': 0.0},
      {'name': 'Wheat bran', 'category': 'Cattle', 'subcategory': 'Bran', 'unit': 'Kgs', 'quantity': 20.0, 'reorder_level': 5.0, 'cost_price': 0.0, 'selling_price': 0.0},
      {'name': 'Rice bran ordinary bag', 'category': 'Cattle', 'subcategory': 'Bran', 'unit': 'Nos', 'quantity': 49.0, 'reorder_level': 10.0, 'cost_price': 0.0, 'selling_price': 700.0},
      {'name': 'Rice bran karuka bag', 'category': 'Cattle', 'subcategory': 'Bran', 'unit': 'Nos', 'quantity': 47.0, 'reorder_level': 10.0, 'cost_price': 0.0, 'selling_price': 800.0},
      {'name': 'KNC Special 50kg', 'category': 'Cattle', 'subcategory': 'Pellets', 'unit': 'Nos', 'quantity': 50.0, 'reorder_level': 10.0, 'cost_price': 0.0, 'selling_price': 0.0},
      {'name': 'KNC Bypass 50kg', 'category': 'Cattle', 'subcategory': 'Pellets', 'unit': 'Nos', 'quantity': 50.0, 'reorder_level': 10.0, 'cost_price': 0.0, 'selling_price': 0.0},
      {'name': 'KNC Probest 50kg', 'category': 'Cattle', 'subcategory': 'Pellets', 'unit': 'Nos', 'quantity': 50.0, 'reorder_level': 10.0, 'cost_price': 0.0, 'selling_price': 0.0},
      {'name': 'SKM Popular 50kg', 'category': 'Cattle', 'subcategory': 'Pellets', 'unit': 'Nos', 'quantity': 50.0, 'reorder_level': 10.0, 'cost_price': 0.0, 'selling_price': 0.0},
      {'name': 'KNC Special 20kg', 'category': 'Cattle', 'subcategory': 'Pellets', 'unit': 'Nos', 'quantity': 50.0, 'reorder_level': 10.0, 'cost_price': 0.0, 'selling_price': 0.0},
      {'name': 'KNC Bypass 20kg', 'category': 'Cattle', 'subcategory': 'Pellets', 'unit': 'Nos', 'quantity': 2.0, 'reorder_level': 5.0, 'cost_price': 0.0, 'selling_price': 0.0},
      {'name': 'KNC Poultry 50kg', 'category': 'Cattle', 'subcategory': 'Pellets', 'unit': 'Nos', 'quantity': 1.0, 'reorder_level': 5.0, 'cost_price': 0.0, 'selling_price': 1000.0},
    ];

    final batch = db.batch();
    for (final item in items) {
      batch.insert('products', {
        ...item,
        'supplier_id': null,
        'created_at': now,
        'updated_at': now,
      });
    }
    await batch.commit(noResult: true);
  }

  // ---------------- PRODUCTS / INVENTORY ----------------

  Future<int> insertProduct(Map<String, dynamic> product) async {
    final db = await database;
    return db.insert('products', product);
  }

  Future<int> updateProduct(int id, Map<String, dynamic> product) async {
    final db = await database;
    return db.update('products', product, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteProduct(int id) async {
    final db = await database;
    return db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getProducts({String? search}) async {
    final db = await database;
    if (search != null && search.isNotEmpty) {
      return db.query('products',
          where: 'name LIKE ?', whereArgs: ['%$search%'], orderBy: 'name');
    }
    return db.query('products', orderBy: 'name');
  }

  Future<List<Map<String, dynamic>>> getLowStockProducts() async {
    final db = await database;
    return db.rawQuery(
        'SELECT * FROM products WHERE quantity <= reorder_level ORDER BY quantity ASC');
  }

  /// Adjusts a product's stock and logs the movement. deltaQty is positive
  /// for stock IN (purchase, correction) or negative for stock OUT (sale).
  Future<void> adjustStock({
    required int productId,
    required double deltaQty,
    required String reason, // SALE, PURCHASE, ADJUSTMENT
    String? notes,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows =
          await txn.query('products', where: 'id = ?', whereArgs: [productId]);
      if (rows.isEmpty) return;
      final current = (rows.first['quantity'] as num).toDouble();
      final updated = current + deltaQty;
      await txn.update(
        'products',
        {'quantity': updated, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [productId],
      );
      await txn.insert('stock_movements', {
        'product_id': productId,
        'date': DateTime.now().toIso8601String(),
        'type': deltaQty >= 0 ? 'IN' : 'OUT',
        'quantity': deltaQty.abs(),
        'reason': reason,
        'notes': notes,
      });
    });
  }

  Future<List<Map<String, dynamic>>> getStockHistory(int productId) async {
    final db = await database;
    return db.query('stock_movements',
        where: 'product_id = ?',
        whereArgs: [productId],
        orderBy: 'date DESC');
  }

  // ---------------- SUPPLIERS ----------------

  Future<int> insertSupplier(Map<String, dynamic> supplier) async {
    final db = await database;
    return db.insert('suppliers', supplier);
  }

  Future<List<Map<String, dynamic>>> getSuppliers() async {
    final db = await database;
    return db.query('suppliers', orderBy: 'name');
  }

  Future<double> getSupplierBalance(int supplierId) async {
    final db = await database;
    final supplier = await db
        .query('suppliers', where: 'id = ?', whereArgs: [supplierId]);
    double balance =
        supplier.isNotEmpty ? (supplier.first['opening_balance'] as num).toDouble() : 0;
    final txns = await db.rawQuery(
        'SELECT balance_after FROM supplier_transactions WHERE supplier_id = ? ORDER BY id DESC LIMIT 1',
        [supplierId]);
    if (txns.isNotEmpty) balance = (txns.first['balance_after'] as num).toDouble();
    return balance;
  }

  /// Records a purchase (increases what the store owes) or a payment
  /// (decreases what the store owes) and keeps a running balance.
  Future<void> addSupplierTransaction({
    required int supplierId,
    required String type, // PURCHASE or PAYMENT
    required double amount,
    String? notes,
  }) async {
    final db = await database;
    final currentBalance = await getSupplierBalance(supplierId);
    final newBalance =
        type == 'PURCHASE' ? currentBalance + amount : currentBalance - amount;
    await db.insert('supplier_transactions', {
      'supplier_id': supplierId,
      'date': DateTime.now().toIso8601String(),
      'type': type,
      'amount': amount,
      'balance_after': newBalance,
      'notes': notes,
    });
  }

  Future<List<Map<String, dynamic>>> getSupplierTransactions(
      int supplierId) async {
    final db = await database;
    return db.query('supplier_transactions',
        where: 'supplier_id = ?', whereArgs: [supplierId], orderBy: 'date DESC');
  }

  /// Records a stock purchase made up of specific products, quantities and
  /// costs (rather than a single lump amount). Also receives the stock into
  /// inventory (adjusts product quantity + logs a stock movement) and
  /// updates each product's cost price to the latest cost paid.
  Future<int> addSupplierPurchase({
    required int supplierId,
    required List<Map<String, dynamic>> items, // product_id, product_name, quantity, unit_cost
    String? notes,
  }) async {
    final db = await database;
    final amount = items.fold<double>(
        0, (sum, i) => sum + (i['quantity'] as num) * (i['unit_cost'] as num));
    final currentBalance = await getSupplierBalance(supplierId);
    final newBalance = currentBalance + amount;

    late int txnId;
    await db.transaction((txn) async {
      txnId = await txn.insert('supplier_transactions', {
        'supplier_id': supplierId,
        'date': DateTime.now().toIso8601String(),
        'type': 'PURCHASE',
        'amount': amount,
        'balance_after': newBalance,
        'notes': notes,
      });

      for (final item in items) {
        final qty = (item['quantity'] as num).toDouble();
        final cost = (item['unit_cost'] as num).toDouble();
        await txn.insert('supplier_purchase_items', {
          'supplier_transaction_id': txnId,
          'product_id': item['product_id'],
          'product_name': item['product_name'],
          'quantity': qty,
          'unit_cost': cost,
          'subtotal': qty * cost,
        });

        if (item['product_id'] != null) {
          final pid = item['product_id'] as int;
          final rows = await txn.query('products', where: 'id = ?', whereArgs: [pid]);
          if (rows.isNotEmpty) {
            final current = (rows.first['quantity'] as num).toDouble();
            await txn.update(
              'products',
              {
                'quantity': current + qty,
                'cost_price': cost,
                'updated_at': DateTime.now().toIso8601String(),
              },
              where: 'id = ?',
              whereArgs: [pid],
            );
            await txn.insert('stock_movements', {
              'product_id': pid,
              'date': DateTime.now().toIso8601String(),
              'type': 'IN',
              'quantity': qty,
              'reason': 'PURCHASE',
              'notes': 'Purchase #$txnId',
            });
          }
        }
      }
    });

    return txnId;
  }

  Future<List<Map<String, dynamic>>> getSupplierPurchaseItems(int supplierTransactionId) async {
    final db = await database;
    return db.query('supplier_purchase_items',
        where: 'supplier_transaction_id = ?', whereArgs: [supplierTransactionId]);
  }

  // ---------------- VENDORS (CREDIT CUSTOMERS) ----------------

  Future<int> insertVendor(Map<String, dynamic> vendor) async {
    final db = await database;
    return db.insert('vendors', vendor);
  }

  Future<List<Map<String, dynamic>>> getVendors() async {
    final db = await database;
    return db.query('vendors', orderBy: 'name');
  }

  Future<double> getVendorBalance(int vendorId) async {
    final db = await database;
    final vendor = await db.query('vendors', where: 'id = ?', whereArgs: [vendorId]);
    double balance =
        vendor.isNotEmpty ? (vendor.first['opening_balance'] as num).toDouble() : 0;
    final txns = await db.rawQuery(
        'SELECT balance_after FROM credit_transactions WHERE vendor_id = ? ORDER BY id DESC LIMIT 1',
        [vendorId]);
    if (txns.isNotEmpty) balance = (txns.first['balance_after'] as num).toDouble();
    return balance;
  }

  /// Records credit given (sale on credit) or a payment/collection from a
  /// vendor and keeps a running balance, date-wise.
  Future<void> addCreditTransaction({
    required int vendorId,
    required String type, // CREDIT or PAYMENT
    required double amount,
    String? notes,
    int? saleId,
  }) async {
    final db = await database;
    final currentBalance = await getVendorBalance(vendorId);
    final newBalance =
        type == 'CREDIT' ? currentBalance + amount : currentBalance - amount;
    await db.insert('credit_transactions', {
      'vendor_id': vendorId,
      'date': DateTime.now().toIso8601String(),
      'type': type,
      'amount': amount,
      'balance_after': newBalance,
      'notes': notes,
      'sale_id': saleId,
    });
  }

  Future<List<Map<String, dynamic>>> getVendorTransactions(int vendorId) async {
    final db = await database;
    return db.query('credit_transactions',
        where: 'vendor_id = ?', whereArgs: [vendorId], orderBy: 'date DESC');
  }

  Future<List<Map<String, dynamic>>> getTodaysCollections() async {
    final db = await database;
    final todayPrefix = DateTime.now().toIso8601String().substring(0, 10);
    return db.rawQuery('''
      SELECT ct.*, v.name as vendor_name FROM credit_transactions ct
      JOIN vendors v ON v.id = ct.vendor_id
      WHERE ct.type = 'PAYMENT' AND ct.date LIKE ?
      ORDER BY ct.date DESC
    ''', ['$todayPrefix%']);
  }

  Future<double> getTotalOutstandingCredit() async {
    final db = await database;
    final vendors = await getVendors();
    double total = 0;
    for (final v in vendors) {
      total += await getVendorBalance(v['id'] as int);
    }
    return total;
  }

  // ---------------- SALES ----------------

  /// Creates a sale with its line items in a single transaction, deducts
  /// stock for each item, and — if sold on credit — records the credit
  /// against the vendor automatically.
  Future<int> createSale({
    required List<Map<String, dynamic>> items, // product_id, product_name, quantity, unit_price
    required double discount,
    required String paymentType, // CASH, CREDIT, PARTIAL
    int? vendorId,
    required double paidAmount,
    String? notes,
  }) async {
    final db = await database;
    final subtotal = items.fold<double>(
        0, (sum, item) => sum + (item['quantity'] as num) * (item['unit_price'] as num));
    final total = subtotal - discount;

    late int saleId;
    await db.transaction((txn) async {
      saleId = await txn.insert('sales', {
        'date': DateTime.now().toIso8601String(),
        'subtotal': subtotal,
        'discount': discount,
        'total_amount': total,
        'payment_type': paymentType,
        'vendor_id': vendorId,
        'paid_amount': paidAmount,
        'notes': notes,
      });

      for (final item in items) {
        final qty = (item['quantity'] as num).toDouble();
        final price = (item['unit_price'] as num).toDouble();
        await txn.insert('sale_items', {
          'sale_id': saleId,
          'product_id': item['product_id'],
          'product_name': item['product_name'],
          'quantity': qty,
          'unit_price': price,
          'subtotal': qty * price,
        });

        if (item['product_id'] != null) {
          final pid = item['product_id'] as int;
          final rows = await txn.query('products', where: 'id = ?', whereArgs: [pid]);
          if (rows.isNotEmpty) {
            final current = (rows.first['quantity'] as num).toDouble();
            await txn.update(
              'products',
              {
                'quantity': current - qty,
                'updated_at': DateTime.now().toIso8601String()
              },
              where: 'id = ?',
              whereArgs: [pid],
            );
            await txn.insert('stock_movements', {
              'product_id': pid,
              'date': DateTime.now().toIso8601String(),
              'type': 'OUT',
              'quantity': qty,
              'reason': 'SALE',
              'notes': 'Sale #$saleId',
            });
          }
        }
      }
    });

    // Credit portion is recorded after the sale exists so it can reference sale_id.
    if ((paymentType == 'CREDIT' || paymentType == 'PARTIAL') && vendorId != null) {
      final creditAmount = total - paidAmount;
      if (creditAmount > 0) {
        await addCreditTransaction(
          vendorId: vendorId,
          type: 'CREDIT',
          amount: creditAmount,
          notes: 'Credit sale #$saleId',
          saleId: saleId,
        );
      }
    }

    return saleId;
  }

  Future<List<Map<String, dynamic>>> getSales({String? dateFilter}) async {
    final db = await database;
    if (dateFilter != null) {
      return db.query('sales',
          where: 'date LIKE ?', whereArgs: ['$dateFilter%'], orderBy: 'date DESC');
    }
    return db.query('sales', orderBy: 'date DESC');
  }

  Future<List<Map<String, dynamic>>> getSaleItems(int saleId) async {
    final db = await database;
    return db.query('sale_items', where: 'sale_id = ?', whereArgs: [saleId]);
  }

  Future<double> getTodaysSalesTotal() async {
    final db = await database;
    final todayPrefix = DateTime.now().toIso8601String().substring(0, 10);
    final result = await db.rawQuery(
        'SELECT SUM(total_amount) as total FROM sales WHERE date LIKE ?',
        ['$todayPrefix%']);
    final value = result.first['total'];
    return value == null ? 0 : (value as num).toDouble();
  }

  Future<List<Map<String, dynamic>>> getSalesSummaryByDay({int days = 7}) async {
    final db = await database;
    return db.rawQuery('''
      SELECT substr(date, 1, 10) as day, SUM(total_amount) as total
      FROM sales
      GROUP BY day
      ORDER BY day DESC
      LIMIT ?
    ''', [days]);
  }

  /// Sales broken down by product for a date range — feeds the "product
  /// wise" pie chart. [startIso]/[endIsoExclusive] are ISO8601 timestamps;
  /// the range covers from start (inclusive) to end (exclusive).
  Future<List<Map<String, dynamic>>> getProductWiseSales({
    required String startIso,
    required String endIsoExclusive,
  }) async {
    final db = await database;
    return db.rawQuery('''
      SELECT si.product_name AS name, SUM(si.subtotal) AS total, SUM(si.quantity) AS qty
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      WHERE s.date >= ? AND s.date < ?
      GROUP BY si.product_name
      ORDER BY total DESC
    ''', [startIso, endIsoExclusive]);
  }

  /// Sales broken down by payment type (cash / credit / partial) for a date
  /// range — feeds the "sales vs credit" pie chart.
  Future<List<Map<String, dynamic>>> getPaymentTypeWiseSales({
    required String startIso,
    required String endIsoExclusive,
  }) async {
    final db = await database;
    return db.rawQuery('''
      SELECT payment_type, SUM(total_amount) AS total
      FROM sales
      WHERE date >= ? AND date < ?
      GROUP BY payment_type
    ''', [startIso, endIsoExclusive]);
  }
}
