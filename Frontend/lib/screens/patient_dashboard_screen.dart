import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/dashboard_provider.dart';

class PatientDashboardScreen extends ConsumerWidget {
  const PatientDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dashboardProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('My Clinical Record')),
      body: data.when(
        data: (dashboard) {
          if (dashboard.patients.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Your account has not been linked to a patient record. '
                  'Please contact your clinician.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final patient = dashboard.patients.first;
          final sessions = dashboard.activities
              .where((item) => item.patient.id == patient.id)
              .toList();
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(patient.fullName,
                          style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 8),
                      Text(
                          'Date of birth: ${patient.dateOfBirth.split('T')[0]}'),
                      Text('Diagnosis: ${patient.diagnosis}'),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () =>
                            context.push('/patients/${patient.id}'),
                        icon: const Icon(Icons.folder_shared_outlined),
                        label: const Text('Open complete record'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text('Biopsy history',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              if (sessions.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No biopsy sessions are available yet.'),
                  ),
                )
              else
                ...sessions.take(5).map(
                      (item) => Card(
                        child: ListTile(
                          leading: Icon(
                            item.session.isComplete
                                ? Icons.check_circle_outline
                                : Icons.hourglass_top,
                            color: item.session.isComplete
                                ? const Color(0xFF00CEC9)
                                : const Color(0xFFFDCB6E),
                          ),
                          title: Text(item.session.sessionDate
                              .toLocal()
                              .toString()
                              .split(' ')[0]),
                          subtitle: Text(item.session.status.toUpperCase()),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: item.session.isComplete
                              ? () =>
                                  context.push('/sessions/${item.session.id}')
                              : null,
                        ),
                      ),
                    ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: FilledButton(
            onPressed: () => ref.invalidate(dashboardProvider),
            child: const Text('Retry loading my record'),
          ),
        ),
      ),
    );
  }
}
