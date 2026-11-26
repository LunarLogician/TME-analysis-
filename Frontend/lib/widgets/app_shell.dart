import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';

class AppShell extends ConsumerWidget {
  final Widget child;
  final String location;

  const AppShell({
    super.key,
    required this.child,
    required this.location,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(userRoleProvider);
    final destinations = role == 'admin'
        ? const [
            _Destination('Overview', Icons.dashboard_outlined, '/dashboard'),
            _Destination(
                'Users', Icons.manage_accounts_outlined, '/admin/users'),
            _Destination('Analytics', Icons.insights_outlined, '/analytics'),
            _Destination('Profile', Icons.person_outline, '/profile'),
          ]
        : role == 'patient'
            ? const [
                _Destination('My record', Icons.home_outlined, '/dashboard'),
                _Destination('Reports', Icons.description_outlined, '/reports'),
                _Destination('Profile', Icons.person_outline, '/profile'),
              ]
            : const [
                _Destination('Home', Icons.home_outlined, '/dashboard'),
                _Destination('Patients', Icons.people_outline, '/patients'),
                _Destination('New biopsy', Icons.biotech_outlined, '/upload'),
                _Destination('Reports', Icons.description_outlined, '/reports'),
                _Destination('Profile', Icons.person_outline, '/profile'),
              ];

    var selectedIndex = destinations.indexWhere(
      (item) => location == item.path || location.startsWith('${item.path}/'),
    );
    if (selectedIndex < 0) selectedIndex = 0;

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) => context.go(destinations[index].path),
        destinations: destinations
            .map((item) => NavigationDestination(
                  icon: Icon(item.icon),
                  selectedIcon: Icon(item.icon, color: const Color(0xFF6C5CE7)),
                  label: item.label,
                ))
            .toList(),
      ),
    );
  }
}

class _Destination {
  final String label;
  final IconData icon;
  final String path;

  const _Destination(this.label, this.icon, this.path);
}
