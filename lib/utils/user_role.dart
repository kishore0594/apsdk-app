import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the current signed-in account's role ('admin' or 'viewer') for
/// the session — fetched once at sign-in (see RootNav's initState in
/// main.dart) and cached here, rather than re-read on every screen.
///
/// An account with no role document in Firestore is treated as admin —
/// this is what keeps the two original pre-existing accounts (created
/// before this system existed) working exactly as before, with no
/// migration step needed. Every account created through Sign Up from
/// here on writes its own role document (defaulting to viewer) as part
/// of account creation — see login_screen.dart's _signUp.
///
/// Offline: each account's role is remembered on the phone every time
/// it is confirmed online, and that remembered role is used whenever the
/// database can't be reached — so master and view-only accounts both
/// work fully offline. Only a phone that has never confirmed the role
/// online falls back to view-only, the safe direction to fail in.
class UserRole extends ChangeNotifier {
  UserRole._internal();
  static final UserRole instance = UserRole._internal();

  bool _isViewer = false;
  bool _loaded = false;

  bool get isViewer => _isViewer;
  bool get isAdmin => !_isViewer;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    _loaded = false;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _isViewer = false;
      _loaded = true;
      notifyListeners();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'role_$uid';
    try {
      // Online: ask the database. Master accounts have NO role document
      // (that's what marks them as admin) — but "no document" can only
      // be confirmed by the server, so offline this lookup fails. The
      // timeout stops a slow connection from holding up the app.
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 5));
      final role = doc.exists ? (doc.data()?['role'] as String? ?? 'admin') : 'admin';
      _isViewer = role == 'viewer';
      // Remember the confirmed role on this phone for offline use.
      await prefs.setString(cacheKey, role);
    } catch (_) {
      // Offline (or server unreachable): use the role last confirmed
      // online for THIS account — so a master account stays master and
      // a view-only account stays view-only, with no internet at all.
      // Only if this phone has never confirmed the role does it fall
      // back to view-only, the safe direction to fail in.
      final cached = prefs.getString(cacheKey);
      _isViewer = cached == null ? true : cached == 'viewer';
    }
    _loaded = true;
    notifyListeners();
  }


  /// Resets to a safe (restricted) default when signing out, so the
  /// instant between one account signing out and the next one's load()
  /// finishing never briefly shows the previous account's role.
  void reset() {
    _isViewer = true;
    _loaded = false;
  }
}
