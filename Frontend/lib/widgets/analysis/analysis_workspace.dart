import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/analysis_v2.dart';

const _classNames = [
  'NEOPLASTIC',
  'INFLAMMATORY',
  'CONNECTIVE',
  'DEAD',
  'EPITHELIAL',
];

const _classColors = <String, Color>{
  'NEOPLASTIC': Color(0xFFFF6B81),
  'INFLAMMATORY': Color(0xFF55B7FF),
  'CONNECTIVE': Color(0xFF52D6A6),
  'DEAD': Color(0xFFB7B7C9),
  'EPITHELIAL': Color(0xFFC792EA),
  'UNCERTAIN': Color(0xFFFFC857),
};

enum _AnalysisSection { overview, nuclei, tumor, tme, report }

class _SectionDefinition {
  final _AnalysisSection section;
  final String title;
  final String description;
  final IconData icon;

  const _SectionDefinition(
    this.section,
    this.title,
    this.description,
    this.icon,
  );
}

const _sections = [
  _SectionDefinition(
    _AnalysisSection.overview,
    'Overview',
    'Quality and review summary',
    Icons.dashboard_customize_outlined,
  ),
  _SectionDefinition(
    _AnalysisSection.nuclei,
    'Nuclei',
    'Overlay and cell explorer',
    Icons.bubble_chart_outlined,
  ),
  _SectionDefinition(
    _AnalysisSection.tumor,
    'Tumor context',
    'Pathologist confirmation',
    Icons.fact_check_outlined,
  ),
  _SectionDefinition(
    _AnalysisSection.tme,
    'TME interpretation',
    'Spatial measurements and policy',
    Icons.hub_outlined,
  ),
  _SectionDefinition(
    _AnalysisSection.report,
    'Report',
    'Review and export findings',
    Icons.description_outlined,
  ),
];

class AnalysisWorkspace extends StatefulWidget {
  final AnalysisV2 analysis;
  final AsyncValue<List<CellInstanceV2>> cells;
  final AsyncValue<List<int>> overlay;
  final Future<void> Function() onRefresh;
  final Future<void> Function(String status) onUpdateTumor;
  final Future<void> Function() onDrawRegion;
  final Future<void> Function() onGenerateReport;
  final Future<void> Function() onDownloadReport;
  final bool updatingTumor;
  final bool generatingReport;
  final bool downloadingReport;
  final bool reportReady;

  const AnalysisWorkspace({
    super.key,
    required this.analysis,
    required this.cells,
    required this.overlay,
    required this.onRefresh,
    required this.onUpdateTumor,
    required this.onDrawRegion,
    required this.onGenerateReport,
    required this.onDownloadReport,
    required this.updatingTumor,
    required this.generatingReport,
    required this.downloadingReport,
    required this.reportReady,
  });

  @override
  State<AnalysisWorkspace> createState() => _AnalysisWorkspaceState();
}

class _AnalysisWorkspaceState extends State<AnalysisWorkspace> {
  _AnalysisSection _selectedSection = _AnalysisSection.overview;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B1020), Color(0xFF111426), Color(0xFF0C1420)],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 980;
          return Column(
            children: [
              _WorkspaceHeader(
                analysis: widget.analysis,
                onRefresh: widget.onRefresh,
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    desktop ? 24 : 16,
                    0,
                    desktop ? 24 : 16,
                    20,
                  ),
                  child: desktop
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _WorkspaceNavigation(
                              selected: _selectedSection,
                              onSelected: _select,
                            ),
                            const SizedBox(width: 18),
                            Expanded(child: _sectionContent()),
                          ],
                        )
                      : Column(
                          children: [
                            _SectionDropdown(
                              selected: _selectedSection,
                              onSelected: _select,
                            ),
                            const SizedBox(height: 12),
                            Expanded(child: _sectionContent()),
                          ],
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _select(_AnalysisSection section) {
    if (section == _selectedSection) return;
    setState(() => _selectedSection = section);
  }

  Widget _sectionContent() {
    final child = switch (_selectedSection) {
      _AnalysisSection.overview => _OverviewSection(
          key: const ValueKey('overview'),
          analysis: widget.analysis,
          onOpenSection: _select,
        ),
      _AnalysisSection.nuclei => _NucleiSection(
          key: const ValueKey('nuclei'),
          analysis: widget.analysis,
          cells: widget.cells,
          overlay: widget.overlay,
        ),
      _AnalysisSection.tumor => _TumorContextSection(
          key: const ValueKey('tumor'),
          analysis: widget.analysis,
          updating: widget.updatingTumor,
          onUpdate: widget.onUpdateTumor,
          onDrawRegion: widget.onDrawRegion,
        ),
      _AnalysisSection.tme => _TmeSection(
          key: const ValueKey('tme'),
          analysis: widget.analysis,
        ),
      _AnalysisSection.report => _ReportSection(
          key: const ValueKey('report'),
          analysis: widget.analysis,
          reportReady: widget.reportReady,
          generating: widget.generatingReport,
          downloading: widget.downloadingReport,
          onGenerate: widget.onGenerateReport,
          onDownload: widget.onDownloadReport,
        ),
    };
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: child,
      ),
    );
  }
}

class _WorkspaceHeader extends StatelessWidget {
  final AnalysisV2 analysis;
  final Future<void> Function() onRefresh;

  const _WorkspaceHeader({required this.analysis, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final id = analysis.id.length > 10
        ? '${analysis.id.substring(0, 10)}…'
        : analysis.id;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final heading = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B7CFF).withValues(alpha: .16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.biotech_outlined,
                      color: Color(0xFFAE9FFF),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Analysis workspace',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        Text(
                          'Run $id · reviewable clinical decision support',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.white54,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          );
          final summary = Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              _HeaderMetric(
                label: 'Detected',
                value: '${analysis.totalCells}',
                color: const Color(0xFFAE9FFF),
              ),
              _HeaderMetric(
                label: 'Accepted',
                value: '${analysis.acceptedCells}',
                color: const Color(0xFF52D6A6),
              ),
              _HeaderMetric(
                label: 'Uncertain',
                value: '${analysis.uncertainCells}',
                color: const Color(0xFFFFC857),
              ),
              _HeaderMetric(
                label: 'TME',
                value: _display(analysis.tmeState),
                color: _tmeColor(analysis.tmeState),
              ),
              IconButton.filledTonal(
                tooltip: 'Refresh analysis',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading,
                const SizedBox(height: 14),
                Align(alignment: Alignment.centerLeft, child: summary),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: heading),
              const SizedBox(width: 20),
              Flexible(child: summary),
            ],
          );
        },
      ),
    );
  }
}

class _HeaderMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _HeaderMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 92),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: .2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 11, color: Colors.white54)),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
}

class _WorkspaceNavigation extends StatelessWidget {
  final _AnalysisSection selected;
  final ValueChanged<_AnalysisSection> onSelected;

  const _WorkspaceNavigation({
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: 250,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF12182B).withValues(alpha: .92),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: .07)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Text(
                'REVIEW SECTIONS',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            ..._sections.map(
              (item) => _NavigationTile(
                key: Key('analysis-nav-${item.section.name}'),
                definition: item,
                selected: selected == item.section,
                onTap: () => onSelected(item.section),
              ),
            ),
            const Spacer(),
            const _SafetyNote(),
          ],
        ),
      );
}

class _NavigationTile extends StatelessWidget {
  final _SectionDefinition definition;
  final bool selected;
  final VoidCallback onTap;

  const _NavigationTile({
    super.key,
    required this.definition,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Material(
          color: selected
              ? const Color(0xFF8B7CFF).withValues(alpha: .15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    definition.icon,
                    size: 21,
                    color: selected ? const Color(0xFFAE9FFF) : Colors.white54,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          definition.title,
                          style: TextStyle(
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                            color: selected ? Colors.white : Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          definition.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white38,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selected)
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFFAE9FFF),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _SectionDropdown extends StatelessWidget {
  final _AnalysisSection selected;
  final ValueChanged<_AnalysisSection> onSelected;

  const _SectionDropdown({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) =>
      DropdownButtonFormField<_AnalysisSection>(
        key: const Key('analysis-section-dropdown'),
        initialValue: selected,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Review section',
          prefixIcon: Icon(Icons.view_quilt_outlined),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        items: _sections
            .map(
              (item) => DropdownMenuItem(
                value: item.section,
                child: Text(item.title),
              ),
            )
            .toList(),
        onChanged: (value) {
          if (value != null) onSelected(value);
        },
      );
}

class _SafetyNote extends StatelessWidget {
  const _SafetyNote();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF55B7FF).withValues(alpha: .07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFF55B7FF).withValues(alpha: .16),
          ),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.verified_user_outlined,
                size: 18, color: Color(0xFF55B7FF)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Decision support only. Final interpretation remains with the pathologist.',
                style: TextStyle(fontSize: 11, color: Colors.white60),
              ),
            ),
          ],
        ),
      );
}

class _SectionSurface extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String description;
  final IconData icon;
  final Widget child;
  final List<Widget> actions;

  const _SectionSurface({
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.icon,
    required this.child,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFF12182B).withValues(alpha: .94),
        child: CustomScrollView(
          key: PageStorageKey<String>('analysis-section-$title'),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              sliver: SliverToBoxAdapter(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final header = Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF8B7CFF).withValues(alpha: .14),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Icon(icon, color: const Color(0xFFAE9FFF)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                eyebrow.toUpperCase(),
                                style: const TextStyle(
                                  color: Color(0xFF8F83E8),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                title,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                description,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(color: Colors.white54),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                    if (constraints.maxWidth < 680 || actions.isEmpty) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          header,
                          if (actions.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Wrap(spacing: 8, runSpacing: 8, children: actions),
                          ],
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: header),
                        const SizedBox(width: 20),
                        Wrap(spacing: 8, runSpacing: 8, children: actions),
                      ],
                    );
                  },
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
              sliver: SliverToBoxAdapter(child: child),
            ),
          ],
        ),
      );
}

class _OverviewSection extends StatelessWidget {
  final AnalysisV2 analysis;
  final ValueChanged<_AnalysisSection> onOpenSection;

  const _OverviewSection({
    super.key,
    required this.analysis,
    required this.onOpenSection,
  });

  @override
  Widget build(BuildContext context) {
    final warnings = _stringList(analysis.quality['warnings']);
    final qualityStatus = (analysis.quality['status'] ?? 'UNKNOWN').toString();
    return _SectionSurface(
      eyebrow: 'Case dashboard',
      title: 'Review at a glance',
      description:
          'A concise summary of image readiness, nuclei evidence, and the current interpretation state.',
      icon: Icons.dashboard_customize_outlined,
      actions: [
        FilledButton.tonalIcon(
          key: const Key('overview-open-nuclei'),
          onPressed: () => onOpenSection(_AnalysisSection.nuclei),
          icon: const Icon(Icons.bubble_chart_outlined),
          label: const Text('Review nuclei'),
        ),
      ],
      child: Column(
        children: [
          _KpiGrid(analysis: analysis),
          const SizedBox(height: 16),
          _ResponsivePair(
            first: _Panel(
              title: 'Image quality and calibration',
              subtitle: 'Input suitability and physical-scale confidence',
              icon: Icons.image_search_outlined,
              accent: _qualityColor(qualityStatus),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _StatusPill(
                        label: 'QC ${_display(qualityStatus)}',
                        color: _qualityColor(qualityStatus),
                      ),
                      _StatusPill(
                        label: analysis.scaleTrusted
                            ? 'Scale verified'
                            : 'Scale unavailable',
                        color: analysis.scaleTrusted
                            ? const Color(0xFF52D6A6)
                            : const Color(0xFFFFC857),
                      ),
                      if (analysis.quality['he_stain_valid'] != null)
                        _StatusPill(
                          label: analysis.quality['he_stain_valid'] == true
                              ? 'H&E compatible'
                              : 'H&E unsupported',
                          color: analysis.quality['he_stain_valid'] == true
                              ? const Color(0xFF52D6A6)
                              : const Color(0xFFFF7675),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _KeyValueRow(
                    label: 'Scale source',
                    value: _display(analysis.scaleSource),
                  ),
                  _KeyValueRow(
                    label: 'Tissue coverage',
                    value: _percentage(analysis.quality['tissue_fraction']),
                  ),
                  if (analysis.quality['he_stain_score'] != null)
                    _KeyValueRow(
                      label: 'H&E compatibility score',
                      value: _percentage(analysis.quality['he_stain_score']),
                    ),
                  if (analysis.scaleTrusted)
                    _KeyValueRow(
                      label: 'Microns per pixel',
                      value:
                          '${analysis.imageMetadata['source_mpp_x']} × ${analysis.imageMetadata['source_mpp_y']}',
                    ),
                  const SizedBox(height: 8),
                  ExpansionTile(
                    key: const PageStorageKey<String>(
                      'overview-quality-warnings',
                    ),
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: 8),
                    title: Text(
                      warnings.isEmpty
                          ? 'No image-quality warnings'
                          : '${warnings.length} review warning${warnings.length == 1 ? '' : 's'}',
                    ),
                    children: [
                      if (warnings.isEmpty)
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'The supplied image passed the configured quality checks.',
                            style: TextStyle(color: Colors.white54),
                          ),
                        )
                      else
                        ...warnings.map(
                          (warning) => _BulletLine(_reasonLabel(warning)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            second: _ClassDistributionPanel(analysis: analysis),
          ),
          const SizedBox(height: 16),
          _ReviewPathPanel(analysis: analysis, onOpenSection: onOpenSection),
        ],
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  final AnalysisV2 analysis;

  const _KpiGrid({required this.analysis});

  @override
  Widget build(BuildContext context) {
    final total = math.max(analysis.totalCells, 1);
    final acceptedRate = analysis.acceptedCells / total;
    final uncertainRate = analysis.uncertainCells / total;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 900
            ? 4
            : width >= 520
                ? 2
                : 1;
        const gap = 12.0;
        final tileWidth = (width - (gap * (columns - 1))) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            _KpiCard(
              width: tileWidth,
              label: 'Detected nuclei',
              value: '${analysis.totalCells}',
              note: 'After cross-tile stitching',
              icon: Icons.scatter_plot_outlined,
              color: const Color(0xFFAE9FFF),
            ),
            _KpiCard(
              width: tileWidth,
              label: 'Accepted',
              value: '${analysis.acceptedCells}',
              note: '${(acceptedRate * 100).toStringAsFixed(1)}% of detections',
              icon: Icons.task_alt_rounded,
              color: const Color(0xFF52D6A6),
            ),
            _KpiCard(
              width: tileWidth,
              label: 'Uncertain',
              value: '${analysis.uncertainCells}',
              note: '${(uncertainRate * 100).toStringAsFixed(1)}% needs review',
              icon: Icons.help_outline_rounded,
              color: const Color(0xFFFFC857),
            ),
            _KpiCard(
              width: tileWidth,
              label: 'TME state',
              value: _display(analysis.tmeState),
              note: analysis.scaleTrusted
                  ? 'Physical scale available'
                  : 'Physical scale required',
              icon: Icons.hub_outlined,
              color: _tmeColor(analysis.tmeState),
            ),
          ],
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  final double width;
  final String label;
  final String value;
  final String note;
  final IconData icon;
  final Color color;

  const _KpiCard({
    required this.width,
    required this.label,
    required this.value,
    required this.note,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .035),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: .07)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  Text(note,
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      );
}

class _ClassDistributionPanel extends StatelessWidget {
  final AnalysisV2 analysis;

  const _ClassDistributionPanel({required this.analysis});

  @override
  Widget build(BuildContext context) {
    final maxCount = _classNames.fold<int>(
      1,
      (current, name) => math.max(current, _intValue(analysis.counts[name])),
    );
    return _Panel(
      title: 'Cell distribution',
      subtitle: 'Detected nuclei by biological class',
      icon: Icons.bar_chart_rounded,
      accent: const Color(0xFF55B7FF),
      child: Column(
        children: _classNames.map((name) {
          final count = _intValue(analysis.counts[name]);
          final accepted = _intValue(analysis.acceptedCounts[name]);
          return Padding(
            padding: const EdgeInsets.only(bottom: 13),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _classColors[name],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_display(name))),
                    Text(
                      '$count',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$accepted accepted',
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    value: count / maxCount,
                    backgroundColor: Colors.white.withValues(alpha: .05),
                    valueColor: AlwaysStoppedAnimation(_classColors[name]),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ReviewPathPanel extends StatelessWidget {
  final AnalysisV2 analysis;
  final ValueChanged<_AnalysisSection> onOpenSection;

  const _ReviewPathPanel({
    required this.analysis,
    required this.onOpenSection,
  });

  @override
  Widget build(BuildContext context) {
    final tumorStatus =
        (analysis.tumor['status'] ?? 'INDETERMINATE').toString();
    final steps = [
      _ReviewStep(
        'Image ready',
        'QC ${_display((analysis.quality['status'] ?? 'UNKNOWN').toString())}',
        Icons.image_outlined,
        true,
        _AnalysisSection.overview,
      ),
      _ReviewStep(
        'Nuclei review',
        '${analysis.uncertainCells} uncertain detections',
        Icons.bubble_chart_outlined,
        analysis.uncertainCells == 0,
        _AnalysisSection.nuclei,
      ),
      _ReviewStep(
        'Tumor context',
        tumorStatus == 'INDETERMINATE'
            ? 'Pathologist confirmation needed'
            : _display(tumorStatus),
        Icons.fact_check_outlined,
        tumorStatus != 'INDETERMINATE',
        _AnalysisSection.tumor,
      ),
      _ReviewStep(
        'Interpretation',
        _display(analysis.tmeState),
        Icons.hub_outlined,
        !{'NOT_ASSESSABLE', 'INDETERMINATE'}.contains(analysis.tmeState),
        _AnalysisSection.tme,
      ),
    ];
    return _Panel(
      title: 'Review pathway',
      subtitle:
          'Move through each checkpoint without rerunning nuclei inference',
      icon: Icons.route_outlined,
      accent: const Color(0xFF8B7CFF),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontal = constraints.maxWidth >= 720;
          if (!horizontal) {
            return Column(
              children: steps
                  .map((step) => _ReviewStepTile(
                        step: step,
                        onTap: () => onOpenSection(step.section),
                      ))
                  .toList(),
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: steps
                .map(
                  (step) => Expanded(
                    child: _ReviewStepTile(
                      step: step,
                      onTap: () => onOpenSection(step.section),
                    ),
                  ),
                )
                .toList(),
          );
        },
      ),
    );
  }
}

class _ReviewStep {
  final String title;
  final String note;
  final IconData icon;
  final bool complete;
  final _AnalysisSection section;

  const _ReviewStep(
    this.title,
    this.note,
    this.icon,
    this.complete,
    this.section,
  );
}

class _ReviewStepTile extends StatelessWidget {
  final _ReviewStep step;
  final VoidCallback onTap;

  const _ReviewStepTile({required this.step, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(4),
        child: Material(
          color: Colors.white.withValues(alpha: .025),
          borderRadius: BorderRadius.circular(13),
          child: InkWell(
            borderRadius: BorderRadius.circular(13),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(13),
              child: Row(
                children: [
                  Icon(
                    step.complete ? Icons.check_circle_rounded : step.icon,
                    color: step.complete
                        ? const Color(0xFF52D6A6)
                        : const Color(0xFFFFC857),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(step.title,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                          step.note,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Color(0x73FFFFFF), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _NucleiSection extends StatefulWidget {
  final AnalysisV2 analysis;
  final AsyncValue<List<CellInstanceV2>> cells;
  final AsyncValue<List<int>> overlay;

  const _NucleiSection({
    super.key,
    required this.analysis,
    required this.cells,
    required this.overlay,
  });

  @override
  State<_NucleiSection> createState() => _NucleiSectionState();
}

class _NucleiSectionState extends State<_NucleiSection> {
  String _classFilter = 'ALL';
  String _acceptanceFilter = 'ALL';
  String _sort = 'CONFIDENCE';
  final TransformationController _overlayController =
      TransformationController();

  @override
  void dispose() {
    _overlayController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _SectionSurface(
        eyebrow: 'Cell-level evidence',
        title: 'Nuclei explorer',
        description:
            'Pan and zoom the overlay, filter detections, and inspect calibrated cell-level evidence.',
        icon: Icons.bubble_chart_outlined,
        child: Column(
          children: [
            _NucleiFilterBar(
              classFilter: _classFilter,
              acceptanceFilter: _acceptanceFilter,
              sort: _sort,
              onClassChanged: (value) => setState(() => _classFilter = value),
              onAcceptanceChanged: (value) =>
                  setState(() => _acceptanceFilter = value),
              onSortChanged: (value) => setState(() => _sort = value),
              onReset: () => setState(() {
                _classFilter = 'ALL';
                _acceptanceFilter = 'ALL';
                _sort = 'CONFIDENCE';
              }),
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final overlay = _OverlayViewer(
                  overlay: widget.overlay,
                  controller: _overlayController,
                  onZoomIn: () => _zoom(1.25),
                  onZoomOut: () => _zoom(.8),
                  onReset: () => _overlayController.value = Matrix4.identity(),
                );
                final explorer = _CellExplorer(
                  cells: widget.cells,
                  classFilter: _classFilter,
                  acceptanceFilter: _acceptanceFilter,
                  sort: _sort,
                );
                if (constraints.maxWidth >= 900) {
                  return SizedBox(
                    height: 610,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 6, child: overlay),
                        const SizedBox(width: 14),
                        Expanded(flex: 4, child: explorer),
                      ],
                    ),
                  );
                }
                return Column(
                  children: [
                    SizedBox(height: 420, child: overlay),
                    const SizedBox(height: 14),
                    SizedBox(height: 560, child: explorer),
                  ],
                );
              },
            ),
          ],
        ),
      );

  void _zoom(double factor) {
    final current = _overlayController.value.getMaxScaleOnAxis();
    final next = (current * factor).clamp(1.0, 6.0);
    _overlayController.value = Matrix4.diagonal3Values(next, next, 1);
  }
}

class _NucleiFilterBar extends StatelessWidget {
  final String classFilter;
  final String acceptanceFilter;
  final String sort;
  final ValueChanged<String> onClassChanged;
  final ValueChanged<String> onAcceptanceChanged;
  final ValueChanged<String> onSortChanged;
  final VoidCallback onReset;

  const _NucleiFilterBar({
    required this.classFilter,
    required this.acceptanceFilter,
    required this.sort,
    required this.onClassChanged,
    required this.onAcceptanceChanged,
    required this.onSortChanged,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: .06)),
        ),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              key: const Key('nuclei-class-filter'),
              width: 190,
              child: DropdownButtonFormField<String>(
                key: ValueKey('nuclei-class-filter-$classFilter'),
                initialValue: classFilter,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Cell class',
                  prefixIcon: Icon(Icons.category_outlined, size: 20),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: ['ALL', ..._classNames]
                    .map((value) => DropdownMenuItem(
                          value: value,
                          child: Text(
                              value == 'ALL' ? 'All classes' : _display(value)),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) onClassChanged(value);
                },
              ),
            ),
            SizedBox(
              key: const Key('nuclei-acceptance-filter'),
              width: 190,
              child: DropdownButtonFormField<String>(
                key: ValueKey('nuclei-acceptance-filter-$acceptanceFilter'),
                initialValue: acceptanceFilter,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Review status',
                  prefixIcon: Icon(Icons.rule_outlined, size: 20),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: const [
                  DropdownMenuItem(value: 'ALL', child: Text('All statuses')),
                  DropdownMenuItem(value: 'ACCEPTED', child: Text('Accepted')),
                  DropdownMenuItem(
                      value: 'UNCERTAIN', child: Text('Uncertain')),
                  DropdownMenuItem(value: 'REJECTED', child: Text('Rejected')),
                ],
                onChanged: (value) {
                  if (value != null) onAcceptanceChanged(value);
                },
              ),
            ),
            SizedBox(
              key: const Key('nuclei-sort'),
              width: 190,
              child: DropdownButtonFormField<String>(
                key: ValueKey('nuclei-sort-$sort'),
                initialValue: sort,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Sort cells',
                  prefixIcon: Icon(Icons.sort_rounded, size: 20),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: const [
                  DropdownMenuItem(
                      value: 'CONFIDENCE',
                      child: Text('Confidence, high first')),
                  DropdownMenuItem(value: 'CLASS', child: Text('Cell class')),
                  DropdownMenuItem(
                      value: 'AREA', child: Text('Area, large first')),
                ],
                onChanged: (value) {
                  if (value != null) onSortChanged(value);
                },
              ),
            ),
            TextButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.filter_alt_off_outlined),
              label: const Text('Reset filters'),
            ),
          ],
        ),
      );
}

class _OverlayViewer extends StatelessWidget {
  final AsyncValue<List<int>> overlay;
  final TransformationController controller;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;

  const _OverlayViewer({
    required this.overlay,
    required this.controller,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) => _Panel(
        title: 'Nuclei overlay',
        subtitle: 'Use touch, mouse, or the controls to inspect the field',
        icon: Icons.zoom_in_map_outlined,
        accent: const Color(0xFF8B7CFF),
        trailing: Wrap(
          spacing: 4,
          children: [
            IconButton(
              tooltip: 'Zoom out',
              onPressed: onZoomOut,
              icon: const Icon(Icons.remove_rounded),
            ),
            IconButton(
              tooltip: 'Reset zoom',
              onPressed: onReset,
              icon: const Icon(Icons.center_focus_strong_outlined),
            ),
            IconButton(
              tooltip: 'Zoom in',
              onPressed: onZoomIn,
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        footer: const Padding(
          padding: EdgeInsets.only(top: 10),
          child: Text(
            'Filters apply to the cell explorer. The rendered overlay remains an auditable full-field artifact.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ),
        child: Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              color: const Color(0xFF080B13),
              child: overlay.when(
                data: (bytes) => bytes.isEmpty
                    ? const _CenteredMessage(
                        icon: Icons.image_not_supported_outlined,
                        title: 'Overlay unavailable',
                        message:
                            'No rendered overlay was returned for this run.',
                      )
                    : InteractiveViewer(
                        transformationController: controller,
                        minScale: 1,
                        maxScale: 6,
                        boundaryMargin: const EdgeInsets.all(80),
                        child: Center(
                          child: Image.memory(
                            Uint8List.fromList(bytes),
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                          ),
                        ),
                      ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => _CenteredMessage(
                  icon: Icons.broken_image_outlined,
                  title: 'Overlay unavailable',
                  message: '$error',
                ),
              ),
            ),
          ),
        ),
      );
}

class _CellExplorer extends StatelessWidget {
  final AsyncValue<List<CellInstanceV2>> cells;
  final String classFilter;
  final String acceptanceFilter;
  final String sort;

  const _CellExplorer({
    required this.cells,
    required this.classFilter,
    required this.acceptanceFilter,
    required this.sort,
  });

  @override
  Widget build(BuildContext context) => cells.when(
        loading: () => const _Panel(
          title: 'Cell explorer',
          subtitle: 'Loading calibrated detections',
          icon: Icons.table_rows_outlined,
          accent: Color(0xFF55B7FF),
          child: Expanded(child: Center(child: CircularProgressIndicator())),
        ),
        error: (error, _) => _Panel(
          title: 'Cell explorer',
          subtitle: 'The cell table could not be loaded',
          icon: Icons.table_rows_outlined,
          accent: const Color(0xFFFF6B81),
          child: Expanded(
            child: _CenteredMessage(
              icon: Icons.error_outline_rounded,
              title: 'Cell table unavailable',
              message: '$error',
            ),
          ),
        ),
        data: (items) {
          final filtered = items.where((cell) {
            final classMatches =
                classFilter == 'ALL' || cell.className == classFilter;
            final acceptanceMatches = acceptanceFilter == 'ALL' ||
                cell.acceptance == acceptanceFilter;
            return classMatches && acceptanceMatches;
          }).toList();
          switch (sort) {
            case 'CLASS':
              filtered.sort((a, b) => a.className.compareTo(b.className));
            case 'AREA':
              filtered.sort((a, b) => b.areaPx.compareTo(a.areaPx));
            default:
              filtered.sort((a, b) => b.confidence.compareTo(a.confidence));
          }
          return _Panel(
            title: 'Cell explorer',
            subtitle: '${filtered.length} of ${items.length} cells shown',
            icon: Icons.table_rows_outlined,
            accent: const Color(0xFF55B7FF),
            child: Expanded(
              child: filtered.isEmpty
                  ? const _CenteredMessage(
                      icon: Icons.filter_alt_off_outlined,
                      title: 'No matching cells',
                      message: 'Change or reset the active filters.',
                    )
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: Colors.white.withValues(alpha: .05),
                      ),
                      itemBuilder: (context, index) {
                        final cell = filtered[index];
                        return _CellRow(
                          cell: cell,
                          onTap: () => _showCellDetails(context, cell),
                        );
                      },
                    ),
            ),
          );
        },
      );
}

class _CellRow extends StatelessWidget {
  final CellInstanceV2 cell;
  final VoidCallback onTap;

  const _CellRow({required this.cell, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = _classColors[cell.className] ?? Colors.grey;
    final uncertain = cell.acceptance == 'UNCERTAIN';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _display(cell.className),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'x ${cell.xPx.toStringAsFixed(1)} · y ${cell.yPx.toStringAsFixed(1)} · ${cell.areaPx.toStringAsFixed(0)} px²',
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${(cell.confidence * 100).toStringAsFixed(1)}%',
                    style: TextStyle(color: color, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    _display(cell.acceptance),
                    style: TextStyle(
                      color:
                          uncertain ? const Color(0xFFFFC857) : Colors.white38,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: Colors.white30),
            ],
          ),
        ),
      ),
    );
  }
}

void _showCellDetails(BuildContext context, CellInstanceV2 cell) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF151B2E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => FractionallySizedBox(
      heightFactor: .78,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _classColors[cell.className],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _display(cell.className),
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                _StatusPill(
                  label: _display(cell.acceptance),
                  color: cell.acceptance == 'ACCEPTED'
                      ? const Color(0xFF52D6A6)
                      : const Color(0xFFFFC857),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MiniMetric(
                    label: 'Confidence',
                    value: cell.confidence.toStringAsFixed(4)),
                _MiniMetric(
                    label: 'Entropy', value: cell.entropy.toStringAsFixed(4)),
                _MiniMetric(
                    label: 'Top-1/2 margin',
                    value: cell.margin.toStringAsFixed(4)),
                _MiniMetric(
                    label: 'Area',
                    value: '${cell.areaPx.toStringAsFixed(1)} px²'),
              ],
            ),
            const SizedBox(height: 22),
            Text('Calibrated class probabilities',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  ...List.generate(_classNames.length, (index) {
                    final probability = index < cell.probabilities.length
                        ? cell.probabilities[index]
                        : 0.0;
                    final name = _classNames[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 13),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(_display(name))),
                              Text(
                                  '${(probability * 100).toStringAsFixed(2)}%'),
                            ],
                          ),
                          const SizedBox(height: 6),
                          LinearProgressIndicator(
                            minHeight: 7,
                            borderRadius: BorderRadius.circular(999),
                            value: probability.clamp(0, 1),
                            backgroundColor:
                                Colors.white.withValues(alpha: .05),
                            valueColor:
                                AlwaysStoppedAnimation(_classColors[name]),
                          ),
                        ],
                      ),
                    );
                  }),
                  const Divider(height: 26),
                  _KeyValueRow(
                    label: 'Pixel coordinates',
                    value:
                        '${cell.xPx.toStringAsFixed(2)}, ${cell.yPx.toStringAsFixed(2)}',
                  ),
                  _KeyValueRow(
                    label: 'Physical coordinates',
                    value: cell.xUm == null
                        ? 'Unavailable'
                        : '${cell.xUm!.toStringAsFixed(2)}, ${cell.yUm!.toStringAsFixed(2)} µm',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _TumorContextSection extends StatefulWidget {
  final AnalysisV2 analysis;
  final bool updating;
  final Future<void> Function(String status) onUpdate;
  final Future<void> Function() onDrawRegion;

  const _TumorContextSection({
    super.key,
    required this.analysis,
    required this.updating,
    required this.onUpdate,
    required this.onDrawRegion,
  });

  @override
  State<_TumorContextSection> createState() => _TumorContextSectionState();
}

class _TumorContextSectionState extends State<_TumorContextSection> {
  late String _selection;

  @override
  void initState() {
    super.initState();
    _selection = _currentStatus;
  }

  @override
  void didUpdateWidget(covariant _TumorContextSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.analysis.tumor['status'] != widget.analysis.tumor['status']) {
      _selection = _currentStatus;
    }
  }

  String get _currentStatus {
    final value =
        (widget.analysis.tumor['status'] ?? 'INDETERMINATE').toString();
    return {'PRESENT', 'ABSENT', 'INDETERMINATE'}.contains(value)
        ? value
        : 'INDETERMINATE';
  }

  @override
  Widget build(BuildContext context) {
    final evidence =
        (widget.analysis.tumor['evidence_source'] ?? 'UNCONFIRMED_NUCLEI_ONLY')
            .toString();
    final current = _currentStatus;
    final changed = current != _selection;
    return _SectionSurface(
      eyebrow: 'Pathologist checkpoint',
      title: 'Tumor context',
      description:
          'Confirm the tissue context used for spatial interpretation. Updating this does not rerun the neural model.',
      icon: Icons.fact_check_outlined,
      child: _ResponsivePair(
        ratio: const [6, 4],
        first: _Panel(
          title: 'Clinical confirmation',
          subtitle: 'Select the context supported by your review',
          icon: Icons.assignment_turned_in_outlined,
          accent: const Color(0xFF8B7CFF),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KeyedSubtree(
                key: const Key('tumor-context-dropdown'),
                child: DropdownButtonFormField<String>(
                  key: ValueKey('tumor-context-$_selection'),
                  initialValue: _selection,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Tumor context decision',
                    helperText:
                        'This decision controls whether physical TME policy can run.',
                    prefixIcon: Icon(Icons.medical_information_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'PRESENT',
                      child: Text('Confirm tumor in whole ROI'),
                    ),
                    DropdownMenuItem(
                      value: 'ABSENT',
                      child: Text('Confirm no tumor'),
                    ),
                    DropdownMenuItem(
                      value: 'INDETERMINATE',
                      child: Text('Leave unconfirmed'),
                    ),
                  ],
                  onChanged: widget.updating
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _selection = value);
                          }
                        },
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    key: const Key('apply-tumor-context'),
                    onPressed: !changed || widget.updating
                        ? null
                        : () => widget.onUpdate(_selection),
                    icon: widget.updating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(widget.updating
                        ? 'Saving context…'
                        : 'Apply confirmation'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('draw-tumor-region'),
                    onPressed: widget.updating ? null : widget.onDrawRegion,
                    icon: const Icon(Icons.polyline_outlined),
                    label: const Text('Draw/confirm tumor region'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const _InfoPanel(
                icon: Icons.memory_outlined,
                title: 'Stored cells are reused',
                message:
                    'Changing tumor context recalculates spatial measurements and the TME policy from persisted cells. Nuclei inference is not repeated.',
              ),
            ],
          ),
        ),
        second: _Panel(
          title: 'Current provenance',
          subtitle: 'Auditable context attached to this analysis',
          icon: Icons.history_edu_outlined,
          accent: current == 'PRESENT'
              ? const Color(0xFF52D6A6)
              : current == 'ABSENT'
                  ? const Color(0xFF55B7FF)
                  : const Color(0xFFFFC857),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StatusPill(
                label: _display(current),
                color: current == 'PRESENT'
                    ? const Color(0xFF52D6A6)
                    : current == 'ABSENT'
                        ? const Color(0xFF55B7FF)
                        : const Color(0xFFFFC857),
              ),
              const SizedBox(height: 16),
              _KeyValueRow(label: 'Evidence source', value: _display(evidence)),
              _KeyValueRow(
                label: 'Region mode',
                value: _display(
                    (widget.analysis.tumor['tumor_region_mode'] ?? 'NONE')
                        .toString()),
              ),
              _KeyValueRow(
                label: 'Confirmed by',
                value: (widget.analysis.tumor['confirmed_by_user_id'] ??
                        'Not confirmed')
                    .toString(),
              ),
              _KeyValueRow(
                label: 'Confirmed at',
                value: (widget.analysis.tumor['confirmed_at'] ?? 'Not recorded')
                    .toString(),
              ),
              const Divider(height: 26),
              Text(
                current == 'PRESENT'
                    ? 'Physical TME interpretation may proceed when scale and evidence requirements are met.'
                    : current == 'ABSENT'
                        ? 'TME is correctly reported as not applicable.'
                        : 'Nuclei evidence remains available, but tumor-dependent interpretation is withheld.',
                style: const TextStyle(color: Colors.white60),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TmeSection extends StatelessWidget {
  final AnalysisV2 analysis;

  const _TmeSection({super.key, required this.analysis});

  @override
  Widget build(BuildContext context) {
    final state = analysis.tmeState;
    final reasons = _stringList(analysis.tme['reason_codes']);
    final spatial = analysis.spatial;
    final color = _tmeColor(state);
    return _SectionSurface(
      eyebrow: 'Policy output',
      title: 'TME interpretation',
      description:
          'Review the canonical state, the supporting spatial measurements, and every limitation carried into the result.',
      icon: Icons.hub_outlined,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  color.withValues(alpha: .18),
                  color.withValues(alpha: .04),
                ],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: color.withValues(alpha: .3)),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stateWidget = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('CURRENT STATE',
                        style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        )),
                    const SizedBox(height: 8),
                    Text(
                      _display(state),
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                color: color,
                                fontWeight: FontWeight.w800,
                              ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _tmeHeadline(state),
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                );
                final explanation = Text(
                  _tmeExplanation(state),
                  style: const TextStyle(color: Colors.white60, height: 1.45),
                );
                if (constraints.maxWidth < 700) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      stateWidget,
                      const SizedBox(height: 16),
                      explanation
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(flex: 4, child: stateWidget),
                    Container(
                      width: 1,
                      height: 76,
                      color: Colors.white.withValues(alpha: .1),
                    ),
                    const SizedBox(width: 24),
                    Expanded(flex: 6, child: explanation),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          _ResponsivePair(
            ratio: const [6, 4],
            first: _SpatialMeasurementsPanel(
              spatial: spatial,
              scaleTrusted: analysis.scaleTrusted,
            ),
            second: _Panel(
              title: 'Policy and limitations',
              subtitle: 'Why this state was produced',
              icon: Icons.policy_outlined,
              accent: color,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _KeyValueRow(
                    label: 'Policy version',
                    value: (analysis.tme['policy_version'] ?? 'Not supplied')
                        .toString(),
                  ),
                  _KeyValueRow(
                    label: 'Measurement version',
                    value: (analysis.tme['input_measurement_version'] ??
                            'Not supplied')
                        .toString(),
                  ),
                  const SizedBox(height: 8),
                  ExpansionTile(
                    key: const PageStorageKey<String>(
                      'tme-policy-reason-codes',
                    ),
                    initiallyExpanded: true,
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                      reasons.isEmpty
                          ? 'No limiting reason codes'
                          : '${reasons.length} reason code${reasons.length == 1 ? '' : 's'}',
                    ),
                    children: reasons.isEmpty
                        ? [
                            const _BulletLine(
                                'All configured preconditions were available.'),
                          ]
                        : reasons
                            .map((reason) => _BulletLine(_reasonLabel(reason)))
                            .toList(),
                  ),
                  if (state == 'NOT_ASSESSABLE' && !analysis.scaleTrusted)
                    const _InfoPanel(
                      icon: Icons.next_plan_outlined,
                      title: 'Recommended next step',
                      message:
                          'Rerun with verified scanner MPP or enter a validated MPP during upload. Existing nuclei detections remain reviewable.',
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpatialMeasurementsPanel extends StatelessWidget {
  final Map<String, dynamic>? spatial;
  final bool scaleTrusted;

  const _SpatialMeasurementsPanel({
    required this.spatial,
    required this.scaleTrusted,
  });

  @override
  Widget build(BuildContext context) => _Panel(
        title: 'Spatial measurements',
        subtitle: 'Physical-coordinate metrics from accepted cells',
        icon: Icons.straighten_outlined,
        accent: const Color(0xFF55B7FF),
        child: !scaleTrusted || spatial == null
            ? const _InfoPanel(
                icon: Icons.lock_clock_outlined,
                title: 'Physical measurements unavailable',
                message:
                    'Micron distances and density/mm² are withheld until a trusted physical scale and valid tumor context are available.',
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final itemWidth = width >= 560 ? (width - 10) / 2 : width;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _MetricBox(
                        width: itemWidth,
                        label: 'Neo → immune mean',
                        value:
                            '${_metric(spatial!['neo_to_immune_mean_um'])} µm',
                      ),
                      _MetricBox(
                        width: itemWidth,
                        label: 'Neo → immune median',
                        value:
                            '${_metric(spatial!['neo_to_immune_median_um'])} µm',
                      ),
                      _MetricBox(
                        width: itemWidth,
                        label: 'Neoplastic density',
                        value: '${_metric(spatial!['neo_density_mm2'])} /mm²',
                      ),
                      _MetricBox(
                        width: itemWidth,
                        label: 'Inflammatory density',
                        value:
                            '${_metric(spatial!['immune_density_mm2'])} /mm²',
                      ),
                      _MetricBox(
                        width: itemWidth,
                        label: 'Immune : neoplastic ratio',
                        value: _metric(spatial!['immune_to_neo_ratio']),
                      ),
                      _MetricBox(
                        width: itemWidth,
                        label: 'Tissue area',
                        value: '${_metric(spatial!['tissue_area_mm2'])} mm²',
                      ),
                    ],
                  );
                },
              ),
      );
}

class _ReportSection extends StatelessWidget {
  final AnalysisV2 analysis;
  final bool reportReady;
  final bool generating;
  final bool downloading;
  final Future<void> Function() onGenerate;
  final Future<void> Function() onDownload;

  const _ReportSection({
    super.key,
    required this.analysis,
    required this.reportReady,
    required this.generating,
    required this.downloading,
    required this.onGenerate,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    const sections = [
      ('Clinical information', 'Clinician-supplied history and case context.'),
      ('Image quality and scale', 'QC findings and physical-scale provenance.'),
      ('AI nuclei analysis', 'Detected nuclei and biological class counts.'),
      ('Accepted and uncertain counts', 'Calibrated acceptance breakdown.'),
      ('Tumor-context provenance', 'Human confirmation and region mode.'),
      ('Spatial measurements', 'Available physical TME measurements.'),
      ('TME interpretation', 'Canonical state and policy version.'),
      ('Limitations and uncertainty', 'Technical and evidence constraints.'),
      ('Model provenance', 'Bundle identity and analysis traceability.'),
    ];
    return _SectionSurface(
      eyebrow: 'Clinical handoff',
      title: 'Structured report',
      description:
          'Review what will be included, then generate a deterministic PDF from the persisted analysis.',
      icon: Icons.description_outlined,
      actions: [
        _StatusPill(
          label: reportReady ? 'PDF ready' : 'Not generated',
          color:
              reportReady ? const Color(0xFF52D6A6) : const Color(0xFFFFC857),
        ),
      ],
      child: _ResponsivePair(
        ratio: const [6, 4],
        first: _Panel(
          title: 'Report contents',
          subtitle: 'Nine auditable sections generated from structured facts',
          icon: Icons.format_list_numbered_rounded,
          accent: const Color(0xFF55B7FF),
          child: Column(
            children: sections.indexed.map((entry) {
              final index = entry.$1;
              final section = entry.$2;
              return ExpansionTile(
                key: PageStorageKey<String>('report-section-$index'),
                tilePadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 15,
                  backgroundColor:
                      const Color(0xFF8B7CFF).withValues(alpha: .14),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Color(0xFFAE9FFF),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                title: Text(section.$1),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(46, 0, 12, 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        section.$2,
                        style: const TextStyle(color: Colors.white54),
                      ),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
        second: _Panel(
          title: 'Generate and export',
          subtitle: 'Create the report when the review is ready',
          icon: Icons.picture_as_pdf_outlined,
          accent: const Color(0xFF8B7CFF),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ReportReadinessRow(
                label: 'Analysis complete',
                ready: analysis.isComplete,
              ),
              _ReportReadinessRow(
                label: 'Tumor context recorded',
                ready: analysis.tumor.isNotEmpty,
              ),
              const _ReportReadinessRow(
                label: 'Limitations carried forward',
                ready: true,
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                key: const Key('generate-report'),
                onPressed: generating ? null : onGenerate,
                icon: generating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_stories_outlined),
                label: Text(generating
                    ? 'Generating…'
                    : reportReady
                        ? 'Refresh structured PDF'
                        : 'Generate structured PDF'),
              ),
              if (reportReady) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  key: const Key('download-report'),
                  onPressed: downloading ? null : onDownload,
                  icon: downloading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_rounded),
                  label: Text(downloading ? 'Saving…' : 'Save PDF to device'),
                ),
              ],
              const SizedBox(height: 18),
              const _InfoPanel(
                icon: Icons.shield_outlined,
                title: 'Deterministic clinical facts',
                message:
                    'Automated wording cannot change counts, establish tumor presence, alter the TME state, or predict treatment response.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportReadinessRow extends StatelessWidget {
  final String label;
  final bool ready;

  const _ReportReadinessRow({required this.label, required this.ready});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Icon(
              ready ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: 19,
              color: ready ? const Color(0xFF52D6A6) : Colors.white30,
            ),
            const SizedBox(width: 9),
            Expanded(child: Text(label)),
          ],
        ),
      );
}

class _ResponsivePair extends StatelessWidget {
  final Widget first;
  final Widget second;
  final List<int> ratio;

  const _ResponsivePair({
    required this.first,
    required this.second,
    this.ratio = const [1, 1],
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 800) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [first, const SizedBox(height: 14), second],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: ratio[0], child: first),
              const SizedBox(width: 14),
              Expanded(flex: ratio[1], child: second),
            ],
          );
        },
      );
}

class _Panel extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final Widget child;
  final Widget? trailing;
  final Widget? footer;

  const _Panel({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.child,
    this.trailing,
    this.footer,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .035),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: .07)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .11),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: accent, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 18),
            child,
            if (footer != null) footer!,
          ],
        ),
      );
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: .32)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

class _KeyValueRow extends StatelessWidget {
  final String label;
  final String value;

  const _KeyValueRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: Color(0x73FFFFFF)),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
}

class _MiniMetric extends StatelessWidget {
  final String label;
  final String value;

  const _MiniMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 130),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .035),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: .06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(color: Color(0x73FFFFFF), fontSize: 11)),
            const SizedBox(height: 3),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

class _MetricBox extends StatelessWidget {
  final double width;
  final String label;
  final String value;

  const _MetricBox({
    required this.width,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF55B7FF).withValues(alpha: .055),
          borderRadius: BorderRadius.circular(13),
          border:
              Border.all(color: const Color(0xFF55B7FF).withValues(alpha: .12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(color: Color(0x73FFFFFF), fontSize: 11)),
            const SizedBox(height: 4),
            Text(value,
                style: const TextStyle(
                    color: Color(0xFF8ACBFF),
                    fontWeight: FontWeight.w700,
                    fontSize: 17)),
          ],
        ),
      );
}

class _InfoPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _InfoPanel({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF55B7FF).withValues(alpha: .055),
          borderRadius: BorderRadius.circular(13),
          border:
              Border.all(color: const Color(0xFF55B7FF).withValues(alpha: .12)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: const Color(0xFF55B7FF)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(message,
                      style:
                          const TextStyle(color: Colors.white54, height: 1.35)),
                ],
              ),
            ),
          ],
        ),
      );
}

class _BulletLine extends StatelessWidget {
  final String text;

  const _BulletLine(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 7),
              child: CircleAvatar(
                radius: 2.5,
                backgroundColor: Color(0xFFFFC857),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(text, style: const TextStyle(color: Colors.white60)),
            ),
          ],
        ),
      );
}

class _CenteredMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 38, color: Colors.white30),
              const SizedBox(height: 10),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0x73FFFFFF))),
            ],
          ),
        ),
      );
}

Color _qualityColor(String status) => switch (status) {
      'PASS' => const Color(0xFF52D6A6),
      'FAIL' => const Color(0xFFFF6B81),
      _ => const Color(0xFFFFC857),
    };

Color _tmeColor(String state) => switch (state) {
      'HOT' => const Color(0xFFFF6B81),
      'COLD' => const Color(0xFF55B7FF),
      'EXCLUDED' => const Color(0xFFFF9F43),
      'INDETERMINATE' => const Color(0xFFFFC857),
      'NOT_ASSESSABLE' => const Color(0xFFFFC857),
      'NOT_APPLICABLE' => const Color(0xFF91A0B8),
      _ => Colors.grey,
    };

int _intValue(dynamic value) => value is num ? value.toInt() : 0;

String _percentage(dynamic value) => value is num
    ? '${(value.toDouble() * 100).toStringAsFixed(1)}%'
    : 'Unavailable';

String _metric(dynamic value) =>
    value is num ? value.toDouble().toStringAsFixed(2) : 'N/A';

List<String> _stringList(dynamic value) =>
    value is List ? value.map((item) => item.toString()).toList() : const [];

String _tmeHeadline(String state) {
  const labels = {
    'HOT': 'Findings meet the configured HOT spatial policy',
    'COLD': 'Findings meet the configured COLD spatial policy',
    'EXCLUDED': 'Findings meet the configured EXCLUDED spatial policy',
    'INDETERMINATE': 'Available evidence does not support a stable category',
    'NOT_ASSESSABLE': 'A physical TME category was not calculated',
    'NOT_APPLICABLE': 'TME categorization is not applicable to this context',
  };
  return labels[state] ?? 'TME interpretation unavailable';
}

String _tmeExplanation(String state) {
  if (state == 'NOT_ASSESSABLE') {
    return 'HOT, COLD, and EXCLUDED depend on calibrated micron-space measurements. '
        'The system preserves the technical limitation instead of inferring a category from pixel distances.';
  }
  if (state == 'NOT_APPLICABLE') {
    return 'The current tumor context does not permit a physical TME category.';
  }
  if (state == 'INDETERMINATE') {
    return 'The measurements or accepted-cell evidence are insufficient for the configured policy. '
        'Pathologist review remains required.';
  }
  return 'This is a policy-based decision-support result derived from accepted cells and persisted spatial measurements; it is not a diagnosis.';
}

String _reasonLabel(String reason) {
  const labels = {
    'PHYSICAL_SCALE_UNKNOWN': 'Physical scale not provided',
    'POSSIBLE_BLUR': 'Possible image blur',
    'POSSIBLE_EXPOSURE_ISSUE': 'Possible exposure issue',
    'IMAGE_QUALITY_FAILED': 'Image quality requirements not met',
    'IMAGE_DIMENSIONS_TOO_SMALL': 'Image dimensions too small',
    'INSUFFICIENT_TISSUE': 'Insufficient tissue detected',
    'UNSUPPORTED_NON_HE_IMAGE':
        'Image is not compatible with an H&E-stained biopsy sample',
    'GROSS_BLUR': 'Severe image blur',
    'GROSS_EXPOSURE': 'Severe exposure issue',
    'TUMOR_NOT_CONFIRMED': 'Tumor context not confirmed',
    'CLINICIAN_CONFIRMED_NO_TUMOR': 'Clinician confirmed no tumor',
    'SPATIAL_MEASUREMENTS_UNAVAILABLE': 'Spatial measurements unavailable',
    'INSUFFICIENT_ACCEPTED_NEOPLASTIC_EVIDENCE':
        'Insufficient accepted neoplastic cells',
    'INSUFFICIENT_ACCEPTED_IMMUNE_EVIDENCE':
        'Insufficient accepted inflammatory cells',
    'NEAREST_NEIGHBOR_DISTANCE_UNAVAILABLE':
        'Nearest-neighbor distance unavailable',
  };
  return labels[reason] ?? _display(reason);
}

String _display(String value) => value
    .toLowerCase()
    .split('_')
    .map((part) =>
        part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');
