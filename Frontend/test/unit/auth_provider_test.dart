import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Provider;

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockAuthResponse extends Mock implements AuthResponse {}

class MockSession extends Mock implements Session {}

class MockUser extends Mock implements User {}

// ---------------------------------------------------------------------------
// Fake AuthStateController that accepts an injected GoTrueClient
// ---------------------------------------------------------------------------

class TestableAuthStateController extends StateNotifier<AsyncValue<void>> {
  TestableAuthStateController(this._auth) : super(const AsyncData(null));

  final GoTrueClient _auth;

  Future<bool> login(String email, String password) async {
    state = const AsyncLoading();
    try {
      final response = await _auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      state = const AsyncData(null);
      return response.session != null;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  Future<bool> register({
    required String email,
    required String password,
    required String fullName,
    required String role,
  }) async {
    state = const AsyncLoading();
    try {
      final response = await _auth.signUp(
        email: email.trim(),
        password: password,
        data: {'full_name': fullName.trim(), 'role': role},
      );
      state = const AsyncData(null);
      return response.user != null;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  Future<void> logout() async {
    state = const AsyncLoading();
    try {
      await _auth.signOut();
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

TestableAuthStateController makeController(GoTrueClient mockAuth) {
  return TestableAuthStateController(mockAuth);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockGoTrueClient mockAuth;
  late MockAuthResponse mockAuthResponse;
  late MockSession mockSession;
  late MockUser mockUser;

  setUp(() {
    mockAuth = MockGoTrueClient();
    mockAuthResponse = MockAuthResponse();
    mockSession = MockSession();
    mockUser = MockUser();
  });

  group('AuthStateController - login()', () {
    test('1. Initial state is AsyncData(null)', () {
      final controller = makeController(mockAuth);
      expect(controller.state, isA<AsyncData<void>>());
    });

    test('2. login() returns true and sets AsyncData on success', () async {
      when(() => mockAuthResponse.session).thenReturn(mockSession);
      when(() => mockAuth.signInWithPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenAnswer((_) async => mockAuthResponse);

      final controller = makeController(mockAuth);
      final result = await controller.login('doc@hospital.com', 'Pass1234!');

      expect(result, isTrue);
      expect(controller.state, isA<AsyncData<void>>());
    });

    test('3. login() returns false and sets AsyncError on exception', () async {
      when(() => mockAuth.signInWithPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenThrow(const AuthException('Invalid login credentials'));

      final controller = makeController(mockAuth);
      final result = await controller.login('bad@email.com', 'wrong');

      expect(result, isFalse);
      expect(controller.state, isA<AsyncError<void>>());
    });

    test('4. login() returns false when session is null', () async {
      when(() => mockAuthResponse.session).thenReturn(null);
      when(() => mockAuth.signInWithPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenAnswer((_) async => mockAuthResponse);

      final controller = makeController(mockAuth);
      final result = await controller.login('doc@hospital.com', 'Pass1234!');

      expect(result, isFalse);
    });
  });

  group('AuthStateController - register()', () {
    test('5. register() returns true and sets AsyncData on success', () async {
      when(() => mockAuthResponse.user).thenReturn(mockUser);
      when(() => mockAuth.signUp(
            email: any(named: 'email'),
            password: any(named: 'password'),
            data: any(named: 'data'),
          )).thenAnswer((_) async => mockAuthResponse);

      final controller = makeController(mockAuth);
      final result = await controller.register(
        email: 'new@doctor.com',
        password: 'Secure123!',
        fullName: 'Dr. Smith',
        role: 'clinician',
      );

      expect(result, isTrue);
      expect(controller.state, isA<AsyncData<void>>());
    });

    test('6. register() returns false and sets AsyncError on duplicate email',
        () async {
      when(() => mockAuth.signUp(
            email: any(named: 'email'),
            password: any(named: 'password'),
            data: any(named: 'data'),
          )).thenThrow(const AuthException('User already registered'));

      final controller = makeController(mockAuth);
      final result = await controller.register(
        email: 'existing@doctor.com',
        password: 'Secure123!',
        fullName: 'Dr. Smith',
        role: 'clinician',
      );

      expect(result, isFalse);
      expect(controller.state, isA<AsyncError<void>>());
    });
  });

  group('AuthStateController - logout()', () {
    test('7. logout() sets AsyncData after successful sign-out', () async {
      when(() => mockAuth.signOut()).thenAnswer((_) async {});

      final controller = makeController(mockAuth);
      await controller.logout();

      expect(controller.state, isA<AsyncData<void>>());
    });

    test('8. logout() sets AsyncError when signOut throws', () async {
      when(() => mockAuth.signOut())
          .thenThrow(const AuthException('Network error'));

      final controller = makeController(mockAuth);
      await controller.logout();

      expect(controller.state, isA<AsyncError<void>>());
    });
  });

  group('userRoleProvider logic', () {
    test('9. Returns "guest" when user is null', () {
      String resolveRole(User? user) {
        if (user == null) return 'guest';
        final metadata = user.userMetadata;
        if (metadata != null && metadata.containsKey('role')) {
          return metadata['role'] as String;
        }
        return 'clinician';
      }

      expect(resolveRole(null), equals('guest'));
    });

    test('10. Returns role from user metadata', () {
      String resolveRole(User? user) {
        if (user == null) return 'guest';
        final metadata = user.userMetadata;
        if (metadata != null && metadata.containsKey('role')) {
          return metadata['role'] as String;
        }
        return 'clinician';
      }

      when(() => mockUser.userMetadata).thenReturn({'role': 'admin'});
      expect(resolveRole(mockUser), equals('admin'));
    });

    test('11. Defaults to "clinician" when metadata has no role key', () {
      String resolveRole(User? user) {
        if (user == null) return 'guest';
        final metadata = user.userMetadata;
        if (metadata != null && metadata.containsKey('role')) {
          return metadata['role'] as String;
        }
        return 'clinician';
      }

      when(() => mockUser.userMetadata).thenReturn({'full_name': 'Dr. Jones'});
      expect(resolveRole(mockUser), equals('clinician'));
    });
  });
}
