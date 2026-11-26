import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tme_insight/models/patient.dart';
import 'package:tme_insight/models/dashboard_data.dart';
import 'package:tme_insight/providers/auth_provider.dart';
import 'package:tme_insight/providers/patient_provider.dart';
import 'package:tme_insight/providers/dashboard_provider.dart';
import 'package:tme_insight/screens/dashboard_screen.dart';
import 'package:tme_insight/screens/patient_list_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Create a mock User for the currentUserProvider
class MockUser extends User {
  MockUser({
    required super.id,
    required String appMetadata,
    required String userMetadata,
    required super.aud,
    required super.createdAt,
  }) : super(
          appMetadata: {},
          userMetadata: {'full_name': 'Dr. Test'},
        );
}

void main() {
  group('WP-06: Patient Management Screens Widget Tests', () {
    testWidgets('DashboardScreen renders stats and quick actions',
        (WidgetTester tester) async {
      // Arrange
      final mockUser = MockUser(
        id: 'test-user',
        appMetadata: '',
        userMetadata: '',
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
      );

      final mockPatients = [
        Patient(
            id: '1',
            clinicianId: 'c1',
            fullName: 'John Doe',
            dateOfBirth: '1990-01-01T00:00:00Z',
            gender: 'Male',
            diagnosis: 'None',
            createdAt: DateTime.parse('2023-10-01T12:00:00Z')),
        Patient(
            id: '2',
            clinicianId: 'c1',
            fullName: 'Jane Doe',
            dateOfBirth: '1992-01-01T00:00:00Z',
            gender: 'Female',
            diagnosis: 'None',
            createdAt: DateTime.parse('2023-10-02T12:00:00Z')),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(mockUser),
            patientListProvider.overrideWith((ref) => mockPatients),
            dashboardProvider.overrideWith(
              (ref) =>
                  DashboardData(patients: mockPatients, activities: const []),
            ),
          ],
          child: const MaterialApp(
            home: DashboardScreen(),
          ),
        ),
      );

      // Act
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Welcome, Dr. Test'), findsOneWidget);
      expect(find.text('2'), findsOneWidget); // Total patients
      expect(find.text('Total Patients'), findsOneWidget);
      expect(find.text('Add New Patient'), findsOneWidget);
      expect(find.text('View Patient List'), findsOneWidget);
    });

    testWidgets('PatientListScreen renders list of patients',
        (WidgetTester tester) async {
      // Arrange
      final mockPatients = [
        Patient(
            id: 'p1',
            clinicianId: 'c1',
            fullName: 'John Smith',
            dateOfBirth: '1985-05-15T00:00:00Z',
            gender: 'Male',
            diagnosis: 'Asthma',
            createdAt: DateTime.parse('2023-10-01T12:00:00Z')),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            patientListProvider.overrideWith((ref) => mockPatients),
          ],
          child: const MaterialApp(
            home: PatientListScreen(),
          ),
        ),
      );

      // Act
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Patient Roster'), findsOneWidget);
      expect(find.text('John Smith'), findsOneWidget);
      expect(find.text('Diagnosis: Asthma'), findsOneWidget);
      expect(find.text('DOB: 1985-05-15'), findsOneWidget);
    });
  });
}
