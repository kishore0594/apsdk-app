import 'package:flutter/material.dart';
import '../db/db_helper.dart';
import '../utils/app_theme.dart';
import '../utils/keyed_stream.dart';

class ManageUsersScreen extends StatefulWidget {
  const ManageUsersScreen({super.key});

  @override
  State<ManageUsersScreen> createState() => _ManageUsersScreenState();
}

class _ManageUsersScreenState extends State<ManageUsersScreen> {
  final _usersStream = KeyedStream<List<Map<String, dynamic>>>();
  final _db = DBHelper.instance;

  Future<void> _changeRole(Map<String, dynamic> user) async {
    final currentRole = user['approved'] == true ? (user['role'] as String? ?? 'viewer') : 'revoked';
    final newRole = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(user['email'] as String? ?? 'This account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<String>(
              value: 'viewer',
              groupValue: currentRole,
              title: const Text('View Only'),
              subtitle: const Text('Can see everything, can\'t add, edit, or delete anything'),
              onChanged: (v) => Navigator.pop(context, v),
            ),
            RadioListTile<String>(
              value: 'admin',
              groupValue: currentRole,
              title: const Text('Admin'),
              subtitle: const Text('Full access — same as your own account'),
              onChanged: (v) => Navigator.pop(context, v),
            ),
            RadioListTile<String>(
              value: 'revoked',
              groupValue: currentRole,
              title: const Text('No access'),
              subtitle: const Text('Waiting for approval, or access removed'),
              onChanged: (v) => Navigator.pop(context, v),
            ),
          ],
        ),
      ),
    );
    if (newRole != null && newRole != currentRole) {
      await _db.setUserRole(user['id'] as String, newRole);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      appBar: AppBar(title: const Text('Manage Users')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _usersStream.get(0, () => _db.watchUserRoles()),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final users = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(14),
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'New sign-ups can\'t see anything until you approve them here. Owner accounts '
                  'are listed in Firebase under "admins" and always have full access.',
                  style: TextStyle(fontSize: 12, height: 1.4),
                ),
              ),
              if (users.isEmpty)
                const EmptyState(
                  icon: Icons.people_outline,
                  title: 'No accounts yet',
                  message: 'Accounts created via Sign Up will appear here.',
                )
              else
                for (final u in users)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppCard(
                      padding: const EdgeInsets.all(14),
                      onTap: () => _changeRole(u),
                      child: Row(
                        children: [
                          IconBadge(
                            icon: (u['role'] == 'admin') ? Icons.shield_outlined : Icons.visibility_outlined,
                            color: (u['role'] == 'admin') ? AppTheme.danger : AppTheme.accent,
                            size: 20,
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(u['email'] as String? ?? '(no email)',
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                const SizedBox(height: 2),
                                Text(
                                  u['approved'] != true
                                      ? 'Waiting for approval — tap to allow'
                                      : (u['role'] == 'admin' ? 'Admin — full access' : 'View Only'),
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: Colors.black38),
                        ],
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}
