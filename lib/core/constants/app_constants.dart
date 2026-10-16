class AppConstants {
  // Required task minimum productive seconds (10 minutes)
  static const int dailyTargetSeconds = 600;

  // ML Detection Grace Period (30 seconds)
  static const int gracePeriodSeconds = 30;

  // Monthly Emergency Days limit
  static const int monthlyEmergencyDaysLimit = 5;

  // Alarm Hour (11 PM = 23:00)
  static const int accountabilityAlarmHour = 23;
  static const int accountabilityAlarmMinute = 0;

  // Task Types
  static const String taskTypeCamera = 'CAMERA';
  static const String taskTypeManual = 'MANUAL';

  // Default Required Task IDs
  static const String defaultTaskIdReadBook = 'default_read_book';
  static const String defaultTaskIdLeetCode = 'default_leetcode';
  static const String defaultTaskIdMyProject = 'default_my_project';
  static const String defaultTaskIdSpeakIt = 'default_speakit';
}
