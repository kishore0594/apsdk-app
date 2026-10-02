import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Registers this phone for new-order alerts sent by the shop's server
/// (Cloud Functions, Blaze plan). These arrive even when the app is fully
/// closed — Android shows them in the notification bar on the "orders"
/// channel. Never blocks or crashes the app if anything is unavailable.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  /// True once this phone is registered with the server.
  bool active = false;
  StreamSubscription<String>? _refresh;

  Future<void> start() async {
    try {
      final m = FirebaseMessaging.instance;
      await m.requestPermission(alert: true, badge: true, sound: true);
      final token = await m.getToken().timeout(const Duration(seconds: 10));
      if (token == null) return;
      await _save(token);
      _refresh ??= m.onTokenRefresh.listen(_save, onError: (Object e) => debugPrint('Token refresh: $e'));
    } catch (e) {
      debugPrint('Push registration skipped: $e');
    }
  }

  Future<void> _save(String token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    // One document per phone; the id is derived from the token so a phone
    // registers once, however often the app opens.
    final id = token.length > 140 ? token.substring(token.length - 140) : token;
    final ref = FirebaseFirestore.instance.collection('staff_devices').doc(id.replaceAll('/', '_'));
    final op = ref.set({'token': token, 'uid': uid, 'platform': 'android', 'updated_at': DateTime.now().toIso8601String()});
    try {
      await op.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      op.catchError((Object e) => debugPrint('Device save failed later: $e'));
    }
    active = true;
  }
}
