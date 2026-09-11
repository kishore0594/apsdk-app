import 'package:cloud_firestore/cloud_firestore.dart';

class CreditService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> issueNewCredit({
    required String vendorId,
    required double newAmount,
    required int termsInDays,
  }) async {
    final vendorRef = _db.collection('vendors').doc(vendorId);

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(vendorRef);

      if (!snapshot.exists) {
        throw Exception("Vendor record not found");
      }

      final data = snapshot.data()!;
      final double oldCredit = (data['oldCredit'] ?? 0.0).toDouble();
      final double currentNewCredit = (data['newCredit'] ?? 0.0).toDouble();
      final double creditLimit = (data['creditLimit'] ?? 0.0).toDouble();

      final double proposedNewCredit = currentNewCredit + newAmount;
      final double proposedTotal = oldCredit + proposedNewCredit;

      if (proposedTotal > creditLimit) {
        throw Exception("Credit limit of ₹$creditLimit exceeded. Total would be ₹$proposedTotal");
      }

      transaction.update(vendorRef, {
        'newCredit': proposedNewCredit,
        'dueDate': DateTime.now().add(Duration(days: termsInDays)).toIso8601String(),
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> recordPayment({
    required String vendorId,
    required double amountPaid,
  }) async {
    final vendorRef = _db.collection('vendors').doc(vendorId);

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(vendorRef);
      if (!snapshot.exists) throw Exception("Vendor record not found");

      final data = snapshot.data()!;
      double oldCredit = (data['oldCredit'] ?? 0.0).toDouble();
      double newCredit = (data['newCredit'] ?? 0.0).toDouble();

      double remainingPayment = amountPaid;

      if (oldCredit > 0) {
        if (remainingPayment >= oldCredit) {
          remainingPayment -= oldCredit;
          oldCredit = 0;
        } else {
          oldCredit -= remainingPayment;
          remainingPayment = 0;
        }
      }

      if (remainingPayment > 0 && newCredit > 0) {
        newCredit = (newCredit - remainingPayment).clamp(0, double.infinity);
      }

      transaction.update(vendorRef, {
        'oldCredit': oldCredit,
        'newCredit': newCredit,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> processMonthlyRollover(String vendorId) async {
    final vendorRef = _db.collection('vendors').doc(vendorId);

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(vendorRef);
      if (!snapshot.exists) return;

      final data = snapshot.data()!;
      final double oldCredit = (data['oldCredit'] ?? 0.0).toDouble();
      final double newCredit = (data['newCredit'] ?? 0.0).toDouble();

      transaction.update(vendorRef, {
        'oldCredit': oldCredit + newCredit,
        'newCredit': 0.0,
        'lastRolloverDate': FieldValue.serverTimestamp(),
      });
    });
  }
}
