import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'vendor_list_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  double _totalVendorCredit = 0.0;
  int _totalVendors = 0;

  @override
  void initState() {
    super.initState();
    _fetchDashboardData();
  }

  Future<void> _fetchDashboardData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('vendors')
          .get()
          .timeout(const Duration(seconds: 10));

      double totalCredit = 0.0;
      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        totalCredit += ((data['currentCredit'] ?? 0) as num).toDouble();
      }

      if (mounted) {
        setState(() {
          _totalVendorCredit = totalCredit;
          _totalVendors = querySnapshot.docs.length;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "Failed to load dashboard: ${e.toString()}";
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Madhura Agro Traders'),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchDashboardData,
          ),
        ],
      ),
      body: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.green),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _fetchDashboardData,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchDashboardData,
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Card(
            child: ListTile(
              title: const Text('Total Vendor Credit'),
              subtitle: Text('₹${_totalVendorCredit.toStringAsFixed(2)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const VendorListScreen()),
              ).then((_) => _fetchDashboardData());
            },
            child: const Text('View All Vendors'),
          ),
        ],
      ),
    );
  }
}
