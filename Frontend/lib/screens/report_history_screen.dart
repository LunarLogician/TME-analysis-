import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/dashboard_data.dart';
import '../providers/dashboard_provider.dart';

class ReportHistoryScreen extends ConsumerWidget {
  const ReportHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(dashboardProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clinical Report History'),
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(dashboardProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: dashboard.when(
        data: (data) {
          final completed = data.activities
              .where((activity) => activity.session.isComplete)
              .toList();
          if (completed.isEmpty) {
            return const _ReportsEmptyState();
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(dashboardProvider);
              await ref.read(dashboardProvider.future);
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: completed.length,
              itemBuilder: (_, index) => _ReportHistoryCard(
                activity: completed[index],
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: FilledButton.icon(
            onPressed: () => ref.invalidate(dashboardProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry report history'),
          ),
        ),
      ),
    );
  }
}

class _ReportHistoryCard extends StatelessWidget {
  final SessionActivity activity;
  const _ReportHistoryCard({required this.activity});

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.description_outlined,
                      color: Color(0xFF6C5CE7)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(activity.patient.fullName,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                  ),
                  const Chip(label: Text('COMPLETE')),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Biopsy date: ${activity.session.sessionDate.toLocal().toString().split(' ')[0]}',
                style: const TextStyle(color: Colors.white60),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () =>
                      context.push('/sessions/${activity.session.id}'),
                  icon: const Icon(Icons.analytics_outlined),
                  label: const Text('Open analysis'),
                ),
              ),
            ],
          ),
        ),
      );
}

class _ReportsEmptyState extends StatelessWidget {
  const _ReportsEmptyState();
  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.description_outlined, size: 64, color: Colors.white38),
              SizedBox(height: 12),
              Text('No completed biopsy reports yet'),
            ],
          ),
        ),
      );
}
