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
///   stored directly as fields on their own document ("denormalized") so
///   displaying a balance is a single cheap document read, not a replay
///   of their whole history.
/// - Money/stock-affecting writes (a sale, a payment, a purchase) read the
///   relevant documents first, then commit everything as a single
///   WriteBatch — deliberately NOT a Firestore transaction
///   (runTransaction), because transactions require a live connection to
///   the server even to queue up, and fail outright while offline. A
///   WriteBatch, like a plain set()/update(), queues normally in the
///   local cache and syncs whenever a connection is available — which is
///   what lets every screen keep working indefinitely with no internet at
///   all. The trade-off: if both phones happen to edit the exact same
///   vendor/product at the exact same instant while both online, the
///   last write wins rather than one being rejected — an acceptable
///   trade for a small store where that's rare, against "must work
///   offline" which matters every day.
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

  /// Live version of getProducts — see watchVendors for why this exists:
  /// updates automatically, including a pending write made while offline.
  Stream<List<Map<String, dynamic>>> watchProducts({String? search}) {
    return _products.orderBy('name').snapshots().map((snap) {
      var products = _fromSnapshot(snap);
      if (search != null && search.isNotEmpty) {
        final q = search.toLowerCase();
        products = products.where((p) => (p['name'] as String).toLowerCase().contains(q)).toList();
      }
      return products;
    });
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
  /// Reads then writes via a WriteBatch (not a transaction) so this works
  /// fully offline — see the class doc comment for why.
  Future<void> adjustStock({
    required String productId,
    required double deltaQty,
    required String reason, // SALE, PURCHASE, ADJUSTMENT
    String? notes,
  }) async {
    final productRef = _products.doc(productId);
    final snap = await productRef.get();
    if (!snap.exists) return;
    final data = snap.data() as Map<String, dynamic>;
    final current = (data['quantity'] as num?)?.toDouble() ?? 0;
    final updated = current + deltaQty;
    final now = DateTime.now().toIso8601String();

    final batch = _fs.batch();
    batch.update(productRef, {'quantity': updated, 'updated_at': now});
    batch.set(_stockMovements.doc(), {
      'product_id': productId,
      'product_name': data['name'],
      'date': now,
      'type': deltaQty >= 0 ? 'IN' : 'OUT',
      'quantity': deltaQty.abs(),
      'reason': reason,
      'notes': notes,
    });
    await batch.commit();
  }

  Future<List<Map<String, dynamic>>> getStockHistory(String productId) async {
    // No orderBy in the query itself — combining a where() with orderBy()
    // on a different field needs a Firestore composite index, which isn't
    // set up. Sorting the (small) result client-side avoids needing one.
    final snap = await _stockMovements.where('product_id', isEqualTo: productId).get();
    final list = _fromSnapshot(snap);
    list.sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
    return list;
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

  /// Live version of getSuppliers — updates automatically whenever the
  /// data changes, including a pending write made while offline (a
  /// one-time get() can miss that until the device reconnects; a
  /// snapshots() stream reflects the local cache immediately).
  Stream<List<Map<String, dynamic>>> watchSuppliers() {
    return _suppliers.orderBy('name').snapshots().map(_fromSnapshot);
  }

  Stream<Map<String, dynamic>?> watchSupplier(String supplierId) {
    return _suppliers.doc(supplierId).snapshots().map((doc) => doc.exists ? _withId(doc) : null);
  }

  Stream<List<Map<String, dynamic>>> watchSupplierTransactions(String supplierId) {
    return _supplierTxns.where('supplier_id', isEqualTo: supplierId).snapshots().map((snap) {
      final list = _fromSnapshot(snap);
      list.sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
      return list;
    });
  }

  /// Edits a supplier's own profile fields — never touches their balance.
  Future<void> updateSupplier(String supplierId, {String? name, String? phone, String? address}) async {
    await _suppliers.doc(supplierId).update({
      if (name != null) 'name': name,
      if (name != null) 'name_lower': name.toLowerCase(),
      if (phone != null) 'phone': phone,
      if (address != null) 'address': address,
    });
  }

  /// Deletes a supplier profile — see deleteVendor for the same
  /// keep-the-audit-trail reasoning.
  Future<void> deleteSupplier(String supplierId) async {
    await _suppliers.doc(supplierId).delete();
  }

  Future<double> getSupplierBalance(String supplierId) async {
    final doc = await _suppliers.doc(supplierId).get();
    if (!doc.exists) return 0;
    final data = doc.data() as Map<String, dynamic>;
    return (data['balance'] as num?)?.toDouble() ?? 0;
  }

  /// Records a purchase (increases what the store owes) or a payment
  /// (decreases what the store owes), keeping the supplier's balance field
  /// in sync. Reads then writes via a WriteBatch (not a transaction) so
  /// this works fully offline — see the class doc comment for why.
  Future<void> addSupplierTransaction({
    required String supplierId,
    required String type, // PURCHASE or PAYMENT
    required double amount,
    String? notes,
    String? date,
  }) async {
    final supplierRef = _suppliers.doc(supplierId);
    final snap = await supplierRef.get();
    final data = snap.data() as Map<String, dynamic>? ?? {};
    final current = (data['balance'] as num?)?.toDouble() ?? 0;
    final newBalance = type == 'PURCHASE' ? current + amount : current - amount;

    final batch = _fs.batch();
    batch.set(_supplierTxns.doc(), {
      'supplier_id': supplierId,
      'supplier_name': data['name'],
      'date': date ?? DateTime.now().toIso8601String(),
      'type': type,
      'amount': amount,
      'balance_after': newBalance,
      'notes': notes,
    });
    batch.update(supplierRef, {'balance': newBalance});
    await batch.commit();
  }

  Future<List<Map<String, dynamic>>> getSupplierTransactions(String supplierId) async {
    // Sorted client-side — see getStockHistory for why.
    final snap = await _supplierTxns.where('supplier_id', isEqualTo: supplierId).get();
    final list = _fromSnapshot(snap);
    list.sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
    return list;
  }

  /// Records a stock purchase made up of specific products, quantities and
  /// costs. Reads the supplier and every referenced product first, then
  /// writes the purchase record, its line items, the updated supplier
  /// balance, each product's new stock/cost, and stock movement logs, all
  /// via a single WriteBatch (not a transaction) so this works fully
  /// offline — see the class doc comment for why.
  Future<String> addSupplierPurchase({
    required String supplierId,
    required List<Map<String, dynamic>> items, // product_id, product_name, quantity, unit_cost
    String? notes,
  }) async {
    final supplierRef = _suppliers.doc(supplierId);
    final txnRef = _supplierTxns.doc();
    final amount = items.fold<double>(
        0, (sum, i) => sum + (i['quantity'] as num) * (i['unit_cost'] as num));
    final now = DateTime.now().toIso8601String();

    final supplierSnap = await supplierRef.get();
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
      final snap = await ref.get();
      if (snap.exists) {
        productRefs[pid] = ref;
        productData[pid] = snap.data() as Map<String, dynamic>;
      }
    }

    final batch = _fs.batch();
    batch.set(txnRef, {
      'supplier_id': supplierId,
      'supplier_name': supplierData['name'],
      'date': now,
      'type': 'PURCHASE',
      'amount': amount,
      'balance_after': newBalance,
      'notes': notes,
    });
    batch.update(supplierRef, {'balance': newBalance});

    for (final item in items) {
      final qty = (item['quantity'] as num).toDouble();
      final cost = (item['unit_cost'] as num).toDouble();
      batch.set(_supplierPurchaseItems.doc(), {
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
        batch.update(productRefs[pid]!, {
          'quantity': current + qty,
          'cost_price': cost,
          'updated_at': now,
        });
        batch.set(_stockMovements.doc(), {
          'product_id': pid,
          'product_name': item['product_name'],
          'date': now,
          'type': 'IN',
          'quantity': qty,
          'reason': 'PURCHASE',
          'notes': 'Purchase #${txnRef.id}',
        });
      }
    }
    await batch.commit();

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

  /// Live version of getVendors — see watchSuppliers for why this exists.
  Stream<List<Map<String, dynamic>>> watchVendors() {
    return _vendors.orderBy('name').snapshots().map(_fromSnapshot);
  }

  Stream<Map<String, dynamic>?> watchVendor(String vendorId) {
    return _vendors.doc(vendorId).snapshots().map((doc) => doc.exists ? _withId(doc) : null);
  }

  Stream<List<Map<String, dynamic>>> watchVendorTransactions(String vendorId) {
    return _creditTxns.where('vendor_id', isEqualTo: vendorId).snapshots().map((snap) {
      final list = _fromSnapshot(snap);
      list.sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
      return list;
    });
  }

  /// Edits a vendor's own profile fields — never touches their balance,
  /// so it can't be used (accidentally or otherwise) to alter what's owed.
  Future<void> updateVendor(String vendorId, {String? name, String? phone, String? address}) async {
    await _vendors.doc(vendorId).update({
      if (name != null) 'name': name,
      if (name != null) 'name_lower': name.toLowerCase(),
      if (phone != null) 'phone': phone,
      if (address != null) 'address': address,
    });
  }

  /// Deletes a vendor profile. Their past credit_transactions rows are
  /// left as-is (same "keep the audit trail" approach used for cancelled
  /// sales) — they'll just no longer resolve to a vendor name in the app,
  /// though they still show in a data export.
  Future<void> deleteVendor(String vendorId) async {
    await _vendors.doc(vendorId).delete();
  }

  Future<double> getVendorBalance(String vendorId) async {
    final doc = await _vendors.doc(vendorId).get();
    if (!doc.exists) return 0;
    final data = doc.data() as Map<String, dynamic>;
    return (data['balance'] as num?)?.toDouble() ?? 0;
  }

  /// Records credit given (sale on credit) or a payment/collection from a
  /// vendor, keeping the vendor's balance field in sync. Reads then writes
  /// via a WriteBatch (not a transaction) so this works fully offline —
  /// see the class doc comment for why. Pass [date] to backdate an entry
  /// (e.g. entering old credit history) — defaults to now if omitted.
  Future<void> addCreditTransaction({
    required String vendorId,
    required String type, // CREDIT or PAYMENT
    required double amount,
    String? notes,
    String? saleId,
    String? date,
  }) async {
    final vendorRef = _vendors.doc(vendorId);
    final snap = await vendorRef.get();
    final data = snap.data() as Map<String, dynamic>? ?? {};
    final current = (data['balance'] as num?)?.toDouble() ?? 0;
    final newBalance = type == 'CREDIT' ? current + amount : current - amount;

    final batch = _fs.batch();
    batch.set(_creditTxns.doc(), {
      'vendor_id': vendorId,
      'vendor_name': data['name'],
      'date': date ?? DateTime.now().toIso8601String(),
      'type': type,
      'amount': amount,
      'balance_after': newBalance,
      'notes': notes,
      'sale_id': saleId,
    });
    batch.update(vendorRef, {'balance': newBalance});
    await batch.commit();
  }

  Future<List<Map<String, dynamic>>> getVendorTransactions(String vendorId) async {
    // Sorted client-side — see getStockHistory for why.
    final snap = await _creditTxns.where('vendor_id', isEqualTo: vendorId).get();
    final list = _fromSnapshot(snap);
    list.sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
    return list;
  }

  Future<List<Map<String, dynamic>>> getTodaysCollections() async {
    final todayPrefix = DateTime.now().toIso8601String().substring(0, 10);
    // Filters only by date range here (needs no composite index, same as
    // getSales) and filters type == PAYMENT client-side afterward, rather
    // than combining an equality filter with a range filter in the query.
    final snap = await _creditTxns
        .where('date', isGreaterThanOrEqualTo: todayPrefix)
        .where('date', isLessThan: '$todayPrefix\uf8ff')
        .get();
    final list = _fromSnapshot(snap).where((t) => t['type'] == 'PAYMENT').toList();
    list.sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
    return list;
  }

  /// Live version of getTodaysCollections — collections happen throughout
  /// the day from either phone, so this screen benefits from the same
  /// auto-update-without-refresh treatment as the other list screens.
  Stream<List<Map<String, dynamic>>> watchTodaysCollections() {
    final todayPrefix = DateTime.now().toIso8601String().substring(0, 10);
    return _creditTxns
        .where('date', isGreaterThanOrEqualTo: todayPrefix)
        .where('date', isLessThan: '$todayPrefix\uf8ff')
        .snapshots()
        .map((snap) {
      final list = _fromSnapshot(snap).where((t) => t['type'] == 'PAYMENT').toList();
      list.sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
      return list;
    });
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

  /// Day-by-day total outstanding credit (summed across every vendor) for
  /// the given period — feeds the "Credit Trend" chart on Reports &
  /// Trends. Unlike the vendor's own balance_after field (which reflects
  /// just that one vendor), this reconstructs the store-wide total at
  /// each point in time by replaying every CREDIT/PAYMENT/ADJUSTMENT
  /// transaction across all vendors in chronological order. A day with no
  /// transactions carries forward the previous day's total, since the
  /// total only changes when something is recorded.
  Future<List<Map<String, dynamic>>> getCreditTrend({
    required String startIso,
    required String endIsoExclusive,
  }) async {
    // Needs the FULL history up to the period's end, not just the period
    // itself, to correctly compute the starting balance the period opens
    // with (otherwise day one of the chart would wrongly start at zero).
    final snap = await _creditTxns.where('date', isLessThan: endIsoExclusive).get();
    final all = _fromSnapshot(snap);
    all.sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));

    double running = 0;
    final closingBalanceByDay = <String, double>{};
    for (final txn in all) {
      final type = txn['type'] as String;
      final amount = (txn['amount'] as num).toDouble();
      running += (type == 'CREDIT') ? amount : -amount; // PAYMENT and ADJUSTMENT both reduce it
      final day = (txn['date'] as String).substring(0, 10);
      closingBalanceByDay[day] = running; // last write per day wins == that day's closing balance
    }

    final startDate = DateTime.parse(startIso);
    final endDate = DateTime.parse(endIsoExclusive).subtract(const Duration(days: 1));

    // Carry-forward baseline: the latest closing balance strictly before
    // the period starts.
    final startKey = startIso.substring(0, 10);
    final priorDays = closingBalanceByDay.keys.where((d) => d.compareTo(startKey) < 0).toList()..sort();
    double carry = priorDays.isEmpty ? 0 : closingBalanceByDay[priorDays.last]!;

    final result = <Map<String, dynamic>>[];
    for (var d = startDate; !d.isAfter(endDate); d = d.add(const Duration(days: 1))) {
      final key = d.toIso8601String().substring(0, 10);
      if (closingBalanceByDay.containsKey(key)) carry = closingBalanceByDay[key]!;
      result.add({'date': key, 'total': carry});
    }
    return result;
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

    // Sorted client-side (ascending, oldest first) — see getStockHistory
    // for why the query itself has no orderBy.
    final snap = await _creditTxns.where('vendor_id', isEqualTo: vendorId).get();
    final txns = _fromSnapshot(snap);
    txns.sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));

    double runningBalance = 0;
    DateTime? openedSince;

    for (final t in txns) {
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

  /// Every vendor, enriched with purchase count, last purchase date, and
  /// (for anyone with a balance) how many days it's been outstanding —
  /// one combined dataset the Vendor Insights screen then sorts/groups
  /// different ways (by location, frequency, balance, or how overdue).
  /// A one-time fetch, not a live stream — this is a considered analysis
  /// view a store owner opens deliberately, not a running list, same
  /// reasoning as Reports & Trends.
  Future<List<Map<String, dynamic>>> getVendorAnalytics() async {
    final vendors = await getVendors();
    final salesSnap = await _sales.get();

    final purchaseCount = <String, int>{};
    final lastPurchase = <String, String>{};
    for (final doc in salesSnap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['status'] == 'cancelled') continue;
      final vid = data['vendor_id'] as String?;
      final date = data['date'] as String?;
      if (vid == null || date == null) continue;
      purchaseCount[vid] = (purchaseCount[vid] ?? 0) + 1;
      if (lastPurchase[vid] == null || date.compareTo(lastPurchase[vid]!) > 0) {
        lastPurchase[vid] = date;
      }
    }

    final result = <Map<String, dynamic>>[];
    for (final v in vendors) {
      final vid = v['id'] as String;
      final balance = (v['balance'] as num?)?.toDouble() ?? 0;
      final daysOutstanding = balance > 0 ? await getVendorOutstandingDays(vid) : null;
      result.add({
        ...v,
        'balance': balance,
        'purchase_count': purchaseCount[vid] ?? 0,
        'last_purchase_date': lastPurchase[vid],
        'days_outstanding': daysOutstanding,
      });
    }
    return result;
  }

  /// One consolidated fetch for the Vendors tab's insights strip — each
  /// vendor's transaction history is read once and used to derive
  /// several things together, rather than a separate query per metric:
  /// - avg_days_outstanding: average, across vendors currently owing,
  ///   of how long their present balance has been unpaid.
  /// - new_this_month: vendors added since the start of this calendar
  ///   month.
  /// - collected_this_week: credit payments collected in the last 7
  ///   days, across every vendor.
  /// - needs_attention: vendors who both owe money for 30+ days AND
  ///   have had no transaction (credit or payment) in the last 14 days
  ///   — overdue and gone quiet, the ones most worth following up on
  ///   first.
  /// - trends: each vendor's net balance change over the last 14 days
  ///   (positive = growing, i.e. owing more; negative = shrinking, i.e.
  ///   being paid down), keyed by vendor id.
  ///
  /// A one-time fetch per screen visit, not a live stream — same
  /// reasoning as Vendor Insights and Reports & Trends: a considered
  /// snapshot, not something that needs to update mid-glance.
  Future<Map<String, dynamic>> getVendorInsightsSummary() async {
    final vendors = await getVendors();
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7)).toIso8601String();
    final monthStart = DateTime(now.year, now.month, 1).toIso8601String();
    final trendCutoff = now.subtract(const Duration(days: 14)).toIso8601String();
    final attentionCutoff = now.subtract(const Duration(days: 14)).toIso8601String();

    var newThisMonth = 0;
    double collectedThisWeek = 0;
    final daysOutstandingList = <int>[];
    final needsAttention = <Map<String, dynamic>>[];
    final trends = <String, double>{};

    for (final v in vendors) {
      final createdAt = v['created_at'] as String?;
      if (createdAt != null && createdAt.compareTo(monthStart) >= 0) newThisMonth++;

      final vendorId = v['id'] as String;
      final balance = (v['balance'] as num?)?.toDouble() ?? 0;

      // Sorted client-side (ascending, oldest first) — see getStockHistory
      // for why the query itself has no orderBy.
      final snap = await _creditTxns.where('vendor_id', isEqualTo: vendorId).get();
      final txns = _fromSnapshot(snap)..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));

      for (final t in txns) {
        final date = t['date'] as String;
        final amount = (t['amount'] as num).toDouble();
        if (t['type'] == 'PAYMENT' && date.compareTo(weekAgo) >= 0) {
          collectedThisWeek += amount;
        }
      }

      if (balance <= 0) continue;

      // Same days-outstanding algorithm as getVendorOutstandingDays,
      // computed here inline so the transaction history fetched above
      // isn't queried a second time.
      double runningBalance = 0;
      DateTime? openedSince;
      String? lastActivity;
      for (final t in txns) {
        final date = t['date'] as String;
        final amount = (t['amount'] as num).toDouble();
        runningBalance = t['type'] == 'CREDIT' ? runningBalance + amount : runningBalance - amount;
        if (runningBalance <= 0) {
          openedSince = null;
        } else if (openedSince == null) {
          openedSince = DateTime.tryParse(date);
        }
        if (lastActivity == null || date.compareTo(lastActivity) > 0) lastActivity = date;
      }
      if (runningBalance <= 0 || openedSince == null) continue;
      final daysOut = now.difference(openedSince).inDays;
      daysOutstandingList.add(daysOut);

      double netChange = 0;
      for (final t in txns) {
        final date = t['date'] as String;
        if (date.compareTo(trendCutoff) < 0) continue;
        final amount = (t['amount'] as num).toDouble();
        netChange += t['type'] == 'CREDIT' ? amount : -amount;
      }
      trends[vendorId] = netChange;

      if (daysOut >= 30 && (lastActivity == null || lastActivity.compareTo(attentionCutoff) < 0)) {
        needsAttention.add({...v, 'balance': balance, 'days_outstanding': daysOut});
      }
    }

    needsAttention.sort((a, b) => (b['days_outstanding'] as int).compareTo(a['days_outstanding'] as int));
    final avgDaysOutstanding =
        daysOutstandingList.isEmpty ? 0.0 : daysOutstandingList.reduce((a, b) => a + b) / daysOutstandingList.length;

    return {
      'avg_days_outstanding': avgDaysOutstanding,
      'new_this_month': newThisMonth,
      'collected_this_week': collectedThisWeek,
      'needs_attention': needsAttention,
      'trends': trends,
    };
  }

  // ---------------- SALES ----------------

  /// Creates a sale with its line items, deducts stock for each item, and
  /// — if sold on credit — records the credit against the vendor. Every
  /// product and (if relevant) the vendor are read first, then everything
  /// is written via a single WriteBatch (not a transaction) so this works
  /// fully offline — see the class doc comment for why.
  Future<String> createSale({
    required List<Map<String, dynamic>> items, // product_id, product_name, quantity, unit_price
    required double discount,
    required String paymentType, // CASH, CREDIT, PARTIAL
    String? vendorId,
    required double paidAmount,
    String? notes,
    String? saleDate,
    String? dueDate,
  }) async {
    final subtotal = items.fold<double>(
        0, (sum, item) => sum + (item['quantity'] as num) * (item['unit_price'] as num));
    final total = subtotal - discount;
    final saleRef = _sales.doc();
    final now = saleDate ?? DateTime.now().toIso8601String();

    // ---- reads first ----
    final productRefs = <String, DocumentReference>{};
    final productData = <String, Map<String, dynamic>>{};
    for (final item in items) {
      final pid = item['product_id'] as String?;
      if (pid == null || productRefs.containsKey(pid)) continue;
      final ref = _products.doc(pid);
      final snap = await ref.get();
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
      final snap = await vendorRef.get();
      vendorData = snap.data() as Map<String, dynamic>? ?? {};
      vendorCurrentBalance = (vendorData['balance'] as num?)?.toDouble() ?? 0;
    }

    // ---- writes ----
    final batch = _fs.batch();
    batch.set(saleRef, {
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
      'due_date': dueDate,
    });

    for (final item in items) {
      final qty = (item['quantity'] as num).toDouble();
      final price = (item['unit_price'] as num).toDouble();
      final pid = item['product_id'] as String?;
      // Snapshot cost + category/subcategory at time of sale (not just
      // now, in case the product's price/category changes later) — feeds
      // the Gross Profit and By-Category/By-Subcategory numbers on
      // Reports & Trends.
      final unitCost = (pid != null && productData.containsKey(pid))
          ? (productData[pid]!['cost_price'] as num?)?.toDouble() ?? 0
          : 0.0;
      final category = (pid != null && productData.containsKey(pid))
          ? (productData[pid]!['category'] as String? ?? '')
          : '';
      final subcategory = (pid != null && productData.containsKey(pid))
          ? (productData[pid]!['subcategory'] as String? ?? '')
          : '';
      batch.set(_saleItems.doc(), {
        'sale_id': saleRef.id,
        'sale_date': now,
        'product_id': item['product_id'],
        'product_name': item['product_name'],
        'quantity': qty,
        'unit_price': price,
        'subtotal': qty * price,
        'unit_cost': unitCost,
        'category': category,
        'subcategory': subcategory,
        'status': 'confirmed',
      });

      if (pid != null && productRefs.containsKey(pid)) {
        final current = (productData[pid]!['quantity'] as num?)?.toDouble() ?? 0;
        batch.update(productRefs[pid]!, {
          'quantity': current - qty,
          'updated_at': now,
        });
        batch.set(_stockMovements.doc(), {
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
        batch.set(_creditTxns.doc(), {
          'vendor_id': vendorId,
          'vendor_name': vendorData?['name'],
          'date': now,
          'type': 'CREDIT',
          'amount': creditAmount,
          'balance_after': newBalance,
          'notes': 'Credit sale #${saleRef.id}',
          'sale_id': saleRef.id,
        });
        batch.update(vendorRef, {'balance': newBalance});
      }
    }

    await batch.commit();
    return saleRef.id;
  }

  /// Reverses a sale: restores the stock it deducted, reverses the credit
  /// it posted to the vendor's balance (if any), and marks the sale (and
  /// its line items) as cancelled rather than deleting them, so there's
  /// still a full audit trail of what happened. Safe to call even if
  /// items/vendor were since deleted — those parts are just skipped.
  ///
  /// Reads the sale, its line items, the vendor, and every referenced
  /// product first, then writes every reversal via a single WriteBatch
  /// (not a transaction) so this works fully offline — see the class doc
  /// comment for why.
  Future<void> cancelSale(String saleId) async {
    final saleDoc = await _sales.doc(saleId).get();
    if (!saleDoc.exists) return;
    final saleData = saleDoc.data() as Map<String, dynamic>;
    if (saleData['status'] == 'cancelled') return; // already cancelled

    final itemsSnap = await _saleItems.where('sale_id', isEqualTo: saleId).get();
    final creditSnap = await _creditTxns.where('sale_id', isEqualTo: saleId).limit(1).get();
    final vendorId = saleData['vendor_id'] as String?;
    final now = DateTime.now().toIso8601String();

    // ---- reads first ----
    final saleRef = _sales.doc(saleId);
    final productRefs = <String, DocumentReference>{};
    final productData = <String, Map<String, dynamic>>{};
    for (final doc in itemsSnap.docs) {
      final item = doc.data() as Map<String, dynamic>;
      final pid = item['product_id'] as String?;
      if (pid == null || productRefs.containsKey(pid)) continue;
      final ref = _products.doc(pid);
      final snap = await ref.get();
      if (snap.exists) {
        productRefs[pid] = ref;
        productData[pid] = snap.data() as Map<String, dynamic>;
      }
    }

    DocumentReference? vendorRef;
    Map<String, dynamic>? vendorData;
    if (vendorId != null) {
      vendorRef = _vendors.doc(vendorId);
      final snap = await vendorRef.get();
      if (snap.exists) vendorData = snap.data() as Map<String, dynamic>;
    }

    // ---- writes ----
    final batch = _fs.batch();
    batch.update(saleRef, {'status': 'cancelled', 'cancelled_at': now});

    for (final doc in itemsSnap.docs) {
      final item = doc.data() as Map<String, dynamic>;
      batch.update(doc.reference, {'status': 'cancelled'});

      final pid = item['product_id'] as String?;
      final qty = (item['quantity'] as num).toDouble();
      if (pid != null && productRefs.containsKey(pid)) {
        final current = (productData[pid]!['quantity'] as num?)?.toDouble() ?? 0;
        batch.update(productRefs[pid]!, {
          'quantity': current + qty,
          'updated_at': now,
        });
        batch.set(_stockMovements.doc(), {
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
      batch.update(vendorRef, {'balance': newBalance});
      batch.set(_creditTxns.doc(), {
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

    await batch.commit();
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

  /// Live version of getSales — see watchSuppliers for why this exists.
  Stream<List<Map<String, dynamic>>> watchSales({String? dateFilter}) {
    Query query = _sales.orderBy('date', descending: true);
    if (dateFilter != null) {
      query = _sales
          .where('date', isGreaterThanOrEqualTo: dateFilter)
          .where('date', isLessThan: '$dateFilter\uf8ff')
          .orderBy('date', descending: true);
    }
    return query.snapshots().map(_fromSnapshot);
  }

  /// Raw change streams (not mapped to our usual list shape) purely so the
  /// Dashboard can listen for "something changed" and refresh its
  /// aggregates automatically — without needing every individual metric
  /// on the Dashboard rebuilt as its own stream.
  Stream<QuerySnapshot> watchSalesRaw() => _sales.snapshots();
  Stream<QuerySnapshot> watchCreditTransactionsRaw() => _creditTxns.snapshots();

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

  /// Revenue (post-discount total actually invoiced), cost of goods sold
  /// (from each sale item's cost snapshot), the resulting gross profit,
  /// and the number of sales — feeds Reports & Trends and the Dashboard's
  /// Gross Profit card. Revenue/count come from `sales`; cost comes from
  /// `sale_items`, since that's where the per-line cost is recorded.
  Future<Map<String, dynamic>> getRevenueCostProfit({
    required String startIso,
    required String endIsoExclusive,
  }) async {
    final salesSnap = await _sales
        .where('date', isGreaterThanOrEqualTo: startIso)
        .where('date', isLessThan: endIsoExclusive)
        .get();
    double revenue = 0;
    int count = 0;
    for (final doc in salesSnap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['status'] == 'cancelled') continue;
      revenue += (data['total_amount'] as num?)?.toDouble() ?? 0;
      count++;
    }

    final itemsSnap = await _saleItems
        .where('sale_date', isGreaterThanOrEqualTo: startIso)
        .where('sale_date', isLessThan: endIsoExclusive)
        .get();
    double cost = 0;
    for (final doc in itemsSnap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['status'] == 'cancelled') continue;
      final qty = (data['quantity'] as num?)?.toDouble() ?? 0;
      final unitCost = (data['unit_cost'] as num?)?.toDouble() ?? 0;
      cost += qty * unitCost;
    }

    return {'revenue': revenue, 'cost': cost, 'profit': revenue - cost, 'count': count};
  }

  /// Actual cash that physically came into the shop during a period —
  /// deliberately separate from Revenue/Profit above, which count a sale
  /// the moment it's made regardless of payment type. Split into two
  /// sources, matching how money actually arrives:
  /// - cash_collected: the immediate amount collected on sales made THIS
  ///   period (full amount for a CASH sale, just the upfront portion for
  ///   a PARTIAL sale — a CREDIT sale contributes 0 here since nothing
  ///   was collected at the time).
  /// - credit_payments_collected: money collected THIS period against
  ///   debt a vendor already owed — could be from an old sale, not
  ///   necessarily one made this period. ADJUSTMENT entries (a cancelled
  ///   sale reversing its own credit) are excluded — that's a correction,
  ///   not real cash coming in.
  Future<Map<String, dynamic>> getCashCollected({
    required String startIso,
    required String endIsoExclusive,
  }) async {
    final salesSnap = await _sales
        .where('date', isGreaterThanOrEqualTo: startIso)
        .where('date', isLessThan: endIsoExclusive)
        .get();
    double cashCollected = 0;
    for (final doc in salesSnap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['status'] == 'cancelled') continue;
      final type = data['payment_type'] as String?;
      if (type == 'CASH' || type == 'PARTIAL') {
        cashCollected += (data['paid_amount'] as num?)?.toDouble() ?? 0;
      }
    }

    final txnSnap = await _creditTxns
        .where('date', isGreaterThanOrEqualTo: startIso)
        .where('date', isLessThan: endIsoExclusive)
        .get();
    double creditPaymentsCollected = 0;
    for (final doc in txnSnap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['type'] == 'PAYMENT') {
        creditPaymentsCollected += (data['amount'] as num?)?.toDouble() ?? 0;
      }
    }

    return {'cash_collected': cashCollected, 'credit_payments_collected': creditPaymentsCollected};
  }

  /// Sales broken down by product category for a date range — feeds the
  /// "By Category" section of Reports & Trends. Products added before
  /// this feature existed (or with no category set) group under "—".
  Future<List<Map<String, dynamic>>> getCategoryWiseSales({
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
      final category = (data['category'] as String?)?.trim();
      final key = (category == null || category.isEmpty) ? '—' : category;
      totals[key] = (totals[key] ?? 0) + ((data['subtotal'] as num?)?.toDouble() ?? 0);
    }
    final result = totals.entries.map((e) => {'category': e.key, 'total': e.value}).toList();
    result.sort((a, b) => (b['total'] as double).compareTo(a['total'] as double));
    return result;
  }

  /// Same as getCategoryWiseSales, but grouped by subcategory — feeds the
  /// "By Subcategory" section of Reports & Trends. Only sales made after
  /// subcategory-snapshotting was added will have this field; older sale
  /// items group under "—" along with products that have no subcategory.
  Future<List<Map<String, dynamic>>> getSubcategoryWiseSales({
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
      final subcategory = (data['subcategory'] as String?)?.trim();
      final key = (subcategory == null || subcategory.isEmpty) ? '—' : subcategory;
      totals[key] = (totals[key] ?? 0) + ((data['subtotal'] as num?)?.toDouble() ?? 0);
    }
    final result = totals.entries.map((e) => {'subcategory': e.key, 'total': e.value}).toList();
    result.sort((a, b) => (b['total'] as double).compareTo(a['total'] as double));
    return result;
  }

  /// Total currently owed to all suppliers combined — the supplier-side
  /// counterpart to getTotalOutstandingCredit.
  Future<double> getTotalSupplierDues() async {
    final snap = await _suppliers.get();
    double total = 0;
    for (final doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      total += (data['balance'] as num?)?.toDouble() ?? 0;
    }
    return total;
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

  // ---------------- IMPORT: CREDIT / PURCHASE HISTORY ----------------
  // Unlike sales, a credit or payment entry has no stock side effect —
  // it's just a balance adjustment. That makes it safe to import in bulk,
  // as long as each row is replayed through the same addCreditTransaction/
  // addSupplierTransaction used everywhere else in the app (so the
  // balance field stays correctly in sync), rather than writing rows
  // directly. Rows are sorted by date before replaying them, so each
  // entry's running balance snapshot reflects the true historical order,
  // not just whatever order they happened to appear in the file.

  /// Imports vendor credit/payment history from parsed CSV rows. Each row
  /// needs: vendor_name, type (CREDIT or PAYMENT), amount, date — notes
  /// is optional. Rows that don't match an existing vendor by name, or
  /// are missing a valid date/amount/type, are skipped and counted.
  Future<Map<String, int>> importVendorCreditHistory(List<Map<String, dynamic>> rows) async {
    final valid = <Map<String, dynamic>>[];
    var skipped = 0;
    for (final row in rows) {
      final vendorName = (row['vendor_name'] as String? ?? '').trim();
      final type = (row['type'] as String? ?? '').trim().toUpperCase();
      final amount = (row['amount'] as num?)?.toDouble() ?? 0;
      final parsedDate = DateTime.tryParse((row['date'] as String? ?? '').trim());
      if (vendorName.isEmpty || amount <= 0 || (type != 'CREDIT' && type != 'PAYMENT') || parsedDate == null) {
        skipped++;
        continue;
      }
      valid.add({
        'vendor_name': vendorName,
        'type': type,
        'amount': amount,
        'date': parsedDate.toIso8601String(),
        'notes': row['notes'],
      });
    }
    valid.sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));

    var imported = 0;
    for (final row in valid) {
      final existing = await _vendors
          .where('name_lower', isEqualTo: (row['vendor_name'] as String).toLowerCase())
          .limit(1)
          .get();
      if (existing.docs.isEmpty) {
        skipped++;
        continue;
      }
      await addCreditTransaction(
        vendorId: existing.docs.first.id,
        type: row['type'] as String,
        amount: row['amount'] as double,
        notes: row['notes'] as String?,
        date: row['date'] as String,
      );
      imported++;
    }
    return {'imported': imported, 'skipped': skipped};
  }

  /// Same as importVendorCreditHistory, for suppliers. Each row needs:
  /// supplier_name, type (PURCHASE or PAYMENT), amount, date, and
  /// optional notes.
  Future<Map<String, int>> importSupplierTransactionHistory(List<Map<String, dynamic>> rows) async {
    final valid = <Map<String, dynamic>>[];
    var skipped = 0;
    for (final row in rows) {
      final supplierName = (row['supplier_name'] as String? ?? '').trim();
      final type = (row['type'] as String? ?? '').trim().toUpperCase();
      final amount = (row['amount'] as num?)?.toDouble() ?? 0;
      final parsedDate = DateTime.tryParse((row['date'] as String? ?? '').trim());
      if (supplierName.isEmpty ||
          amount <= 0 ||
          (type != 'PURCHASE' && type != 'PAYMENT') ||
          parsedDate == null) {
        skipped++;
        continue;
      }
      valid.add({
        'supplier_name': supplierName,
        'type': type,
        'amount': amount,
        'date': parsedDate.toIso8601String(),
        'notes': row['notes'],
      });
    }
    valid.sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));

    var imported = 0;
    for (final row in valid) {
      final existing = await _suppliers
          .where('name_lower', isEqualTo: (row['supplier_name'] as String).toLowerCase())
          .limit(1)
          .get();
      if (existing.docs.isEmpty) {
        skipped++;
        continue;
      }
      await addSupplierTransaction(
        supplierId: existing.docs.first.id,
        type: row['type'] as String,
        amount: row['amount'] as double,
        notes: row['notes'] as String?,
      );
      imported++;
    }
    return {'imported': imported, 'skipped': skipped};
  }
}
