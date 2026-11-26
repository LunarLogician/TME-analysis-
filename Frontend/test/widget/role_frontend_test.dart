import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tme_insight/models/analytics.dart';
import 'package:tme_insight/models/app_user.dart';
import 'package:tme_insight/providers/analytics_provider.dart';
import 'package:tme_insight/providers/auth_provider.dart';
import 'package:tme_insight/providers/dashboard_provider.dart';
import 'package:tme_insight/screens/admin_dashboard_screen.dart';
import 'package:tme_insight/widgets/app_shell.dart';

void main() {
  testWidgets('clinician shell exposes clinical workflow tabs', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [userRoleProvider.overrideWithValue('clinician')],
        child: const MaterialApp(
          home: AppShell(location: '/dashboard', child: SizedBox()),
        ),
      ),
    );

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Patients'), findsOneWidget);
    expect(find.text('New biopsy'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
  });

  testWidgets('administrator shell exposes oversight tabs', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [userRoleProvider.overrideWithValue('admin')],
        child: const MaterialApp(
          home: AppShell(location: '/dashboard', child: SizedBox()),
        ),
      ),
    );

    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Users'), findsOneWidget);
    expect(find.text('Analytics'), findsOneWidget);
    expect(find.text('Patients'), findsNothing);
    expect(find.text('New biopsy'), findsNothing);
  });

  testWidgets('admin dashboard shows platform and user metrics',
      (tester) async {
    final analytics = AnalyticsSummary(
      totalSessions: 30,
      activeClinicians: 4,
      phenotypeDistribution: PhenotypeDistribution(
        hotCount: 10,
        coldCount: 12,
        excludedCount: 8,
      ),
      sessionsPerMonth: const {},
    );
    final users = [
      AppUser(
        id: 'u1',
        email: 'doctor@example.com',
        fullName: 'Doctor One',
        role: 'clinician',
        createdAt: DateTime(2026),
      ),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          analyticsProvider.overrideWith((ref) => analytics),
          adminUsersProvider.overrideWith((ref) => users),
        ],
        child: const MaterialApp(home: AdminDashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Administration Overview'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('1 registered accounts'), findsOneWidget);
    expect(find.text('Operational boundary'), findsOneWidget);
  });
}
