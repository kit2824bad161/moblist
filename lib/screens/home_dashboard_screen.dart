import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/constants/app_colors.dart';
import '../models/daily_task_record_model.dart';
import '../providers/moblist_provider.dart';
import '../widgets/emergency_status_banner.dart';
import '../widgets/task_card.dart';
import 'active_session_screen.dart';
import 'add_task_dialog.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

class HomeDashboardScreen extends StatefulWidget {
  const HomeDashboardScreen({super.key});

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  int _currentNavIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _currentNavIndex,
        children: const [
          _HomeDashboardView(),
          HistoryScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentNavIndex,
        onTap: (index) {
          setState(() => _currentNavIndex = index);
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_filled),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.insights_rounded),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _HomeDashboardView extends StatelessWidget {
  const _HomeDashboardView();

  void _openTaskSession(BuildContext context, DailyTaskRecordModel record) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ActiveSessionScreen(record: record),
      ),
    );
  }

  void _showAddTaskDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const AddTaskDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MobListProvider>();

    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final todayFormatted = DateFormat('EEEE, MMMM d').format(DateTime.now());
    final totalCompleted = provider.completedRequiredTasksCount;
    final totalRequired = provider.totalRequiredTasksCount;
    final totalProductiveMinutes = provider.totalTodayProductiveSeconds ~/ 60;
    final alarmService = provider.alarmService;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.bolt_rounded, color: AppColors.primary, size: 26),
            SizedBox(width: 8),
            Text(
              'MOBLIST',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Day',
            onPressed: () => provider.refresh(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Task', style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () => _showAddTaskDialog(context),
      ),
      body: RefreshIndicator(
        onRefresh: () => provider.refresh(),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            // Dynamic Accountability Alarm Notification Banner (if active)
            if (alarmService.isAlarmActive)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.alarmBg.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.alarm, width: 1.5),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.alarm_on_rounded, color: AppColors.alarm, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '⚠️ ${provider.formattedAlarmTime} Accountability Alarm',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Required tasks incomplete (${alarmService.incompleteTasks.join(", ")}). '
                            'Alarm is temporarily silenced while you are in MobList.',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // Today's Progress Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      todayFormatted.toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Today\'s Progress',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: totalCompleted == totalRequired && totalRequired > 0
                        ? AppColors.completedBg.withOpacity(0.3)
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: totalCompleted == totalRequired && totalRequired > 0
                          ? AppColors.completed
                          : AppColors.surfaceBorder,
                    ),
                  ),
                  child: Text(
                    '$totalCompleted / $totalRequired Tasks Completed',
                    style: TextStyle(
                      color: totalCompleted == totalRequired && totalRequired > 0
                          ? AppColors.completed
                          : AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Total productive time widget
            Text(
              'Total Productive Time: $totalProductiveMinutes minutes',
              style: const TextStyle(
                color: AppColors.accent,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 12),

            // Emergency Days Banner
            const EmergencyStatusBanner(),

            const SizedBox(height: 12),

            // Required Tasks Section Title
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'REQUIRED ACTIVITIES (10 MIN TARGET)',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
            ),

            // List of Required Tasks
            ...provider.todayRecords
                .where((r) => r.task?.isDefault ?? false)
                .map((record) {
              return TaskCard(
                record: record,
                onStart: () => _openTaskSession(context, record),
              );
            }),

            const SizedBox(height: 16),

            // Custom Tasks Section Title
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'CUSTOM ACTIVITIES (10 MIN TARGET)',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _showAddTaskDialog(context),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Add', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                ),
              ],
            ),

            // List of Custom Tasks
            if (provider.todayRecords.where((r) => !(r.task?.isDefault ?? false)).isEmpty)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.surfaceBorder),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 20, color: AppColors.textSecondary),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'No custom tasks yet. Tap "+ Add Task" to create manual timer tasks (e.g. Gym, Study, Assignment).',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              )
            else
              ...provider.todayRecords
                  .where((r) => !(r.task?.isDefault ?? false))
                  .map((record) {
                return TaskCard(
                  record: record,
                  onStart: () => _openTaskSession(context, record),
                );
              }),

            const SizedBox(height: 80), // Padding for FAB
          ],
        ),
      ),
    );
  }
}
