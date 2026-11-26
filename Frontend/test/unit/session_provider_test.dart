import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tme_insight/providers/patient_provider.dart';
import 'package:tme_insight/providers/session_provider.dart';
import 'package:tme_insight/services/api_service.dart';

class MockApiService extends Mock implements ApiService {}

void main() {
  late MockApiService mockApiService;
  late ProviderContainer container;

  setUp(() {
    mockApiService = MockApiService();
    container = ProviderContainer(
      overrides: [apiServiceProvider.overrideWithValue(mockApiService)],
    );
  });

  tearDown(() => container.dispose());

  test('sessionDetailProvider fetches and parses session data', () async {
    when(() => mockApiService.getSession('s1')).thenAnswer((_) async => {
          'id': 's1',
          'patient_id': 'p1',
          'session_date': '2024-01-01T10:00:00Z',
          'image_url': 'image.png',
          'status': 'complete',
          'created_at': '2024-01-01T10:00:00Z',
        });

    final session = await container.read(sessionDetailProvider('s1').future);

    expect(session.id, 's1');
    expect(session.patientId, 'p1');
    expect(session.isComplete, isTrue);
  });

  test('latest analysis provider resolves a session to its current run',
      () async {
    when(() => mockApiService.getLatestV2AnalysisForSession('s1'))
        .thenAnswer((_) async => {
              'analysis_run_id': 'run-1',
              'session_id': 's1',
              'status': 'COMPLETE',
              'stage': 'COMPLETE',
              'progress': 1.0,
            });

    final analysis = await container.read(
      latestV2AnalysisForSessionProvider('s1').future,
    );

    expect(analysis.id, 'run-1');
    expect(analysis.sessionId, 's1');
    expect(analysis.isComplete, isTrue);
  });
}
