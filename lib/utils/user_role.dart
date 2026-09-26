import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Access levels — these match firestore.rules exactly, so what the app
/// shows is always what the database will actually allow.
enum AccessLevel { master, viewer, pending }

/// The signed-in account's access level, loaded once per sign-in.
///
/// Master  = listed under `admins` (created in the Firebase console), or
///           approved by a master with role "admin".
/// Viewer  = approved by a master with role "viewer": sees, can't change.
/// Pending = signed up but not approved yet (or an owner account whose
///           UID hasn't been added to `admins` yet): sees a setup screen.
///
/// The old rule "no role record = master" is gone: once the web store is
/// live, anyone can create an account with the public connection details,
/// so an account must be explicitly allowed.
///
/// Offline: the level is remembered on the phone each time it's confirmed
/// online, and that remembered level is used when the database can't be
/// reached — so master and viewer accounts both work fully offline.
class UserRole extends ChangeNotifier {
  UserRole._internal();
  static final UserRole instance = UserRole._internal();

  AccessLevel _level = AccessLevel.viewer;
  bool _loaded = false;

  AccessLevel get level => _level;
  bool get isAdmin => _level == AccessLevel.master;
  bool get isViewer => _level != AccessLevel.master;
  bool get isPending => _level == AccessLevel.pending;
  bool get isLoaded => _loaded;

  static AccessLevel _parse(String? v) {
    switch (v) {
      case 'master':
      case 'admin': // remembered by earlier app versions
        return AccessLevel.master;
      case 'pending':
        return AccessLevel.pending;
      default:
        return AccessLevel.viewer;
    }
  }

  Future<void> load() async {
    _loaded = false;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _level = AccessLevel.pending;
      _loaded = true;
      notifyListeners();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'role_$uid';
    try {
      final fs = FirebaseFirestore.instance;
      final owner = await fs.collection('admins').doc(uid).get().timeout(const Duration(seconds: 5));
      if (owner.exists) {
        _level = AccessLevel.master;
      } else {
        final user = await fs.collection('users').doc(uid).get().timeout(const Duration(seconds: 5));
        final data = user.data();
        if (!user.exists || data == null || data['approved'] != true) {
          _level = AccessLevel.pending;
        } else {
          _level = data['role'] == 'admin' ? AccessLevel.master : AccessLevel.viewer;
        }
      }
      await prefs.setString(cacheKey, _level.name);
    } catch (_) {
      // Offline or unreachable: use the level last confirmed online.
      final cached = prefs.getString(cacheKey);
      _level = cached == null ? AccessLevel.pending : _parse(cached);
    }
    _loaded = true;
    notifyListeners();
  }

  /// Safe (restricted) default between one account signing out and the
  /// next one's load() finishing.
  void reset() {
    _level = AccessLevel.viewer;
    _loaded = false;
  }
}
