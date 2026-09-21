/// App version info, shown in the Reports & Trends footer.
///
/// Bump [appVersion] and [buildDate] whenever a new build is pushed — so
/// when something is reported, it's unambiguous which build it came from
/// rather than guessing from "I installed it last week".
class AppInfo {
  static const String appName = 'Madhura Agro Traders';
  static const String appVersion = '1.17.2';
  static const String buildDate = 'September 21, 2026 (Crashlytics non-blocking + R8 keep rules)';

  /// Required to create a new account from the Sign Up screen. This app
  /// is still single-tenant — every account sees the same store data —
  /// so sign-up can't be fully open, or literally anyone with the APK
  /// could get full access to your sales, inventory, and vendor credit.
  /// This code is a simple shared gate, not real per-account security:
  /// share it only with family/staff who should have access.
  ///
  /// Deliberately a multi-word phrase rather than a single dictionary
  /// word or "storename+year" — same length-over-complexity reasoning
  /// as the account password rule below: longer and unrelated to
  /// anything guessable beats short-but-"complicated". Easy to say
  /// out loud to someone in person, hard to guess cold.
  /// Change it here (then push a rebuild) if it ever gets out further
  /// than intended, or swap it for a phrase of your own choosing.
  static const String signupAccessCode = 'GOLDEN-HARVEST-92';

  /// e.g. "v1.17.2 · September 21, 2026 (Crashlytics non-blocking + R8 keep rules)"
  static String get versionLine => 'v$appVersion · $buildDate';
}
