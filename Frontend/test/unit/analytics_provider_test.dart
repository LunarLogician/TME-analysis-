import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tme_insight/providers/analytics_provider.dart';
import 'package:tme_insight/services/api_service.dart';
import 'package:tme_insight/providers/patient_provider.dart';

class MockApiService extends Mock implements ApiService {}

void main() {
  late MockApiService mockApiService;
  late ProviderContainer container;

  setUp(() {
    mockApiService = MockApiService();
    container = ProviderContainer(
      overrides: [
        apiServiceProvider.overrideWithValue(mockApiService),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  group('analyticsProvider', () {
    test('fetches and parses analytics summary', () async {
      when(() => mockApiService.getAnalyticsSummary()).thenAnswer((_) async => {
            'total_sessions': 100,
            'phenotype_distribution': {
              'hot_count': 50,
              'cold_count': 30,
              'excluded_count': 20
            },
            'active_clinicians': 5,
            'sessions_per_month': {'2026-07': 40, '2026-06': 60}
          });

      final summary = await container.read(analyticsProvider.future);

      expect(summary.totalSessions, 100);
      expect(summary.activeClinicians, 5);
      expect(summary.phenotypeDistribution.hotCount, 50);
      expect(summary.phenotypeDistribution.coldCount, 30);
      expect(summary.phenotypeDistribution.excludedCount, 20);
      expect(summary.sessionsPerMonth['2026-07'], 40);
      verify(() => mockApiService.getAnalyticsSummary()).called(1);
    });
  });
}
