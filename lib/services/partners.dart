import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../db/db_helper.dart';

/// Partner (friend) referral programme.
///
/// - Each partner gets a short random code. Their link is
///   madhuraagro.in/r/CODE — the customer only ever sees madhuraagro.in;
///   the website quietly saves the code on the order.
/// - A NEW customer who comes through a partner is linked to that partner
///   for [linkDays] days: their online orders AND shop bills in that time
///   earn the partner commission (written on each sale by createSale).
/// - Commission is "pending" until the customer pays, then "earned";
///   cancelled sales drop out. Paying a partner also records a Marketing
///   expense, so profit reports stay right.
class Partners {
  Partners._();
  static final Partners instance = Partners._();

  static const int linkDays = 90;
  static const String site = 'https://madhuraagro.in';
  static String linkFor(String code) => '$site/r/$code';

  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  CollectionReference get _partners => _fs.collection('partners');
  CollectionReference get _payments => _fs.collection('partner_payments');

  /// Same offline rule as DBHelper: saved on the phone at once, syncs later.
  Future<void> _write(Future<void> op) async {
    try {
      await op.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      op.catchError((Object e) {
        debugPrint('Queued partner write failed when syncing: $e');
      });
    }
  }

  Map<String, dynamic> _withId(DocumentSnapshot d) => {...((d.data() as Map<String, dynamic>?) ?? {}), 'id': d.id};

  Stream<List<Map<String, dynamic>>> watchPartners() => _partners.snapshots().map((s) {
        final list = s.docs.map(_withId).toList();
        list.sort((a, b) => (a['name'] ?? '').toString().toLowerCase().compareTo((b['name'] ?? '').toString().toLowerCase()));
        return list;
      });

  Future<List<Map<String, dynamic>>> getPartners() async {
    final s = await _partners.get();
    return s.docs.map(_withId).toList();
  }

  static const _letters = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; // no 0/O, 1/I/L

  static String newCode(Iterable<String> taken) {
    final r = math.Random.secure();
    final used = taken.map((e) => e.toUpperCase()).toSet();
    while (true) {
      final c = List.generate(5, (_) => _letters[r.nextInt(_letters.length)]).join();
      if (!used.contains(c)) return c;
    }
  }

  Future<String> addPartner({
    required String name,
    required String phone,
    String upi = '',
    String place = '',
    required Iterable<String> takenCodes,
  }) async {
    final ref = _partners.doc();
    final code = newCode(takenCodes);
    await _write(ref.set({
      'name': name.trim(),
      'phone': phone.trim(),
      'upi': upi.trim(),
      'place': place.trim(),
      'code': code,
      'active': true,
      'created_at': DateTime.now().toIso8601String(),
    }));
    return ref.id;
  }

  Future<void> updatePartner(String id, Map<String, dynamic> data) => _write(_partners.doc(id).update(data));

  /// Partner for a website order's code, or null.
  Future<Map<String, dynamic>?> findByCode(String code) async {
    final c = code.trim().toUpperCase();
    if (c.isEmpty) return null;
    try {
      final s = await _partners.where('code', isEqualTo: c).limit(1).get();
      return s.docs.isEmpty ? null : _withId(s.docs.first);
    } catch (_) {
      return null;
    }
  }

  /// Link a customer (vendor) to a partner from today.
  Future<void> linkCustomer(String vendorId, Map<String, dynamic> partner) =>
      _write(_fs.collection('vendors').doc(vendorId).update({
        'partner_id': partner['id'],
        'partner_name': partner['name'],
        'partner_since': DateTime.now().toIso8601String(),
      }));

  Future<void> unlinkCustomer(String vendorId) => _write(_fs.collection('vendors').doc(vendorId).update({
        'partner_id': FieldValue.delete(),
        'partner_name': FieldValue.delete(),
        'partner_since': FieldValue.delete(),
      }));

  /// Is this customer still inside their partner's 90 days?
  static bool linkActive(Map<String, dynamic>? vendor, {DateTime? at}) {
    if (vendor == null) return false;
    final pid = (vendor['partner_id'] ?? '').toString();
    final since = DateTime.tryParse((vendor['partner_since'] ?? '').toString());
    if (pid.isEmpty || since == null) return false;
    final when = at ?? DateTime.now();
    return !when.isBefore(since.subtract(const Duration(days: 1))) &&
        when.difference(since).inDays < linkDays;
  }

  static DateTime? linkEnds(Map<String, dynamic> vendor) {
    final since = DateTime.tryParse((vendor['partner_since'] ?? '').toString());
    return since?.add(const Duration(days: linkDays));
  }

  /// Everything one partner's account shows.
  Future<PartnerAccount> account(String partnerId) async {
    final r = await Future.wait([
      _fs.collection('sales').where('partner_id', isEqualTo: partnerId).get(),
      _fs.collection('vendors').where('partner_id', isEqualTo: partnerId).get(),
      _payments.where('partner_id', isEqualTo: partnerId).get(),
    ]);
    final sales = r[0].docs.map(_withId).toList();
    final customers = r[1].docs.map(_withId).toList();
    final payments = r[2].docs.map(_withId).toList();
    // Vendors of these sales (also ones since unlinked) — for "has paid?".
    final balances = <String, double>{for (final v in customers) v['id'] as String: _n(v['balance'])};
    for (final s in sales) {
      final vid = (s['vendor_id'] ?? '').toString();
      if (vid.isEmpty || balances.containsKey(vid)) continue;
      try {
        final d = await _fs.collection('vendors').doc(vid).get();
        balances[vid] = _n((d.data() as Map<String, dynamic>?)?['balance']);
      } catch (_) {
        balances[vid] = 0;
      }
    }
    final entries = <PartnerEntry>[];
    for (final s in sales) {
      final amount = _n(s['partner_commission']);
      final total = _n(s['total_amount']);
      final paid = _n(s['paid_amount']);
      final vid = (s['vendor_id'] ?? '').toString();
      final String state;
      if (s['status'] == 'cancelled') {
        state = 'cancelled';
      } else if (s['payment_type'] == 'CASH' || paid >= total - 0.5 || (vid.isNotEmpty && (balances[vid] ?? 0) <= 0.5)) {
        state = 'earned';
      } else {
        state = 'pending';
      }
      entries.add(PartnerEntry(
        saleId: s['id'] as String,
        date: (s['date'] ?? '').toString(),
        customer: (s['vendor_name'] ?? s['customer_name'] ?? 'Customer').toString(),
        online: (s['notes'] ?? '').toString().startsWith('Web order'),
        saleTotal: total,
        commission: amount,
        state: state,
      ));
    }
    entries.sort((a, b) => b.date.compareTo(a.date));
    payments.sort((a, b) => (b['date'] ?? '').toString().compareTo((a['date'] ?? '').toString()));
    return PartnerAccount(entries: entries, customers: customers, payments: payments);
  }

  /// Record a UPI payment to the partner. Also saved as a Marketing expense.
  Future<void> recordPayment({
    required Map<String, dynamic> partner,
    required double amount,
    String ref = '',
    DateTime? date,
  }) async {
    final when = (date ?? DateTime.now()).toIso8601String();
    final expenseId = await DBHelper.instance.addExpense(
      category: 'Marketing',
      amount: amount,
      notes: 'Partner commission — ${partner['name']}${ref.isEmpty ? '' : ' (UPI $ref)'}',
      date: when,
    );
    await _write(_payments.doc().set({
      'partner_id': partner['id'],
      'partner_name': partner['name'],
      'amount': amount,
      'date': when,
      'ref': ref.trim(),
      'expense_id': expenseId,
      'created_at': DateTime.now().toIso8601String(),
    }));
  }

  static double _n(Object? v) => v is num ? v.toDouble() : 0.0;
}

class PartnerEntry {
  final String saleId, date, customer, state; // state: earned / pending / cancelled
  final bool online;
  final double saleTotal, commission;
  const PartnerEntry({
    required this.saleId,
    required this.date,
    required this.customer,
    required this.online,
    required this.saleTotal,
    required this.commission,
    required this.state,
  });
}

class PartnerAccount {
  final List<PartnerEntry> entries;
  final List<Map<String, dynamic>> customers, payments;
  const PartnerAccount({required this.entries, required this.customers, required this.payments});

  double _sum(String state) => entries.where((e) => e.state == state).fold(0.0, (a, e) => a + e.commission);
  double get earned => _sum('earned');
  double get pending => _sum('pending');
  double get paid => payments.fold(0.0, (a, p) => a + ((p['amount'] as num?)?.toDouble() ?? 0));
  double get due => earned - paid;
  double get sales => entries.where((e) => e.state != 'cancelled').fold(0.0, (a, e) => a + e.saleTotal);
  int get orders => entries.where((e) => e.state != 'cancelled').length;
}
