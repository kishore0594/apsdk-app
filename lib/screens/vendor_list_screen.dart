import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/vendor_service.dart';
import 'vendor_credit_history_screen.dart';

class VendorListScreen extends StatefulWidget {
  const VendorListScreen({super.key});

  @override
  State<VendorListScreen> createState() => _VendorListScreenState();
}

class _VendorListScreenState extends State<VendorListScreen> {
  final VendorService _vendorService = VendorService();

  void _showAddVendorDialog() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final initialCreditController = TextEditingController(text: '0');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Vendor'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Name')),
            TextField(controller: phoneController, decoration: const InputDecoration(labelText: 'Phone')),
            TextField(controller: initialCreditController, decoration: const InputDecoration(labelText: 'Opening Credit (₹)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty) {
                Navigator.pop(ctx);
                await _vendorService.createVendor(
                  name: nameController.text.trim(),
                  phone: phoneController.text.trim(),
                  initialCredit: double.tryParse(initialCreditController.text.trim()) ?? 0.0,
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vendors'), backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddVendorDialog,
        backgroundColor: Colors.green.shade700,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _vendorService.getVendorsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data?.docs ?? [];
          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();
              return ListTile(
                title: Text(data['name'] ?? ''),
                subtitle: Text('Credit: ₹${((data['currentCredit'] ?? 0) as num).toStringAsFixed(2)}'),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => VendorCreditHistoryScreen(
                        vendorId: doc.id,
                        vendorName: data['name'] ?? '',
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
