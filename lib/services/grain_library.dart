/// Starter content for the web store's Benefits and How to use tabs.
///
/// Written conservatively ("rich in", "good source of", never "cures")
/// from: ICAR-Indian Institute of Millets Research, "Nutritional and
/// Health Benefits of Millets" (2017); IJCMPH review "Millets as
/// nutri-cereals" (finger millet calcium 300–400 mg/100 g; kodo millet
/// 11% protein, 4.2% fat, 14.3% fibre); ILSI-India/MDRF presentation
/// (glycaemic index of barnyard and sorghum foods); PMC reviews on
/// millets (proso minerals) and horse gram (protein ~22 g, fat ~0.6 g,
/// fibre ~16 g per 100 g; soaking reduces anti-nutrients).
/// The shop can edit or replace every line in the app.
class GrainInfo {
  final List<String> keywords;
  final List<String> benefits, benefitsTa, howTo, howToTa;
  const GrainInfo(this.keywords, this.benefits, this.benefitsTa, this.howTo, this.howToTa);
}

const _milletCookTa = [
  'இரண்டு முதல் மூன்று முறை நன்றாக கழுவவும்',
  'குறைந்தது 30 நிமிடம் ஊறவைக்கவும் (4–6 மணி நேரம் சிறந்தது)',
  '1 கப் தானியத்திற்கு 2½ கப் தண்ணீர் சேர்த்து, மூடி 15–20 நிமிடம் வேகவைக்கவும்',
];
const _milletCook = [
  'Rinse 2–3 times in clean water',
  'Soak at least 30 minutes (4–6 hours is best)',
  'Cook 1 cup with 2½ cups water, covered, for 15–20 minutes',
];

const grainLibrary = <GrainInfo>[
  GrainInfo(
    ['ragi', 'finger millet', 'கேழ்வரகு', 'கேப்பை', 'ராகி'],
    [
      'Richest in calcium among cereals and millets — about 300–400 mg per 100 g',
      'Good source of dietary fibre and iron',
      'Naturally gluten-free',
    ],
    [
      'தானியங்களிலேயே அதிக கால்சியம் — 100 கிராமில் சுமார் 300–400 மி.கி',
      'நார்ச்சத்து மற்றும் இரும்புச்சத்து நிறைந்தது',
      'இயற்கையாகவே குளூட்டன் இல்லாதது',
    ],
    [
      'Koozh: mix 3 tbsp ragi flour in 1 cup water without lumps',
      'Cook on a low flame, stirring, 5–7 minutes until thick',
      'Serve with buttermilk and salt, or with jaggery and milk',
      'Also good for dosa, roti and adai — mix with rice or wheat flour',
    ],
    [
      'கூழ்: 3 மேசைக்கரண்டி கேழ்வரகு மாவை 1 கப் தண்ணீரில் கட்டியில்லாமல் கலக்கவும்',
      'குறைந்த தீயில் கிளறியபடி 5–7 நிமிடம் கெட்டியாகும் வரை வேகவைக்கவும்',
      'மோர் மற்றும் உப்பு, அல்லது வெல்லம் மற்றும் பாலுடன் பரிமாறவும்',
      'தோசை, ரொட்டி, அடைக்கும் ஏற்றது',
    ],
  ),
  GrainInfo(
    ['foxtail', 'thinai', 'தினை'],
    [
      'Rich in dietary fibre and protein',
      'Slower-digesting than polished white rice',
      'Naturally gluten-free',
    ],
    [
      'நார்ச்சத்து மற்றும் புரதம் நிறைந்தது',
      'பாலிஷ் செய்த வெள்ளை அரிசியை விட மெதுவாக செரிக்கும்',
      'இயற்கையாகவே குளூட்டன் இல்லாதது',
    ],
    [..._milletCook, 'Use in place of rice, or for upma, pongal and payasam'],
    [..._milletCookTa, 'அரிசிக்கு பதிலாக, அல்லது உப்புமா, பொங்கல், பாயசத்திற்கு பயன்படுத்தவும்'],
  ),
  GrainInfo(
    ['little millet', 'samai', 'சாமை'],
    [
      'Good source of dietary fibre',
      'Contains minerals such as phosphorus and iron',
      'Naturally gluten-free and light to digest',
    ],
    [
      'நல்ல நார்ச்சத்து உள்ளது',
      'பாஸ்பரஸ், இரும்பு போன்ற தாதுக்கள் உள்ளன',
      'குளூட்டன் இல்லாதது, எளிதில் செரிக்கும்',
    ],
    [..._milletCook, 'Make samai rice, curd rice, pongal or khichdi'],
    [..._milletCookTa, 'சாமை சாதம், தயிர் சாதம், பொங்கல் அல்லது கிச்சடி செய்யலாம்'],
  ),
  GrainInfo(
    ['kodo', 'varagu', 'வரகு'],
    [
      'About 11% protein, low in fat (4.2%) and high in fibre (14.3%)',
      'Contains B vitamins — niacin, B6 and folic acid',
      'Naturally gluten-free',
    ],
    [
      'சுமார் 11% புரதம், குறைந்த கொழுப்பு (4.2%), அதிக நார்ச்சத்து (14.3%)',
      'நியாசின், B6, ஃபோலிக் அமிலம் போன்ற B வைட்டமின்கள் உள்ளன',
      'இயற்கையாகவே குளூட்டன் இல்லாதது',
    ],
    [..._milletCook, 'Good for varagu rice, biryani and lemon rice'],
    [..._milletCookTa, 'வரகு சாதம், பிரியாணி, எலுமிச்சை சாதத்திற்கு ஏற்றது'],
  ),
  GrainInfo(
    ['barnyard', 'kuthiraivali', 'kudiraivali', 'குதிரைவாலி'],
    [
      'Cooked barnyard millet has shown a low glycaemic index (about 42–50) in studies',
      'Rich in dietary fibre',
      'Naturally gluten-free',
    ],
    [
      'சமைத்த குதிரைவாலி ஆய்வுகளில் குறைந்த கிளைசெமிக் குறியீடு (சுமார் 42–50) காட்டியுள்ளது',
      'நார்ச்சத்து நிறைந்தது',
      'இயற்கையாகவே குளூட்டன் இல்லாதது',
    ],
    [..._milletCook, 'Use for kuthiraivali rice, idli and dosa batter'],
    [..._milletCookTa, 'குதிரைவாலி சாதம், இட்லி, தோசை மாவுக்கு பயன்படுத்தவும்'],
  ),
  GrainInfo(
    ['proso', 'panivaragu', 'பனிவரகு'],
    [
      'Rich in dietary fibre and protein',
      'Contains potassium, iron, phosphorus, calcium, magnesium and zinc',
      'Naturally gluten-free',
    ],
    [
      'நார்ச்சத்து மற்றும் புரதம் நிறைந்தது',
      'பொட்டாசியம், இரும்பு, பாஸ்பரஸ், கால்சியம், மெக்னீசியம், துத்தநாகம் உள்ளன',
      'இயற்கையாகவே குளூட்டன் இல்லாதது',
    ],
    [..._milletCook, 'Make upma, pongal or sweet porridge'],
    [..._milletCookTa, 'உப்புமா, பொங்கல் அல்லது இனிப்பு கஞ்சி செய்யலாம்'],
  ),
  GrainInfo(
    ['pearl millet', 'bajra', 'kambu', 'கம்பு'],
    [
      'Filling and energy-giving — a traditional summer food',
      'Good source of dietary fibre',
      'Naturally gluten-free',
    ],
    [
      'வயிறு நிறைவான, ஆற்றல் தரும் பாரம்பரிய கோடைகால உணவு',
      'நல்ல நார்ச்சத்து உள்ளது',
      'இயற்கையாகவே குளூட்டன் இல்லாதது',
    ],
    [
      'Kambu koozh: cook coarse kambu with water until soft, rest overnight',
      'Next morning, mix with buttermilk, salt and small onions',
      'Kambu flour also makes good roti and dosa',
    ],
    [
      'கம்பங்கூழ்: ஒன்றிரண்டாக உடைத்த கம்பை மென்மையாகும் வரை வேகவைத்து இரவு முழுவதும் வைக்கவும்',
      'காலையில் மோர், உப்பு, சின்ன வெங்காயத்துடன் கலக்கவும்',
      'கம்பு மாவில் ரொட்டி, தோசையும் செய்யலாம்',
    ],
  ),
  GrainInfo(
    ['sorghum', 'jowar', 'cholam', 'சோளம்'],
    [
      'Sorghum upma has shown a moderate glycaemic index (about 53–56) in studies',
      'Good source of dietary fibre',
      'Naturally gluten-free',
    ],
    [
      'சோள உப்புமா ஆய்வுகளில் மிதமான கிளைசெமிக் குறியீடு (சுமார் 53–56) காட்டியுள்ளது',
      'நல்ல நார்ச்சத்து உள்ளது',
      'இயற்கையாகவே குளூட்டன் இல்லாதது',
    ],
    [
      'Soak whole sorghum 6–8 hours before cooking',
      'Pressure-cook 1 cup with 3 cups water for 4–5 whistles',
      'Sorghum flour makes soft roti and dosa',
    ],
    [
      'முழு சோளத்தை சமைப்பதற்கு முன் 6–8 மணி நேரம் ஊறவைக்கவும்',
      '1 கப்புக்கு 3 கப் தண்ணீர் சேர்த்து குக்கரில் 4–5 விசில் வரை வேகவைக்கவும்',
      'சோள மாவில் மென்மையான ரொட்டி, தோசை செய்யலாம்',
    ],
  ),
  GrainInfo(
    ['horse gram', 'horsegram', 'kollu', 'கொள்ளு'],
    [
      'High in plant protein — about 22 g per 100 g',
      'Very low in fat (under 1 g per 100 g) and high in dietary fibre',
      'Soaking and sprouting improve digestibility',
    ],
    [
      'அதிக தாவர புரதம் — 100 கிராமில் சுமார் 22 கிராம்',
      'மிகக் குறைந்த கொழுப்பு (100 கிராமில் 1 கிராமுக்கும் குறைவு), அதிக நார்ச்சத்து',
      'ஊறவைத்தல், முளைகட்டுதல் செரிமானத்தை மேம்படுத்தும்',
    ],
    [
      'Soak overnight (8–12 hours) and drain the water',
      'Pressure-cook with fresh water for 5–6 whistles',
      'Make kollu rasam, sundal or thuvaiyal',
      'Start with small portions — like other pulses, it can cause gas',
    ],
    [
      'இரவு முழுவதும் (8–12 மணி நேரம்) ஊறவைத்து தண்ணீரை வடிக்கவும்',
      'புதிய தண்ணீரில் குக்கரில் 5–6 விசில் வரை வேகவைக்கவும்',
      'கொள்ளு ரசம், சுண்டல் அல்லது துவையல் செய்யலாம்',
      'சிறிய அளவில் தொடங்கவும் — மற்ற பருப்புகளைப் போல வாயு ஏற்படுத்தலாம்',
    ],
  ),
  GrainInfo(
    ['green gram', 'greengram', 'moong', 'mung', 'pasi payaru', 'பாசிப்பயறு', 'பச்சைப்பயறு'],
    [
      'Rich in plant protein and dietary fibre',
      'Light and easy to digest — sprouts are a popular healthy snack',
      'Contains potassium and B vitamins',
    ],
    [
      'தாவர புரதம் மற்றும் நார்ச்சத்து நிறைந்தது',
      'இலகுவானது, எளிதில் செரிக்கும் — முளைகட்டிய பயறு சத்தான சிற்றுண்டி',
      'பொட்டாசியம் மற்றும் B வைட்டமின்கள் உள்ளன',
    ],
    [
      'Soak 6–8 hours; for sprouts, drain and keep covered for a day',
      'Pressure-cook soaked gram with water for 3–4 whistles',
      'Make sundal, kootu, pesarattu dosa or sprout salad',
    ],
    [
      '6–8 மணி நேரம் ஊறவைக்கவும்; முளைகட்ட, வடித்து ஒரு நாள் மூடி வைக்கவும்',
      'ஊறிய பயறை குக்கரில் 3–4 விசில் வரை வேகவைக்கவும்',
      'சுண்டல், கூட்டு, பெசரட்டு தோசை அல்லது முளைப்பயறு சாலட் செய்யலாம்',
    ],
  ),
];

/// Finds library content for a product by its English or Tamil name.
GrainInfo? findGrainInfo(Map<String, dynamic> product) {
  final hay = '${product['name'] ?? ''} ${product['name_local'] ?? ''}'.toLowerCase();
  for (final g in grainLibrary) {
    if (g.keywords.any((k) => hay.contains(k.toLowerCase()))) return g;
  }
  return null;
}
