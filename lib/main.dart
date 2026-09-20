import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'utils/app_theme.dart';
import 'utils/app_logo.dart';
import 'utils/locale_controller.dart';
import 'utils/app_strings.dart';
import 'utils/user_role.dart';
import 'screens/dashboard_screen.dart';
import 'screens/sales_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/vendors_screen.dart';
import 'screens/suppliers_screen.dart';
import 'screens/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runZonedGuarded(() async {
    await _initializeAndRun();
  }, (error, stack) {
    // Catches anything that escapes even the startup try/catch below —
    // the last line of defense so a startup failure is at least
    // reported to Crashlytics (once it's initialized) rather than
    // silently crashing with nothing recorded anywhere.
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  });
}

Future<void> _initializeAndRun() async {
  try {
    await Firebase.initializeApp();
    // Offline persistence is on by default on Android/iOS, but this makes it
    // explicit rather than relying on an unstated default — and removes any
    // cache-size limit, so a store's data (small by any reasonable measure)
    // is never evicted from the on-device cache to make room, no matter how
    // long the phone stays offline.
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
    await LocaleController.instance.load();

    // Routes real crashes to Firebase Crashlytics instead of only ever
    // being diagnosed from a screenshot and a description — this is the
    // single biggest gap in how bugs have been found and fixed in this
    // app so far. Two separate hooks are needed for full coverage:
    // FlutterError.onError catches errors from within Flutter's own
    // framework (widget build/layout/paint errors); PlatformDispatcher's
    // onError catches everything else — async code running outside that
    // framework's error zone, which FlutterError.onError alone would miss.
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };

    runApp(const ApsdkApp());
  } catch (e, stack) {
    // If anything above fails — for any reason, on any connection —
    // this shows a real, recoverable screen with the actual error text
    // and a way to try again, instead of the app crashing with nothing
    // visible, or a blank screen with no explanation and no way forward.
    // Whatever "offline login" has actually been showing, this at least
    // makes it possible to see the real message behind it, rather than
    // guessing from a description alone.
    try {
      await FirebaseCrashlytics.instance.recordError(e, stack, fatal: true);
    } catch (_) {
      // Crashlytics itself may not be available if Firebase never
      // finished initializing — nothing more to do here.
    }
    runApp(_StartupErrorApp(error: e.toString()));
  }
}

class _StartupErrorApp extends StatelessWidget {
  final String error;
  const _StartupErrorApp({required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  const Text('Could not start the app',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Text(error, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5)),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () => main(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ApsdkApp extends StatelessWidget {
  const ApsdkApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuilds the whole app whenever the language changes, anywhere.
    return ListenableBuilder(
      listenable: LocaleController.instance,
      builder: (context, _) {
        return MaterialApp(
          title: 'Madhura Agro Traders',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(),
          home: const AuthGate(),
        );
      },
    );
  }
}

/// Shows the login screen when signed out, and the main app once signed
/// in. Listens live to Firebase's auth state, so signing out from
/// anywhere in the app immediately drops back to the login screen.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      // FirebaseAuth.instance.currentUser is the locally-cached signed-in
      // user, available synchronously with no network involved — used
      // here as the stream's initial value so a real, already-signed-in
      // session is trusted immediately if one exists, rather than
      // waiting on the stream's first event to decide anything.
      //
      // This matters specifically when the app is opened with no
      // internet: some Firebase Auth SDK versions, as part of resolving
      // that first stream event, try to re-verify the cached session
      // against the server — and clear it if that check fails, rather
      // than falling back to the cache. Deciding from currentUser
      // directly sidesteps that path entirely: a real cached session
      // means RootNav shows immediately, offline or not, and nothing
      // here has any opportunity to fail a network call and undo it.
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, snapshot) {
        if (snapshot.data != null) {
          return const RootNav();
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppLogo(size: 76),
                  SizedBox(height: 20),
                  Text('Madhura Agro Traders',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  SizedBox(height: 20),
                  SizedBox(
                      width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5)),
                ],
              ),
            ),
          );
        }
        return const LoginScreen();
      },
    );
  }
}

class RootNav extends StatefulWidget {
  const RootNav({super.key});

  @override
  State<RootNav> createState() => _RootNavState();
}

class _RootNavState extends State<RootNav> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Fetched once per sign-in (RootNav only exists while signed in —
    // see AuthGate) rather than re-fetched by every screen that needs
    // to know the role.
    UserRole.instance.load();
  }

  final _screens = const [
    DashboardScreen(),
    SalesScreen(),
    InventoryScreen(),
    VendorsScreen(),
    SuppliersScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
              icon: const Icon(Icons.dashboard_outlined),
              selectedIcon: const Icon(Icons.dashboard),
              label: AppStrings.t('nav_home')),
          NavigationDestination(
              icon: const Icon(Icons.point_of_sale_outlined),
              selectedIcon: const Icon(Icons.point_of_sale),
              label: AppStrings.t('nav_sales')),
          NavigationDestination(
              icon: const Icon(Icons.inventory_2_outlined),
              selectedIcon: const Icon(Icons.inventory_2),
              label: AppStrings.t('nav_inventory')),
          NavigationDestination(
              icon: const Icon(Icons.people_outline),
              selectedIcon: const Icon(Icons.people),
              label: AppStrings.t('nav_credit')),
          NavigationDestination(
              icon: const Icon(Icons.local_shipping_outlined),
              selectedIcon: const Icon(Icons.local_shipping),
              label: AppStrings.t('nav_suppliers')),
        ],
      ),
    );
  }
}
