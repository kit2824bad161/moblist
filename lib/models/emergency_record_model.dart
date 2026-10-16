class EmergencyRecordModel {
  final int? id;
  final String date; // YYYY-MM-DD
  final String yearMonth; // YYYY-MM
  final DateTime activatedAt;

  EmergencyRecordModel({
    this.id,
    required this.date,
    required this.yearMonth,
    required this.activatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'date': date,
      'year_month': yearMonth,
      'activated_at': activatedAt.toIso8601String(),
    };
  }

  factory EmergencyRecordModel.fromMap(Map<String, dynamic> map) {
    return EmergencyRecordModel(
      id: map['id'] as int?,
      date: map['date'] as String,
      yearMonth: map['year_month'] as String,
      activatedAt: DateTime.parse(map['activated_at'] as String),
    );
  }
}
