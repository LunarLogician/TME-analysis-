import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tme_insight/providers/patient_provider.dart';
import 'package:tme_insight/services/api_service.dart';

class MockApiService extends Mock implements ApiService {}

void main() {
  late MockApiService mockApiService;
  late ProviderContainer container;

  setUp(() {
    mockApiService = MockApiService();
    container = ProviderContainer(
      overrides: [
        apiServiceProvider.overrideWithValue(mockApiService),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  group('patientListProvider', () {
    test('successfully fetches and parses patients', () async {
      // Arrange
      final mockJsonResponse = [
        {
          'id': 'p1',
          'clinician_id': 'c1',
          'full_name': 'John Doe',
          'date_of_birth': '1990-01-01T00:00:00Z',
          'gender': 'Male',
          'diagnosis': 'Test',
          'created_at': '2023-10-01T12:00:00Z'
        }
      ];
      when(() => mockApiService.getPatients())
          .thenAnswer((_) async => mockJsonResponse);

      // Act
      final patients = await container.read(patientListProvider.future);

      // Assert
      expect(patients.length, 1);
      expect(patients.first.id, 'p1');
      expect(patients.first.fullName, 'John Doe');
      verify(() => mockApiService.getPatients()).called(1);
    });

    test('handles errors from ApiService', () async {
      // Arrange
      when(() => mockApiService.getPatients())
          .thenThrow(Exception('API Error'));

      // Act & Assert
      expect(
        () => container.read(patientListProvider.future),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('patientNotifierProvider', () {
    test('createPatient success updates state to data', () async {
      // Arrange
      when(() => mockApiService.createPatient(
            fullName: any(named: 'fullName'),
            dateOfBirth: any(named: 'dateOfBirth'),
            gender: any(named: 'gender'),
            diagnosis: any(named: 'diagnosis'),
          )).thenAnswer((_) async => {'id': 'pnew'});

      // Act
      final notifier = container.read(patientNotifierProvider.notifier);
      final success = await notifier.createPatient(
        fullName: 'Jane Doe',
        dateOfBirth: '1985-05-15',
        gender: 'Female',
        diagnosis: 'Breast Cancer',
      );

      // Assert
      expect(success, isTrue);
      expect(container.read(patientNotifierProvider).isLoading, isFalse);
      expect(container.read(patientNotifierProvider).hasError, isFalse);
    });

    test('createPatient failure sets error state', () async {
      // Arrange
      when(() => mockApiService.createPatient(
            fullName: any(named: 'fullName'),
            dateOfBirth: any(named: 'dateOfBirth'),
            gender: any(named: 'gender'),
            diagnosis: any(named: 'diagnosis'),
          )).thenThrow(Exception('Failed to create'));

      // Act
      final notifier = container.read(patientNotifierProvider.notifier);
      final success = await notifier.createPatient(
        fullName: 'Jane Doe',
        dateOfBirth: '1985-05-15',
        gender: 'Female',
        diagnosis: 'Breast Cancer',
      );

      // Assert
      expect(success, isFalse);
      expect(container.read(patientNotifierProvider).hasError, isTrue);
    });
  });
}
