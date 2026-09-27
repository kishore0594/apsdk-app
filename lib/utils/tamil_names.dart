import 'locale_controller.dart';

/// Automatic Tamil names for products and categories — a built-in
/// dictionary of agro product words (no internet, no cost, can't crash).
///
/// Phrases are matched longest-first, then single words, keeping the
/// English word order ("Ragi flour" -> "கேழ்வரகு மாவு"). If ANY word is
/// unknown, no Tamil name is produced — a half-English name is worse than
/// none. A Tamil name the shop typed itself (name_local) always wins.
const _words = <String, String>{
  // Millets
  'finger millet': 'கேழ்வரகு', 'ragi': 'கேழ்வரகு', 'kezhvaragu': 'கேழ்வரகு',
  'foxtail millet': 'தினை', 'thinai': 'தினை', 'tenai': 'தினை',
  'little millet': 'சாமை', 'samai': 'சாமை', 'saamai': 'சாமை',
  'kodo millet': 'வரகு', 'varagu': 'வரகு',
  'barnyard millet': 'குதிரைவாலி', 'kuthiraivali': 'குதிரைவாலி', 'kudiraivali': 'குதிரைவாலி',
  'proso millet': 'பனிவரகு', 'panivaragu': 'பனிவரகு',
  'pearl millet': 'கம்பு', 'kambu': 'கம்பு', 'bajra': 'கம்பு',
  'sorghum': 'சோளம்', 'jowar': 'சோளம்', 'cholam': 'சோளம்',
  'millet': 'சிறுதானியம்', 'millets': 'சிறுதானியங்கள்',
  // Grams and pulses
  'horse gram': 'கொள்ளு', 'horsegram': 'கொள்ளு', 'kollu': 'கொள்ளு',
  'green gram': 'பாசிப்பயறு', 'greengram': 'பாசிப்பயறு', 'moong': 'பாசிப்பயறு', 'pasi payaru': 'பாசிப்பயறு',
  'black gram': 'உளுந்து', 'blackgram': 'உளுந்து', 'urad': 'உளுந்து', 'ulundhu': 'உளுந்து', 'ulundu': 'உளுந்து',
  'bengal gram': 'கொண்டைக்கடலை', 'chickpea': 'கொண்டைக்கடலை', 'chickpeas': 'கொண்டைக்கடலை', 'chana': 'கொண்டைக்கடலை',
  'roasted gram': 'பொட்டுக்கடலை', 'pottukadalai': 'பொட்டுக்கடலை',
  'cowpea': 'காராமணி', 'karamani': 'காராமணி', 'field beans': 'மொச்சை', 'mochai': 'மொச்சை',
  'groundnut': 'நிலக்கடலை', 'groundnuts': 'நிலக்கடலை', 'peanut': 'நிலக்கடலை', 'peanuts': 'நிலக்கடலை',
  'toor dal': 'துவரம் பருப்பு', 'thuvaram paruppu': 'துவரம் பருப்பு',
  'moong dal': 'பாசிப்பருப்பு', 'urad dal': 'உளுத்தம் பருப்பு', 'chana dal': 'கடலைப் பருப்பு',
  'dal': 'பருப்பு', 'paruppu': 'பருப்பு', 'gram': 'பயறு', 'grams': 'பயறு வகைகள்',
  // Rice
  'sona masoori': 'சோனா மசூரி', 'sona masuri': 'சோனா மசூரி', 'ponni': 'பொன்னி',
  'seeraga samba': 'சீரகச் சம்பா', 'jeeraga samba': 'சீரகச் சம்பா', 'mappillai samba': 'மாப்பிள்ளை சம்பா',
  'karuppu kavuni': 'கருப்பு கவுனி', 'idli rice': 'இட்லி அரிசி', 'raw rice': 'பச்சரிசி',
  'boiled rice': 'புழுங்கல் அரிசி', 'rice': 'அரிசி', 'arisi': 'அரிசி',
  // Other grains
  'maize': 'மக்காச்சோளம்', 'corn': 'மக்காச்சோளம்', 'wheat': 'கோதுமை',
  // Cattle feed
  'cattle feed': 'மாட்டுத் தீவனம்', 'feed': 'தீவனம்', 'cotton seed': 'பருத்திக்கொட்டை',
  'cottonseed': 'பருத்திக்கொட்டை', 'oil cake': 'பிண்ணாக்கு', 'groundnut cake': 'கடலைப் பிண்ணாக்கு',
  'rice bran': 'அரிசி தவிடு', 'wheat bran': 'கோதுமை தவிடு', 'bran': 'தவிடு',
  // Forms and describing words
  'flour': 'மாவு', 'maavu': 'மாவு', 'rava': 'ரவை', 'sooji': 'ரவை', 'semolina': 'ரவை',
  'flakes': 'அவல்', 'poha': 'அவல்', 'aval': 'அவல்', 'broken': 'குருணை', 'whole': 'முழு',
  'split': 'உடைத்த', 'sprouted': 'முளைகட்டிய', 'organic': 'இயற்கை', 'health mix': 'சத்து மாவு',
  'mix': 'கலவை', 'red': 'சிவப்பு', 'black': 'கருப்பு', 'white': 'வெள்ளை', 'jaggery': 'வெல்லம்',
  'and': 'மற்றும்',
};

const _categories = <String, String>{
  'millets': 'சிறுதானியங்கள்', 'millet': 'சிறுதானியங்கள்', 'rice': 'அரிசி',
  'grams': 'பயறு வகைகள்', 'pulses': 'பருப்பு வகைகள்', 'dals': 'பருப்பு வகைகள்',
  'grains': 'தானியங்கள்', 'cattle feed': 'மாட்டுத் தீவனம்', 'cattle feeds': 'மாட்டுத் தீவனம்',
  'feeds': 'தீவனம்', 'flours': 'மாவு வகைகள்', 'flour': 'மாவு வகைகள்', 'other': 'மற்றவை',
};

final int _longest = _words.keys.map((k) => k.split(' ').length).reduce((a, b) => a > b ? a : b);

String? _translate(String text) {
  final tokens = text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (tokens.isEmpty) return null;
  final out = <String>[];
  var i = 0;
  while (i < tokens.length) {
    String? hit;
    var used = 0;
    for (var n = _longest; n >= 1; n--) {
      if (i + n > tokens.length) continue;
      final phrase = tokens.sublist(i, i + n).join(' ');
      if (_words.containsKey(phrase)) {
        hit = _words[phrase];
        used = n;
        break;
      }
    }
    if (hit == null) {
      if (RegExp(r'\d').hasMatch(tokens[i])) {
        out.add(tokens[i]); // keep sizes/numbers like "25kg" as they are
        i++;
        continue;
      }
      return null; // unknown word: no half-translated names
    }
    if (out.isEmpty || out.last != hit) out.add(hit);
    i += used;
  }
  return out.join(' ');
}

/// Tamil for an English product name, or null if a word isn't known.
/// "Kollu (horsegram)" translates the main part, falling back to the
/// part in brackets.
String? autoTamil(String name) {
  final main = name.replaceAll(RegExp(r'\([^)]*\)'), ' ').trim();
  final inBrackets = RegExp(r'\(([^)]*)\)').firstMatch(name)?.group(1) ?? '';
  return _translate(main) ?? (inBrackets.isEmpty ? null : _translate(inBrackets));
}

String? autoTamilCategory(String category) => _categories[category.trim().toLowerCase()];

/// The shop's own Tamil name, otherwise the automatic one, otherwise ''.
String tamilNameOf(Map<String, dynamic> p) {
  final own = (p['name_local'] ?? '').toString().trim();
  if (own.isNotEmpty) return own;
  return autoTamil((p['name'] ?? '').toString()) ?? '';
}

/// Name to show in the app: Tamil when the app is in Tamil (if known).
String displayName(Map<String, dynamic> p) {
  final en = (p['name'] ?? '').toString();
  if (!LocaleController.instance.isTamil) return en;
  final ta = tamilNameOf(p);
  return ta.isEmpty ? en : ta;
}

/// Search matches English or Tamil names.
bool nameMatches(Map<String, dynamic> p, String query) {
  final q = query.toLowerCase();
  return (p['name'] ?? '').toString().toLowerCase().contains(q) || tamilNameOf(p).contains(query);
}
