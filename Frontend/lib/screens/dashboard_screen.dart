import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../providers/dashboard_provider.dart';
import 'admin_dashboard_screen.dart';
import 'patient_dashboard_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(userRoleProvider);
    if (role == 'admin') return const AdminDashboardScreen();
    if (role == 'patient') return const PatientDashboardScreen();

    final user = ref.watch(currentUserProvider);
    final dashboard = ref.watch(dashboardProvider);
    final name = user?.userMetadata?['full_name'] ?? 'Clinician';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clinical Workspace'),
        actions: [
          IconButton(
            tooltip: 'Refresh dashboard',
            onPressed: () => ref.invalidate(dashboardProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: dashboard.when(
        data: (data) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(dashboardProvider);
            await ref.read(dashboardProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('Welcome, $name',
                  style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(_todayLabel(),
                  style: const TextStyle(color: Colors.white60)),
              const SizedBox(height: 24),
              GridView.count(
                crossAxisCount: MediaQuery.sizeOf(context).width > 700 ? 3 : 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.5,
                children: [
                  _SummaryCard(
                    title: 'Total Patients',
                    value: data.totalPatients.toString(),
                    icon: Icons.people_outline,
                    color: const Color(0xFF6C5CE7),
                    onTap: () => context.go('/patients'),
                  ),
                  _SummaryCard(
                    title: 'Completed Sessions',
                    value: data.completedSessions.toString(),
                    icon: Icons.task_alt,
                    color: const Color(0xFF00CEC9),
                    onTap: () => context.go('/reports'),
                  ),
                  _SummaryCard(
                    title: 'Processing',
                    value: data.processingSessions.toString(),
                    icon: Icons.hourglass_top,
                    color: const Color(0xFFFDCB6E),
                    onTap: () => context.go('/patients'),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              const Text('Quick Actions',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _ActionButton(
                    title: 'Add New Patient',
                    icon: Icons.person_add_alt_1,
                    onTap: () => context.push('/add-patient'),
                  ),
                  _ActionButton(
                    title: 'Start New Biopsy',
                    icon: Icons.biotech_outlined,
                    onTap: () => context.go('/upload'),
                  ),
                  _ActionButton(
                    title: 'View Patient List',
                    icon: Icons.format_list_bulleted,
                    onTap: () => context.go('/patients'),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Recent Activity',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  TextButton(
                    onPressed: () => context.go('/reports'),
                    child: const Text('View all'),
                  ),
                ],
              ),
              if (data.activities.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(22),
                    child: Text('No biopsy activity yet.'),
                  ),
                )
              else
                ...data.activities.take(3).map(
                      (activity) => Card(
                        child: ListTile(
                          leading: Icon(
                            activity.session.isComplete
                                ? Icons.check_circle_outline
                                : activity.session.isFailed
                                    ? Icons.error_outline
                                    : Icons.hourglass_top,
                            color: activity.session.isComplete
                                ? const Color(0xFF00CEC9)
                                : activity.session.isFailed
                                    ? const Color(0xFFFF7675)
                                    : const Color(0xFFFDCB6E),
                          ),
                          title: Text(activity.patient.fullName),
                          subtitle: Text(
                            '${activity.session.sessionDate.toLocal().toString().split(' ')[0]} • '
                            '${activity.session.status.toUpperCase()}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () =>
                              context.push('/sessions/${activity.session.id}'),
                        ),
                      ),
                    ),
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: FilledButton.icon(
            onPressed: () => ref.invalidate(dashboardProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry dashboard'),
          ),
        ),
      ),
    );
  }

  static String _todayLabel() {
    final now = DateTime.now();
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return '${months[now.month - 1]} ${now.day}, ${now.year} • Patient care overview';
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color),
                const Spacer(),
                Text(value,
                    style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.bold)),
                Text(title, style: const TextStyle(color: Colors.white60)),
              ],
            ),
          ),
        ),
      );
}

class _ActionButton extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  const _ActionButton(
      {required this.title, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => ActionChip(
        avatar: Icon(icon, size: 20),
        label: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(title),
        ),
        onPressed: onTap,
      );
}
