/// WP-05 Widget Tests - Register Screen
///
///  1. Renders all 4 text input fields
///  2. Renders role dropdown
///  3. Renders Register Now button
///  4. Shows error for empty full name
///  5. Shows error for empty email
///  6. Shows error for invalid email format
///  7. Shows error for password shorter than 8 chars
///  8. Shows error when passwords don't match
///  9. No errors on all valid input
/// 10. Login link navigates back to /login
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tme_insight/providers/auth_provider.dart';
import 'package:tme_insight/screens/register_screen.dart';

import 'login_screen_test.dart' show FakeAuthStateController;

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Widget buildRegisterScreenWithProviders() {
  final router = GoRouter(
    initialLocation: '/register',
    routes: [
      GoRoute(
        path: '/register',
        builder: (_, __) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (_, __) => const Scaffold(body: Text('Login Screen')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(
        (ref) => FakeAuthStateController(ref) as AuthStateController,
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

/// Scroll a widget into view and tap it
Future<void> scrollAndTap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Fill out all required fields
Future<void> fillForm(
  WidgetTester tester, {
  String name = '',
  String email = '',
  String password = '',
  String confirm = '',
}) async {
  final fields = find.byType(TextFormField);
  if (name.isNotEmpty) await tester.enterText(fields.at(0), name);
  if (email.isNotEmpty) await tester.enterText(fields.at(1), email);
  if (password.isNotEmpty) await tester.enterText(fields.at(2), password);
  if (confirm.isNotEmpty) await tester.enterText(fields.at(3), confirm);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('RegisterScreen - UI Rendering', () {
    testWidgets('1. Renders all 4 text input fields', (tester) async {
      await tester.pumpWidget(buildRegisterScreenWithProviders());
      await tester.pumpAndSettle();

      expect(find.byType(TextFormField), findsNWidgets(4));
    });

    testWidgets('2. Renders role dropdown', (tester) async {
      await tester.pumpWidget(buildRegisterScreenWithProviders());
      await tester.pumpAndSettle();

      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    });

    testWidgets('3. Renders Register Now button', (tester) async {
      await tester.pumpWidget(buildRegisterScreenWithProviders());
      await tester.pumpAndSettle();

      expect(find.text('Register Now'), findsOneWidget);
    });
  });

  group('RegisterScreen - Form Validation', () {
    testWidgets('4. Shows error for empty full name', (tester) async {
      await tester.pumpWidget(buildRegisterScreenWithProviders());
      await tester.pumpAndSettle();

      await scrollAndTap(tester, find.byType(ElevatedButton));

      expect(find.text('Please enter your full name'), findsOneWidget);
    });

    testWidgets('5. Shows error for empty email', (tester) async {
      await tester.pumpWidget(buildRegisterScreenWithProviders());
      await tester.pumpAndSettle();

      await fillForm(tester, name: 'Dr. Smith');
      await scrollAndTap(tester, find.byType(ElevatedButton));

      expect(find.text('Please enter your email'), findsOneWidget);
    });

    testWidgets('6. Shows error for invalid email format', (tester) async {
      await tester.pumpWidget(buildRegisterScreenWithProviders());
      await tester.pumpAndSettle();

      await fillForm(tester, name: 'Dr. Smith', email: 'notanemail');
      await scrollAndTap(tester, find.byType(ElevatedButton));

      expect(find.text('Please enter a valid email'), findsOneWidget);
    });

    testWidgets('7. Shows error for short password', (tester) async {
      await tester.pumpWidget(buildRegisterScreenWithProviders());
      await tester.pumpAndSettle();

      await fillForm(
        tester,
        name: 'Dr. Smith',
        email: 'doc@hospital.com',
        password: 'short',
      );
      await scrollAndTap(tester, find.byType(ElevatedButton));

      expect(
        find.text('Password must be at least 8 characters'),
        findsOneWidget,
      );
    });

    testWidgets('8. Shows error when passwords do not match', (tester) async {
      await tester.pumpWidget(buildRegisterScreenWithProviders());
      await tester.pumpAndSettle();

      await fillForm(
        tester,
        name: 'Dr. Smith',
        email: 'doc@hospital.com',
        password: 'Secure123!',
        confirm: 'DifferentPass!',
      );
      await scrollAndTap(tester, find.byType(ElevatedButton));

      expect(find.text('Passwords do not match'), findsOneWidget);
    });

    testWidgets('9. No validation errors on fully valid input', (tester) async {
      await tester.pumpWidget(buildRegisterScreenWithProviders());
      await tester.pumpAndSettle();

      await fillForm(
        tester,
        name: 'Dr. Smith',
        email: 'doc@hospital.com',
        password: 'Secure123!',
        confirm: 'Secure123!',
      );
      await scrollAndTap(tester, find.byType(ElevatedButton));

      expect(find.text('Please enter your full name'), findsNothing);
      expect(find.text('Please enter your email'), findsNothing);
      expect(find.text('Passwords do not match'), findsNothing);
    });
  });

  group('RegisterScreen - Navigation', () {
    testWidgets('10. Back arrow navigates to /login', (tester) async {
      await tester.pumpWidget(buildRegisterScreenWithProviders());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.text('Login Screen'), findsOneWidget);
    });
  });
}
