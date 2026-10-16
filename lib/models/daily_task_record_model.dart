import 'task_model.dart';

class DailyTaskRecordModel {
  final int? id;
  final String date; // YYYY-MM-DD
  final String taskId;
  final int accumulatedSeconds;
  final int accumulatedProductiveMs;
  final DateTime? productiveStartedAt;
  final DateTime? lastValidActivityAt;
  final String timerState;
  final bool isCompleted;
  final DateTime? completedAt;
  final TaskModel? task;

  DailyTaskRecordModel({
    this.id,
    required this.date,
    required this.taskId,
    required this.accumulatedSeconds,
    this.accumulatedProductiveMs = 0,
    this.productiveStartedAt,
    this.lastValidActivityAt,
    this.timerState = 'idle',
    required this.isCompleted,
    this.completedAt,
    this.task,
  });

  /// Total calculated productive milliseconds right now, strictly based on timestamps
  int get totalCalculatedMs {
    int currentBurst = 0;
    if (timerState == 'productive' && productiveStartedAt != null) {
      currentBurst = DateTime.now().difference(productiveStartedAt!).inMilliseconds;
      if (currentBurst < 0) currentBurst = 0;
    }
    return (accumulatedProductiveMs > 0 ? accumulatedProductiveMs : accumulatedSeconds * 1000) + currentBurst;
  }

  int get currentCalculatedSeconds => totalCalculatedMs ~/ 1000;

  double get progressRatio {
    final target = task?.targetSeconds ?? 600;
    if (target <= 0) return 1.0;
    return (currentCalculatedSeconds / target).clamp(0.0, 1.0);
  }

  String get formattedProgress {
    final curMinutes = currentCalculatedSeconds ~/ 60;
    final curSecs = currentCalculatedSeconds % 60;
    final targetMinutes = (task?.targetSeconds ?? 600) ~/ 60;
    final targetSecs = (task?.targetSeconds ?? 600) % 60;
    return '${curMinutes.toString().padLeft(2, '0')}:${curSecs.toString().padLeft(2, '0')} / '
        '${targetMinutes.toString().padLeft(2, '0')}:${targetSecs.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toMap() {
    final effectiveMs = accumulatedProductiveMs > 0
        ? accumulatedProductiveMs
        : accumulatedSeconds * 1000;
    final calcSecs = effectiveMs ~/ 1000;
    return {
      if (id != null) 'id': id,
      'date': date,
      'task_id': taskId,
      'accumulated_seconds': calcSecs,
      'accumulated_productive_ms': effectiveMs,
      'productive_started_at': productiveStartedAt?.toIso8601String(),
      'last_valid_activity_at': lastValidActivityAt?.toIso8601String(),
      'timer_state': timerState,
      'is_completed': isCompleted ? 1 : 0,
      'completed_at': completedAt?.toIso8601String(),
    };
  }

  factory DailyTaskRecordModel.fromMap(Map<String, dynamic> map, {TaskModel? task}) {
    final rawSecs = map['accumulated_seconds'] as int? ?? 0;
    final rawMs = map['accumulated_productive_ms'] as int? ?? (rawSecs * 1000);
    return DailyTaskRecordModel(
      id: map['id'] as int?,
      date: map['date'] as String,
      taskId: map['task_id'] as String,
      accumulatedSeconds: rawMs ~/ 1000,
      accumulatedProductiveMs: rawMs,
      productiveStartedAt: map['productive_started_at'] != null
          ? DateTime.tryParse(map['productive_started_at'] as String)
          : null,
      lastValidActivityAt: map['last_valid_activity_at'] != null
          ? DateTime.tryParse(map['last_valid_activity_at'] as String)
          : null,
      timerState: map['timer_state'] as String? ?? 'idle',
      isCompleted: (map['is_completed'] as int? ?? 0) == 1,
      completedAt: map['completed_at'] != null
          ? DateTime.tryParse(map['completed_at'] as String)
          : null,
      task: task,
    );
  }

  DailyTaskRecordModel copyWith({
    int? id,
    String? date,
    String? taskId,
    int? accumulatedSeconds,
    int? accumulatedProductiveMs,
    DateTime? productiveStartedAt,
    DateTime? lastValidActivityAt,
    String? timerState,
    bool? isCompleted,
    DateTime? completedAt,
    TaskModel? task,
  }) {
    final effectiveMs = accumulatedProductiveMs ??
        (accumulatedSeconds != null ? accumulatedSeconds * 1000 : this.accumulatedProductiveMs);
    return DailyTaskRecordModel(
      id: id ?? this.id,
      date: date ?? this.date,
      taskId: taskId ?? this.taskId,
      accumulatedSeconds: accumulatedSeconds ?? (effectiveMs ~/ 1000),
      accumulatedProductiveMs: effectiveMs,
      productiveStartedAt: productiveStartedAt ?? this.productiveStartedAt,
      lastValidActivityAt: lastValidActivityAt ?? this.lastValidActivityAt,
      timerState: timerState ?? this.timerState,
      isCompleted: isCompleted ?? this.isCompleted,
      completedAt: completedAt ?? this.completedAt,
      task: task ?? this.task,
    );
  }
}
