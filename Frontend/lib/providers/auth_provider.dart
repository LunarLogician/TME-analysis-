import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Provider;
import '../providers/patient_provider.dart';

// Stream of Supabase Auth State
final authStateProvider = StreamProvider<AuthState>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
});

// Current User Provider
final currentUserProvider = Provider<User?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.value?.session?.user ??
      Supabase.instance.client.auth.currentUser;
});

// User Role Provider
final userRoleProvider = Provider<String>((ref) {
  final user = ref.watch(currentUserProvider);
  return resolveUserRole(user);
});

String resolveUserRole(User? user) {
  if (user == null) return 'guest';
  // Roles assigned by an administrator live in app_metadata and must take
  // precedence over user-editable metadata.
  final role = user.appMetadata['role'] ?? user.userMetadata?['role'];
  final normalized = role?.toString().toLowerCase();
  return const {'admin', 'clinician', 'patient'}.contains(normalized)
      ? normalized!
      : 'clinician';
}

// Auth Controller / State
class AuthStateController extends StateNotifier<AsyncValue<void>> {
  final Ref ref;
  AuthStateController(this.ref) : super(const AsyncData(null));

  final _supabase = Supabase.instance.client;

  Future<bool> login(String email, String password) async {
    state = const AsyncLoading();
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      state = const AsyncData(null);
      if (response.session != null) {
        ref.invalidate(patientListProvider);
        return true;
      }
      return false;
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
      final response = await _supabase.auth.signUp(
        email: email.trim(),
        password: password,
        data: {
          'full_name': fullName.trim(),
          'role': role,
        },
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
      await _supabase.auth.signOut();
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthStateController, AsyncValue<void>>((ref) {
  return AuthStateController(ref);
});
