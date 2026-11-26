import 'package:flutter_test/flutter_test.dart';
import 'package:tme_insight/models/analysis_v2.dart';

void main() {
  test('parses canonical V2 counts, scale, and TME state', () {
    const analysis = AnalysisV2({
      'analysis_run_id': 'run-1',
      'session_id': 'session-1',
      'status': 'COMPLETE',
      'stage': 'COMPLETE',
      'progress': 1.0,
      'image_metadata': {
        'scale_trusted': false,
        'scale_source': 'UNKNOWN',
      },
      'quality': {'status': 'WARNING'},
      'cell_counts': {
        'NEOPLASTIC': 4,
        'INFLAMMATORY': 3,
        'CONNECTIVE': 2,
        'DEAD': 1,
        'EPITHELIAL': 5,
      },
      'accepted_cell_counts': {
        'NEOPLASTIC': 2,
        'INFLAMMATORY': 2,
      },
      'uncertain_cell_counts': {
        'NEOPLASTIC': 2,
        'INFLAMMATORY': 1,
      },
      'tumor_assessment': {'status': 'INDETERMINATE'},
      'spatial_measurements': null,
      'tme_assessment': {
        'state': 'NOT_ASSESSABLE',
        'reason_codes': ['PHYSICAL_SCALE_UNKNOWN'],
      },
    });

    expect(analysis.totalCells, 15);
    expect(analysis.acceptedCells, 4);
    expect(analysis.uncertainCells, 3);
    expect(analysis.scaleTrusted, isFalse);
    expect(analysis.tmeState, 'NOT_ASSESSABLE');
    expect(analysis.spatial, isNull);
  });

  test('all six canonical TME states remain distinct', () {
    const states = {
      'HOT',
      'COLD',
      'EXCLUDED',
      'INDETERMINATE',
      'NOT_ASSESSABLE',
      'NOT_APPLICABLE',
    };
    final parsed = states
        .map((state) => AnalysisV2({
              'tme_assessment': {'state': state}
            }).tmeState)
        .toSet();
    expect(parsed, states);
  });
}
