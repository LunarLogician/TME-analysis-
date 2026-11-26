import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide ResponseType;
import '../config/app_config.dart';
import '../models/analysis_v2.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();

  late final Dio _dio;
  late final SupabaseClient _supabase;

  factory ApiService() {
    return _instance;
  }

  ApiService._internal() {
    _supabase = Supabase.instance.client;
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        contentType: 'application/json',
      ),
    );

    // Add JWT token interceptor
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = _supabase.auth.currentSession?.accessToken;
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
      ),
    );
  }

  // ============= Patient Endpoints =============
  Future<List<Map<String, dynamic>>> getPatients() async {
    try {
      final response = await _dio.get('/patients/');
      return List<Map<String, dynamic>>.from(response.data);
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getPatient(String patientId) async {
    try {
      final response = await _dio.get('/patients/$patientId');
      return response.data;
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createPatient({
    required String fullName,
    required String dateOfBirth,
    required String gender,
    required String diagnosis,
  }) async {
    try {
      final response = await _dio.post(
        '/patients/',
        data: {
          'full_name': fullName,
          'date_of_birth': dateOfBirth,
          'gender': gender,
          'diagnosis': diagnosis,
        },
      );
      return response.data;
    } catch (e) {
      rethrow;
    }
  }

  // ============= Session Endpoints =============
  Future<Map<String, dynamic>> createSession({
    required String patientId,
    required String imageUrl,
  }) async {
    try {
      final response = await _dio.post(
        '/sessions/',
        data: {
          'patient_id': patientId,
          'image_url': imageUrl,
        },
      );
      return response.data;
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getSession(String sessionId) async {
    try {
      final response = await _dio.get('/sessions/$sessionId');
      return response.data;
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getPatientSessions(
      String patientId) async {
    try {
      final response = await _dio.get('/patients/$patientId/sessions');
      return List<Map<String, dynamic>>.from(response.data);
    } catch (e) {
      rethrow;
    }
  }

  Future<AnalysisLaunch> startV2Analysis({
    required String sessionId,
    required List<int> bytes,
    required String filename,
    String analysisMode = 'NUCLEI_ONLY',
    double? mpp,
    double? magnification,
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
      'analysis_mode': analysisMode,
      if (mpp != null) 'mpp_x': mpp,
      if (mpp != null) 'mpp_y': mpp,
      if (magnification != null) 'magnification': magnification,
      'tumor_region_mode': 'WHOLE_ROI',
    });
    final response = await _dio.post(
      '/v2/sessions/$sessionId/analysis',
      data: form,
      options: Options(contentType: 'multipart/form-data'),
    );
    return AnalysisLaunch.fromJson(Map<String, dynamic>.from(response.data));
  }

  Future<Map<String, dynamic>> getV2Analysis(String analysisRunId) async {
    final response = await _dio.get('/v2/analysis/$analysisRunId');
    return Map<String, dynamic>.from(response.data);
  }

  Future<Map<String, dynamic>> getLatestV2AnalysisForSession(
    String sessionId,
  ) async {
    final response = await _dio.get('/v2/sessions/$sessionId/analysis');
    return Map<String, dynamic>.from(response.data);
  }

  Future<Map<String, dynamic>> retryV2Analysis(String analysisRunId) async {
    final response = await _dio.post('/v2/analysis/$analysisRunId/retry');
    return Map<String, dynamic>.from(response.data);
  }

  Future<Map<String, dynamic>> generateV2Report(String analysisRunId) async {
    final response = await _dio.post('/v2/analysis/$analysisRunId/report');
    return Map<String, dynamic>.from(response.data);
  }

  Future<void> downloadV2Report(
    String analysisRunId,
    String savePath,
  ) async {
    await _dio.download('/v2/analysis/$analysisRunId/report', savePath);
  }

  Future<List<CellInstanceV2>> getV2Cells(
    String analysisRunId, {
    int offset = 0,
    int limit = 500,
  }) async {
    final response = await _dio.get(
      '/v2/analysis/$analysisRunId/cells',
      queryParameters: {'offset': offset, 'limit': limit},
    );
    final body = Map<String, dynamic>.from(response.data);
    return (body['items'] as List? ?? const [])
        .map((item) => CellInstanceV2(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<List<int>> getV2Overlay(String analysisRunId) async {
    final response = await _dio.get<List<int>>(
      '/v2/analysis/$analysisRunId/overlay',
      options: Options(responseType: ResponseType.bytes),
    );
    return response.data ?? const [];
  }

  Future<Map<String, dynamic>> updateV2TumorContext({
    required String analysisRunId,
    required String status,
    String regionMode = 'WHOLE_ROI',
    List<List<double>>? tumorPolygonPx,
  }) async {
    final response = await _dio.post(
      '/v2/analysis/$analysisRunId/tumor-context',
      data: {
        'status': status,
        'region_mode': regionMode,
        if (tumorPolygonPx != null) 'tumor_polygon_px': tumorPolygonPx,
      },
    );
    return Map<String, dynamic>.from(response.data);
  }

  // ============= Analytics Endpoints =============
  Future<Map<String, dynamic>> getAnalyticsSummary() async {
    try {
      final response = await _dio.get('/analytics/summary');
      return response.data;
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getAdminUsers() async {
    final response = await _dio.get('/auth/admin/users');
    final body = Map<String, dynamic>.from(response.data);
    return List<Map<String, dynamic>>.from(body['users'] as List? ?? const []);
  }
}
