import 'package:flutter/material.dart';
import '../db/db_helper.dart';
import '../utils/formatters.dart';
import '../utils/app_strings.dart';
import '../utils/app_theme.dart';

class TodaysCollectionsScreen extends StatelessWidget {
  const TodaysCollectionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = DBHelper.instance;
    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      appBar: AppBar(title: Text(AppStrings.t('todays_collections'))),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: db.watchTodaysCollections(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(message: "${AppStrings.t('could_not_load_collections')}: ${snapshot.error}");
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final collections = snapshot.data!;
          final total = collections.fold<double>(0, (sum, c) => sum + (c['amount'] as num));

          return Column(
            children: [
              SummaryBanner(
                icon: Icons.payments_outlined,
                label: AppStrings.t('total_collected_today'),
                value: formatCurrency(total),
                color: AppTheme.success,
                caption: '${collections.length} ${AppStrings.t('payments')}',
              ),
              Expanded(
                child: collections.isEmpty
                    ? EmptyState(icon: Icons.payments_outlined, title: AppStrings.t('no_collections_today'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
                        itemCount: collections.length,
                        itemBuilder: (_, i) {
                          final c = collections[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: AppCard(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  const IconBadge(icon: Icons.payments_outlined, color: AppTheme.success, size: 20),
                                  const SizedBox(width: 13),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(c['vendor_name'] as String,
                                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                                        const SizedBox(height: 2),
                                        Text(formatDate(c['date'] as String),
                                            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    formatCurrency(c['amount']),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.success),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
