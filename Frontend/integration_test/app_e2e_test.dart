import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tme_insight/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('End-to-end app navigation flow', (WidgetTester tester) async {
    // Note: This is a basic integration test that launches the app.
    // In a real E2E environment, we'd mock the API or use a test database.
    // Here we just test the app boots and we can interact with some UI elements.
    app.main();
    await tester.pumpAndSettle();

    // Verify we are on login screen (or splash screen transitions to login)
    expect(find.byType(TextField), findsWidgets); // Email/Password fields

    // We can't actually log in easily without a real backend unless we mock ProviderScope
    // But we can verify the login screen renders properly.
    expect(find.text('TME-Insight'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);

    // Tap on 'Don't have an account? Register here'
    final registerButton = find.text("Don't have an account? Register here");
    if (registerButton.evaluate().isNotEmpty) {
      await tester.tap(registerButton);
      await tester.pumpAndSettle();

      // Verify we are on register screen
      expect(find.text('Create Account'), findsOneWidget);

      // Tap on 'Already have an account? Login here'
      final loginButton = find.text("Already have an account? Login here");
      await tester.tap(loginButton);
      await tester.pumpAndSettle();

      expect(find.text('Sign In'), findsOneWidget);
    }
  });
}
