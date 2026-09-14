import 'locale_controller.dart';

/// Looks up a translated string for the app's current language.
/// Usage: AppStrings.t('save') — falls back to English, then to the raw
/// key itself, if a translation is ever missing, so the app never shows
/// a blank label.
///
/// Honest scope note: this first pass covers navigation, the login
/// screen, the Dashboard, and common action words (Save/Cancel/Delete/
/// etc.) reused across the app — the highest-visibility parts. Screens
/// not yet in this dictionary (Sales, Inventory, Vendors, Suppliers,
/// Reports, Vendor Insights, Data Sync) still display in English only,
/// and can be added to this same dictionary incrementally without
/// touching the switching mechanism itself.
class AppStrings {
  static String t(String key) {
    final lang = LocaleController.instance.language;
    return _translations[lang]?[key] ?? _translations['en']?[key] ?? key;
  }

  static const Map<String, Map<String, String>> _translations = {
    'en': {
      // Navigation
      'nav_home': 'Home',
      'nav_sales': 'Sales',
      'nav_inventory': 'Inventory',
      'nav_credit': 'Credit',
      'nav_suppliers': 'Suppliers',

      // Login
      'app_name': 'Madhura Agro Traders',
      'store_management': 'Store management',
      'sign_in': 'Sign In',
      'signing_in': 'Signing in…',
      'email': 'Email',
      'password': 'Password',

      // Dashboard
      'store_overview': 'Store overview',
      'todays_sales': "Today's Sales",
      'todays_collections': "Today's Collections",
      'total_outstanding_credit': 'Total Outstanding Credit',
      'todays_gross_profit': "Today's Gross Profit",
      'supplier_dues': 'Supplier Dues',
      'low_stock_alerts': 'Low Stock Alerts',
      'outstanding_vendors': 'Outstanding Vendors (60+ days)',
      'sales_trend': 'Sales Trend',
      'sign_out': 'Sign out',
      'sign_out_confirm': 'Sign out?',

      // Common actions (reused everywhere)
      'save': 'Save',
      'cancel': 'Cancel',
      'delete': 'Delete',
      'edit': 'Edit',
      'add': 'Add',
      'search': 'Search',
      'retry': 'Retry',
      'yes': 'Yes',
      'no': 'No',
      'close': 'Close',

      // Language picker
      'language': 'Language',
      'select_language': 'Select Language',
      'english': 'English',
      'tamil': 'Tamil',
    },
    'ta': {
      // Navigation
      'nav_home': 'முகப்பு',
      'nav_sales': 'விற்பனை',
      'nav_inventory': 'சரக்கு',
      'nav_credit': 'கடன்',
      'nav_suppliers': 'சப்ளையர்கள்',

      // Login
      'app_name': 'மதுரா அக்ரோ டிரேடர்ஸ்',
      'store_management': 'கடை மேலாண்மை',
      'sign_in': 'உள்நுழை',
      'signing_in': 'உள்நுழைகிறது…',
      'email': 'மின்னஞ்சல்',
      'password': 'கடவுச்சொல்',

      // Dashboard
      'store_overview': 'கடையின் சுருக்கம்',
      'todays_sales': 'இன்றைய விற்பனை',
      'todays_collections': 'இன்றைய வசூல்',
      'total_outstanding_credit': 'மொத்த நிலுவை கடன்',
      'todays_gross_profit': 'இன்றைய மொத்த லாபம்',
      'supplier_dues': 'சப்ளையர் நிலுவைத் தொகை',
      'low_stock_alerts': 'குறைந்த இருப்பு எச்சரிக்கை',
      'outstanding_vendors': 'நிலுவை வாடிக்கையாளர்கள் (60+ நாட்கள்)',
      'sales_trend': 'விற்பனை போக்கு',
      'sign_out': 'வெளியேறு',
      'sign_out_confirm': 'வெளியேற வேண்டுமா?',

      // Common actions (reused everywhere)
      'save': 'சேமி',
      'cancel': 'ரத்துசெய்',
      'delete': 'நீக்கு',
      'edit': 'திருத்து',
      'add': 'சேர்',
      'search': 'தேடு',
      'retry': 'மீண்டும் முயற்சி',
      'yes': 'ஆம்',
      'no': 'இல்லை',
      'close': 'மூடு',

      // Language picker
      'language': 'மொழி',
      'select_language': 'மொழியைத் தேர்ந்தெடுக்கவும்',
      'english': 'English',
      'tamil': 'தமிழ்',
    },
  };
}
