import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/session_provider.dart';
import 'analysis_v2_screen.dart';

class SessionAnalysisScreen extends ConsumerWidget {
  final String sessionId;

  const SessionAnalysisScreen({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analysis = ref.watch(latestV2AnalysisForSessionProvider(sessionId));
    return analysis.when(
      data: (value) => AnalysisV2Screen(analysisRunId: value.id),
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('TME-Insight Review')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.find_in_page_outlined, size: 52),
                const SizedBox(height: 12),
                const Text(
                  'No analysis is available for this biopsy session.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(
                    latestV2AnalysisForSessionProvider(sessionId),
                  ),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
