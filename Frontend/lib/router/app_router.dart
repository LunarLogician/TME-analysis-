import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import '../providers/auth_provider.dart';
import '../screens/splash_screen.dart';
import '../screens/login_screen.dart';
import '../screens/register_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/patient_list_screen.dart';
import '../screens/add_patient_screen.dart';
import '../screens/patient_detail_screen.dart';
import '../screens/upload_screen.dart';
import '../screens/analytics_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/report_history_screen.dart';
import '../screens/user_management_screen.dart';
import '../screens/analysis_v2_screen.dart';
import '../screens/session_analysis_screen.dart';
import '../widgets/app_shell.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: _GoRouterRefreshStream(
      supabase.Supabase.instance.client.auth.onAuthStateChange,
    ),
    redirect: (context, state) {
      final isAuthRoute = state.matchedLocation == '/login' ||
          state.matchedLocation == '/register';

      final isSplashRoute = state.matchedLocation == '/splash';

      final user = supabase.Supabase.instance.client.auth.currentUser;
      final isAuthenticated = user != null;
      final role = resolveUserRole(user);

      // Handle splash screen redirect logic
      if (isSplashRoute) {
        return isAuthenticated ? '/dashboard' : '/login';
      }

      // Handle unauthenticated state
      if (!isAuthenticated && !isAuthRoute) {
        return '/login';
      }

      // Handle authenticated state trying to access login/register
      if (isAuthenticated && isAuthRoute) {
        return '/dashboard';
      }

      if ((state.matchedLocation == '/admin' ||
              state.matchedLocation.startsWith('/admin/') ||
              state.matchedLocation == '/analytics') &&
          role != 'admin') {
        return '/dashboard';
      }

      if ((state.matchedLocation == '/add-patient' ||
              state.matchedLocation == '/upload') &&
          role != 'clinician') {
        return '/dashboard';
      }

      if (role == 'admin' && state.matchedLocation == '/patients') {
        return '/dashboard';
      }

      // Allow navigation
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        name: 'splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        name: 'register',
        builder: (context, state) => const RegisterScreen(),
      ),
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => AppShell(
          location: state.uri.path,
          child: child,
        ),
        routes: [
          GoRoute(
            path: '/dashboard',
            name: 'dashboard',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/patients',
            name: 'patients',
            builder: (context, state) => const PatientListScreen(),
          ),
          GoRoute(
            path: '/upload',
            name: 'upload',
            builder: (context, state) {
              final patientId = state.extra as String?;
              return UploadScreen(patientId: patientId);
            },
          ),
          GoRoute(
            path: '/reports',
            name: 'report-history',
            builder: (context, state) => const ReportHistoryScreen(),
          ),
          GoRoute(
            path: '/admin',
            name: 'admin-dashboard',
            redirect: (_, __) => '/dashboard',
          ),
          GoRoute(
            path: '/admin/users',
            name: 'admin-users',
            builder: (context, state) => const UserManagementScreen(),
          ),
          GoRoute(
            path: '/analytics',
            name: 'analytics',
            builder: (context, state) => const AnalyticsScreen(),
          ),
          GoRoute(
            path: '/profile',
            name: 'profile',
            builder: (context, state) => const ProfileScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/patients/:id',
        name: 'patient-detail',
        builder: (context, state) =>
            PatientDetailScreen(patientId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/add-patient',
        name: 'add-patient',
        builder: (context, state) => const AddPatientScreen(),
      ),
      GoRoute(
        path: '/sessions/:id',
        name: 'session-analysis',
        builder: (context, state) =>
            SessionAnalysisScreen(sessionId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/v2/analysis/:id',
        name: 'analysis-v2',
        builder: (context, state) => AnalysisV2Screen(
          analysisRunId: state.pathParameters['id']!,
        ),
      ),
    ],
  );
});

// Helper to convert Stream to Listenable for GoRouter
class _GoRouterRefreshStream extends ChangeNotifier {
  _GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen(
          (dynamic _) => notifyListeners(),
        );
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
