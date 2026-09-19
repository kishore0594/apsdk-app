import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
/// If the role genuinely can't be determined (a network hiccup on a
/// brand-new account's very first, possibly-offline sign-in, before its
/// role document has ever been cached), this defaults to viewer rather
/// than admin — restricting is the safe direction to fail in, since the
/// entire point of this feature is restriction. This only affects a
/// fetch that actively fails; a fetch that succeeds and simply finds no
/// document still means admin, which is what keeps the two original
/// accounts unaffected.
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
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final role = doc.exists ? (doc.data()?['role'] as String? ?? 'admin') : 'admin';
      _isViewer = role == 'viewer';
    } catch (_) {
      _isViewer = true;
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
