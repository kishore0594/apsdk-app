import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/vendor_service.dart';

class VendorCreditHistoryScreen extends StatelessWidget {
  final String vendorId;
  final String vendorName;

  const VendorCreditHistoryScreen({
    super.key,
    required this.vendorId,
    required this.vendorName,
  });

  @override
  Widget build(BuildContext context) {
    final VendorService vendorService = VendorService();

    return Scaffold(
      appBar: AppBar(title: Text('$vendorName History'), backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: vendorService.getVendorHistoryStream(vendorId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) return const Center(child: Text('No transaction history found.'));

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data();
              final double amount = ((data['amount'] ?? 0) as num).toDouble();
              return ListTile(
                title: Text(data['note'] ?? ''),
                subtitle: Text('New Balance: ₹${((data['newCredit'] ?? 0) as num).toStringAsFixed(2)}'),
                trailing: Text('₹${amount.toStringAsFixed(2)}', style: TextStyle(color: amount > 0 ? Colors.red : Colors.green, fontWeight: FontWeight.bold)),
              );
            },
          );
        },
      ),
    );
  }
}
