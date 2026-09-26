import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'utils/app_theme.dart';
import 'utils/app_logo.dart';
import 'utils/locale_controller.dart';
import 'utils/app_strings.dart';
import 'utils/user_role.dart';
import 'utils/session_lock.dart';
import 'services/web_store_service.dart';
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
    await SessionLock.instance.load();

    // Crash reporting is wrapped in its own try/catch, deliberately
    // separate from the core initialization above — a failure here
    // should never be able to block the app from opening at all.
    // Crash reporting is a "nice to have" for diagnosing problems, not
    // something the app's actual usability should ever depend on; a
    // shop owner needing to record a sale shouldn't be locked out
    // because a crash-reporting tool itself failed to set up.
    try {
      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
      WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    } catch (_) {
      // Crash reporting itself isn't available for some reason — the
      // app still runs normally below, just without it this session.
    }

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
          // Signed in, but locked via Logout -> show the login screen,
          // which can unlock offline against the stored fingerprint.
          return ListenableBuilder(
            listenable: SessionLock.instance,
            builder: (context, _) =>
                SessionLock.instance.isLocked ? const LoginScreen() : const RootNav(),
          );
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
  bool _roleLoaded = false;

  @override
  void initState() {
    super.initState();
    // Fetched once per sign-in (RootNav only exists while signed in —
    // see AuthGate) rather than re-fetched by every screen that needs
    // to know the role. Awaited properly this time and gated behind
    // _roleLoaded below — every screen that checks UserRole.instance
    // reads it directly in its own build() method rather than listening
    // for changes, so the previous fire-and-forget call let the real
    // screens render immediately with whatever UserRole happened to
    // hold at that instant. For an admin account, that could still be
    // "viewer" left over from a previous sign-out's safe default,
    // visible until something else happened to trigger a rebuild —
    // exactly the flash of the View Only page a master account saw
    // before a manual refresh corrected it. Waiting here means every
    // screen sees the right role from the moment it's first built, not
    // just eventually.
    _loadRole();
  }

  Future<void> _loadRole() async {
    await UserRole.instance.load();
    // Master accounts keep the web store's catalog in step with the
    // app's products automatically (see WebStoreService).
    if (UserRole.instance.isAdmin) {
      WebStoreService.instance.startAutoSync();
    } else {
      WebStoreService.instance.stopAutoSync();
    }
    if (mounted) setState(() => _roleLoaded = true);
  }

  @override
  void dispose() {
    WebStoreService.instance.stopAutoSync();
    super.dispose();
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
    if (!_roleLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (UserRole.instance.isPending) {
      return _PendingAccessScreen(onRetry: () async {
        setState(() => _roleLoaded = false);
        await _loadRole();
      });
    }
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

/// Shown to an account that isn't allowed in yet: a new sign-up waiting
/// for approval, or an owner whose user ID hasn't been added to `admins`.
class _PendingAccessScreen extends StatelessWidget {
  final Future<void> Function() onRetry;
  const _PendingAccessScreen({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? '';
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 24),
            const Icon(Icons.lock_clock_outlined, size: 56, color: AppTheme.primary),
            const SizedBox(height: 16),
            const Text('Waiting for access',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(
              'Signed in as ${user?.email ?? ''}. A master account needs to allow this account in '
              'Manage Users before it can see the shop\'s data.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13.5, height: 1.4),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Owner of the shop?',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 6),
                  const Text(
                    'In the Firebase console, open Firestore, collection "admins", and add a '
                    'document whose ID is the user ID below (any field, e.g. role: owner). '
                    'Then tap Check again.',
                    style: TextStyle(fontSize: 12.5, height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  SelectableText(uid, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: uid));
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('User ID copied')));
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy user ID'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Check again'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () async {
                UserRole.instance.reset();
                await SessionLock.instance.lock();
              },
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}
