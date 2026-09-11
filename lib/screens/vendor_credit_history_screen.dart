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
      appBar: AppBar(
        title: Text('$vendorName Details'),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: vendorService.getVendorHistoryStream(vendorId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error loading history: ${snapshot.error}'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.green));
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('No transaction history found for this vendor.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12.0),
            itemCount: docs.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final data = docs[index].data();
              final double amount = ((data['amount'] ?? 0) as num).toDouble();
              final double newCredit = ((data['newCredit'] ?? 0) as num).toDouble();
              final String note = data['note'] ?? 'No Note';
              final String type = data['type'] ?? '';
              final Timestamp? timestamp = data['timestamp'] as Timestamp?;
              final String formattedDate = timestamp != null
                  ? "${timestamp.toDate().day}/${timestamp.toDate().month}/${timestamp.toDate().year}"
                  : "Recent";

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                leading: CircleAvatar(
                  backgroundColor: amount > 0 ? Colors.red.shade100 : Colors.green.shade100,
                  child: Icon(
                    amount > 0 ? Icons.add_circle_outline : Icons.remove_circle_outline,
                    color: amount > 0 ? Colors.red : Colors.green,
                  ),
                ),
                title: Text(note, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('$type • $formattedDate\nBalance: ₹${newCredit.toStringAsFixed(2)}'),
                isThreeLine: true,
                trailing: Text(
                  '${amount > 0 ? "+" : ""}₹${amount.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: amount > 0 ? Colors.red.shade700 : Colors.green.shade700,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
