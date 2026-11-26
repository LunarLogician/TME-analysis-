import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/analytics.dart';
import 'patient_provider.dart';

final analyticsProvider = FutureProvider<AnalyticsSummary>((ref) async {
  final apiService = ref.watch(apiServiceProvider);
  final data = await apiService.getAnalyticsSummary();
  return AnalyticsSummary.fromJson(data);
});
