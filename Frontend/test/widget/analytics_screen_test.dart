import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:tme_insight/models/analytics.dart';
import 'package:tme_insight/providers/analytics_provider.dart';
import 'package:tme_insight/screens/analytics_screen.dart';

void main() {
  testWidgets('AnalyticsScreen renders loading state initially',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: AnalyticsScreen(),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('AnalyticsScreen renders metrics and charts when data is loaded',
      (WidgetTester tester) async {
    final mockData = AnalyticsSummary(
      totalSessions: 150,
      activeClinicians: 8,
      phenotypeDistribution: PhenotypeDistribution(
        hotCount: 80,
        coldCount: 40,
        excludedCount: 30,
      ),
      sessionsPerMonth: {
        '2026-06': 50,
        '2026-07': 100,
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          analyticsProvider.overrideWith((ref) => Future.value(mockData)),
        ],
        child: const MaterialApp(
          home: AnalyticsScreen(),
        ),
      ),
    );

    // Let the FutureProvider resolve
    await tester.pumpAndSettle();

    // Verify KPI Cards
    expect(find.text('Total Sessions'), findsOneWidget);
    expect(find.text('150'), findsOneWidget);

    expect(find.text('Active Clinicians'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);

    // Verify Charts
    expect(find.text('TME Phenotype Distribution'), findsOneWidget);
    expect(find.byType(PieChart), findsOneWidget);

    expect(find.text('Sessions Timeline'), findsOneWidget);
    expect(find.byType(BarChart), findsOneWidget);
  });
}
