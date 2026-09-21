import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Makes sign-in work without internet, the way offline-capable apps do.
///
/// Logout used to call FirebaseAuth.signOut(), which destroys the
/// session — signing back in then had to reach Google's servers, so it
/// failed with "No internet connection" whenever the shop was offline.
///
/// Now, Logout only LOCKS the app on this device; the Firebase session
/// stays alive underneath (so offline data and queued sync keep
/// working). Unlocking checks the password against a salted SHA-256
/// hash saved here after the last successful online sign-in — the
/// password itself is never stored, only a one-way fingerprint of it.
/// No network is involved at any step.
///
/// What still genuinely needs internet, for any cloud app: the very
/// first sign-in on a phone, and switching to a different account.
class SessionLock extends ChangeNotifier {
  SessionLock._internal();
  static final SessionLock instance = SessionLock._internal();

  static const _kLocked = 'session_locked';
  static const _kEmail = 'session_email';
  static const _kSalt = 'session_salt';
  static const _kHash = 'session_hash';

  bool _locked = false;
  String? _email;
  String? _salt;
  String? _hash;

  bool get isLocked => _locked;
  String? get rememberedEmail => _email;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _locked = prefs.getBool(_kLocked) ?? false;
    _email = prefs.getString(_kEmail);
    _salt = prefs.getString(_kSalt);
    _hash = prefs.getString(_kHash);
  }

  String _hashOf(String salt, String password) =>
      sha256.convert(utf8.encode('$salt::$password')).toString();

  /// Called after every successful ONLINE sign-in, sign-up, or password
  /// change — so the offline check always matches the current password.
  Future<void> rememberCredentials(String email, String password) async {
    final rnd = Random.secure();
    final salt = base64Url.encode(List<int>.generate(16, (_) => rnd.nextInt(256)));
    _email = email.trim().toLowerCase();
    _salt = salt;
    _hash = _hashOf(salt, password);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kEmail, _email!);
    await prefs.setString(_kSalt, salt);
    await prefs.setString(_kHash, _hash!);
  }

  bool matches(String email, String password) {
    if (_email == null || _salt == null || _hash == null) return false;
    return email.trim().toLowerCase() == _email && _hashOf(_salt!, password) == _hash;
  }

  /// True if this email is the account whose password fingerprint is
  /// stored here — i.e. offline unlock is possible for it.
  bool knows(String email) => _hash != null && email.trim().toLowerCase() == _email;

  Future<void> lock() async {
    _locked = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kLocked, true);
    notifyListeners();
  }

  Future<void> unlock() async {
    _locked = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kLocked, false);
    notifyListeners();
  }
}
