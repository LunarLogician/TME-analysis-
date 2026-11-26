import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_user.dart';
import '../providers/dashboard_provider.dart';

class UserManagementScreen extends ConsumerStatefulWidget {
  const UserManagementScreen({super.key});

  @override
  ConsumerState<UserManagementScreen> createState() =>
      _UserManagementScreenState();
}

class _UserManagementScreenState extends ConsumerState<UserManagementScreen> {
  String _query = '';
  String _role = 'all';

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(adminUsersProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Directory'),
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(adminUsersProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
              decoration: const InputDecoration(
                hintText: 'Search name or email',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              children: ['all', 'clinician', 'admin', 'patient']
                  .map((role) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(role == 'all' ? 'All roles' : role),
                          selected: _role == role,
                          onSelected: (_) => setState(() => _role = role),
                        ),
                      ))
                  .toList(),
            ),
          ),
          Expanded(
            child: users.when(
              data: (items) {
                final filtered = items.where((user) {
                  final matchesRole = _role == 'all' || user.role == _role;
                  final matchesQuery = _query.isEmpty ||
                      user.fullName.toLowerCase().contains(_query) ||
                      user.email.toLowerCase().contains(_query);
                  return matchesRole && matchesQuery;
                }).toList();
                if (filtered.isEmpty) {
                  return const Center(child: Text('No matching accounts'));
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(adminUsersProvider);
                    await ref.read(adminUsersProvider.future);
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    itemBuilder: (_, index) => _UserCard(user: filtered[index]),
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: Color(0xFFFF7675)),
                    const SizedBox(height: 8),
                    const Text('Could not load the user directory'),
                    TextButton(
                      onPressed: () => ref.invalidate(adminUsersProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final AppUser user;
  const _UserCard({required this.user});

  @override
  Widget build(BuildContext context) {
    final color = user.role == 'admin'
        ? const Color(0xFFFF7675)
        : user.role == 'patient'
            ? const Color(0xFF74B9FF)
            : const Color(0xFF00CEC9);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: .16),
          child: Icon(Icons.person_outline, color: color),
        ),
        title: Text(user.fullName),
        subtitle: Text(
            '${user.email}\nJoined ${user.createdAt.toLocal().toString().split(' ')[0]}'),
        isThreeLine: true,
        trailing: Chip(label: Text(user.role.toUpperCase())),
      ),
    );
  }
}
