import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import 'combos_screen.dart';
import 'feedback_screen.dart';
import 'offer_alerts_screen.dart';
import 'recipes_screen.dart';
import 'search_words_screen.dart';
import 'share_pictures_screen.dart';
import 'web_store_screen.dart';

/// Marketing tab: everything that brings customers in — status videos and
/// pictures, offers, alerts, combos, the website and what customers say.
/// Most-used first.
class MarketingScreen extends StatelessWidget {
  const MarketingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final groups = <(String, List<_M>)>[
      (
        'Every day',
        [
          _M(Icons.movie_creation_outlined, 'Status video & pictures',
              'WhatsApp Status, Reels, Instagram — and send them to chosen customers (late, due, category buyers)',
              const Color(0xFFE36A06), () => const SharePicturesScreen()),
        ]
      ),
      (
        'Offers',
        [
          _M(Icons.notifications_active_outlined, 'Offer alerts', 'Short alerts to customers\' phones', const Color(0xFF7C3AED),
              () => const OfferAlertsScreen()),
          _M(Icons.redeem_outlined, 'Combo offers', 'Bundles with a discount on the website', const Color(0xFFDB2777),
              () => const CombosScreen()),
        ]
      ),
      (
        'Website',
        [
          _M(Icons.storefront_outlined, 'Website & store settings', 'Products online, content, banners, delivery charges',
              AppTheme.primary, () => const WebStoreScreen()),
          _M(Icons.manage_search, 'What customers searched', 'Words typed on your website and what they could not find',
              const Color(0xFF2563EB), () => const SearchWordsScreen()),
          _M(Icons.menu_book_outlined, 'Recipes', 'Millet recipes shown on the website', const Color(0xFF16A34A),
              () => const RecipesScreen()),
        ]
      ),
      (
        'What customers say',
        [
          _M(Icons.star_outline, 'Reviews', 'Approve or hide customer reviews', const Color(0xFFB7791F), () => const ReviewsScreen()),
          _M(Icons.tips_and_updates_outlined, 'Customer tips', 'Tips customers sent in', const Color(0xFF0D9488),
              () => const TipsScreen()),
          _M(Icons.feedback_outlined, 'Feedback', 'Messages and ratings from customers', const Color(0xFF64748B),
              () => const FeedbackScreen()),
        ]
      ),
    ];
    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      appBar: AppBar(title: const Text('Marketing')),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 32), children: [
        for (final g in groups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
            child: Text(g.$1, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ),
          for (final m in g.$2) _tile(context, m),
        ],
      ]),
    );
  }

  Widget _tile(BuildContext context, _M m) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: m.color.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
            child: Icon(m.icon, color: m.color),
          ),
          title: Text(m.title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(m.sub, style: const TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => m.page())),
        ),
      );
}

class _M {
  final IconData icon;
  final String title, sub;
  final Color color;
  final Widget Function() page;
  const _M(this.icon, this.title, this.sub, this.color, this.page);
}
