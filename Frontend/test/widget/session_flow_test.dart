import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tme_insight/models/analysis_v2.dart';
import 'package:tme_insight/providers/session_provider.dart';
import 'package:tme_insight/screens/session_analysis_screen.dart';
import 'package:tme_insight/screens/session_results_screen.dart';

void main() {
  testWidgets('session history opens the current analysis screen',
      (tester) async {
    const sessionId = 'session-1';
    const analysisRunId = 'run-1';
    const pending = AnalysisV2({
      'analysis_run_id': analysisRunId,
      'session_id': sessionId,
      'status': 'RUNNING',
      'stage': 'TILING',
      'progress': 0.25,
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          latestV2AnalysisForSessionProvider(sessionId)
              .overrideWith((ref) => pending),
          v2AnalysisProvider(analysisRunId)
              .overrideWith((ref) => Stream.value(pending)),
        ],
        child: const MaterialApp(
          home: SessionAnalysisScreen(sessionId: sessionId),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('TME-Insight Review'), findsOneWidget);
    expect(find.text('Tiling'), findsOneWidget);
  });

  testWidgets('legacy results screen opens the supported analysis workflow',
      (tester) async {
    const sessionId = 'legacy-session';
    const analysisRunId = 'current-run';
    const pending = AnalysisV2({
      'analysis_run_id': analysisRunId,
      'session_id': sessionId,
      'status': 'RUNNING',
      'stage': 'TILING',
      'progress': 0.25,
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          latestV2AnalysisForSessionProvider(sessionId)
              .overrideWith((ref) => pending),
          v2AnalysisProvider(analysisRunId)
              .overrideWith((ref) => Stream.value(pending)),
        ],
        child: const MaterialApp(
          home: SessionResultsScreen(sessionId: sessionId),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('TME-Insight Review'), findsOneWidget);
    expect(find.text('Tiling'), findsOneWidget);
  });
}
