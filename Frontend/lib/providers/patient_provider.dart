import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/patient.dart';
import '../models/session.dart';
import '../services/api_service.dart';

final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService();
});

// Fetches the list of patients for the authenticated clinician
final patientListProvider = FutureProvider<List<Patient>>((ref) async {
  final apiService = ref.watch(apiServiceProvider);
  final data = await apiService.getPatients();
  return data.map((json) => Patient.fromJson(json)).toList();
});

// Fetches detailed information for a specific patient
final patientDetailProvider =
    FutureProvider.family<Patient, String>((ref, patientId) async {
  final apiService = ref.watch(apiServiceProvider);
  final data = await apiService.getPatient(patientId);
  return Patient.fromJson(data);
});

// Fetches all sessions for a specific patient
final patientSessionsProvider =
    FutureProvider.family<List<Session>, String>((ref, patientId) async {
  final apiService = ref.watch(apiServiceProvider);
  final data = await apiService.getPatientSessions(patientId);
  return data.map((json) => Session.fromJson(json)).toList();
});

// A StateNotifier for patient creation to handle loading/success/error states
class PatientNotifier extends StateNotifier<AsyncValue<void>> {
  final Ref ref;

  PatientNotifier(this.ref) : super(const AsyncData(null));

  Future<bool> createPatient({
    required String fullName,
    required String dateOfBirth,
    required String gender,
    required String diagnosis,
  }) async {
    state = const AsyncLoading();
    try {
      final apiService = ref.read(apiServiceProvider);
      await apiService.createPatient(
        fullName: fullName,
        dateOfBirth: dateOfBirth,
        gender: gender,
        diagnosis: diagnosis,
      );

      // Invalidate the patient list so it refreshes on the dashboard
      ref.invalidate(patientListProvider);

      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }
}

final patientNotifierProvider =
    StateNotifierProvider<PatientNotifier, AsyncValue<void>>((ref) {
  return PatientNotifier(ref);
});
