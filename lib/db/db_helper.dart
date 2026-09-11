import 'package:cloud_firestore/cloud_firestore.dart';

/// Firestore-backed data layer for Madhura Agro Traders. Replaces the old
/// on-device SQLite database so both phones read and write the same live,
/// shared data instead of separate private copies.
///
/// Design notes:
/// - Dates are stored as ISO8601 strings (not Firestore's native Timestamp)
///   so date-range filtering stays simple string comparison, same as the
///   original SQLite version.
/// - Vendor/supplier running balances and product stock quantities are
///   stored directly as fields on their own document ("denormalized") and
///   kept in sync inside Firestore transactions whenever a related
///   transaction is written. This means displaying a vendor's balance is a
///   single cheap document read, not a replay of their whole history.
/// - Firestore has no JOIN, so a few fields that used to come from a SQL
///   join (vendor_name on a credit transaction, product_name on a stock
///   movement, etc.) are instead written directly onto the document at
///   creation time.
/// - Firestore also has no case-insensitive query, so products/vendors/
///   suppliers each keep a name_lower field purely for case-insensitive
///   matching during CSV import.
class DBHelper {
  DBHelper._internal();
  static final DBHelper instance = DBHelper._internal();

  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  CollectionReference get _products => _fs.collection('products');
  CollectionReference get _vendors => _fs.collection('vendors');
  CollectionReference get _suppliers => _fs.collection('suppliers');
  CollectionReference get _sales => _fs.collection('sales');
  CollectionReference get _saleItems => _fs.collection('sale_items');
  CollectionReference get _creditTxns => _fs.collection('credit_transactions');
  CollectionReference get _supplierTxns => _fs.collection('supplier_transactions');
  CollectionReference get _supplierPurchaseItems => _fs.collection('supplier_purchase_items');
  CollectionReference get _stockMovements => _fs.collection('stock_movements');

  Map<String, dynamic> _withId(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    return {...data, 'id': doc.id};
  }

  List<Map<String, dynamic>> _fromSnapshot(QuerySnapshot snap) =>
      snap.docs.map(_withId).toList();

  // ---------------- PRODUCTS / INVENTORY ----------------

  Future<String> insertProduct(Map<String, dynamic> product) async {
    final now = DateTime.now().toIso8601String();
    final ref = await _products.add({
      ...product,
      'name_lower': (product['name'] as String).toLowerCase(),
      'created_at': product['created_at'] ?? now,
      'updated_at': now,
    });
    return ref.id;
  }

  Future<void> updateProduct(String id, Map<String, dynamic> product) async {
    await _products.doc(id).update({
      ...product,
      if (product['name'] != null) 'name_lower': (product['name'] as String).toLowerCase(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> deleteProduct(String id) async {
    await _products.doc(id).delete();
  }

  Future<List<Map<String, dynamic>>> getProducts({String? search}) async {
    final snap = await _products.orderBy('name').get();
    var products = _fromSnapshot(snap);
    if (search != null && search.isNotEmpty) {
      final q = search.toLowerCase();
      products = products.where((p) => (p['name'] as String).toLowerCase().contains(q)).toList();
    }
    return products;
  }

  Future<List<Map<String, dynamic>>> getLowStockProducts() async {
    final snap = await _products.get();
    final products = _fromSnapshot(snap);
    final low = products.where((p) {
      final qty = (p['quantity'] as num?)?.toDouble() ?? 0;
      final reorder = (p['reorder_level'] as num?)?.toDouble() ?? 0;
      return qty <= reorder;
    }).toList();
    low.sort((a, b) => ((a['quantity'] as num?) ?? 0).compareTo((b['quantity'] as num?) ?? 0));
    return low;
  }

  /// Adjusts a product's stock and logs the movement. deltaQty is positive
  /// for stock IN (purchase, correction) or negative for stock OUT (sale).
  /// Uses a transaction so concurrent sales on two phones can't both read
  /// the same starting quantity and silently overwrite each other.
  Future<void> adjustStock({
    required String productId,
    required double deltaQty,
    required String reason, // SALE, PURCHASE, ADJUSTMENT
    String? notes,
  }) async {
    final productRef = _products.doc(productId);
    await _fs.runTransaction((txn) async {
      final snap = await txn.get(productRef);
      if (!snap.exists) return;
      final data = snap.data() as Map<String, dynamic>;
      final current = (data['quantity'] as num?)?.toDouble() ?? 0;
      final updated = current + deltaQty;
      txn.update(productRef, {
        'quantity': updated,
        'updated_at': DateTime.now().toIso8601String(),
      });
      txn.set(_stockMovements.doc(), {
        'product_id': productId,
        'product_name': data['name'],
        'date': DateTime.now().toIso8601String(),
        'type': deltaQty >= 0 ? 'IN' : 'OUT',
        'quantity': deltaQty.abs(),
        'reason': reason,
        'notes': notes,
      });
    });
  }

  Future<List<Map<String, dynamic>>> getStockHistory(String productId) async {
    final snap = await _stockMovements
        .where('product_id', isEqualTo: productId)
        .orderBy('date', descending: true)
        .get();
    return _fromSnapshot(snap);
  }

  // ---------------- SUPPLIERS ----------------

  Future<String> insertSupplier(Map<String, dynamic> supplier) async {
    final ref = await _suppliers.add({
      ...supplier,
      'name_lower': (supplier['name'] as String).toLowerCase(),
      'balance': (supplier['opening_balance'] as num?)?.toDouble() ?? 0,
    });
    return ref.id;
  }

  Future<List<Map<String, dynamic>>> getSuppliers() async {
    final snap = await _suppliers.orderBy('name').get();
    return _fromSnapshot(snap);
  }

  Future<double> getSupplierBalance(String supplierId) async {
    final doc = await _suppliers.doc(supplierId).get();
    if (!doc.exists) return 0;
    final data = doc.data() as Map<String, dynamic>;
    return (data['balance'] as num?)?.toDouble() ?? 0;
  }

  /// Records a purchase (increases what the store owes) or a payment
  /// (decreases what the store owes), keeping the supplier's balance field
  /// in sync inside a transaction.
  Future<void> addSupplierTransaction({
    required String supplierId,
    required String type, // PURCHASE or PAYMENT
    required double amount,
    String? notes,
  }) async {
    final supplierRef = _suppliers.doc(supplierId);
    await _fs.runTransaction((txn) async {
      final snap = await txn.get(supplierRef);
      final data = snap.data() as Map<String, dynamic>? ?? {};
      final current = (data['balance'] as num?)?.toDouble() ?? 0;
      final newBalance = type == 'PURCHASE' ? current + amount : current - amount;
      txn.set(_supplierTxns.doc(), {
        'supplier_id': supplierId,
        'supplier_name': data['name'],
        'date': DateTime.now().toIso8601String(),
        'type': type,
        'amount': amount,
        'balance_after': newBalance,
        'notes': notes,
      });
      txn.update(supplierRef, {'balance': newBalance});
    });
  }

  Future<List<Map<String, dynamic>>> getSupplierTransactions(String supplierId) async {
    final snap = await _supplierTxns
        .where('supplier_id', isEqualTo: supplierId)
        .orderBy('date', descending: true)
        .get();
    return _fromSnapshot(snap);
  }

  /// Records a stock purchase made up of specific products, quantities and
  /// costs. Reads the supplier and every referenced product first (a
  /// Firestore transaction requires all reads before any writes), then
  /// atomically writes the purchase record, its line items, the updated
  /// supplier balance, each product's new stock/cost, and stock movement
  /// logs.
  Future<String> addSupplierPurchase({
    required String supplierId,
    required List<Map<String, dynamic>> items, // product_id, product_name, quantity, unit_cost
    String? notes,
  }) async {
    final supplierRef = _suppliers.doc(supplierId);
    final txnRef = _supplierTxns.doc();
    final amount = items.fold<double>(
        0, (sum, i) => sum + (i['quantity'] as num) * (i['unit_cost'] as num));

    await _fs.runTransaction((txn) async {
      final supplierSnap = await txn.get(supplierRef);
      final supplierData = supplierSnap.data() as Map<String, dynamic>? ?? {};
      final currentBalance = (supplierData['balance'] as num?)?.toDouble() ?? 0;
      final newBalance = currentBalance + amount;

      // Read every referenced product before writing anything.
      final productRefs = <String, DocumentReference>{};
      final productData = <String, Map<String, dynamic>>{};
      for (final item in items) {
        final pid = item['product_id'] as String?;
        if (pid == null || productRefs.containsKey(pid)) continue;
        final ref = _products.doc(pid);
        final snap = await txn.get(ref);
        if (snap.exists) {
          productRefs[pid] = ref;
          productData[pid] = snap.data() as Map<String, dynamic>;
        }
      }

      txn.set(txnRef, {
        'supplier_id': supplierId,
        'supplier_name': supplierData['name'],
        'date': DateTime.now().toIso8601String(),
        'type': 'PURCHASE',
        'amount': amount,
        'balance_after': newBalance,
        'notes': notes,
      });
      txn.update(supplierRef, {'balance': newBalance});

      for (final item in items) {
        final qty = (item['quantity'] as num).toDouble();
        final cost = (item['unit_cost'] as num).toDouble();
        txn.set(_supplierPurchaseItems.doc(), {
          'supplier_transaction_id': txnRef.id,
          'product_id': item['product_id'],
          'product_name': item['product_name'],
          'quantity': qty,
          'unit_cost': cost,
          'subtotal': qty * cost,
        });

        final pid = item['product_id'] as String?;
        if (pid != null && productRefs.containsKey(pid)) {
          final current = (productData[pid]!['quantity'] as num?)?.toDouble() ?? 0;
          txn.update(productRefs[pid]!, {
            'quantity': current + qty,
            'cost_price': cost,
            'updated_at': DateTime.now().toIso8601String(),
          });
          txn.set(_stockMovements.doc(), {
            'product_id': pid,
            'product_name': item['product_name'],
            'date': DateTime.now().toIso8601String(),
            'type': 'IN',
            'quantity': qty,
            'reason': 'PURCHASE',
            'notes': 'Purchase #${txnRef.id}',
          });
        }
      }
    });

    return txnRef.id;
  }

  Future<List<Map<String, dynamic>>> getSupplierPurchaseItems(String supplierTransactionId) async {
    final snap = await _supplierPurchaseItems
        .where('supplier_transaction_id', isEqualTo: supplierTransactionId)
        .get();
    return _fromSnapshot(snap);
  }

  // ---------------- VENDORS (CREDIT CUSTOMERS) ----------------

  Future<String> insertVendor(Map<String, dynamic> vendor) async {
    final ref = await _vendors.add({
      ...vendor,
      'name_lower': (vendor['name'] as String).toLowerCase(),
      'balance': (vendor['opening_balance'] as num?)?.toDouble() ?? 0,
    });
    return ref.id;
  }

  Future<List<Map<String, dynamic>>> getVendors() async {
    final snap = await _vendors.orderBy('name').get();
    return _fromSnapshot(snap);
  }

  Future<double> getVendorBalance(String vendorId) async {
    final doc = await _vendors.doc(vendorId).get();
    if (!doc.exists) return 0;
    final data = doc.data() as Map<String, dynamic>;
    return (data['balance'] as num?)?.toDouble() ?? 0;
  }

  /// Records credit given (sale on credit) or a payment/collection from a
  /// vendor, keeping the vendor's balance field in sync inside a
  /// transaction so two phones recording collections at the same time
  /// can't clobber each other. Pass [date] to backdate an entry (e.g.
  /// entering old credit history) — defaults to now if omitted.
  Future<void> addCreditTransaction({
    required String vendorId,
    required String type, // CREDIT or PAYMENT
    required double amount,
    String? notes,
    String? saleId,
    String? date,
  }) async {
    final vendorRef = _vendors.doc(vendorId);
    await _fs.runTransaction((txn) async {
      final snap = await txn.get(vendorRef);
      final data = snap.data() as Map<String, dynamic>? ?? {};
      final current = (data['balance'] as num?)?.toDouble() ?? 0;
      final newBalance = type == 'CREDIT' ? current + amount : current - amount;
      txn.set(_creditTxns.doc(), {
        'vendor_id': vendorId,
        'vendor_name': data['name'],
        'date': date ?? DateTime.now().toIso8601String(),
        'type': type,
        'amount': amount,
        'balance_after': newBalance,
        'notes': notes,
        'sale_id': saleId,
      });
      txn.update(vendorRef, {'balance': newBalance});
    });
  }

  Future<List<Map<String, dynamic>>> getVendorTransactions(String vendorId) async {
    final snap = await _creditTxns
        .where('vendor_id', isEqualTo: vendorId)
        .orderBy('date', descending: true)
        .get();
    return _fromSnapshot(snap);
  }

  Future<List<Map<String, dynamic>>> getTodaysCollections() async {
    final todayPrefix = DateTime.now().toIso8601String().substring(0, 10);
    final snap = await _creditTxns
        .where('type', isEqualTo: 'PAYMENT')
        .where('date', isGreaterThanOrEqualTo: todayPrefix)
        .where('date', isLessThan: '$todayPrefix\uf8ff')
        .orderBy('date', descending: true)
        .get();
    return _fromSnapshot(snap);
  }

  Future<double> getTotalOutstandingCredit() async {
    final snap = await _vendors.get();
    double total = 0;
    for (final doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      total += (data['balance'] as num?)?.toDouble() ?? 0;
    }
    return total;
  }

  /// For a vendor with an outstanding balance, returns how many days ago
  /// their *current, still-unpaid* balance started accumulating. Walks
  /// their transaction history oldest-to-newest; every time the running
  /// balance drops to zero (or below) it resets, so this reflects the age
  /// of what's currently owed, not the vendor's whole history. Returns
  /// null if the vendor's balance is currently zero.
  Future<int?> getVendorOutstandingDays(String vendorId) async {
    final vendorDoc = await _vendors.doc(vendorId).get();
    if (!vendorDoc.exists) return null;

    final snap = await _creditTxns
        .where('vendor_id', isEqualTo: vendorId)
        .orderBy('date')
        .get();

    double runningBalance = 0;
    DateTime? openedSince;

    for (final doc in snap.docs) {
      final t = doc.data() as Map<String, dynamic>;
      final amount = (t['amount'] as num).toDouble();
      runningBalance = t['type'] == 'CREDIT' ? runningBalance + amount : runningBalance - amount;
      if (runningBalance <= 0) {
        openedSince = null;
      } else if (openedSince == null) {
        openedSince = DateTime.tryParse(t['date'] as String);
      }
    }

    if (runningBalance <= 0 || openedSince == null) return null;
    return DateTime.now().difference(openedSince).inDays;
  }

  /// Vendors whose current outstanding balance has been unpaid for at
  /// least [minDays] days — feeds the Dashboard's aging-credit alert.
  Future<List<Map<String, dynamic>>> getAgingVendors({int minDays = 60}) async {
    final vendors = await getVendors();
    final aging = <Map<String, dynamic>>[];
    for (final v in vendors) {
      final vendorId = v['id'] as String;
      final balance = (v['balance'] as num?)?.toDouble() ?? 0;
      if (balance <= 0) continue;
      final days = await getVendorOutstandingDays(vendorId);
      if (days != null && days >= minDays) {
        aging.add({...v, 'balance': balance, 'days_outstanding': days});
      }
    }
    aging.sort((a, b) => (b['days_outstanding'] as int).compareTo(a['days_outstanding'] as int));
    return aging;
  }

  // ---------------- SALES ----------------

  /// Creates a sale with its line items, deducts stock for each item, and
  /// — if sold on credit — records the credit against the vendor, all in
  /// one Firestore transaction. Every product and (if relevant) the vendor
  /// are read first, since a transaction must finish all its reads before
  /// any of its writes.
  Future<String> createSale({
    required List<Map<String, dynamic>> items, // product_id, product_name, quantity, unit_price
    required double discount,
    required String paymentType, // CASH, CREDIT, PARTIAL
    String? vendorId,
    required double paidAmount,
    String? notes,
  }) async {
    final subtotal = items.fold<double>(
        0, (sum, item) => sum + (item['quantity'] as num) * (item['unit_price'] as num));
    final total = subtotal - discount;
    final saleRef = _sales.doc();
    final now = DateTime.now().toIso8601String();

    await _fs.runTransaction((txn) async {
      // ---- reads first ----
      final productRefs = <String, DocumentReference>{};
      final productData = <String, Map<String, dynamic>>{};
      for (final item in items) {
        final pid = item['product_id'] as String?;
        if (pid == null || productRefs.containsKey(pid)) continue;
        final ref = _products.doc(pid);
        final snap = await txn.get(ref);
        if (snap.exists) {
          productRefs[pid] = ref;
          productData[pid] = snap.data() as Map<String, dynamic>;
        }
      }

      DocumentReference? vendorRef;
      Map<String, dynamic>? vendorData;
      double vendorCurrentBalance = 0;
      if (vendorId != null) {
        vendorRef = _vendors.doc(vendorId);
        final snap = await txn.get(vendorRef);
        vendorData = snap.data() as Map<String, dynamic>? ?? {};
        vendorCurrentBalance = (vendorData['balance'] as num?)?.toDouble() ?? 0;
      }

      // ---- writes ----
      txn.set(saleRef, {
        'date': now,
        'subtotal': subtotal,
        'discount': discount,
        'total_amount': total,
        'payment_type': paymentType,
        'vendor_id': vendorId,
        'vendor_name': vendorData?['name'],
        'paid_amount': paidAmount,
        'notes': notes,
        'status': 'confirmed',
      });

      for (final item in items) {
        final qty = (item['quantity'] as num).toDouble();
        final price = (item['unit_price'] as num).toDouble();
        txn.set(_saleItems.doc(), {
          'sale_id': saleRef.id,
          'sale_date': now,
          'product_id': item['product_id'],
          'product_name': item['product_name'],
          'quantity': qty,
          'unit_price': price,
          'subtotal': qty * price,
          'status': 'confirmed',
        });

        final pid = item['product_id'] as String?;
        if (pid != null && productRefs.containsKey(pid)) {
          final current = (productData[pid]!['quantity'] as num?)?.toDouble() ?? 0;
          txn.update(productRefs[pid]!, {
            'quantity': current - qty,
            'updated_at': now,
          });
          txn.set(_stockMovements.doc(), {
            'product_id': pid,
            'product_name': item['product_name'],
            'date': now,
            'type': 'OUT',
            'quantity': qty,
            'reason': 'SALE',
            'notes': 'Sale #${saleRef.id}',
          });
        }
      }

      if ((paymentType == 'CREDIT' || paymentType == 'PARTIAL') &&
          vendorId != null &&
          vendorRef != null) {
        final creditAmount = total - paidAmount;
        if (creditAmount > 0) {
          final newBalance = vendorCurrentBalance + creditAmount;
          txn.set(_creditTxns.doc(), {
            'vendor_id': vendorId,
            'vendor_name': vendorData?['name'],
            'date': now,
            'type': 'CREDIT',
            'amount': creditAmount,
            'balance_after': newBalance,
            'notes': 'Credit sale #${saleRef.id}',
            'sale_id': saleRef.id,
          });
          txn.update(vendorRef, {'balance': newBalance});
        }
      }
    });

    return saleRef.id;
  }

  /// Reverses a sale: restores the stock it deducted, reverses the credit
  /// it posted to the vendor's balance (if any), and marks the sale (and
  /// its line items) as cancelled rather than deleting them, so there's
  /// still a full audit trail of what happened. Safe to call even if
  /// items/vendor were since deleted — those parts are just skipped.
  ///
  /// The sale document and its line items are read as plain queries
  /// first (Firestore transactions can only re-read specific document
  /// references, not run new queries), then everything is reversed
  /// atomically in one transaction.
  Future<void> cancelSale(String saleId) async {
    final saleDoc = await _sales.doc(saleId).get();
    if (!saleDoc.exists) return;
    final saleData = saleDoc.data() as Map<String, dynamic>;
    if (saleData['status'] == 'cancelled') return; // already cancelled

    final itemsSnap = await _saleItems.where('sale_id', isEqualTo: saleId).get();
    final creditSnap = await _creditTxns.where('sale_id', isEqualTo: saleId).limit(1).get();
    final vendorId = saleData['vendor_id'] as String?;
    final now = DateTime.now().toIso8601String();

    await _fs.runTransaction((txn) async {
      // ---- reads first ----
      final saleRef = _sales.doc(saleId);
      final productRefs = <String, DocumentReference>{};
      final productData = <String, Map<String, dynamic>>{};
      for (final doc in itemsSnap.docs) {
        final item = doc.data() as Map<String, dynamic>;
        final pid = item['product_id'] as String?;
        if (pid == null || productRefs.containsKey(pid)) continue;
        final ref = _products.doc(pid);
        final snap = await txn.get(ref);
        if (snap.exists) {
          productRefs[pid] = ref;
          productData[pid] = snap.data() as Map<String, dynamic>;
        }
      }

      DocumentReference? vendorRef;
      Map<String, dynamic>? vendorData;
      if (vendorId != null) {
        vendorRef = _vendors.doc(vendorId);
        final snap = await txn.get(vendorRef);
        if (snap.exists) vendorData = snap.data() as Map<String, dynamic>;
      }

      // ---- writes ----
      txn.update(saleRef, {'status': 'cancelled', 'cancelled_at': now});

      for (final doc in itemsSnap.docs) {
        final item = doc.data() as Map<String, dynamic>;
        txn.update(doc.reference, {'status': 'cancelled'});

        final pid = item['product_id'] as String?;
        final qty = (item['quantity'] as num).toDouble();
        if (pid != null && productRefs.containsKey(pid)) {
          final current = (productData[pid]!['quantity'] as num?)?.toDouble() ?? 0;
          txn.update(productRefs[pid]!, {
            'quantity': current + qty,
            'updated_at': now,
          });
          txn.set(_stockMovements.doc(), {
            'product_id': pid,
            'product_name': item['product_name'],
            'date': now,
            'type': 'IN',
            'quantity': qty,
            'reason': 'SALE_CANCELLED',
            'notes': 'Reversal for cancelled sale #$saleId',
          });
        }
      }

      // If this sale had posted credit to a vendor, reverse just that
      // amount (a balance-reducing entry, same as a payment, but tagged
      // as an adjustment so it doesn't show up in "today's collections").
      if (creditSnap.docs.isNotEmpty && vendorRef != null && vendorData != null) {
        final creditData = creditSnap.docs.first.data() as Map<String, dynamic>;
        final creditAmount = (creditData['amount'] as num).toDouble();
        final currentBalance = (vendorData['balance'] as num?)?.toDouble() ?? 0;
        final newBalance = currentBalance - creditAmount;
        txn.update(vendorRef, {'balance': newBalance});
        txn.set(_creditTxns.doc(), {
          'vendor_id': vendorId,
          'vendor_name': vendorData['name'],
          'date': now,
          'type': 'ADJUSTMENT',
          'amount': creditAmount,
          'balance_after': newBalance,
          'notes': 'Reversal for cancelled sale #$saleId',
          'sale_id': saleId,
        });
      }
    });
  }

  Future<List<Map<String, dynamic>>> getSales({String? dateFilter}) async {
    Query query = _sales.orderBy('date', descending: true);
    if (dateFilter != null) {
      query = _sales
          .where('date', isGreaterThanOrEqualTo: dateFilter)
          .where('date', isLessThan: '$dateFilter\uf8ff')
          .orderBy('date', descending: true);
    }
    final snap = await query.get();
    return _fromSnapshot(snap);
  }

  Future<List<Map<String, dynamic>>> getSaleItems(String saleId) async {
    final snap = await _saleItems.where('sale_id', isEqualTo: saleId).get();
    return _fromSnapshot(snap);
  }

  Future<double> getTodaysSalesTotal() async {
    final todayPrefix = DateTime.now().toIso8601String().substring(0, 10);
    final snap = await _sales
        .where('date', isGreaterThanOrEqualTo: todayPrefix)
        .where('date', isLessThan: '$todayPrefix\uf8ff')
        .get();
    double total = 0;
    for (final doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['status'] == 'cancelled') continue;
      total += (data['total_amount'] as num?)?.toDouble() ?? 0;
    }
    return total;
  }

  Future<List<Map<String, dynamic>>> getSalesSummaryByDay({int days = 7}) async {
    final start = DateTime.now().subtract(Duration(days: days - 1));
    final startPrefix = DateTime(start.year, start.month, start.day).toIso8601String();
    final snap = await _sales.where('date', isGreaterThanOrEqualTo: startPrefix).get();

    final totalsByDay = <String, double>{};
    for (final doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['status'] == 'cancelled') continue;
      final day = (data['date'] as String).substring(0, 10);
      totalsByDay[day] = (totalsByDay[day] ?? 0) + ((data['total_amount'] as num?)?.toDouble() ?? 0);
    }
    final result = totalsByDay.entries.map((e) => {'day': e.key, 'total': e.value}).toList();
    result.sort((a, b) => (b['day'] as String).compareTo(a['day'] as String));
    return result.take(days).toList();
  }

  /// Sales broken down by product for a date range — feeds the "product
  /// wise" pie chart. Filters sale_items directly on their denormalized
  /// sale_date field (Firestore has no JOIN back to the parent sale).
  Future<List<Map<String, dynamic>>> getProductWiseSales({
    required String startIso,
    required String endIsoExclusive,
  }) async {
    final snap = await _saleItems
        .where('sale_date', isGreaterThanOrEqualTo: startIso)
        .where('sale_date', isLessThan: endIsoExclusive)
        .get();
    final totals = <String, double>{};
    for (final doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['status'] == 'cancelled') continue;
      final name = data['product_name'] as String;
      totals[name] = (totals[name] ?? 0) + ((data['subtotal'] as num?)?.toDouble() ?? 0);
    }
    final result = totals.entries.map((e) => {'name': e.key, 'total': e.value}).toList();
    result.sort((a, b) => (b['total'] as double).compareTo(a['total'] as double));
    return result;
  }

  /// Sales broken down by payment type (cash / credit / partial) for a
  /// date range — feeds the "sales vs credit" pie chart.
  Future<List<Map<String, dynamic>>> getPaymentTypeWiseSales({
    required String startIso,
    required String endIsoExclusive,
  }) async {
    final snap = await _sales
        .where('date', isGreaterThanOrEqualTo: startIso)
        .where('date', isLessThan: endIsoExclusive)
        .get();
    final totals = <String, double>{};
    for (final doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['status'] == 'cancelled') continue;
      final type = data['payment_type'] as String;
      totals[type] = (totals[type] ?? 0) + ((data['total_amount'] as num?)?.toDouble() ?? 0);
    }
    return totals.entries.map((e) => {'payment_type': e.key, 'total': e.value}).toList();
  }

  // ---------------- DATA EXPORT (full dump, all tables) ----------------
  // Read-only reporting queries for CSV export. None of these are used for
  // re-importing transactional data, since sales/credit/purchase entries
  // have side effects (stock levels, running balances) that a raw
  // row-by-row import can't safely replay.

  Future<List<Map<String, dynamic>>> getAllSalesFlat() async {
    final snap = await _sales.orderBy('date', descending: true).get();
    return _fromSnapshot(snap);
  }

  Future<List<Map<String, dynamic>>> getAllSaleItemsFlat() async {
    final snap = await _saleItems.orderBy('sale_date', descending: true).get();
    return _fromSnapshot(snap);
  }

  Future<List<Map<String, dynamic>>> getAllCreditTransactions() async {
    final snap = await _creditTxns.orderBy('date', descending: true).get();
    return _fromSnapshot(snap);
  }

  Future<List<Map<String, dynamic>>> getAllSupplierTransactions() async {
    final snap = await _supplierTxns.orderBy('date', descending: true).get();
    return _fromSnapshot(snap);
  }

  Future<List<Map<String, dynamic>>> getAllStockMovements() async {
    final snap = await _stockMovements.orderBy('date', descending: true).get();
    return _fromSnapshot(snap);
  }

  // ---------------- DATA IMPORT (master data only) ----------------
  // Products, vendors, and suppliers are simple "catalog" data with no
  // side effects, so they're safe to sync between two people's phones by
  // export/import. Matches by name (case-insensitive, via the stored
  // name_lower field): updates the existing row if a match is found,
  // otherwise inserts a new one.

  /// Returns true if an existing product was updated, false if a new one
  /// was inserted.
  Future<bool> upsertProductByName(Map<String, dynamic> data) async {
    final name = (data['name'] as String).trim();
    final existing =
        await _products.where('name_lower', isEqualTo: name.toLowerCase()).limit(1).get();
    final now = DateTime.now().toIso8601String();
    if (existing.docs.isNotEmpty) {
      await existing.docs.first.reference.update({
        ...data,
        'name_lower': name.toLowerCase(),
        'updated_at': now,
      });
      return true;
    } else {
      await _products.add({
        ...data,
        'name_lower': name.toLowerCase(),
        'created_at': now,
        'updated_at': now,
      });
      return false;
    }
  }

  /// Returns true if an existing vendor was updated, false if a new one
  /// was inserted. Only touches name/phone/address — never the balance,
  /// so it can't be used to (accidentally or otherwise) alter what's owed.
  Future<bool> upsertVendorByName({
    required String name,
    String? phone,
    String? address,
  }) async {
    final existing = await _vendors
        .where('name_lower', isEqualTo: name.trim().toLowerCase())
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) {
      await existing.docs.first.reference.update({
        if (phone != null) 'phone': phone,
        if (address != null) 'address': address,
      });
      return true;
    } else {
      await _vendors.add({
        'name': name.trim(),
        'name_lower': name.trim().toLowerCase(),
        'phone': phone ?? '',
        'address': address ?? '',
        'opening_balance': 0,
        'balance': 0,
        'created_at': DateTime.now().toIso8601String(),
      });
      return false;
    }
  }

  /// Same as [upsertVendorByName] but for suppliers.
  Future<bool> upsertSupplierByName({
    required String name,
    String? phone,
    String? address,
  }) async {
    final existing = await _suppliers
        .where('name_lower', isEqualTo: name.trim().toLowerCase())
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) {
      await existing.docs.first.reference.update({
        if (phone != null) 'phone': phone,
        if (address != null) 'address': address,
      });
      return true;
    } else {
      await _suppliers.add({
        'name': name.trim(),
        'name_lower': name.trim().toLowerCase(),
        'phone': phone ?? '',
        'address': address ?? '',
        'opening_balance': 0,
        'balance': 0,
        'created_at': DateTime.now().toIso8601String(),
      });
      return false;
    }
  }
}
