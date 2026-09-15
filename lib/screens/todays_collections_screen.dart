import 'package:flutter/material.dart';
import '../db/db_helper.dart';
import '../utils/formatters.dart';
import '../utils/app_strings.dart';

class TodaysCollectionsScreen extends StatelessWidget {
  const TodaysCollectionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = DBHelper.instance;
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.t('todays_collections'))),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: db.watchTodaysCollections(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text("${AppStrings.t('could_not_load_collections')}: ${snapshot.error}"));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final collections = snapshot.data!;
          final total = collections.fold<double>(0, (sum, c) => sum + (c['amount'] as num));

          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Text(
                  "${AppStrings.t('total_collected_today')}: ${formatCurrency(total)}  (${collections.length} ${AppStrings.t('payments')})",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: collections.isEmpty
                    ? Center(child: Text(AppStrings.t('no_collections_today')))
                    : ListView.builder(
                        itemCount: collections.length,
                        itemBuilder: (_, i) {
                          final c = collections[i];
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            child: ListTile(
                              leading: const CircleAvatar(child: Icon(Icons.payments)),
                              title: Text(c['vendor_name'] as String),
                              subtitle: Text(formatDate(c['date'] as String)),
                              trailing: Text(
                                formatCurrency(c['amount']),
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
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
