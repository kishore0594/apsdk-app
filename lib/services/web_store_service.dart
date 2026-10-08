import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'grain_library.dart';
import '../utils/tamil_names.dart';

enum WebSyncState { idle, pending, publishing, upToDate, error }

/// Everything that connects the app to the web store.
///
/// The app's own `products` collection is the ONLY place products are
/// managed. This service turns it into the web store's catalog
/// (`catalog/main`, one document the website reads) plus one small
/// `catalog_images/{productId}` document per product photo — photos are
/// kept out of the catalog because a Firestore document has a hard 1 MB
/// limit. Shop details, category order / Tamil names / hidden categories
/// live in `webstore/settings`.
///
/// Publishing is automatic for master accounts: any change to products
/// (price, stock, photo, name, web settings) or shop settings republishes
/// a few seconds later — only if the resulting catalog actually differs
/// from what's live, and only the photos that changed.
class WebStoreService {
  WebStoreService._();
  static final WebStoreService instance = WebStoreService._();

  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get catalogRef => _fs.collection('catalog').doc('main');
  DocumentReference<Map<String, dynamic>> get settingsRef => _fs.collection('webstore').doc('settings');
  CollectionReference<Map<String, dynamic>> get _images => _fs.collection('catalog_images');
  CollectionReference<Map<String, dynamic>> get _orders => _fs.collection('orders');
  CollectionReference<Map<String, dynamic>> get _products => _fs.collection('products');
  CollectionReference<Map<String, dynamic>> get _tips => _fs.collection('tips');

  /// Same offline-safe save as the rest of the app: the write is stored
  /// on the phone instantly; we wait briefly for the server, then move on
  /// (it syncs automatically when the connection returns).
  Future<void> _write(Future<void> op) async {
    try {
      await op.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      op.catchError((Object e) {
        debugPrint('Queued web store write failed when syncing: $e');
      });
    }
  }

  // ---------------- Settings & product web fields ----------------

  Stream<Map<String, dynamic>> watchSettings() =>
      settingsRef.snapshots().map((s) => s.data() ?? <String, dynamic>{});

  Future<void> saveSettings(Map<String, dynamic> patch) =>
      _write(settingsRef.set(patch, SetOptions(merge: true)));

  /// Web-only fields on a product: web_visible, name_local, web_pack,
  /// offer_price, web_order. Inventory fields are never touched here.
  Future<void> updateProductWeb(String productId, Map<String, dynamic> fields) =>
      _write(_products.doc(productId).update(fields));

  Stream<List<Map<String, dynamic>>> watchProducts() => _products
      .snapshots()
      .map((s) => s.docs.map((d) => <String, dynamic>{...d.data(), 'id': d.id}).toList());

  // ---------------- Building the catalog ----------------

  static String photoHash(String photo) =>
      sha1.convert(utf8.encode(photo)).toString().substring(0, 12);

  /// Shop (offline) price — the Inventory selling price, used by app sales.
  static double shopPriceOf(Map<String, dynamic> p) => (p['selling_price'] as num?)?.toDouble() ?? 0;

  /// Online price per unit: the Web Store's online price when set,
  /// otherwise the shop price. Everything on the website uses this.
  static double priceOf(Map<String, dynamic> p) {
    final online = (p['web_price'] as num?)?.toDouble() ?? 0;
    return online > 0 ? online : shopPriceOf(p);
  }

  static bool hasOnlinePrice(Map<String, dynamic> p) => ((p['web_price'] as num?)?.toDouble() ?? 0) > 0;

  /// Price a web customer pays today: the offer price when it's valid.
  static double webPriceOf(Map<String, dynamic> p) {
    final price = priceOf(p);
    final offer = (p['offer_price'] as num?)?.toDouble() ?? 0;
    return (offer > 0 && offer < price) ? offer : price;
  }

  /// On the web store unless switched off, and only with a selling price.
  static bool isOnline(Map<String, dynamic> p) => p['web_visible'] != false && priceOf(p) > 0;

  /// The label customers see on the pack, e.g. "25 kg bag". One web pack
  /// always equals ONE app unit, so an order quantity maps 1:1 to stock.
  static String packLabel(Map<String, dynamic> p) {
    final custom = (p['web_pack'] as String? ?? '').trim();
    if (custom.isNotEmpty) return custom;
    final unit = (p['unit'] as String? ?? '').trim();
    return unit.isEmpty ? '1 unit' : '1 $unit';
  }

  static bool unitIsKg(Map<String, dynamic> p) =>
      RegExp(r'^\s*(kg|kgs|kilo|kilos|kilogram|kilograms)\s*\.?$', caseSensitive: false)
          .hasMatch((p['unit'] ?? '').toString());

  /// On automatically for products sold in kg, unless switched off.
  static bool sellsByWeight(Map<String, dynamic> p) =>
      p['web_weight'] is bool ? p['web_weight'] as bool : unitIsKg(p);
  static double _r2(double v) => (v * 100).roundToDouble() / 100;

  static String categoryOf(Map<String, dynamic> p) {
    final c = (p['category'] as String? ?? '').trim();
    return c.isEmpty ? 'Other' : c;
  }

  static List<String> _lines(dynamic v) =>
      ((v as List?) ?? const []).map((d) => d.toString().trim()).where((d) => d.isNotEmpty).toList();

  /// The shop's own "Also called" names for a product (web_aliases):
  /// up to 12, each at most 40 characters, no repeats.
  static List<String> aliasesOf(Map<String, dynamic> p) {
    final raw = p['web_aliases'];
    final parts = raw is List ? raw.map((e) => e.toString()) : (raw ?? '').toString().split(RegExp(r'[,\n]'));
    final seen = <String>{};
    final out = <String>[];
    for (final part in parts) {
      final v = part.trim();
      if (v.isEmpty || v.length > 40 || !seen.add(v.toLowerCase())) continue;
      out.add(v);
      if (out.length == 12) break;
    }
    return out;
  }

  /// Adds one name to a product's "Also called" list (from the search words screen).
  Future<void> addAlias(Map<String, dynamic> p, String name) {
    final list = [...aliasesOf(p), name.trim()];
    return updateProductWeb(p['id'] as String, {'web_aliases': aliasesOf({'web_aliases': list})});
  }

  static Map<String, dynamic> buildCatalog(List<Map<String, dynamic>> products, Map<String, dynamic> settings,
      [Map<String, List<Map<String, dynamic>>> approvedTips = const {},
      Map<String, List<Map<String, dynamic>>> approvedReviews = const {}]) {
    final items = <Map<String, dynamic>>[];
    for (final p in products.where(isOnline)) {
      final price = priceOf(p);
      // Library content fills anything the shop hasn't written itself.
      final lib = findGrainInfo(p);
      List<String> own(String k, List<String>? fallback) {
        final v = _lines(p[k]);
        return v.isNotEmpty ? v : (fallback ?? const []);
      }
      String ownText(String k, String fallback) {
        final v = (p[k] ?? '').toString().trim();
        return v.isNotEmpty ? v : fallback;
      }
      final about = lib == null ? const ['', ''] : aboutFor(lib);
      final offer = (p['offer_price'] as num?)?.toDouble() ?? 0;
      final photo = p['photo'] as String?;
      items.add({
        'id': p['id'],
        'name': (p['name'] ?? '').toString().trim(),
        // The shop's own Tamil name, otherwise an automatic one.
        'nameLocal': tamilNameOf(p),
        // "Also called": other names customers type (Kezhvaragu, Nachni...).
        // The website adds the common ones itself; these are the shop's own.
        if (aliasesOf(p).isNotEmpty) 'aliases': aliasesOf(p),
        'category': categoryOf(p),
        // Sub-category from Inventory (e.g. "Whole grains", "Flours"):
        // shown as filter chips inside the category on the website.
        'subcategory': (p['subcategory'] ?? '').toString().trim(),
        'subcategoryLocal': autoTamil((p['subcategory'] ?? '').toString()) ?? '',
        'image': (photo != null && photo.isNotEmpty) ? 'fs:${p['id']}:${photoHash(photo)}' : '',
        'inStock': ((p['quantity'] as num?)?.toDouble() ?? 0) > 0,
        'order': (p['web_order'] as num?)?.toInt() ?? 999,
        'description': ownText('web_desc', about[0]),
        'descriptionLocal': ownText('web_desc_local', about[1]),
        'details': ((p['web_details'] as List?) ?? const [])
            .map((d) => d.toString().trim())
            .where((d) => d.isNotEmpty)
            .toList(),
        'homemade': p['web_homemade'] == true,
        'benefits': own('web_benefits', lib?.benefits),
        'benefitsLocal': own('web_benefits_local', lib?.benefitsTa),
        'howTo': own('web_howto', lib?.howTo),
        'howToLocal': own('web_howto_local', lib?.howToTa),
        if ((approvedReviews[p['id']] ?? const []).isNotEmpty) ...{
          'rating': {
            'avg': (approvedReviews[p['id']]!.fold<double>(0, (a, r) => a + ((r['stars'] as num?)?.toDouble() ?? 0)) /
                    approvedReviews[p['id']]!.length *
                    10)
                .roundToDouble() /
                10,
            'count': approvedReviews[p['id']]!.length,
          },
          'reviews': [
            for (final r in approvedReviews[p['id']]!.take(10))
              {'name': (r['name'] ?? '').toString(), 'stars': (r['stars'] as num?)?.toInt() ?? 0, 'text': (r['text'] ?? '').toString()}
          ],
        },
        'tips': [
          for (final t in (approvedTips[p['id']] ?? const <Map<String, dynamic>>[]).take(20))
            {'name': (t['name'] ?? '').toString(), 'text': (t['text'] ?? '').toString()}
        ],
        'bestseller': p['web_bestseller'] == true,
        'isNew': p['web_new'] == true,
        // Sell by weight: selling price is per kg; the website offers
        // 500 g / 1 kg / 5 kg plus any custom amount the customer types.
        if (sellsByWeight(p)) ...{
          'byWeight': true,
          'pricePerKg': price,
          if (offer > 0 && offer < price) 'offerPerKg': offer,
          'packs': [
            for (final w in const [(0.25, '250 g'), (0.5, '500 g'), (1.0, '1 kg'), (5.0, '5 kg')])
              {
                'label': w.$2,
                'kg': w.$1,
                // Cards open on 500 g; 250 g is there for small trial packs.
                if (w.$1 == 0.5) 'isDefault': true,
                'price': (price * w.$1).roundToDouble(),
                if (offer > 0 && offer < price && (offer * w.$1).roundToDouble() < (price * w.$1).roundToDouble())
                  'offerPrice': (offer * w.$1).roundToDouble(),
              }
          ],
        } else
          'packs': [
            {
              'label': packLabel(p),
              'price': price.roundToDouble(),
              if (offer > 0 && offer.roundToDouble() < price.roundToDouble()) 'offerPrice': offer.roundToDouble(),
            }
          ],
      });
    }
    items.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
    final present = items.map((i) => i['category'] as String).toSet();
    final order = ((settings['category_order'] as List?) ?? const [])
        .map((e) => e.toString())
        .where(present.contains)
        .toList();
    for (final c in present.toList()..sort()) {
      if (!order.contains(c)) order.add(c);
    }
    return {
      'store': Map<String, dynamic>.from((settings['store'] as Map?) ?? const {}),
      'categories': order,
      'categoriesLocal': {
        for (final c in order)
          if (autoTamilCategory(c) != null) c: autoTamilCategory(c),
        ...Map<String, dynamic>.from((settings['categories_local'] as Map?) ?? const {})
          ..removeWhere((k, v) => v.toString().trim().isEmpty),
      },
      'hiddenCategories':
          ((settings['hidden_categories'] as List?) ?? const []).map((e) => e.toString()).toList(),
      'products': items,
      // Banners, delivery note, trust lines, owner story, about, contact
      // links and category photos — edited in Web Store > Website content.
      'site': Map<String, dynamic>.from((settings['site'] as Map?) ?? const {}),
      'recipes': [
        for (final r in recipesOf(settings))
          {
            for (final k in const ['id', 'name', 'nameLocal', 'photo', 'tip', 'tipLocal']) k: (r[k] ?? '').toString(),
            'minutes': (r['minutes'] as num?)?.toInt() ?? 0,
            'serves': (r['serves'] as num?)?.toInt() ?? 0,
            for (final k in const ['ingredients', 'ingredientsLocal', 'steps', 'stepsLocal', 'benefits', 'benefitsLocal'])
              k: ((r[k] as List?) ?? const []).map((x) => x.toString()).where((x) => x.trim().isNotEmpty).toList(),
            // Only products that are on the web store, and active combos.
            'products': [
              for (final id in ((r['products'] as List?) ?? const []).map((x) => x.toString()))
                if (id.startsWith('combo:')
                    ? combosOf(settings).any((c) => 'combo:${c['id']}' == id && c['active'] != false)
                    : products.any((p) => p['id'] == id && isOnline(p)))
                  id
            ],
          }
      ],
      'todayRecipe': (settings['todayRecipe'] ?? '').toString(),
      'combos': [
        for (final c in combosOf(settings))
          if (c['active'] != false &&
              comboProblem(c, {for (final p in products) p['id'] as String: p}, maxComboDiscount(settings)) == null)
            {
              'id': (c['id'] ?? '').toString(),
              'name': (c['name'] ?? '').toString(),
              'nameLocal': (c['nameLocal'] ?? '').toString().trim().isNotEmpty
                  ? (c['nameLocal'] as String).trim()
                  : (autoTamil((c['name'] ?? '').toString()) ?? ''),
              'price': (c['price'] as num).toDouble().roundToDouble(),
              'normal': comboNormal(c, {for (final p in products) p['id'] as String: p}).roundToDouble(),
              'weightKg': comboWeightKg(c, {for (final p in products) p['id'] as String: p}),
              'items': [
                for (final raw in (c['items'] as List))
                  () {
                    final i = Map<String, dynamic>.from(raw as Map);
                    final p = products.firstWhere((x) => x['id'] == i['id']);
                    final qty = (i['qty'] as num).toDouble();
                    return {
                      'id': i['id'],
                      'qty': qty,
                      'label': comboItemLabel(p, qty),
                      'name': (p['name'] ?? '').toString(),
                      'nameLocal': tamilNameOf(p),
                    };
                  }(),
              ],
            }
      ],
    };
  }

  // ---------------- Recipes ----------------
  // webstore/settings: recipes = [{id, name, nameLocal, photo, minutes, serves,
  // ingredients[], ingredientsLocal[], steps[], stepsLocal[], benefits[],
  // benefitsLocal[], tip, tipLocal, products[]}], todayRecipe = id (chosen by the shop).
  // products holds product ids and 'combo:<id>' for combos.
  static List<Map<String, dynamic>> recipesOf(Map<String, dynamic> settings) =>
      ((settings['recipes'] as List?) ?? const []).map((r) => Map<String, dynamic>.from(r as Map)).toList();

  /// Starter recipes linked to the shop's own products by name.
  static List<Map<String, dynamic>> starterRecipesFor(List<Map<String, dynamic>> products, List<Map<String, Object>> library) {
    return [
      for (final r in library)
        () {
          String? link;
          for (final k in (r['keys'] as List).cast<String>()) {
            final hit = products.where((p) => (p['name'] ?? '').toString().toLowerCase().contains(k)).toList();
            if (hit.isNotEmpty) {
              link = hit.first['id'] as String;
              break;
            }
          }
          final m = Map<String, dynamic>.from(r)..remove('keys');
          m['photo'] = '';
          m['products'] = [if (link != null) link];
          return m;
        }(),
    ];
  }

  // ---------------- Combo offers ----------------
  // Stored in webstore/settings: combos = [{id, name, nameLocal, items:
  // [{id, qty}], price, active}], maxComboDiscount = percent (default 20).

  static double maxComboDiscount(Map<String, dynamic> settings) =>
      (settings['maxComboDiscount'] as num?)?.toDouble() ?? 20;

  static List<Map<String, dynamic>> combosOf(Map<String, dynamic> settings) =>
      ((settings['combos'] as List?) ?? const []).map((c) => Map<String, dynamic>.from(c as Map)).toList();

  static Map<String, Map<String, dynamic>> combosById(Map<String, dynamic> settings) =>
      {for (final c in combosOf(settings)) (c['id'] ?? '').toString(): c};

  static String _fmtQty(double q) => q == q.roundToDouble() ? q.toInt().toString() : q.toString();

  /// How a combo item reads to customers: "500 g", "2 kg", "1 kg bag", "2 × 1 kg bag".
  static String comboItemLabel(Map<String, dynamic> p, double qty) {
    if (sellsByWeight(p)) return qty < 1 ? '${(qty * 1000).round()} g' : '${_fmtQty(qty)} kg';
    return qty == 1 ? packLabel(p) : '${_fmtQty(qty)} × ${packLabel(p)}';
  }

  /// Kilograms in a pack label like "25 kg bag" or "500 g"; 0 if none.
  static double kgInLabel(String label) {
    final m = RegExp(r'(\d+(?:\.\d+)?)\s*(kg|kgs|kilo|kilos|g|gm|gms|gram|grams)\b', caseSensitive: false)
        .firstMatch(label);
    if (m == null) return 0;
    final n = double.tryParse(m.group(1)!) ?? 0;
    return m.group(2)!.toLowerCase().startsWith('k') ? n : n / 1000;
  }

  /// Parcel weight of a combo (for weight-based delivery charges).
  static double comboWeightKg(Map<String, dynamic> combo, Map<String, Map<String, dynamic>> productsById) {
    var kg = 0.0;
    for (final raw in (combo['items'] as List? ?? const [])) {
      final i = Map<String, dynamic>.from(raw as Map);
      final p = productsById[i['id']];
      final q = (i['qty'] as num?)?.toDouble() ?? 0;
      if (p == null) continue;
      final perUnit = sellsByWeight(p) ? 1.0 : (kgInLabel(packLabel(p)) > 0 ? kgInLabel(packLabel(p)) : 1.0);
      kg += q * perUnit;
    }
    return (kg * 1000).roundToDouble() / 1000;
  }

  /// Normal (non-combo) total of a combo at today's online prices.
  static double comboNormal(Map<String, dynamic> combo, Map<String, Map<String, dynamic>> productsById) {
    var sum = 0.0;
    for (final raw in (combo['items'] as List? ?? const [])) {
      final i = Map<String, dynamic>.from(raw as Map);
      final p = productsById[i['id']];
      if (p != null) sum += webPriceOf(p) * ((i['qty'] as num?)?.toDouble() ?? 0);
    }
    return _r2(sum);
  }

  /// Why a combo can't be published, or null if it's fine. Enforces the
  /// shop's maximum discount so a typo can never go live.
  static String? comboProblem(Map<String, dynamic> combo, Map<String, Map<String, dynamic>> productsById,
      double maxDiscountPercent) {
    final items = (combo['items'] as List? ?? const []);
    if (items.length < 2) return 'Choose at least 2 products';
    for (final raw in items) {
      final p = productsById[(raw as Map)['id']];
      if (p == null) return 'A product in this combo was deleted';
      if (!isOnline(p)) return '${p['name']} is not on the web store';
    }
    final price = (combo['price'] as num?)?.toDouble() ?? 0;
    final normal = comboNormal(combo, productsById);
    if (price <= 0) return 'Set a combo price';
    if (price >= normal) return 'Combo price must be lower than the normal total (${normal.toStringAsFixed(0)})';
    final discount = (normal - price) / normal * 100;
    if (discount > maxDiscountPercent + 0.001) {
      return 'Discount ${discount.toStringAsFixed(1)}% is above your maximum of ${maxDiscountPercent.toStringAsFixed(0)}%';
    }
    return null;
  }

  static String signatureOf(Map<String, dynamic> catalog) =>
      sha1.convert(utf8.encode(jsonEncode(catalog))).toString();

  /// Problems the owner should fix before customers can order smoothly.
  static List<String> warnings(List<Map<String, dynamic>> products, Map<String, dynamic> settings) {
    final w = <String>[];
    final store = (settings['store'] as Map?) ?? const {};
    final wa = (store['whatsapp'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
    if (wa.length != 12) w.add('Add the shop WhatsApp number (12 digits, e.g. 919876543210) in Shop details.');
    final noPrice = products.where((p) => p['web_visible'] != false && priceOf(p) <= 0).length;
    if (noPrice > 0) w.add('$noPrice product(s) have no selling price, so they are not on the web store.');
    return w;
  }

  // ---------------- Publishing ----------------

  final ValueNotifier<WebSyncState> sync = ValueNotifier(WebSyncState.idle);
  String? lastError;

  StreamSubscription? _productsSub, _settingsSub, _catalogSub, _tipsSub;
  Map<String, List<Map<String, dynamic>>> _approvedTips = const {};
  Map<String, List<Map<String, dynamic>>> _approvedReviews = const {};
  StreamSubscription? _reviewsSub;
  bool _reviewsSeen = false;
  bool _tipsSeen = false;
  List<Map<String, dynamic>>? _latestProducts;
  Map<String, dynamic>? _latestSettings;
  String? _liveSig;
  bool _catalogSeen = false;
  bool _publishing = false;
  bool _again = false;
  Timer? _debounce;

  /// Started for master accounts only (viewers can't publish).
  void startAutoSync() {
    if (_productsSub != null) return;
    _catalogSub = catalogRef.snapshots().listen((s) {
      _catalogSeen = true;
      _liveSig = s.data()?['sig'] as String?;
      _schedule();
    }, onError: (Object e) => debugPrint('Catalog watch error: $e'));
    _productsSub = watchProducts().listen((p) {
      _latestProducts = p;
      _schedule();
    }, onError: (Object e) => debugPrint('Products watch error: $e'));
    _tipsSub = _tips.where('status', isEqualTo: 'approved').snapshots().listen((snap) {
      final byProduct = <String, List<Map<String, dynamic>>>{};
      for (final d in snap.docs) {
        final m = d.data();
        final pid = (m['productId'] ?? '').toString();
        if (pid.isNotEmpty) byProduct.putIfAbsent(pid, () => []).add(m);
      }
      _approvedTips = byProduct;
      _tipsSeen = true;
      _schedule();
    }, onError: (Object e) {
      debugPrint('Tips watch error: $e');
      _tipsSeen = true; // publish without tips rather than not at all
      _schedule();
    });
    _reviewsSub = _fs.collection('reviews').where('status', isEqualTo: 'approved').snapshots().listen((snap) {
      final byProduct = <String, List<Map<String, dynamic>>>{};
      final docs = [...snap.docs]..sort((a, b) =>
          (b.data()['approved_at'] ?? '').toString().compareTo((a.data()['approved_at'] ?? '').toString()));
      for (final d in docs) {
        final pid = (d.data()['productId'] ?? '').toString();
        if (pid.isNotEmpty) byProduct.putIfAbsent(pid, () => []).add(d.data());
      }
      _approvedReviews = byProduct;
      _reviewsSeen = true;
      _schedule();
    }, onError: (Object e) {
      debugPrint('Reviews watch error: $e');
      _reviewsSeen = true;
      _schedule();
    });
    _settingsSub = watchSettings().listen((s) {
      _latestSettings = s;
      _schedule();
    }, onError: (Object e) => debugPrint('Settings watch error: $e'));
  }

  void stopAutoSync() {
    _debounce?.cancel();
    _productsSub?.cancel();
    _settingsSub?.cancel();
    _catalogSub?.cancel();
    _tipsSub?.cancel();
    _reviewsSub?.cancel();
    _reviewsSub = null;
    _reviewsSeen = false;
    _productsSub = _settingsSub = _catalogSub = _tipsSub = null;
    _tipsSeen = false;
    _catalogSeen = false;
    sync.value = WebSyncState.idle;
  }

  void _schedule() {
    final products = _latestProducts, settings = _latestSettings;
    if (products == null || settings == null || !_catalogSeen || !_tipsSeen || !_reviewsSeen) return;
    final sig = signatureOf(buildCatalog(products, settings, _approvedTips, _approvedReviews));
    if (sig == _liveSig) {
      if (!_publishing) sync.value = WebSyncState.upToDate;
      return;
    }
    if (!_publishing) sync.value = WebSyncState.pending;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 4), publishNow);
  }

  Future<void> publishNow() async {
    final products = _latestProducts, settings = _latestSettings;
    if (products == null || settings == null) return;
    if (_publishing) {
      _again = true;
      return;
    }
    _publishing = true;
    sync.value = WebSyncState.publishing;
    try {
      await _publish(products, settings, _approvedTips, _approvedReviews);
      lastError = null;
      sync.value = WebSyncState.upToDate;
    } catch (e) {
      lastError = '$e';
      sync.value = WebSyncState.error;
    } finally {
      _publishing = false;
      if (_again) {
        _again = false;
        _schedule();
      }
    }
  }

  Future<void> _publish(List<Map<String, dynamic>> products, Map<String, dynamic> settings,
      Map<String, List<Map<String, dynamic>>> tips, Map<String, List<Map<String, dynamic>>> reviews) async {
    final catalog = buildCatalog(products, settings, tips, reviews);
    final sig = signatureOf(catalog);

    // Photos first, so the website never points at a photo not yet there.
    final published = Map<String, dynamic>.from((settings['image_versions'] as Map?) ?? const {});
    final wanted = <String, String>{};
    for (final p in products.where(isOnline)) {
      final photo = p['photo'] as String?;
      if (photo == null || photo.isEmpty) continue;
      final id = p['id'] as String;
      final hash = photoHash(photo);
      wanted[id] = hash;
      if (published[id] != hash) {
        await _write(_images.doc(id).set({'data': photo, 'v': hash}));
      }
    }
    for (final id in published.keys) {
      if (!wanted.containsKey(id)) await _write(_images.doc(id).delete());
    }

    await _write(catalogRef.set({...catalog, 'sig': sig, 'updatedAt': FieldValue.serverTimestamp()}));
    _liveSig = sig;
    await _write(settingsRef.set(
      {'image_versions': wanted, 'last_published_at': DateTime.now().toIso8601String()},
      SetOptions(mergeFields: ['image_versions', 'last_published_at']),
    ));
  }

  // ---------------- Website photos (banners, owner, categories) ----------------
  // Stored straight in catalog_images/{key} (public, like product photos)
  // and referenced from the site content as "fs:<key>:<version>".

  Future<String> uploadSiteImage(String key, String base64Photo) async {
    final v = photoHash(base64Photo);
    await _write(_images.doc(key).set({'data': base64Photo, 'v': v}));
    return 'fs:$key:$v';
  }

  Future<void> deleteSiteImage(String? ref) async {
    if (ref == null || !ref.startsWith('fs:')) return;
    final parts = ref.split(':');
    if (parts.length < 2 || parts[1].isEmpty) return;
    await _write(_images.doc(parts[1]).delete());
  }

  Future<void> saveSite(Map<String, dynamic> patch) => saveSettings({'site': patch});

  // ---------------- Product reviews ----------------
  Stream<List<Map<String, dynamic>>> watchReviews(String status) => _fs
      .collection('reviews')
      .where('status', isEqualTo: status)
      .snapshots()
      .map((s) => s.docs.map((d) => <String, dynamic>{...d.data(), 'id': d.id}).toList());

  Future<void> setReviewStatus(String id, String status) => _write(_fs.collection('reviews').doc(id).update({
        'status': status,
        if (status == 'approved') 'approved_at': DateTime.now().toIso8601String(),
      }));

  // ---------------- Customer tips ----------------
  // Customers suggest tips on the website ("pending"); only approved
  // ones are published with the product.

  Stream<List<Map<String, dynamic>>> watchTips(String status) =>
      _tips.where('status', isEqualTo: status).snapshots().map((s) =>
          s.docs.map((d) => <String, dynamic>{...d.data(), 'id': d.id}).toList());

  Future<void> setTipStatus(String tipId, String status) =>
      _write(_tips.doc(tipId).update({'status': status}));

  Future<void> deleteTip(String tipId) => _write(_tips.doc(tipId).delete());

  // ---------------- Orders from the web store ----------------

  static const statuses = ['requested', 'confirmed', 'dispatched', 'delivered', 'paid', 'cancelled'];

  Stream<List<Map<String, dynamic>>> watchOrders() => _orders
      .orderBy('createdAt', descending: true)
      .limit(300)
      .snapshots()
      .map((s) => s.docs.map((d) => <String, dynamic>{...d.data(), 'id': d.id}).toList());

  /// Orders waiting for the shop — drives the Dashboard bell.
  Stream<int> watchNewOrderCount() =>
      _orders.where('status', isEqualTo: 'requested').snapshots().map((s) => s.docs.length);

  // Order money: items + delivery charge. The shop can change the charge
  // per order (courier costs vary by distance) before confirming.
  static double orderItemsTotal(Map<String, dynamic> o) =>
      (o['itemsTotal'] as num?)?.toDouble() ?? (o['total'] as num?)?.toDouble() ?? 0;
  static double orderDelivery(Map<String, dynamic> o) =>
      (o['delivery_charge_override'] as num?)?.toDouble() ?? (o['deliveryCharge'] as num?)?.toDouble() ?? 0;
  static double orderTotal(Map<String, dynamic> o) => orderItemsTotal(o) + orderDelivery(o);
  static String orderAddress(Map<String, dynamic> c) => [
        c['address'],
        c['landmark'],
        c['area'] == 'Other area' ? '' : c['area'],
        c['city'],
        (c['pincode'] ?? '').toString().isEmpty ? '' : 'PIN ${c['pincode']}',
      ].map((x) => (x ?? '').toString().trim()).where((x) => x.isNotEmpty).join(', ');

  /// Shop checked the customer's payment screenshot. Also updates the
  /// tracking record, which sends the customer a "Payment received" alert.
  Future<void> setPaymentVerified(String orderId) async {
    await _write(_orders.doc(orderId).update({
      'payment_verified': true,
      'payment_verified_at': DateTime.now().toIso8601String(),
    }));
    await _write(_fs.collection('order_status').doc(orderId).set({
      'paymentVerified': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)));
  }

  /// The customer's payment screenshot (data URL), or null.
  Future<String?> paymentProof(String orderId) async {
    try {
      final d = await _fs.collection('payment_proofs').doc(orderId).get().timeout(const Duration(seconds: 10));
      final v = d.data()?['data'];
      return v is String && v.startsWith('data:image/') ? v : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> setDeliveryCharge(String orderId, double amount) =>
      _write(_orders.doc(orderId).update({'delivery_charge_override': amount}));

  /// Moves an order on, and updates the customer's public tracking page
  /// (order_status: status, times and courier details — nothing personal).
  Future<void> setOrderStatus(String orderId, String status,
      {String courier = '', String trackingNo = '', String trackingUrl = ''}) async {
    final courierFields = {
      if (courier.isNotEmpty) 'courier': courier,
      if (trackingNo.isNotEmpty) 'trackingNo': trackingNo,
      if (trackingUrl.startsWith('https://')) 'trackingUrl': trackingUrl,
    };
    await _write(_orders.doc(orderId).update({
      'status': status,
      'status_at': DateTime.now().toIso8601String(),
      ...courierFields,
    }));
    await _write(_fs.collection('order_status').doc(orderId).set({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
      'history': {status: FieldValue.serverTimestamp()},
      ...courierFields,
    }, SetOptions(merge: true)));
  }

  /// Public tracking link for an order, e.g. https://<project>.web.app/?track=SMA-1001-AB12
  static String trackingLink(String orderNo, String projectId) => 'https://$projectId.web.app/?track=$orderNo';

  /// One WhatsApp confirmation sent — kept as a count plus a history.
  Future<void> logOrderWhatsApp(String orderId, String language) => _write(_orders.doc(orderId).update({
        'whatsapp_count': FieldValue.increment(1),
        'whatsapp_log': FieldValue.arrayUnion([
          {'at': DateTime.now().toIso8601String(), 'lang': language}
        ]),
      }));

  Future<void> linkSale(String orderId, String saleId, {required bool confirm}) =>
      _write(_orders.doc(orderId).update({
        'sale_id': saleId,
        if (confirm) 'status': 'confirmed',
        if (confirm) 'status_at': DateTime.now().toIso8601String(),
      }));

  /// Compares each ordered item with the product's price in the app
  /// today. The website calculates prices in the customer's browser,
  /// so a changed page could send any price — this catches it.
  static List<Map<String, dynamic>> priceCheck(
      Map<String, dynamic> order, Map<String, Map<String, dynamic>> productsById,
      [Map<String, Map<String, dynamic>> combosById = const {}]) {
    final out = <Map<String, dynamic>>[];
    for (final raw in (order['items'] as List? ?? const [])) {
      final item = Map<String, dynamic>.from(raw as Map);
      // A combo line becomes one row per product inside it, each carrying
      // its fair share of the combo price, so stock and reports stay exact.
      final parts = (item['combo'] as List?) ?? const [];
      if (parts.isNotEmpty) {
        final orderQty = (item['qty'] as num?)?.toDouble() ?? 0;
        final orderedCombo = (item['price'] as num?)?.toDouble() ?? 0;
        final combo = combosById[(item['id'] ?? '').toString().replaceFirst('combo:', '')];
        final currentCombo = (combo?['price'] as num?)?.toDouble();
        final rows = parts.map((x) => Map<String, dynamic>.from(x as Map)).toList();
        final normals = [
          for (final r in rows)
            (productsById[r['id']] == null ? 0.0 : webPriceOf(productsById[r['id']]!)) *
                ((r['qty'] as num?)?.toDouble() ?? 0)
        ];
        final sumN = normals.fold<double>(0, (a, b) => a + b);
        for (var k = 0; k < rows.length; k++) {
          final r = rows[k];
          final product = productsById[r['id']];
          final partQty = (r['qty'] as num?)?.toDouble() ?? 0;
          if (partQty <= 0) continue;
          final share = sumN > 0 ? normals[k] / sumN : 1 / rows.length;
          final orderedUnit = _r2(orderedCombo * share / partQty);
          final currentUnit = (product == null || currentCombo == null) ? null : _r2(currentCombo * share / partQty);
          out.add({
            'id': r['id'],
            'name': '${product?['name'] ?? r['id']} (${item['name']})',
            'pack': 'combo',
            'qty': partQty * orderQty,
            'per_pack': 1.0,
            'units': partQty * orderQty,
            'ordered_price': orderedUnit,
            'current_price': currentUnit,
            'product': product,
            'ok': currentUnit != null && (currentUnit - orderedUnit).abs() < 0.5,
          });
        }
        continue;
      }
      final product = productsById[item['id']];
      final ordered = (item['price'] as num?)?.toDouble() ?? 0;
      final qty = (item['qty'] as num?)?.toDouble() ?? 0;
      // Weight items carry kg per pack (e.g. 2.5); others are one app unit.
      final kg = (item['kg'] as num?)?.toDouble();
      final perPack = kg ?? 1.0;
      final current = product == null ? null : (webPriceOf(product) * perPack).roundToDouble();
      out.add({
        ...item,
        'qty': qty,
        'per_pack': perPack,
        'units': qty * perPack, // quantity to record in Inventory (kg for weight items)
        'ordered_price': ordered,
        'current_price': current,
        'product': product,
        'ok': current != null && (current - ordered).abs() < 0.5,
      });
    }
    return out;
  }
}
