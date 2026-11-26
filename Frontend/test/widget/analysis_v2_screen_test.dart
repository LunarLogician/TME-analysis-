import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tme_insight/models/analysis_v2.dart';
import 'package:tme_insight/providers/session_provider.dart';
import 'package:tme_insight/screens/analysis_v2_screen.dart';

const _runId = 'run-1';

const _analysis = AnalysisV2({
  'analysis_run_id': _runId,
  'session_id': 'session-1',
  'status': 'COMPLETE',
  'stage': 'COMPLETE',
  'progress': 1.0,
  'image_metadata': {
    'scale_trusted': false,
    'scale_source': 'UNKNOWN',
    'width_px': 256,
    'height_px': 256,
  },
  'quality': {
    'status': 'WARNING',
    'tissue_fraction': 0.5,
    'warnings': ['PHYSICAL_SCALE_UNKNOWN'],
  },
  'cell_counts': {
    'NEOPLASTIC': 2,
    'INFLAMMATORY': 1,
    'CONNECTIVE': 0,
    'DEAD': 0,
    'EPITHELIAL': 0,
  },
  'accepted_cell_counts': {
    'NEOPLASTIC': 1,
    'INFLAMMATORY': 1,
    'CONNECTIVE': 0,
    'DEAD': 0,
    'EPITHELIAL': 0,
  },
  'uncertain_cell_counts': {
    'NEOPLASTIC': 1,
    'INFLAMMATORY': 0,
    'CONNECTIVE': 0,
    'DEAD': 0,
    'EPITHELIAL': 0,
  },
  'tumor_assessment': {
    'status': 'INDETERMINATE',
    'evidence_source': 'UNCONFIRMED_NUCLEI_ONLY',
    'tumor_region_mode': 'NONE',
  },
  'spatial_measurements': null,
  'tme_assessment': {
    'state': 'NOT_ASSESSABLE',
    'reason_codes': ['PHYSICAL_SCALE_UNKNOWN'],
    'policy_version': 'TMEPolicyV1',
  },
});

final _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

void main() {
  testWidgets('provides focused interactive review sections on desktop',
      (tester) async {
    await _pumpAnalysis(tester, const Size(1400, 920));

    expect(find.text('Analysis workspace'), findsOneWidget);
    expect(find.text('Review at a glance'), findsOneWidget);
    expect(find.text('Detected nuclei'), findsOneWidget);
    expect(find.text('Scale unavailable'), findsOneWidget);
    expect(find.text('Cell distribution'), findsOneWidget);

    await tester.tap(find.byKey(const Key('analysis-nav-nuclei')));
    await tester.pumpAndSettle();
    expect(find.text('Nuclei explorer'), findsOneWidget);
    expect(find.text('Nuclei overlay'), findsOneWidget);
    expect(find.text('Cell explorer'), findsOneWidget);
    expect(find.byKey(const Key('nuclei-class-filter')), findsOneWidget);
    expect(find.byKey(const Key('nuclei-acceptance-filter')), findsOneWidget);

    await tester.tap(find.byKey(const Key('analysis-nav-tumor')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tumor-context-dropdown')), findsOneWidget);
    expect(find.text('Draw/confirm tumor region'), findsOneWidget);
    expect(find.text('Stored cells are reused'), findsOneWidget);

    await tester.tap(find.byKey(const Key('analysis-nav-tme')));
    await tester.pumpAndSettle();
    expect(find.text('Not Assessable'), findsWidgets);
    expect(
      find.text('A physical TME category was not calculated'),
      findsOneWidget,
    );
    expect(find.text('Physical measurements unavailable'), findsOneWidget);

    await tester.tap(find.byKey(const Key('analysis-nav-report')));
    await tester.pumpAndSettle();
    expect(find.text('Structured report'), findsOneWidget);
    expect(find.text('Generate structured PDF'), findsOneWidget);
    expect(find.text('Deterministic clinical facts'), findsOneWidget);
  });

  testWidgets('uses a section dropdown on compact layouts', (tester) async {
    await _pumpAnalysis(tester, const Size(390, 820));

    final dropdown = find.byKey(const Key('analysis-section-dropdown'));
    expect(dropdown, findsOneWidget);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report').last);
    await tester.pumpAndSettle();

    expect(find.text('Structured report'), findsOneWidget);
    expect(find.byKey(const Key('generate-report')), findsOneWidget);
  });

  testWidgets('keeps scroll and expansion state isolated between sections',
      (tester) async {
    await _pumpAnalysis(tester, const Size(1400, 920));

    for (final section in ['nuclei', 'overview', 'tme', 'nuclei', 'tme']) {
      await tester.tap(find.byKey(Key('analysis-nav-$section')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    for (final section in ['report', 'nuclei', 'report']) {
      await tester.tap(find.byKey(Key('analysis-nav-$section')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}

Future<void> _pumpAnalysis(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        v2AnalysisProvider(_runId)
            .overrideWith((ref) => Stream.value(_analysis)),
        v2CellsProvider(_runId).overrideWith((ref) async => const []),
        v2OverlayProvider(_runId).overrideWith((ref) async => _onePixelPng),
      ],
      child: const MaterialApp(
        home: AnalysisV2Screen(analysisRunId: _runId),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
