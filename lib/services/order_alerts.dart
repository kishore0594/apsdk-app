import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../utils/formatters.dart';

/// Phone notifications for new web store orders: sound, vibration and a
/// notification-bar alert (native code in MainActivity, "madhura/notify").
///
/// Listens from sign-in onwards — independent of which screen is open —
/// so alerts keep arriving while the app is in the background. When
/// Android fully closes the app, alerts stop until it's opened again
/// (alerts with the app closed need the Blaze plan + a server function).
class OrderAlerts {
  OrderAlerts._();
  static final OrderAlerts instance = OrderAlerts._();

  static const _channel = MethodChannel('madhura/notify');
  StreamSubscription? _sub;
  bool _first = true;
  DateTime _startedAt = DateTime.now();

  Future<void> start() async {
    if (_sub != null) return;
    try {
      await _channel.invokeMethod('permission'); // asks once on Android 13+
    } catch (e) {
      debugPrint('Notification permission: $e');
    }
    _first = true;
    _startedAt = DateTime.now();
    _sub = FirebaseFirestore.instance
        .collection('orders')
        .where('status', isEqualTo: 'requested')
        .snapshots()
        .listen((snap) {
      // The first result is the orders already waiting — shown on the
      // Dashboard bell, not announced again.
      if (_first) {
        _first = false;
        return;
      }
      for (final change in snap.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final d = change.doc.data() ?? const <String, dynamic>{};
        final created = d['createdAt'];
        if (created is Timestamp &&
            created.toDate().isBefore(_startedAt.subtract(const Duration(minutes: 2)))) {
          continue; // an older order arriving late from sync
        }
        final customer = (d['customer'] as Map?) ?? const {};
        final name = (customer['name'] ?? 'Customer').toString();
        final total = (d['total'] as num?) ?? 0;
        _show(change.doc.id, 'New web order', '$name · ${formatCurrency(total)}');
      }
    }, onError: (Object e) => debugPrint('Order alerts: $e'));
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  Future<void> _show(String orderId, String title, String body) async {
    HapticFeedback.heavyImpact();
    try {
      await _channel.invokeMethod('show', {
        'id': orderId.hashCode & 0x7fffffff,
        'title': title,
        'body': body,
      });
    } catch (e) {
      debugPrint('Notification not shown: $e');
    }
  }
}
