import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../models/analysis_v2.dart';
import '../providers/patient_provider.dart';
import '../providers/session_provider.dart';
import '../widgets/analysis/analysis_workspace.dart';

class AnalysisV2Screen extends ConsumerStatefulWidget {
  final String analysisRunId;

  const AnalysisV2Screen({super.key, required this.analysisRunId});

  @override
  ConsumerState<AnalysisV2Screen> createState() => _AnalysisV2ScreenState();
}

class _AnalysisV2ScreenState extends ConsumerState<AnalysisV2Screen> {
  bool _retrying = false;
  bool _updatingTumor = false;
  bool _generatingReport = false;
  bool _downloadingReport = false;
  bool _reportReady = false;

  @override
  Widget build(BuildContext context) {
    final analysisAsync = ref.watch(v2AnalysisProvider(widget.analysisRunId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('TME-Insight Review'),
        centerTitle: false,
        backgroundColor: const Color(0xFF0B1020),
        surfaceTintColor: Colors.transparent,
      ),
      body: analysisAsync.when(
        loading: () => const _InitialProgress(),
        error: (error, _) => _Failure(
          error: error,
          retrying: _retrying,
          onRetry: _retryAnalysis,
        ),
        data: (analysis) {
          if (!analysis.isComplete) return _Progress(analysis: analysis);
          final cells = ref.watch(v2CellsProvider(widget.analysisRunId));
          final overlay = ref.watch(v2OverlayProvider(widget.analysisRunId));
          return AnalysisWorkspace(
            analysis: analysis,
            cells: cells,
            overlay: overlay,
            onRefresh: _refresh,
            onUpdateTumor: _updateTumor,
            onDrawRegion: () => _drawTumorRegion(analysis, overlay.value),
            onGenerateReport: _generateReport,
            onDownloadReport: _downloadReport,
            updatingTumor: _updatingTumor,
            generatingReport: _generatingReport,
            downloadingReport: _downloadingReport,
            reportReady: _reportReady,
          );
        },
      ),
    );
  }

  Future<void> _refresh() async {
    ref.invalidate(v2AnalysisProvider(widget.analysisRunId));
    ref.invalidate(v2CellsProvider(widget.analysisRunId));
    ref.invalidate(v2OverlayProvider(widget.analysisRunId));
    await ref.read(v2AnalysisProvider(widget.analysisRunId).future);
  }

  Future<void> _retryAnalysis() async {
    setState(() => _retrying = true);
    final success = await ref
        .read(sessionNotifierProvider.notifier)
        .retryV2Analysis(widget.analysisRunId);
    if (!mounted) return;
    setState(() => _retrying = false);
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not retry the analysis.')),
      );
    }
  }

  Future<void> _generateReport() async {
    setState(() => _generatingReport = true);
    try {
      await ref.read(apiServiceProvider).generateV2Report(widget.analysisRunId);
      if (!mounted) return;
      setState(() => _reportReady = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Structured TME-Insight report generated from persisted results.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not generate report: $error')),
      );
    } finally {
      if (mounted) setState(() => _generatingReport = false);
    }
  }

  Future<void> _downloadReport() async {
    setState(() => _downloadingReport = true);
    try {
      final directory = await getApplicationDocumentsDirectory();
      final path = '${directory.path}/tme-insight-${widget.analysisRunId}.pdf';
      await ref
          .read(apiServiceProvider)
          .downloadV2Report(widget.analysisRunId, path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Report saved to $path')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not download report: $error')),
      );
    } finally {
      if (mounted) setState(() => _downloadingReport = false);
    }
  }

  Future<void> _updateTumor(String status) async {
    setState(() => _updatingTumor = true);
    try {
      final success =
          await ref.read(sessionNotifierProvider.notifier).updateV2TumorContext(
                analysisRunId: widget.analysisRunId,
                status: status,
              );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? 'Tumor context updated from stored cells; neural inference was not rerun.'
              : 'Could not update tumor context.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _updatingTumor = false);
    }
  }

  Future<void> _drawTumorRegion(
    AnalysisV2 analysis,
    List<int>? overlayBytes,
  ) async {
    if (overlayBytes == null || overlayBytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The overlay must finish loading before annotation.',
          ),
        ),
      );
      return;
    }
    final width = (analysis.imageMetadata['width_px'] as num?)?.toDouble();
    final height = (analysis.imageMetadata['height_px'] as num?)?.toDouble();
    if (width == null || height == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Source image dimensions are unavailable.'),
        ),
      );
      return;
    }
    final polygon = await showDialog<List<List<double>>>(
      context: context,
      builder: (context) => _TumorRegionDialog(
        imageBytes: Uint8List.fromList(overlayBytes),
        sourceWidth: width,
        sourceHeight: height,
      ),
    );
    if (polygon == null || polygon.length < 3) return;
    setState(() => _updatingTumor = true);
    try {
      final success =
          await ref.read(sessionNotifierProvider.notifier).updateV2TumorContext(
                analysisRunId: widget.analysisRunId,
                status: 'PRESENT',
                regionMode: 'ANNOTATED_REGION',
                tumorPolygonPx: polygon,
              );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? 'Annotated tumor region saved.'
              : 'Could not save region.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _updatingTumor = false);
    }
  }
}

class _InitialProgress extends StatelessWidget {
  const _InitialProgress();

  @override
  Widget build(BuildContext context) => const _ProgressShell(
        progress: null,
        icon: Icons.hourglass_top_rounded,
        title: 'Analysis queued',
        description: 'Preparing the image and model worker.',
      );
}

class _Progress extends StatelessWidget {
  final AnalysisV2 analysis;

  const _Progress({required this.analysis});

  @override
  Widget build(BuildContext context) {
    final tiles = analysis.tileCount > 0
        ? '${analysis.processedTileCount} of ${analysis.tileCount} tiles'
        : 'Preparing analysis stages';
    return _ProgressShell(
      progress: analysis.progress,
      icon: Icons.biotech_outlined,
      title: _stageLabel(analysis.stage),
      description: tiles,
    );
  }
}

class _ProgressShell extends StatelessWidget {
  final double? progress;
  final IconData icon;
  final String title;
  final String description;

  const _ProgressShell({
    required this.progress,
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0B1020), Color(0xFF15172A)],
          ),
        ),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xFF12182B),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: .07)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B7CFF).withValues(alpha: .13),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 34, color: const Color(0xFFAE9FFF)),
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(description,
                    style: const TextStyle(color: Colors.white54)),
                const SizedBox(height: 22),
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(999),
                ),
                if (progress != null) ...[
                  const SizedBox(height: 10),
                  Text('${(progress! * 100).round()}% complete'),
                ],
              ],
            ),
          ),
        ),
      );
}

class _Failure extends StatelessWidget {
  final Object error;
  final bool retrying;
  final VoidCallback onRetry;

  const _Failure({
    required this.error,
    required this.retrying,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: const Color(0xFFFF6B81).withValues(alpha: .07),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
                color: const Color(0xFFFF6B81).withValues(alpha: .22)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 44, color: Color(0xFFFF6B81)),
              const SizedBox(height: 14),
              Text('Analysis could not be completed',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('$error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54)),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: retrying ? null : onRetry,
                icon: retrying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
                label: Text(retrying ? 'Retrying…' : 'Retry analysis'),
              ),
            ],
          ),
        ),
      );
}

class _TumorRegionDialog extends StatefulWidget {
  final Uint8List imageBytes;
  final double sourceWidth;
  final double sourceHeight;

  const _TumorRegionDialog({
    required this.imageBytes,
    required this.sourceWidth,
    required this.sourceHeight,
  });

  @override
  State<_TumorRegionDialog> createState() => _TumorRegionDialogState();
}

class _TumorRegionDialogState extends State<_TumorRegionDialog> {
  final List<Offset> _normalizedPoints = [];

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Annotate tumor region'),
        content: SizedBox(
          width: 620,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tap at least three boundary points in order. The polygon is stored as pathologist-confirmed context.',
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: AspectRatio(
                  aspectRatio: widget.sourceWidth / widget.sourceHeight,
                  child: LayoutBuilder(
                    builder: (context, constraints) => GestureDetector(
                      onTapDown: (details) => setState(() {
                        _normalizedPoints.add(Offset(
                          (details.localPosition.dx / constraints.maxWidth)
                              .clamp(0, 1)
                              .toDouble(),
                          (details.localPosition.dy / constraints.maxHeight)
                              .clamp(0, 1)
                              .toDouble(),
                        ));
                      }),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(widget.imageBytes, fit: BoxFit.fill),
                          CustomPaint(
                            painter: _PolygonPainter(
                              List<Offset>.of(_normalizedPoints),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text('${_normalizedPoints.length} boundary points'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _normalizedPoints.isEmpty
                ? null
                : () => setState(() => _normalizedPoints.removeLast()),
            child: const Text('Undo'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _normalizedPoints.length < 3
                ? null
                : () => Navigator.pop(
                      context,
                      _normalizedPoints
                          .map((point) => [
                                point.dx * widget.sourceWidth,
                                point.dy * widget.sourceHeight,
                              ])
                          .toList(),
                    ),
            child: const Text('Confirm region'),
          ),
        ],
      );
}

class _PolygonPainter extends CustomPainter {
  final List<Offset> normalizedPoints;

  const _PolygonPainter(this.normalizedPoints);

  @override
  void paint(Canvas canvas, Size size) {
    if (normalizedPoints.isEmpty) return;
    final points = normalizedPoints
        .map((point) => Offset(point.dx * size.width, point.dy * size.height))
        .toList();
    final fill = Paint()
      ..color = const Color(0xFFFFC857).withValues(alpha: .16)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = const Color(0xFFFFC857)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    if (points.length >= 3) {
      path.close();
      canvas.drawPath(path, fill);
    }
    canvas.drawPath(path, stroke);
    final pointPaint = Paint()..color = const Color(0xFFFFC857);
    for (final point in points) {
      canvas.drawCircle(point, 4.5, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PolygonPainter oldDelegate) =>
      oldDelegate.normalizedPoints != normalizedPoints;
}

String _stageLabel(String stage) {
  const labels = {
    'QUEUED': 'Queued',
    'VALIDATING_IMAGE': 'Validating image',
    'READING_METADATA': 'Reading scale',
    'RESAMPLING': 'Normalizing physical scale',
    'TISSUE_MASKING': 'Finding tissue',
    'TILING': 'Tiling',
    'NUCLEAR_INFERENCE': 'Analyzing nuclei',
    'INSTANCE_RECONSTRUCTION': 'Reconstructing nuclei',
    'CALIBRATION': 'Calibrating classifications',
    'STITCHING': 'Stitching global cells',
    'PERSISTING_CELLS': 'Saving results',
    'AWAITING_TUMOR_CONTEXT': 'Awaiting tumor context',
    'SPATIAL_ANALYSIS': 'Computing spatial measurements',
    'TME_INTERPRETATION': 'Interpreting TME policy',
    'RENDERING_ARTIFACTS': 'Rendering review artifacts',
  };
  return labels[stage] ?? stage.replaceAll('_', ' ').toLowerCase();
}
