import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/session.dart';
import '../models/analysis_v2.dart';
import 'patient_provider.dart';

// Fetches a single session by ID
final sessionDetailProvider =
    FutureProvider.family<Session, String>((ref, sessionId) async {
  final apiService = ref.watch(apiServiceProvider);
  final data = await apiService.getSession(sessionId);
  return Session.fromJson(data);
});

final latestV2AnalysisForSessionProvider =
    FutureProvider.family<AnalysisV2, String>((ref, sessionId) async {
  final data = await ref
      .watch(apiServiceProvider)
      .getLatestV2AnalysisForSession(sessionId);
  return AnalysisV2(data);
});

final v2AnalysisProvider =
    StreamProvider.family<AnalysisV2, String>((ref, analysisRunId) async* {
  final apiService = ref.watch(apiServiceProvider);
  for (var attempt = 0; attempt < 1200; attempt++) {
    final analysis = AnalysisV2(await apiService.getV2Analysis(analysisRunId));
    yield analysis;
    if (analysis.isComplete) return;
    if (analysis.isFailed) {
      throw StateError(
        analysis.failureMessage ?? 'TME-Insight analysis failed.',
      );
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  throw TimeoutException(
    'TME-Insight analysis is taking longer than expected.',
  );
});

final v2CellsProvider =
    FutureProvider.family<List<CellInstanceV2>, String>((ref, analysisRunId) {
  return ref.watch(apiServiceProvider).getV2Cells(analysisRunId);
});

final v2OverlayProvider =
    FutureProvider.family<List<int>, String>((ref, analysisRunId) {
  return ref.watch(apiServiceProvider).getV2Overlay(analysisRunId);
});

// Session Actions Controller
class SessionNotifier extends StateNotifier<AsyncValue<void>> {
  final Ref ref;

  SessionNotifier(this.ref) : super(const AsyncData(null));

  Future<AnalysisLaunch?> uploadAndAnalyzeV2({
    required String patientId,
    required List<int> bytes,
    required String filename,
    String analysisMode = 'NUCLEI_ONLY',
    double? mpp,
  }) async {
    state = const AsyncLoading();
    try {
      final apiService = ref.read(apiServiceProvider);
      final sessionData = await apiService.createSession(
        patientId: patientId,
        imageUrl: filename,
      );
      final launch = await apiService.startV2Analysis(
        sessionId: sessionData['id'] as String,
        bytes: bytes,
        filename: filename,
        analysisMode: analysisMode,
        mpp: mpp,
      );
      ref.invalidate(patientSessionsProvider(patientId));
      ref.invalidate(sessionDetailProvider(launch.sessionId));
      ref.invalidate(v2AnalysisProvider(launch.analysisRunId));
      state = const AsyncData(null);
      return launch;
    } catch (e, st) {
      state = AsyncError(e, st);
      return null;
    }
  }

  Future<bool> updateV2TumorContext({
    required String analysisRunId,
    required String status,
    String regionMode = 'WHOLE_ROI',
    List<List<double>>? tumorPolygonPx,
  }) async {
    state = const AsyncLoading();
    try {
      await ref.read(apiServiceProvider).updateV2TumorContext(
            analysisRunId: analysisRunId,
            status: status,
            regionMode: regionMode,
            tumorPolygonPx: tumorPolygonPx,
          );
      ref.invalidate(v2AnalysisProvider(analysisRunId));
      ref.invalidate(v2CellsProvider(analysisRunId));
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  Future<bool> retryV2Analysis(String analysisRunId) async {
    state = const AsyncLoading();
    try {
      await ref.read(apiServiceProvider).retryV2Analysis(analysisRunId);
      ref.invalidate(v2AnalysisProvider(analysisRunId));
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }
}

final sessionNotifierProvider =
    StateNotifierProvider<SessionNotifier, AsyncValue<void>>((ref) {
  return SessionNotifier(ref);
});
