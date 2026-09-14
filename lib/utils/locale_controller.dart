import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the app's current language ('en' or 'ta') and persists the
/// choice on-device (via shared_preferences — a simple local key/value
/// store, not Firestore, so switching language works instantly offline
/// and doesn't need to sync between the two phones — each phone can be
/// set to whichever language its user prefers).
///
/// A single app-wide instance (LocaleController.instance), wrapped around
/// the whole app in main.dart with a ListenableBuilder, so changing the
/// language anywhere immediately re-renders every screen — deliberately
/// not using Flutter's built-in localization code-generation (arb files
/// + `flutter gen-l10n`), since that adds a build-time code-generation
/// step to the GitHub Actions pipeline that could introduce exactly the
/// kind of fragile, hard-to-diagnose CI failures already hard-won away
/// from this project. This plain Dart approach has no such risk.
class LocaleController extends ChangeNotifier {
  LocaleController._internal();
  static final LocaleController instance = LocaleController._internal();

  static const _prefsKey = 'app_language';
  String _language = 'en';

  String get language => _language;
  bool get isTamil => _language == 'ta';

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _language = prefs.getString(_prefsKey) ?? 'en';
      notifyListeners();
    } catch (_) {
      // If local storage isn't available for some reason, just stay on
      // English rather than blocking app startup.
    }
  }

  Future<void> setLanguage(String lang) async {
    if (lang == _language) return;
    _language = lang;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, lang);
    } catch (_) {
      // Language still applies for this session even if it couldn't be
      // saved for next time.
    }
  }
}
