import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/vendor_credit_model.dart';
import '../widgets/vendor_credit_card.dart';
import '../services/credit_service.dart';

class VendorCreditScreen extends StatelessWidget {
  const VendorCreditScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final CreditService creditService = CreditService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vendor Credit Management'),
        backgroundColor: Colors.blue[900],
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('vendors').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error loading credit data: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];
          final vendors = docs
              .map((doc) => VendorCredit.fromMap(doc.id, doc.data() as Map<String, dynamic>))
              .toList();

          if (vendors.isEmpty) {
            return const Center(child: Text('No vendor credit accounts found.'));
          }

          final double totalOutstanding = vendors.fold(0, (sum, v) => sum + v.totalCredit);
          final double totalOverdue = vendors
              .where((v) => v.overdueDays > 0)
              .fold(0, (sum, v) => sum + v.totalCredit);

          return Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.blue[900],
                child: Row(
                  children: [
                    _buildKpiCard('Total Outstanding', '₹${totalOutstanding.toStringAsFixed(0)}', Colors.white),
                    Container(height: 40, width: 1, color: Colors.white30),
                    _buildKpiCard('Overdue Balance', '₹${totalOverdue.toStringAsFixed(0)}', Colors.orangeAccent),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: vendors.length,
                  itemBuilder: (context, index) {
                    final vendor = vendors[index];
                    return VendorCreditCard(
                      vendor: vendor,
                      onAddCredit: () => _showAddCreditDialog(context, vendor, creditService),
                      onRecordPayment: () => _showPaymentDialog(context, vendor, creditService),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildKpiCard(String title, String amount, Color amountColor) {
    return Expanded(
      child: Column(
        children: [
          Text(title, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 4),
          Text(amount, style: TextStyle(color: amountColor, fontSize: 20, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  void _showAddCreditDialog(BuildContext context, VendorCredit vendor, CreditService service) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Issue Credit — ${vendor.vendorName}'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Amount (₹)', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final double? amount = double.tryParse(controller.text);
              if (amount != null && amount > 0) {
                Navigator.pop(ctx);
                try {
                  await service.issueNewCredit(vendorId: vendor.id, newAmount: amount, termsInDays: 30);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Credit issued successfully')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
                    );
                  }
                }
              }
            },
            child: const Text('Issue Credit'),
          ),
        ],
      ),
    );
  }

  void _showPaymentDialog(BuildContext context, VendorCredit vendor, CreditService service) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Record Payment — ${vendor.vendorName}'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Amount Paid (₹)', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final double? amount = double.tryParse(controller.text);
              if (amount != null && amount > 0) {
                Navigator.pop(ctx);
                try {
                  await service.recordPayment(vendorId: vendor.id, amountPaid: amount);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Payment recorded successfully')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
                    );
                  }
                }
              }
            },
            child: const Text('Record Payment'),
          ),
        ],
      ),
    );
  }
}
