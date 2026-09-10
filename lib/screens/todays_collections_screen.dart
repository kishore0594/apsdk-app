import 'package:flutter/material.dart';
import '../db/db_helper.dart';
import '../utils/formatters.dart';

class TodaysCollectionsScreen extends StatefulWidget {
  const TodaysCollectionsScreen({super.key});

  @override
  State<TodaysCollectionsScreen> createState() => _TodaysCollectionsScreenState();
}

class _TodaysCollectionsScreenState extends State<TodaysCollectionsScreen> {
  final _db = DBHelper.instance;
  List<Map<String, dynamic>> _collections = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await _db.getTodaysCollections();
    setState(() {
      _collections = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final total = _collections.fold<double>(0, (sum, c) => sum + (c['amount'] as num));
    return Scaffold(
      appBar: AppBar(title: const Text("Today's Collections")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Text(
                      'Total collected today: ${formatCurrency(total)}  (${_collections.length} payments)',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(
                    child: _collections.isEmpty
                        ? ListView(
                            children: const [
                              Padding(
                                padding: EdgeInsets.all(24),
                                child: Center(child: Text('No collections recorded yet today.')),
                              ),
                            ],
                          )
                        : ListView.builder(
                            itemCount: _collections.length,
                            itemBuilder: (_, i) {
                              final c = _collections[i];
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
              ),
            ),
    );
  }
}
