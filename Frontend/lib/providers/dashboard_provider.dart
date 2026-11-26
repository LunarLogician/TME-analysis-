import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_user.dart';
import '../models/analysis_v2.dart';
import '../models/dashboard_data.dart';
import '../models/patient.dart';
import '../models/session.dart';
import 'patient_provider.dart';

final dashboardProvider = FutureProvider<DashboardData>((ref) async {
  final api = ref.watch(apiServiceProvider);
  final patientJson = await api.getPatients();
  final patients = patientJson.map(Patient.fromJson).toList();
  final activities = <SessionActivity>[];

  final sessionGroups = await Future.wait(
    patients.map((patient) async {
      try {
        final data = await api.getPatientSessions(patient.id);
        return data
            .map(Session.fromJson)
            .map((session) =>
                SessionActivity(session: session, patient: patient))
            .toList();
      } catch (_) {
        return <SessionActivity>[];
      }
    }),
  );
  for (final group in sessionGroups) {
    activities.addAll(group);
  }
  activities
      .sort((a, b) => b.session.sessionDate.compareTo(a.session.sessionDate));
  return DashboardData(patients: patients, activities: activities);
});

final patientTrendProvider =
    FutureProvider.family<List<TrendPoint>, String>((ref, patientId) async {
  final api = ref.watch(apiServiceProvider);
  final sessions = (await api.getPatientSessions(patientId))
      .map(Session.fromJson)
      .where((session) => session.isComplete)
      .toList();
  final points = <TrendPoint>[];
  for (final session in sessions) {
    try {
      final result = AnalysisV2(
        await api.getLatestV2AnalysisForSession(session.id),
      );
      if (!result.isComplete) continue;
      final score = (result.tme['score'] as num?)?.toDouble();
      if (score == null) continue;
      points.add(TrendPoint(
        date: session.sessionDate,
        score: score,
        phenotype: result.tmeState,
      ));
    } catch (_) {
      // Historical sessions without persisted metrics are omitted from trends.
    }
  }
  points.sort((a, b) => a.date.compareTo(b.date));
  return points;
});

final adminUsersProvider = FutureProvider<List<AppUser>>((ref) async {
  final api = ref.watch(apiServiceProvider);
  final users = await api.getAdminUsers();
  return users.map(AppUser.fromJson).toList();
});
