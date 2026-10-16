import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/constants/app_colors.dart';
import '../models/daily_summary_model.dart';
import '../providers/moblist_provider.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _selectedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
  DailySummaryModel? _summary;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    setState(() => _isLoading = true);
    final provider = context.read<MobListProvider>();
    final summary = await provider.getSummaryForDate(_selectedDate);
    if (mounted) {
      setState(() {
        _summary = summary;
        _isLoading = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final current = DateTime.tryParse(_selectedDate) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2025),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.primary,
              surface: AppColors.surface,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final formatted = DateFormat('yyyy-MM-dd').format(picked);
      setState(() => _selectedDate = formatted);
      await _loadSummary();
    }
  }

  @override
  Widget build(BuildContext context) {
    final parsedDate = DateTime.tryParse(_selectedDate) ?? DateTime.now();
    final displayDateStr = DateFormat('EEEE, MMMM d, yyyy').format(parsedDate);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('History & Analytics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month_rounded, color: AppColors.primary),
            tooltip: 'Select Date',
            onPressed: _pickDate,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Selected Date Picker Bar
                  InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.surfaceBorder),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.event_note_rounded, color: AppColors.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Viewing History for',
                                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                                ),
                                Text(
                                  displayDateStr,
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down, color: AppColors.textSecondary),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Emergency Day Badge if applicable
                  if (_summary?.isEmergencyDay ?? false)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.emergencyBg.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.emergency),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.shield_rounded, color: AppColors.emergency),
                          SizedBox(width: 10),
                          Text(
                            '🛑 Excused / Emergency Day',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Stat Summary Cards (Total Minutes, Total Hours, Completion)
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricCard(
                          title: 'Productive Time',
                          value: '${_summary?.totalMinutes ?? 0} min',
                          subtitle: '${(_summary?.totalHours ?? 0).toStringAsFixed(1)} hrs',
                          icon: Icons.timer_rounded,
                          accentColor: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildMetricCard(
                          title: 'Tasks Finished',
                          value: '${_summary?.completedTasksCount ?? 0} / ${_summary?.totalTasksCount ?? 0}',
                          subtitle: '${((_summary?.completionRate ?? 0) * 100).toInt()}% completed',
                          icon: Icons.task_alt_rounded,
                          accentColor: AppColors.completed,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Task-by-task visual breakdown chart
                  const Text(
                    'Productive Minutes per Task',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildBarChart(),

                  const SizedBox(height: 24),

                  // Detailed Task List for the Day
                  const Text(
                    'Daily Task Breakdown',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_summary?.taskRecords.isEmpty ?? true)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'No records found for this date.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    )
                  else
                    ...(_summary!.taskRecords.map((record) {
                      final minutes = record.accumulatedSeconds ~/ 60;
                      final seconds = record.accumulatedSeconds % 60;
                      final isCompleted = record.isCompleted;

                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isCompleted
                                ? AppColors.completed.withOpacity(0.5)
                                : AppColors.surfaceBorder,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isCompleted
                                  ? Icons.check_circle_rounded
                                  : Icons.cancel_outlined,
                              color: isCompleted ? AppColors.completed : AppColors.alarm,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                record.task?.name ?? 'Task',
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              '$minutes min ${seconds > 0 ? "$seconds s" : ""}',
                              style: TextStyle(
                                color: isCompleted ? AppColors.completed : AppColors.textSecondary,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      );
                    })),
                ],
              ),
            ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              Icon(icon, color: accentColor, size: 18),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(color: accentColor, fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildBarChart() {
    final records = _summary?.taskRecords ?? [];
    if (records.isEmpty) {
      return const SizedBox(height: 180, child: Center(child: Text('No data for chart')));
    }

    final barGroups = <BarChartGroupData>[];
    for (int i = 0; i < records.length; i++) {
      final r = records[i];
      final mins = (r.accumulatedSeconds / 60.0);
      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: mins,
              color: r.isCompleted ? AppColors.completed : AppColors.primary,
              width: 16,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            ),
          ],
        ),
      );
    }

    return Container(
      height: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: 30, // Reference 30 min ceiling
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final taskName = records[group.x].task?.name ?? '';
                return BarTooltipItem(
                  '$taskName\n${rod.toY.toStringAsFixed(1)} min',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (val, meta) {
                  final idx = val.toInt();
                  if (idx >= 0 && idx < records.length) {
                    final name = records[idx].task?.name ?? '';
                    final shortName = name.length > 5 ? '${name.substring(0, 5)}..' : name;
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        shortName,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
                      ),
                    );
                  }
                  return const SizedBox();
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (val, meta) {
                  if (val % 10 == 0) {
                    return Text(
                      '${val.toInt()}m',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
                    );
                  }
                  return const SizedBox();
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 10,
            getDrawingHorizontalLine: (val) => FlLine(
              color: AppColors.surfaceBorder.withOpacity(0.5),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: barGroups,
        ),
      ),
    );
  }
}
