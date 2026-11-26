import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/patient.dart';
import '../providers/patient_provider.dart';

class PatientListScreen extends ConsumerStatefulWidget {
  const PatientListScreen({super.key});

  @override
  ConsumerState<PatientListScreen> createState() => _PatientListScreenState();
}

class _PatientListScreenState extends ConsumerState<PatientListScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final patientsAsync = ref.watch(patientListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Patient Roster')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              key: const Key('patient-search'),
              onChanged: (value) =>
                  setState(() => _query = value.toLowerCase().trim()),
              decoration: const InputDecoration(
                hintText: 'Search by patient name or diagnosis',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: patientsAsync.when(
              data: (patients) {
                final filtered = patients.where((patient) {
                  return _query.isEmpty ||
                      patient.fullName.toLowerCase().contains(_query) ||
                      patient.diagnosis.toLowerCase().contains(_query);
                }).toList();
                if (patients.isEmpty) return const _PatientEmptyState();
                if (filtered.isEmpty) {
                  return const Center(
                      child: Text('No patients match your search'));
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(patientListProvider);
                    await ref.read(patientListProvider.future);
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    itemBuilder: (_, index) =>
                        _PatientCard(patient: filtered[index]),
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => _PatientLoadError(
                onRetry: () => ref.invalidate(patientListProvider),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/add-patient'),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add Patient'),
      ),
    );
  }
}

class _PatientCard extends StatelessWidget {
  final Patient patient;
  const _PatientCard({required this.patient});

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: ListTile(
          contentPadding: const EdgeInsets.all(16),
          leading: CircleAvatar(
            backgroundColor: const Color(0xFF6C5CE7).withValues(alpha: .18),
            child: Icon(
              patient.gender.toLowerCase() == 'female'
                  ? Icons.female
                  : Icons.male,
              color: const Color(0xFF6C5CE7),
            ),
          ),
          title: Text(patient.fullName,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Diagnosis: ${patient.diagnosis}'),
                const SizedBox(height: 3),
                Text('DOB: ${patient.dateOfBirth.split('T')[0]}'),
              ],
            ),
          ),
          isThreeLine: true,
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/patients/${patient.id}'),
        ),
      );
}

class _PatientEmptyState extends StatelessWidget {
  const _PatientEmptyState();
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.people_outline, size: 60, color: Colors.white38),
            const SizedBox(height: 12),
            const Text('No patients found'),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => context.push('/add-patient'),
              child: const Text('Create first patient'),
            ),
          ],
        ),
      );
}

class _PatientLoadError extends StatelessWidget {
  final VoidCallback onRetry;
  const _PatientLoadError({required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFFF7675), size: 44),
            const SizedBox(height: 10),
            const Text('Failed to load patients'),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
}
