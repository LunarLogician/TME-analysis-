import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import '../providers/patient_provider.dart';
import '../providers/dashboard_provider.dart';
import '../models/dashboard_data.dart';

class PatientDetailScreen extends ConsumerWidget {
  final String patientId;

  const PatientDetailScreen({super.key, required this.patientId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patientAsync = ref.watch(patientDetailProvider(patientId));
    final sessionsAsync = ref.watch(patientSessionsProvider(patientId));
    final trendAsync = ref.watch(patientTrendProvider(patientId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              // ignore: unused_result
              ref.refresh(patientDetailProvider(patientId));
              // ignore: unused_result
              ref.refresh(patientSessionsProvider(patientId));
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        // Patient detail is hosted by the root navigator while upload lives
        // inside ShellRoute. Pushing across that boundary duplicates the shell
        // page key; replace the location instead.
        onPressed: () => context.go('/upload', extra: patientId),
        backgroundColor: const Color(0xFF6C5CE7),
        icon: const Icon(Icons.add_a_photo, color: Colors.white),
        label: const Text('New Biopsy', style: TextStyle(color: Colors.white)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Patient Info Card
              patientAsync.when(
                data: (patient) => Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                      color: const Color(0xFF2D3436),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.05),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ]),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundColor:
                                const Color(0xFF6C5CE7).withValues(alpha: 0.2),
                            child: Icon(
                              patient.gender.toLowerCase() == 'female'
                                  ? Icons.female
                                  : Icons.male,
                              color: const Color(0xFF6C5CE7),
                              size: 32,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  patient.fullName,
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'DOB: ${patient.dateOfBirth.split('T')[0]}',
                                  style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.6)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Diagnosis',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF00CEC9),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        patient.diagnosis,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: CircularProgressIndicator(color: Color(0xFF6C5CE7)),
                  ),
                ),
                error: (error, _) => Text(
                  'Error loading patient: $error',
                  style: const TextStyle(color: Color(0xFFFF7675)),
                ),
              ),

              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'TME Trend',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () =>
                        ref.invalidate(patientTrendProvider(patientId)),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Refresh'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              trendAsync.when(
                data: (points) => _TrendCard(points: points),
                loading: () => const SizedBox(
                  height: 180,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('Trend metrics are not available yet.'),
                  ),
                ),
              ),

              const SizedBox(height: 32),
              const Text(
                'Biopsy Sessions',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),

              // Sessions List
              sessionsAsync.when(
                data: (sessions) {
                  if (sessions.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(32),
                      alignment: Alignment.center,
                      child: Text(
                        'No biopsy sessions found.\nClick "New Biopsy" to start.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: sessions.length,
                    itemBuilder: (context, index) {
                      final session = sessions[index];
                      final bool isCompleted = session.isComplete ||
                          session.status.toLowerCase() == 'completed';

                      return Card(
                        color: const Color(0xFF2D3436),
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.05),
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isCompleted
                                  ? const Color(0xFF00CEC9)
                                      .withValues(alpha: 0.2)
                                  : const Color(0xFFFDCB6E)
                                      .withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isCompleted
                                  ? Icons.check_circle
                                  : Icons.hourglass_top,
                              color: isCompleted
                                  ? const Color(0xFF00CEC9)
                                  : const Color(0xFFFDCB6E),
                            ),
                          ),
                          title: Text(
                            'Session on ${session.sessionDate.toLocal().toString().split(' ')[0]}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            'Status: ${session.status.toUpperCase()}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 12,
                            ),
                          ),
                          trailing: Text(
                            isCompleted ? 'View report' : 'View',
                            style: const TextStyle(color: Color(0xFF00CEC9)),
                          ),
                          onTap: () {
                            if (isCompleted || session.isFailed) {
                              context.push('/sessions/${session.id}');
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content:
                                        Text('Session is still processing.')),
                              );
                            }
                          },
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: CircularProgressIndicator(color: Color(0xFF00CEC9)),
                  ),
                ),
                error: (error, _) => Text(
                  'Error loading sessions: $error',
                  style: const TextStyle(color: Color(0xFFFF7675)),
                ),
              ),
              const SizedBox(height: 60), // Padding for FAB
            ],
          ),
        ),
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  final List<TrendPoint> points;
  const _TrendCard({required this.points});

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Complete at least one biopsy analysis to begin the longitudinal trend.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 20, 14),
        child: SizedBox(
          height: 210,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: 1,
              minX: 0,
              maxX: points.length == 1 ? 1 : (points.length - 1).toDouble(),
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) =>
                    const FlLine(color: Colors.white12, strokeWidth: 1),
              ),
              titlesData: FlTitlesData(
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(
                      showTitles: true, reservedSize: 34, interval: .25),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 34,
                    interval: 1,
                    getTitlesWidget: (value, _) {
                      final index = value.toInt();
                      if (index < 0 || index >= points.length) {
                        return const SizedBox.shrink();
                      }
                      final date = points[index].date;
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                            '${date.month}/${date.year.toString().substring(2)}',
                            style: const TextStyle(fontSize: 10)),
                      );
                    },
                  ),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: [
                    for (var i = 0; i < points.length; i++)
                      FlSpot(
                          i.toDouble(), points[i].score.clamp(0, 1).toDouble()),
                  ],
                  isCurved: true,
                  color: const Color(0xFF6C5CE7),
                  barWidth: 3,
                  belowBarData: BarAreaData(
                    show: true,
                    color: const Color(0xFF6C5CE7).withValues(alpha: .14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
