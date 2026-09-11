class VendorCredit {
  final String id;
  final String vendorName;
  final double creditLimit;
  final double oldCredit;
  final double newCredit;
  final DateTime dueDate;

  VendorCredit({
    required this.id,
    required this.vendorName,
    required this.creditLimit,
    required this.oldCredit,
    required this.newCredit,
    required this.dueDate,
  });

  double get totalCredit => oldCredit + newCredit;

  int get overdueDays {
    final now = DateTime.now();
    if (now.isBefore(dueDate)) return 0;
    return now.difference(dueDate).inDays;
  }

  bool get isBlocked => overdueDays > 60 || totalCredit > creditLimit;

  factory VendorCredit.fromMap(String id, Map<String, dynamic> map) {
    return VendorCredit(
      id: id,
      vendorName: map['vendorName'] ?? '',
      creditLimit: (map['creditLimit'] ?? 0.0).toDouble(),
      oldCredit: (map['oldCredit'] ?? 0.0).toDouble(),
      newCredit: (map['newCredit'] ?? 0.0).toDouble(),
      dueDate: map['dueDate'] != null ? DateTime.parse(map['dueDate']) : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'vendorName': vendorName,
      'creditLimit': creditLimit,
      'oldCredit': oldCredit,
      'newCredit': newCredit,
      'dueDate': dueDate.toIso8601String(),
    };
  }
}
