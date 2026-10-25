import 'package:flutter/material.dart';
import '../services/web_store_service.dart';
import '../utils/app_theme.dart';
import 'finance_screen.dart';
import 'inventory_screen.dart';
import 'online_orders_screen.dart';
import 'product_margins_screen.dart';
import 'suppliers_screen.dart';
import 'todays_collections_screen.dart';
import 'vendor_insights_screen.dart';

/// One shortcut in a tab's top strip.
class HubLink {
  final IconData icon;
  final String label;
  final Widget Function() page;
  final Stream<int> Function()? badge;
  const HubLink(this.icon, this.label, this.page, {this.badge});
}

/// A strip of white pills under a main tab's title — the related screens
/// that belong to that tab (one home for every feature).
class HubBar extends StatelessWidget implements PreferredSizeWidget {
  final List<HubLink> links;
  const HubBar(this.links, {super.key});

  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      color: AppTheme.primary,
      padding: const EdgeInsets.only(bottom: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: links.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) => _pill(context, links[i]),
      ),
    );
  }

  Widget _pill(BuildContext context, HubLink l) => _Pill(l);
}

class _Pill extends StatefulWidget {
  final HubLink l;
  const _Pill(this.l);

  @override
  State<_Pill> createState() => _PillState();
}

class _PillState extends State<_Pill> {
  late final Stream<int>? _badge = widget.l.badge?.call();

  Widget _body(int n) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(widget.l.icon, size: 17, color: Colors.white),
        const SizedBox(width: 6),
        Text(widget.l.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
        if (n > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: const Color(0xFFFFB020), borderRadius: BorderRadius.circular(10)),
            child: Text('$n', style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w800)),
          ),
        ],
      ]);

  @override
  Widget build(BuildContext context) {
    final b = _badge;
    return Material(
      color: Colors.white.withOpacity(0.16),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => widget.l.page())),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Center(
            child: b == null ? _body(0) : StreamBuilder<int>(stream: b, builder: (_, s) => _body(s.data ?? 0)),
          ),
        ),
      ),
    );
  }
}

/// New online orders waiting (live).
Stream<int> newOrdersBadge() => WebStoreService.instance.watchNewOrderCount();

List<HubLink> salesLinks() => [
      HubLink(Icons.shopping_bag_outlined, 'Online orders', () => const OnlineOrdersScreen(), badge: newOrdersBadge),
      HubLink(Icons.payments_outlined, "Today's collections", () => const TodaysCollectionsScreen()),
    ];

List<HubLink> stockLinks() => [
      HubLink(Icons.warning_amber_rounded, 'Low stock', () => const InventoryScreen(initialCategoryFilter: 'Low Stock')),
      HubLink(Icons.percent, 'Pricing & margins', () => const ProductMarginsScreen()),
      HubLink(Icons.local_shipping_outlined, 'Suppliers & purchases', () => const SuppliersScreen()),
    ];

List<HubLink> customerLinks() => [
      HubLink(Icons.insights_outlined, 'Buying pattern', () => const VendorInsightsScreen(startWithPattern: true)),
      HubLink(Icons.hourglass_bottom, 'Debts by age', () => const FinanceScreen(initialTab: 4)),
      HubLink(Icons.place_outlined, 'Insights', () => const VendorInsightsScreen()),
    ];
