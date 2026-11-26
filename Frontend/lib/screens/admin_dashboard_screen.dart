import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/analytics_provider.dart';
import '../providers/dashboard_provider.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analytics = ref.watch(analyticsProvider);
    final users = ref.watch(adminUsersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Administration Overview'),
        actions: [
          IconButton(
            tooltip: 'Refresh platform data',
            onPressed: () {
              ref.invalidate(analyticsProvider);
              ref.invalidate(adminUsersProvider);
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(analyticsProvider);
          ref.invalidate(adminUsersProvider);
          await ref.read(analyticsProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Platform control centre',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 6),
            const Text(
              'Monitor clinical operations without becoming the owner of patient care.',
              style: TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 24),
            analytics.when(
              data: (data) => GridView.count(
                crossAxisCount: MediaQuery.sizeOf(context).width > 720 ? 4 : 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.45,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                children: [
                  _AdminMetric('Sessions', data.totalSessions.toString(),
                      Icons.biotech, const Color(0xFF6C5CE7)),
                  _AdminMetric('Clinicians', data.activeClinicians.toString(),
                      Icons.medical_services, const Color(0xFF00CEC9)),
                  _AdminMetric(
                      'Hot TME',
                      data.phenotypeDistribution.hotCount.toString(),
                      Icons.local_fire_department,
                      const Color(0xFFFF7675)),
                  _AdminMetric(
                      'Cold TME',
                      data.phenotypeDistribution.coldCount.toString(),
                      Icons.ac_unit,
                      const Color(0xFF74B9FF)),
                ],
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const _AdminError('Analytics are unavailable'),
            ),
            const SizedBox(height: 24),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.manage_accounts_outlined,
                        color: Color(0xFF6C5CE7)),
                    title: const Text('User directory'),
                    subtitle: Text(users.when(
                      data: (items) => '${items.length} registered accounts',
                      loading: () => 'Loading accounts…',
                      error: (_, __) => 'Directory unavailable',
                    )),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.go('/admin/users'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.insights_outlined,
                        color: Color(0xFF00CEC9)),
                    title: const Text('Platform analytics'),
                    subtitle:
                        const Text('Phenotypes and monthly processing volume'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.go('/analytics'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Card(
              child: ListTile(
                leading: Icon(Icons.health_and_safety_outlined,
                    color: Color(0xFF00CEC9)),
                title: Text('Operational boundary'),
                subtitle: Text(
                  'Administrators supervise users and system-wide activity. '
                  'Clinical decisions and patient records remain the responsibility of assigned clinicians.',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminMetric extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  const _AdminMetric(this.title, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value,
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold)),
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white60)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _AdminError extends StatelessWidget {
  final String message;
  const _AdminError(this.message);
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child:
              Text(message, style: const TextStyle(color: Color(0xFFFF7675))),
        ),
      );
}
