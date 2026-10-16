class ProductiveSessionModel {
  final int? id;
  final String taskId;
  final String date;
  final DateTime startTime;
  final DateTime? endTime;
  final int productiveSeconds;
  final String sessionType; // CAMERA or MANUAL

  ProductiveSessionModel({
    this.id,
    required this.taskId,
    required this.date,
    required this.startTime,
    this.endTime,
    required this.productiveSeconds,
    required this.sessionType,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'task_id': taskId,
      'date': date,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'productive_seconds': productiveSeconds,
      'session_type': sessionType,
    };
  }

  factory ProductiveSessionModel.fromMap(Map<String, dynamic> map) {
    return ProductiveSessionModel(
      id: map['id'] as int?,
      taskId: map['task_id'] as String,
      date: map['date'] as String,
      startTime: DateTime.parse(map['start_time'] as String),
      endTime: map['end_time'] != null
          ? DateTime.tryParse(map['end_time'] as String)
          : null,
      productiveSeconds: map['productive_seconds'] as int? ?? 0,
      sessionType: map['session_type'] as String? ?? 'CAMERA',
    );
  }
}
