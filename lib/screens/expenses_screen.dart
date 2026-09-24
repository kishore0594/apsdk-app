import 'package:flutter/material.dart';
import '../db/db_helper.dart';
import '../utils/formatters.dart';
import '../utils/app_theme.dart';
import '../utils/user_role.dart';
import '../utils/keyed_stream.dart';

const List<String> kExpenseCategories = [
  'Rent',
  'Electricity',
  'Wages',
  'Transport',
  'Maintenance',
  'Other',
];

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final _expensesStream = KeyedStream<List<Map<String, dynamic>>>();
  final _db = DBHelper.instance;
  String _period = 'Month'; // Week, Month, Custom
  DateTime _customStart = DateTime.now().subtract(const Duration(days: 29));
  DateTime _customEnd = DateTime.now();

  (String, String) _range() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (_period == 'Week') {
      return (
        today.subtract(const Duration(days: 6)).toIso8601String(),
        today.add(const Duration(days: 1)).toIso8601String(),
      );
    }
    if (_period == 'Custom') {
      final start = DateTime(_customStart.year, _customStart.month, _customStart.day);
      final endExclusive =
          DateTime(_customEnd.year, _customEnd.month, _customEnd.day).add(const Duration(days: 1));
      return (start.toIso8601String(), endExclusive.toIso8601String());
    }
    // Month
    final start = DateTime(now.year, now.month, 1);
    final endExclusive = DateTime(now.year, now.month + 1, 1);
    return (start.toIso8601String(), endExclusive.toIso8601String());
  }

  Future<void> _pickCustomRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _customStart, end: _customEnd),
    );
    if (range != null && mounted) {
      setState(() {
        _customStart = range.start;
        _customEnd = range.end;
        _period = 'Custom';
      });
    }
  }

  Future<void> _openExpenseForm({Map<String, dynamic>? expense}) async {
    String category = (expense?['category'] as String?) ?? kExpenseCategories.first;
    if (!kExpenseCategories.contains(category)) category = 'Other';
    final amountCtrl = TextEditingController(text: expense != null ? '${expense['amount']}' : '');
    final notesCtrl = TextEditingController(text: expense?['notes'] as String? ?? '');
    DateTime date = expense != null
        ? (DateTime.tryParse(expense['date'] as String) ?? DateTime.now())
        : DateTime.now();

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(expense == null ? 'Add Expense' : 'Edit Expense'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: kExpenseCategories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => category = v ?? category),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: amountCtrl,
                  decoration: const InputDecoration(labelText: 'Amount'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  autofocus: expense == null,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(labelText: 'Notes (optional)'),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Date', style: TextStyle(fontSize: 13)),
                  subtitle: Text(formatDay(date.toIso8601String())),
                  trailing: const Icon(Icons.calendar_today, size: 18),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setDialogState(() => date = picked);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            if (UserRole.instance.isAdmin)
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );

    final amount = double.tryParse(amountCtrl.text) ?? 0;
    if (saved != true || amount <= 0) return;

    if (expense == null) {
      await _db.addExpense(
        category: category,
        amount: amount,
        notes: notesCtrl.text.trim(),
        date: date.toIso8601String(),
      );
    } else {
      await _db.updateExpense(
        expense['id'] as String,
        category: category,
        amount: amount,
        notes: notesCtrl.text.trim(),
        date: date.toIso8601String(),
      );
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> expense) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete this expense?'),
        content: Text('${expense['category']} — ${formatCurrency(expense['amount'])}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) await _db.deleteExpense(expense['id'] as String);
  }

  @override
  Widget build(BuildContext context) {
    final (start, end) = _range();
    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      appBar: AppBar(title: const Text('Operating Expenses')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(
              children: [
                Expanded(
                  child: _PeriodPill(
                    label: 'Week',
                    selected: _period == 'Week',
                    onTap: () => setState(() => _period = 'Week'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _PeriodPill(
                    label: 'Month',
                    selected: _period == 'Month',
                    onTap: () => setState(() => _period = 'Month'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _PeriodPill(
                    label: 'Custom',
                    icon: Icons.calendar_month,
                    selected: _period == 'Custom',
                    onTap: _pickCustomRange,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _expensesStream.get('$start|$end',
                  () => _db.watchExpenses(startIso: start, endIsoExclusive: end)),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return ErrorState(message: 'Could not load expenses: ${snapshot.error}');
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final expenses = snapshot.data!;
                final total = expenses.fold<double>(0, (sum, e) => sum + (e['amount'] as num));
                final byCategory = <String, double>{};
                for (final e in expenses) {
                  final cat = e['category'] as String? ?? 'Other';
                  byCategory[cat] = (byCategory[cat] ?? 0) + (e['amount'] as num).toDouble();
                }
                final categoryEntries = byCategory.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value));

                return ListView(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 90),
                  children: [
                    SummaryBanner(
                      icon: Icons.receipt_long_outlined,
                      label: 'Total Expenses',
                      value: formatCurrency(total),
                      color: AppTheme.cost,
                      caption: '${expenses.length} entries',
                    ),
                    if (categoryEntries.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: categoryEntries
                            .map((e) => Chip(
                                  label: Text('${e.key}: ${formatCurrency(e.value)}',
                                      style: const TextStyle(fontSize: 11.5)),
                                  visualDensity: VisualDensity.compact,
                                ))
                            .toList(),
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (expenses.isEmpty)
                      EmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: 'No expenses recorded for this period',
                        message: 'Add rent, electricity, wages, or other overhead to see a real profit number.',
                        action: UserRole.instance.isAdmin
                            ? FilledButton.icon(
                                onPressed: () => _openExpenseForm(),
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('Add Expense'),
                              )
                            : null,
                      )
                    else
                      for (final e in expenses)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: AppCard(
                            padding: const EdgeInsets.all(14),
                            onTap: () => _openExpenseForm(expense: e),
                            onLongPress: UserRole.instance.isAdmin ? () => _confirmDelete(e) : null,
                            child: Row(
                              children: [
                                const IconBadge(icon: Icons.receipt_long_outlined, color: AppTheme.cost, size: 18),
                                const SizedBox(width: 13),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(e['category'] as String? ?? 'Other',
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                                      const SizedBox(height: 2),
                                      Text(
                                        (e['notes'] as String?)?.isNotEmpty == true
                                            ? '${formatDate(e['date'] as String)} • ${e['notes']}'
                                            : formatDate(e['date'] as String),
                                        style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                Text(formatCurrency(e['amount']),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.cost)),
                              ],
                            ),
                          ),
                        ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: UserRole.instance.isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _openExpenseForm(),
              icon: const Icon(Icons.add),
              label: const Text('Add Expense'),
            )
          : null,
    );
  }
}

class _PeriodPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  const _PeriodPill({required this.label, required this.selected, required this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          border: Border.all(color: selected ? AppTheme.primary : AppTheme.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: selected ? Colors.white : Colors.black54),
              const SizedBox(width: 4),
            ],
            Text(label,
                style: TextStyle(
                  fontSize: 13,
                  color: selected ? Colors.white : Colors.black87,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                )),
          ],
        ),
      ),
    );
  }
}
