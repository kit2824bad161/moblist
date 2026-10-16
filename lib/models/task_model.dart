import '../core/constants/app_constants.dart';

class TaskModel {
  final String id;
  final String name;
  final String taskType; // CAMERA or MANUAL
  final bool isDefault;
  final String iconName;
  final int targetSeconds;
  final DateTime createdAt;

  TaskModel({
    required this.id,
    required this.name,
    required this.taskType,
    required this.isDefault,
    required this.iconName,
    this.targetSeconds = AppConstants.dailyTargetSeconds,
    required this.createdAt,
  });

  bool get isCameraTask => taskType == AppConstants.taskTypeCamera;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'task_type': taskType,
      'is_default': isDefault ? 1 : 0,
      'icon_name': iconName,
      'target_seconds': targetSeconds,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory TaskModel.fromMap(Map<String, dynamic> map) {
    return TaskModel(
      id: map['id'] as String,
      name: map['name'] as String,
      taskType: map['task_type'] as String,
      isDefault: (map['is_default'] as int) == 1,
      iconName: map['icon_name'] as String,
      targetSeconds: map['target_seconds'] as int? ?? AppConstants.dailyTargetSeconds,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  TaskModel copyWith({
    String? id,
    String? name,
    String? taskType,
    bool? isDefault,
    String? iconName,
    int? targetSeconds,
    DateTime? createdAt,
  }) {
    return TaskModel(
      id: id ?? this.id,
      name: name ?? this.name,
      taskType: taskType ?? this.taskType,
      isDefault: isDefault ?? this.isDefault,
      iconName: iconName ?? this.iconName,
      targetSeconds: targetSeconds ?? this.targetSeconds,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
