/// App version info, shown in the Reports & Trends footer.
///
/// Bump [appVersion] and [buildDate] whenever a new build is pushed — so
/// when something is reported, it's unambiguous which build it came from
/// rather than guessing from "I installed it last week".
class AppInfo {
  static const String appName = 'Madhura Agro Traders';
  static const String appVersion = '1.1.0';
  static const String buildDate = 'September 2026';

  /// e.g. "v1.1.0 · September 2026"
  static String get versionLine => 'v$appVersion · $buildDate';
}
