/// WP-05 Widget Tests - Login Screen
///
/// Tests the LoginScreen UI and interaction logic:
///  1. Renders email and password fields
///  2. Shows validation error for empty email
///  3. Shows validation error for invalid email format
///  4. Shows validation error for empty password
///  5. Login button is present and tappable
///  6. Register navigation link is visible
///  7. Password field is obscured by default
///  8. Password visibility toggle works
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tme_insight/providers/auth_provider.dart';
import 'package:tme_insight/screens/login_screen.dart';

// ---------------------------------------------------------------------------
// Fake AuthStateController for widget tests
// ---------------------------------------------------------------------------

class FakeAuthStateController extends StateNotifier<AsyncValue<void>>
    implements AuthStateController {
  @override
  final Ref ref;

  FakeAuthStateController(this.ref) : super(const AsyncData(null));

  @override
  Future<bool> login(String email, String password) async {
    state = const AsyncData(null);
    return true;
  }

  @override
  Future<bool> register({
    required String email,
    required String password,
    required String fullName,
    required String role,
  }) async {
    state = const AsyncData(null);
    return true;
  }

  @override
  Future<void> logout() async {
    state = const AsyncData(null);
  }
}

// ---------------------------------------------------------------------------
// Test helper
// ---------------------------------------------------------------------------

Widget buildLoginScreenWithProviders({
  AuthStateController Function(Ref)? controllerBuilder,
}) {
  final builder = controllerBuilder ?? ((ref) => FakeAuthStateController(ref));

  final router = GoRouter(
    initialLocation: '/login',
    routes: [
      GoRoute(
        path: '/login',
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (_, __) => const Scaffold(body: Text('Register Screen')),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (_, __) => const Scaffold(body: Text('Dashboard')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith((ref) => builder(ref)),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('LoginScreen - UI Rendering', () {
    testWidgets('1. Renders email and password fields', (tester) async {
      await tester.pumpWidget(buildLoginScreenWithProviders());
      await tester.pumpAndSettle();

      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
    });

    testWidgets('2. Renders Sign In button', (tester) async {
      await tester.pumpWidget(buildLoginScreenWithProviders());
      await tester.pumpAndSettle();

      expect(find.text('Sign In'), findsOneWidget);
    });

    testWidgets('3. Renders Register navigation link', (tester) async {
      await tester.pumpWidget(buildLoginScreenWithProviders());
      await tester.pumpAndSettle();

      expect(find.text('Register'), findsOneWidget);
    });

    testWidgets('4. Password field is obscured by default', (tester) async {
      await tester.pumpWidget(buildLoginScreenWithProviders());
      await tester.pumpAndSettle();

      // Find the password TextField via its EditableText
      final editableTexts =
          tester.widgetList<EditableText>(find.byType(EditableText));
      // Second one is password
      final passwordField = editableTexts.elementAt(1);
      expect(passwordField.obscureText, isTrue);
    });
  });

  group('LoginScreen - Form Validation', () {
    testWidgets('5. Shows error for empty email on submit', (tester) async {
      await tester.pumpWidget(buildLoginScreenWithProviders());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter your email'), findsOneWidget);
    });

    testWidgets('6. Shows error for invalid email format', (tester) async {
      await tester.pumpWidget(buildLoginScreenWithProviders());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).first,
        'notanemail',
      );
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a valid email'), findsOneWidget);
    });

    testWidgets('7. Shows error for empty password on submit', (tester) async {
      await tester.pumpWidget(buildLoginScreenWithProviders());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).first,
        'doc@hospital.com',
      );
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter your password'), findsOneWidget);
    });

    testWidgets('8. No validation errors on valid input', (tester) async {
      await tester.pumpWidget(buildLoginScreenWithProviders());
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'doc@hospital.com');
      await tester.enterText(fields.at(1), 'SecurePass123');
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter your email'), findsNothing);
      expect(find.text('Please enter your password'), findsNothing);
    });
  });

  group('LoginScreen - Navigation', () {
    testWidgets('9. Register link navigates to /register', (tester) async {
      await tester.pumpWidget(buildLoginScreenWithProviders());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Register'));
      await tester.pumpAndSettle();

      expect(find.text('Register Screen'), findsOneWidget);
    });
  });
}
