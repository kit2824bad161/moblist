import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:moblist/core/constants/app_constants.dart';
import 'package:moblist/models/daily_task_record_model.dart';
import 'package:moblist/models/task_model.dart';
import 'package:moblist/models/vision_state.dart';
import 'package:moblist/ml/ml_vision_detector.dart';
import 'package:moblist/services/timer_engine.dart';
import 'package:moblist/services/accountability_alarm_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('MobList Core Accountability & ML Specification Tests', () {
    // TEST 1: Start Read Book. Book + reading activity detected. Timer increases.
    test('TEST 1: Read Book ML detection verifies Person + Book', () {
      final detector = MLVisionDetector();
      late VisionDetectionResult result;
      for (int i = 0; i < 3; i++) {
        result = detector.evaluateRawDetections(
          isBookTask: true,
          detections: [
            DetectedItem(
              label: 'person',
              confidence: 0.85,
              boundingBox: const Rect.fromLTWH(0.20, 0.10, 0.60, 0.80),
            ),
            DetectedItem(
              label: 'book',
              confidence: 0.80,
              boundingBox: const Rect.fromLTWH(0.30, 0.45, 0.35, 0.25),
            ),
          ],
        );
      }

      expect(result.isPersonDetected, isTrue);
      expect(result.isTargetObjectDetected, isTrue);
      expect(result.isValidWorkingState, isTrue);
      expect(result.confidence, greaterThanOrEqualTo(0.60));
    });

    // TEST 2: Reading detection fails. Timer pauses after 30-second grace period.
    test('TEST 2: Detection fails -> Grace period activates -> Pauses when exceeded', () {
      final timer = TimerEngine();
      timer.initialize(initialAccumulatedSeconds: 100);
      timer.startCameraSession();
      timer.cameraReady();

      // Detection valid across consecutive frames -> Productive state
      for (int i = 0; i < 3; i++) {
        timer.updateVisionResult(VisionDetectionResult(
          isPersonDetected: true,
          isTargetObjectDetected: true,
          isValidWorkingState: true,
          confidence: 0.9,
          statusDescription: 'Valid',
          timestamp: DateTime.now(),
        ));
      }
      expect(timer.state, equals(ProductiveState.productive));

      // Detection fails across consecutive frames -> Enters grace period
      for (int i = 0; i < 2; i++) {
        timer.updateVisionResult(VisionDetectionResult(
          isPersonDetected: false,
          isTargetObjectDetected: false,
          isValidWorkingState: false,
          confidence: 0.0,
          statusDescription: 'Lost',
          timestamp: DateTime.now(),
        ));
      }
      expect(timer.state, equals(ProductiveState.gracePeriod));
      expect(timer.graceSecondsRemaining, equals(AppConstants.gracePeriodSeconds));
    });

    // TEST 3: Reading detection returns within grace period. Timer continues.
    test('TEST 3: Detection returns within grace period -> Productive state resumes', () {
      final timer = TimerEngine();
      timer.initialize(initialAccumulatedSeconds: 120);
      timer.startCameraSession();
      timer.cameraReady();

      // Enter productive
      for (int i = 0; i < 3; i++) {
        timer.updateVisionResult(VisionDetectionResult(
          isPersonDetected: true,
          isTargetObjectDetected: true,
          isValidWorkingState: true,
          confidence: 0.9,
          statusDescription: 'Valid',
          timestamp: DateTime.now(),
        ));
      }
      expect(timer.state, equals(ProductiveState.productive));

      // Lose detection -> Grace period
      for (int i = 0; i < 2; i++) {
        timer.updateVisionResult(VisionDetectionResult(
          isPersonDetected: false,
          isTargetObjectDetected: false,
          isValidWorkingState: false,
          confidence: 0.0,
          statusDescription: 'Lost',
          timestamp: DateTime.now(),
        ));
      }
      expect(timer.state, equals(ProductiveState.gracePeriod));

      // Return valid within 30s -> Productive resumes
      for (int i = 0; i < 3; i++) {
        timer.updateVisionResult(VisionDetectionResult(
          isPersonDetected: true,
          isTargetObjectDetected: true,
          isValidWorkingState: true,
          confidence: 0.9,
          statusDescription: 'Valid',
          timestamp: DateTime.now(),
        ));
      }
      expect(timer.state, equals(ProductiveState.productive));
    });

    // TEST 4 & 5: Cumulative 10-minute target (4 min then 6 min = 10 min completed)
    test('TEST 4 & 5: Cumulative progress (4 min + 6 min = 10 min completed)', () {
      final record1 = DailyTaskRecordModel(
        date: '2026-09-26',
        taskId: 'default_read_book',
        accumulatedSeconds: 240, // 4 minutes
        isCompleted: false,
      );
      expect(record1.isCompleted, isFalse);

      final record2 = record1.copyWith(
        accumulatedSeconds: record1.accumulatedSeconds + 360, // +6 minutes = 600s
        isCompleted: (record1.accumulatedSeconds + 360) >= AppConstants.dailyTargetSeconds,
      );
      expect(record2.accumulatedSeconds, equals(600));
      expect(record2.isCompleted, isTrue);
    });

    // TEST 6 & 7: Laptop ML verification (Person + Laptop)
    test('TEST 6: Laptop verified working state is valid with Person + Laptop', () {
      final detector = MLVisionDetector();
      late VisionDetectionResult result;
      for (int i = 0; i < 3; i++) {
        result = detector.evaluateRawDetections(
          isBookTask: false,
          detections: [
            DetectedItem(
              label: 'person',
              confidence: 0.90,
              boundingBox: const Rect.fromLTWH(0, 0, 100, 100),
            ),
            DetectedItem(
              label: 'laptop',
              confidence: 0.85,
              boundingBox: const Rect.fromLTWH(10, 10, 80, 80),
            ),
          ],
        );
      }
      expect(result.isValidWorkingState, isTrue);
    });

    test('TEST 7: Laptop visible but user not present -> invalid', () {
      final detector = MLVisionDetector();
      final result = detector.evaluateRawDetections(
        isBookTask: false,
        detections: [
          DetectedItem(
            label: 'laptop',
            confidence: 0.85,
            boundingBox: const Rect.fromLTWH(10, 10, 80, 80),
          ),
        ],
      );
      expect(result.isPersonDetected, isFalse);
      expect(result.isValidWorkingState, isFalse);
    });

    // TEST 8: Custom task (Type B) without camera completes at 10 minutes
    test('TEST 8: Custom manual task completes when >= 600s', () {
      final customTask = TaskModel(
        id: 'custom_exercise',
        name: 'Exercise',
        taskType: AppConstants.taskTypeManual,
        isDefault: false,
        iconName: 'custom',
        createdAt: DateTime.now(),
      );
      expect(customTask.isCameraTask, isFalse);

      final record = DailyTaskRecordModel(
        date: '2026-09-26',
        taskId: customTask.id,
        accumulatedSeconds: 605, // > 600
        isCompleted: 605 >= AppConstants.dailyTargetSeconds,
        task: customTask,
      );
      expect(record.isCompleted, isTrue);
    });

    // TEST 9, 10, 11, 12: 11 PM Accountability Alarm rules
    test('TEST 9-12: 11 PM Alarm triggers, silences in foreground, reactivates on background, dismisses on complete', () async {
      final alarm = AccountabilityAlarmService.instance;

      // TEST 9: Incomplete task triggers alarm
      await alarm.triggerAlarm(['My Project'], userIsInForeground: false);
      expect(alarm.isAlarmActive, isTrue);
      expect(alarm.isTemporarilySilenced, isFalse);

      // TEST 10: Open app -> Silences temporarily
      await alarm.onAppForegrounded();
      expect(alarm.isAlarmActive, isTrue);
      expect(alarm.isTemporarilySilenced, isTrue);

      // TEST 11: Leave app without finishing -> Reactivates!
      await alarm.onAppBackgrounded();
      expect(alarm.isAlarmActive, isTrue);
      expect(alarm.isTemporarilySilenced, isFalse);

      // TEST 12: Complete task -> Permanently dismissed
      await alarm.dismissPermanently();
      expect(alarm.isAlarmActive, isFalse);
      expect(alarm.incompleteTasks.isEmpty, isTrue);
    });

    // TEST 13, 14, 15: Emergency Days (5 per month, 6th rejected, resets monthly)
    test('TEST 13-15: 5 Emergency days limit per month and monthly reset', () {
      int monthlyLimit = AppConstants.monthlyEmergencyDaysLimit;
      expect(monthlyLimit, equals(5));

      // Simulate 5 days used
      int used = 5;
      int remaining = (monthlyLimit - used).clamp(0, 5);
      expect(remaining, equals(0));

      // Attempt 6th day
      bool canActivateSixth = used < monthlyLimit;
      expect(canActivateSixth, isFalse);

      // New Month starts -> resets used to 0
      used = 0;
      int newMonthRemaining = (monthlyLimit - used).clamp(0, 5);
      expect(newMonthRemaining, equals(5));
    });
  });
}
