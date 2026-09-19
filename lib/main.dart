import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  runApp(const ApsdkApp());
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
      builder: (context, snapshot) {
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
        if (snapshot.hasData) {
          return const RootNav();
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
