import 'package:flutter/material.dart';

import 'session_analysis_screen.dart';

/// Keeps older callers on the current session-analysis workflow.
///
/// The previous results screen depended on the retired segmentation API and
/// report route. SessionAnalysisScreen resolves the latest persisted analysis
/// and opens the supported nuclei, tumor-context, TME, and report workspace.
class SessionResultsScreen extends StatelessWidget {
  final String sessionId;

  const SessionResultsScreen({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context) =>
      SessionAnalysisScreen(sessionId: sessionId);
}
