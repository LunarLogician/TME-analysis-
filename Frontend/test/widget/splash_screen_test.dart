/// WP-05 Widget Tests - Splash Screen
///
///  1. Renders the TME-Insight logo icon
///  2. Renders the app name
///  3. Renders a loading indicator
///  4. Renders the subtitle text
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tme_insight/screens/splash_screen.dart';

Widget buildSplashScreen() {
  final router = GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (_, __) => const Scaffold(body: Text('Login Screen')),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (_, __) => const Scaffold(body: Text('Dashboard')),
      ),
    ],
  );

  return ProviderScope(
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  group('SplashScreen - UI Rendering', () {
    testWidgets('1. Renders the biotech icon', (tester) async {
      await tester.pumpWidget(buildSplashScreen());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byIcon(Icons.biotech), findsOneWidget);
    });

    testWidgets('2. Renders the app name TME-Insight', (tester) async {
      await tester.pumpWidget(buildSplashScreen());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('TME-Insight'), findsOneWidget);
    });

    testWidgets('3. Renders a CircularProgressIndicator', (tester) async {
      await tester.pumpWidget(buildSplashScreen());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('4. Renders the subtitle text', (tester) async {
      await tester.pumpWidget(buildSplashScreen());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Clinical Decision Support'), findsOneWidget);
    });
  });
}
