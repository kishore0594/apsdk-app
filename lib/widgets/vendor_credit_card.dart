import 'package:flutter/material.dart';
import '../models/vendor_credit_model.dart';

class VendorCreditCard extends StatelessWidget {
  final VendorCredit vendor;
  final VoidCallback onAddCredit;
  final VoidCallback onRecordPayment;

  const VendorCreditCard({
    super.key,
    required this.vendor,
    required this.onAddCredit,
    required this.onRecordPayment,
  });

  Color _getBadgeColor() {
    if (vendor.isBlocked) return Colors.red;
    if (vendor.overdueDays > 30) return Colors.orange;
    return Colors.green;
  }

  String _getBadgeText() {
    if (vendor.overdueDays > 60) return 'BLOCKED (60+ Days Overdue)';
    if (vendor.totalCredit > vendor.creditLimit) return 'LIMIT EXCEEDED';
    if (vendor.overdueDays > 0) return '${vendor.overdueDays} Days Overdue';
    return 'ON TIME';
  }

  @override
  Widget build(BuildContext context) {
    final double usageRatio = (vendor.totalCredit / vendor.creditLimit).clamp(0.0, 1.0);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    vendor.vendorName,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getBadgeColor().withAlpha(30),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _getBadgeColor()),
                  ),
                  child: Text(
                    _getBadgeText(),
                    style: TextStyle(
                      color: _getBadgeColor(),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildMetric('Old Credit', '₹${vendor.oldCredit.toStringAsFixed(0)}', Colors.grey[700]!),
                _buildMetric('New Credit', '₹${vendor.newCredit.toStringAsFixed(0)}', Colors.blue[800]!),
                _buildMetric('Total Balance', '₹${vendor.totalCredit.toStringAsFixed(0)}', Colors.black),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Credit Utilization', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                Text(
                  '₹${vendor.totalCredit.toStringAsFixed(0)} / ₹${vendor.creditLimit.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: usageRatio,
              backgroundColor: Colors.grey[200],
              color: usageRatio > 0.9 ? Colors.red : Colors.green,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: vendor.isBlocked ? null : onAddCredit,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New Credit'),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.blue[800]),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onRecordPayment,
                    icon: const Icon(Icons.payments, size: 18),
                    label: const Text('Record Payment'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetric(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}
