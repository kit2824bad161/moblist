import 'daily_task_record_model.dart';

class DailySummaryModel {
  final String date;
  final int totalProductiveSeconds;
  final int completedTasksCount;
  final int totalTasksCount;
  final bool isEmergencyDay;
  final List<DailyTaskRecordModel> taskRecords;

  DailySummaryModel({
    required this.date,
    required this.totalProductiveSeconds,
    required this.completedTasksCount,
    required this.totalTasksCount,
    required this.isEmergencyDay,
    required this.taskRecords,
  });

  int get totalMinutes => totalProductiveSeconds ~/ 60;
  double get totalHours => totalProductiveSeconds / 3600.0;

  double get completionRate {
    if (totalTasksCount == 0) return 0.0;
    return (completedTasksCount / totalTasksCount).clamp(0.0, 1.0);
  }
}
