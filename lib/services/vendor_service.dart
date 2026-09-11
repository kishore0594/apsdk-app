import 'package:cloud_firestore/cloud_firestore.dart';

class VendorService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<QuerySnapshot<Map<String, dynamic>>> getVendorsStream() {
    return _db.collection('vendors').orderBy('name').snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getVendorHistoryStream(String vendorId) {
    return _db
        .collection('vendors')
        .doc(vendorId)
        .collection('credit_history')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  Future<void> recordTransaction({
    required String vendorId,
    required double amount,
    required String type,
    required String note,
  }) async {
    final vendorRef = _db.collection('vendors').doc(vendorId);
    final historyRef = vendorRef.collection('credit_history').doc();

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(vendorRef);
      if (!snapshot.exists) throw Exception("Vendor does not exist.");

      final double currentCredit = ((snapshot.data()?['currentCredit'] ?? 0) as num).toDouble();
      final double newCredit = currentCredit + amount;

      transaction.set(historyRef, {
        'id': historyRef.id,
        'vendorId': vendorId,
        'amount': amount,
        'previousCredit': currentCredit,
        'newCredit': newCredit,
        'type': type,
        'note': note,
        'timestamp': FieldValue.serverTimestamp(),
      });

      transaction.update(vendorRef, {
        'currentCredit': newCredit,
        'lastTransactionDate': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> createVendor({
    required String name,
    required String phone,
    double initialCredit = 0.0,
  }) async {
    final docRef = _db.collection('vendors').doc();
    await _db.runTransaction((transaction) async {
      transaction.set(docRef, {
        'id': docRef.id,
        'name': name,
        'phone': phone,
        'currentCredit': initialCredit,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (initialCredit != 0) {
        final historyRef = docRef.collection('credit_history').doc();
        transaction.set(historyRef, {
          'id': historyRef.id,
          'vendorId': docRef.id,
          'amount': initialCredit,
          'previousCredit': 0.0,
          'newCredit': initialCredit,
          'type': 'INITIAL_BALANCE',
          'note': 'Initial opening credit',
          'timestamp': FieldValue.serverTimestamp(),
        });
      }
    });
  }
}
