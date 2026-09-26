import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

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

  static double priceOf(Map<String, dynamic> p) => (p['selling_price'] as num?)?.toDouble() ?? 0;

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

  static String categoryOf(Map<String, dynamic> p) {
    final c = (p['category'] as String? ?? '').trim();
    return c.isEmpty ? 'Other' : c;
  }

  static Map<String, dynamic> buildCatalog(
      List<Map<String, dynamic>> products, Map<String, dynamic> settings) {
    final items = <Map<String, dynamic>>[];
    for (final p in products.where(isOnline)) {
      final price = priceOf(p);
      final offer = (p['offer_price'] as num?)?.toDouble() ?? 0;
      final photo = p['photo'] as String?;
      items.add({
        'id': p['id'],
        'name': (p['name'] ?? '').toString().trim(),
        'nameLocal': (p['name_local'] ?? '').toString().trim(),
        'category': categoryOf(p),
        'image': (photo != null && photo.isNotEmpty) ? 'fs:${p['id']}:${photoHash(photo)}' : '',
        'inStock': ((p['quantity'] as num?)?.toDouble() ?? 0) > 0,
        'order': (p['web_order'] as num?)?.toInt() ?? 999,
        'description': (p['web_desc'] ?? '').toString().trim(),
        'descriptionLocal': (p['web_desc_local'] ?? '').toString().trim(),
        'details': ((p['web_details'] as List?) ?? const [])
            .map((d) => d.toString().trim())
            .where((d) => d.isNotEmpty)
            .toList(),
        'homemade': p['web_homemade'] == true,
        'bestseller': p['web_bestseller'] == true,
        'isNew': p['web_new'] == true,
        'packs': [
          {
            'label': packLabel(p),
            'price': price,
            if (offer > 0 && offer < price) 'offerPrice': offer,
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
      'categoriesLocal': Map<String, dynamic>.from((settings['categories_local'] as Map?) ?? const {}),
      'hiddenCategories':
          ((settings['hidden_categories'] as List?) ?? const []).map((e) => e.toString()).toList(),
      'products': items,
      // Banners, delivery note, trust lines, owner story, about, contact
      // links and category photos — edited in Web Store > Website content.
      'site': Map<String, dynamic>.from((settings['site'] as Map?) ?? const {}),
    };
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

  StreamSubscription? _productsSub, _settingsSub, _catalogSub;
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
    _productsSub = _settingsSub = _catalogSub = null;
    _catalogSeen = false;
    sync.value = WebSyncState.idle;
  }

  void _schedule() {
    final products = _latestProducts, settings = _latestSettings;
    if (products == null || settings == null || !_catalogSeen) return;
    final sig = signatureOf(buildCatalog(products, settings));
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
      await _publish(products, settings);
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

  Future<void> _publish(List<Map<String, dynamic>> products, Map<String, dynamic> settings) async {
    final catalog = buildCatalog(products, settings);
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

  // ---------------- Orders from the web store ----------------

  static const statuses = ['requested', 'confirmed', 'delivered', 'paid', 'cancelled'];

  Stream<List<Map<String, dynamic>>> watchOrders() => _orders
      .orderBy('createdAt', descending: true)
      .limit(300)
      .snapshots()
      .map((s) => s.docs.map((d) => <String, dynamic>{...d.data(), 'id': d.id}).toList());

  /// Orders waiting for the shop — drives the Dashboard bell.
  Stream<int> watchNewOrderCount() =>
      _orders.where('status', isEqualTo: 'requested').snapshots().map((s) => s.docs.length);

  Future<void> setOrderStatus(String orderId, String status) => _write(_orders.doc(orderId).update({
        'status': status,
        'status_at': DateTime.now().toIso8601String(),
      }));

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
      Map<String, dynamic> order, Map<String, Map<String, dynamic>> productsById) {
    final out = <Map<String, dynamic>>[];
    for (final raw in (order['items'] as List? ?? const [])) {
      final item = Map<String, dynamic>.from(raw as Map);
      final product = productsById[item['id']];
      final ordered = (item['price'] as num?)?.toDouble() ?? 0;
      final qty = (item['qty'] as num?)?.toDouble() ?? 0;
      final current = product == null ? null : webPriceOf(product);
      out.add({
        ...item,
        'qty': qty,
        'ordered_price': ordered,
        'current_price': current,
        'product': product,
        'ok': current != null && (current - ordered).abs() < 0.5,
      });
    }
    return out;
  }
}
