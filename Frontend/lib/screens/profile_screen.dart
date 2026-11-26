import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final role = ref.watch(userRoleProvider);
    final name = user?.userMetadata?['full_name']?.toString().trim();
    final displayName =
        name == null || name.isEmpty ? 'TME-Insight user' : name;
    final initials = displayName
        .split(RegExp(r'\s+'))
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();

    return Scaffold(
      appBar: AppBar(title: const Text('Profile & Security')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: CircleAvatar(
              radius: 44,
              backgroundColor: const Color(0xFF6C5CE7),
              child: Text(initials,
                  style: const TextStyle(fontSize: 28, color: Colors.white)),
            ),
          ),
          const SizedBox(height: 16),
          Text(displayName,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(user?.email ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60)),
          const SizedBox(height: 12),
          Center(child: _RoleChip(role: role)),
          const SizedBox(height: 32),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.verified_user_outlined),
                  title: const Text('Account role'),
                  subtitle: Text(_roleDescription(role)),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.lock_clock_outlined),
                  title: const Text('Session security'),
                  subtitle: Text(user?.lastSignInAt == null
                      ? 'Authenticated with Supabase'
                      : 'Last sign-in: ${_formatDate(user!.lastSignInAt!)}'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => _confirmLogout(context, ref),
            icon: const Icon(Icons.logout, color: Color(0xFFFF7675)),
            label: const Text('Sign out',
                style: TextStyle(color: Color(0xFFFF7675))),
          ),
        ],
      ),
    );
  }

  static String _formatDate(String value) {
    final parsed = DateTime.tryParse(value)?.toLocal();
    return parsed == null ? value : parsed.toString().split('.')[0];
  }

  static String _roleDescription(String role) {
    if (role == 'admin') {
      return 'Platform oversight, analytics, and user management';
    }
    if (role == 'patient') return 'Read-only access to your record and reports';
    return 'Patient care, biopsy analysis, and clinical reporting';
  }

  static Future<void> _confirmLogout(
      BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content:
            const Text('Your current session will be closed on this device.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Sign out')),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }
}

class _RoleChip extends StatelessWidget {
  final String role;
  const _RoleChip({required this.role});

  @override
  Widget build(BuildContext context) => Chip(
        avatar: Icon(
          role == 'admin' ? Icons.admin_panel_settings : Icons.badge_outlined,
          size: 18,
        ),
        label: Text(role.toUpperCase()),
      );
}
