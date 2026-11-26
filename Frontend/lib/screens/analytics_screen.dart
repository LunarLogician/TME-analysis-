import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../providers/analytics_provider.dart';
import '../models/analytics.dart';
import '../providers/auth_provider.dart';
import 'package:go_router/go_router.dart';

class AnalyticsScreen extends ConsumerWidget {
  final bool showBackButton;
  const AnalyticsScreen({super.key, this.showBackButton = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsAsync = ref.watch(analyticsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Platform Analytics',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: showBackButton
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go('/dashboard'),
              )
            : null,
        actions: showBackButton
            ? null
            : [
                IconButton(
                  icon: const Icon(Icons.person),
                  onPressed: () => context.push('/profile'),
                ),
                IconButton(
                  icon: const Icon(Icons.logout),
                  onPressed: () =>
                      ref.read(authControllerProvider.notifier).logout(),
                ),
              ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F172A), Color(0xFF1E1B4B)],
          ),
        ),
        child: analyticsAsync.when(
          data: (data) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(analyticsProvider);
            },
            color: const Color(0xFF6C5CE7),
            child: _buildDashboard(context, data),
          ),
          loading: () => const Center(
            child: CircularProgressIndicator(color: Color(0xFF6C5CE7)),
          ),
          error: (error, stack) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Unable to load platform analytics',
                    style: TextStyle(color: Colors.redAccent)),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () => ref.invalidate(analyticsProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDashboard(BuildContext context, AnalyticsSummary data) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  'Total Sessions',
                  data.totalSessions.toString(),
                  Icons.science,
                  const Color(0xFF6C5CE7),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricCard(
                  'Active Clinicians',
                  data.activeClinicians.toString(),
                  Icons.people,
                  const Color(0xFF00B8D9),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'TME Phenotype Distribution',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 250,
            child: _buildPieChart(data.phenotypeDistribution),
          ),
          const SizedBox(height: 32),
          const Text(
            'Sessions Timeline',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 250,
            child: _buildBarChart(data.sessionsPerMonth),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildMetricCard(
      String title, String value, IconData icon, Color color) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 12),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPieChart(PhenotypeDistribution dist) {
    final hot = dist.hotCount.toDouble();
    final cold = dist.coldCount.toDouble();
    final excluded = dist.excludedCount.toDouble();
    final total = hot + cold + excluded;

    if (total == 0) {
      return const Center(
        child: Text(
          'No phenotype data available',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 40,
        sections: [
          PieChartSectionData(
            color: Colors.redAccent,
            value: hot,
            title: '${((hot / total) * 100).toStringAsFixed(1)}%',
            radius: 50,
            titleStyle: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
            badgeWidget: _buildBadge('HOT'),
            badgePositionPercentageOffset: 1.1,
          ),
          PieChartSectionData(
            color: Colors.blueAccent,
            value: cold,
            title: '${((cold / total) * 100).toStringAsFixed(1)}%',
            radius: 50,
            titleStyle: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
            badgeWidget: _buildBadge('COLD'),
            badgePositionPercentageOffset: 1.1,
          ),
          PieChartSectionData(
            color: Colors.orangeAccent,
            value: excluded,
            title: '${((excluded / total) * 100).toStringAsFixed(1)}%',
            radius: 50,
            titleStyle: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
            badgeWidget: _buildBadge('EXCLUDED'),
            badgePositionPercentageOffset: 1.1,
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildBarChart(Map<String, int> sessionsPerMonth) {
    if (sessionsPerMonth.isEmpty) {
      return const Center(
        child: Text(
          'No timeline data available',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    final entries = sessionsPerMonth.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    // Get last 6 months max
    final displayEntries =
        entries.length > 6 ? entries.sublist(entries.length - 6) : entries;

    double maxY = 0;
    for (var entry in displayEntries) {
      if (entry.value > maxY) maxY = entry.value.toDouble();
    }
    maxY = (maxY * 1.2).ceilToDouble();
    if (maxY < 5) maxY = 5;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            tooltipBgColor: Colors.black87,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                '${rod.toY.toInt()} Sessions',
                const TextStyle(color: Colors.white),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (value.toInt() >= 0 &&
                    value.toInt() < displayEntries.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      '${displayEntries[value.toInt()].key.split('-')[1]}/${displayEntries[value.toInt()].key.split('-')[0].substring(2)}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
              reservedSize: 30,
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, meta) {
                if (value % 1 == 0) {
                  return Text(
                    value.toInt().toString(),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval:
              (maxY / 5).ceilToDouble() > 0 ? (maxY / 5).ceilToDouble() : 1,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.white.withValues(alpha: 0.1),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(
          show: false,
        ),
        barGroups: List.generate(displayEntries.length, (index) {
          return BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: displayEntries[index].value.toDouble(),
                color: const Color(0xFF6C5CE7),
                width: 16,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}
