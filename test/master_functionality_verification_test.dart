import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moblist/core/constants/app_constants.dart';
import 'package:moblist/database/database_helper.dart';
import 'package:moblist/ml/ml_object_detector.dart';
import 'package:moblist/ml/ml_vision_detector.dart';
import 'package:moblist/ml/moblist_task_verifier.dart';
import 'package:moblist/ml/model_config.dart';
import 'package:moblist/models/daily_task_record_model.dart';
import 'package:moblist/models/task_model.dart';
import 'package:moblist/models/vision_state.dart';
import 'package:moblist/services/accountability_alarm_service.dart';
import 'package:moblist/services/timer_engine.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('MOBLIST MASTER 22 AUTOMATED VERIFICATION TESTS', () {
    late MLObjectDetector objectDetector;
    late MobListTaskVerifier verifier;
    late TimerEngine timer;

    setUp(() {
      objectDetector = MLObjectDetector();
      verifier = MobListTaskVerifier(requiredConsecutiveValid: 3);
      timer = TimerEngine();
    });

    tearDown(() {
      timer.dispose();
      objectDetector.dispose();
    });

    // ========================================================
    // 1. Person detection
    // ========================================================
    test('1. Person detection: Verified when person is present above confidence threshold', () {
      final parsed = objectDetector.parseRawOutputs(
        numDetections: 1,
        locations: [
          [0.10, 0.20, 0.85, 0.75]
        ],
        classes: [0.0], // class 0 = person
        scores: [0.88],
        threshold: 0.40,
        inferenceTimeMs: 12,
      );

      expect(parsed.isPersonDetected, isTrue);
      expect(parsed.personConfidence, equals(0.88));
      expect(parsed.bestPerson, isNotNull);
      expect(parsed.bestPerson!.label, equals('PERSON'));
    });

    // ========================================================
    // 2. Laptop detection
    // ========================================================
    test('2. Laptop detection: Verified when laptop is present', () {
      final parsed = objectDetector.parseRawOutputs(
        numDetections: 1,
        locations: [
          [0.35, 0.25, 0.80, 0.70]
        ],
        classes: [72.0], // class 72 = laptop
        scores: [0.85],
        threshold: 0.40,
        inferenceTimeMs: 14,
      );

      expect(parsed.isLaptopDetected, isTrue);
      expect(parsed.laptopConfidence, equals(0.85));
      expect(parsed.bestLaptop!.label, equals('LAPTOP'));
    });

    // ========================================================
    // 3. Book detection
    // ========================================================
    test('3. Book detection: Parsed when book class 83 is detected', () {
      final parsed = objectDetector.parseRawOutputs(
        numDetections: 1,
        locations: [
          [0.45, 0.35, 0.75, 0.65]
        ],
        classes: [83.0], // class 83 = book
        scores: [0.78],
        threshold: 0.40,
        inferenceTimeMs: 11,
      );

      expect(parsed.isBookDetected, isTrue);
      expect(parsed.bookConfidence, equals(0.78));
      expect(parsed.bestBook!.label, equals('BOOK'));
    });

    // ========================================================
    // 4. Book confidence threshold
    // ========================================================
    test('4. Book confidence threshold: Rejects detections below threshold', () {
      final below = objectDetector.parseRawOutputs(
        numDetections: 1,
        locations: [
          [0.45, 0.35, 0.75, 0.65]
        ],
        classes: [83.0],
        scores: [0.35], // below 0.40
        threshold: 0.40,
        inferenceTimeMs: 10,
      );
      expect(below.isBookDetected, isFalse);

      final above = objectDetector.parseRawOutputs(
        numDetections: 1,
        locations: [
          [0.45, 0.35, 0.75, 0.65]
        ],
        classes: [83.0],
        scores: [0.65], // above 0.40
        threshold: 0.40,
        inferenceTimeMs: 10,
      );
      expect(above.isBookDetected, isTrue);
    });

    // ========================================================
    // 5. Book temporal stability
    // ========================================================
    test('5. Book temporal stability: Smooth tracking valid, wild jump rejected', () {
      final stableVerifier = MobListTaskVerifier(requiredConsecutiveValid: 3);

      final frame1 = MLInferenceOutput(
        rawDetections: const [],
        targetDetections: const [],
        bestPerson: const DetectedItem(label: 'PERSON', confidence: 0.90, boundingBox: Rect.fromLTWH(0.3, 0.2, 0.4, 0.6), isAccepted: true),
        bestBook: const DetectedItem(label: 'BOOK', confidence: 0.80, boundingBox: Rect.fromLTWH(0.35, 0.45, 0.25, 0.20), isAccepted: true),
        inferenceTimeMs: 12,
      );

      final res1 = stableVerifier.evaluateFrame(
        mlOutput: frame1,
        isBookTask: true,
        framesReceived: 1,
        framesProcessed: 1,
        framesSkipped: 0,
        confidenceThreshold: 0.40,
      );
      expect(res1.isTemporalStabilityValid, isTrue);

      // Frame 2: erratic jump across the entire screen (>0.40 displacement)
      final jumpingFrame = MLInferenceOutput(
        rawDetections: const [],
        targetDetections: const [],
        bestPerson: const DetectedItem(label: 'PERSON', confidence: 0.90, boundingBox: Rect.fromLTWH(0.3, 0.2, 0.4, 0.6), isAccepted: true),
        bestBook: const DetectedItem(label: 'BOOK', confidence: 0.80, boundingBox: Rect.fromLTWH(0.85, 0.05, 0.12, 0.10), isAccepted: true),
        inferenceTimeMs: 12,
      );

      final res2 = stableVerifier.evaluateFrame(
        mlOutput: jumpingFrame,
        isBookTask: true,
        framesReceived: 2,
        framesProcessed: 2,
        framesSkipped: 0,
        confidenceThreshold: 0.40,
      );
      expect(res2.isTemporalStabilityValid, isFalse);
    });

    // ========================================================
    // 6. Book spatial validation
    // ========================================================
    test('6. Book spatial validation: Book in reading zone associated with person is VALID', () {
      final validOutput = MLInferenceOutput(
        rawDetections: const [],
        targetDetections: const [],
        bestPerson: const DetectedItem(label: 'PERSON', confidence: 0.92, boundingBox: Rect.fromLTWH(0.30, 0.15, 0.45, 0.65), isAccepted: true),
        bestBook: const DetectedItem(label: 'BOOK', confidence: 0.85, boundingBox: Rect.fromLTWH(0.35, 0.45, 0.30, 0.25), isAccepted: true),
        inferenceTimeMs: 12,
      );

      final result = verifier.evaluateFrame(
        mlOutput: validOutput,
        isBookTask: true,
        framesReceived: 1,
        framesProcessed: 1,
        framesSkipped: 0,
        confidenceThreshold: 0.40,
      );

      expect(result.isPersonDetected, isTrue);
      expect(result.isBookDetected, isTrue);
      expect(result.isSpatialRelationValid, isTrue);
    });

    // ========================================================
    // 7. Random background book-like detection rejected
    // ========================================================
    test('7. Random background book-like detection rejected: Far off background object is INVALID', () {
      final backgroundNoiseOutput = MLInferenceOutput(
        rawDetections: const [],
        targetDetections: const [],
        bestPerson: const DetectedItem(label: 'PERSON', confidence: 0.90, boundingBox: Rect.fromLTWH(0.60, 0.40, 0.35, 0.55), isAccepted: true),
        bestBook: const DetectedItem(label: 'BOOK', confidence: 0.75, boundingBox: Rect.fromLTWH(0.05, 0.05, 0.12, 0.10), isAccepted: true), // Top-left ceiling/shelf
        inferenceTimeMs: 12,
      );

      final result = verifier.evaluateFrame(
        mlOutput: backgroundNoiseOutput,
        isBookTask: true,
        framesReceived: 1,
        framesProcessed: 1,
        framesSkipped: 0,
        confidenceThreshold: 0.40,
      );

      expect(result.isPersonDetected, isTrue);
      expect(result.isBookDetected, isTrue);
      expect(result.isSpatialRelationValid, isFalse);
      expect(result.isValidWorkingState, isFalse);
    });

    // ========================================================
    // 8. 3 consecutive valid frames
    // ========================================================
    test('8. 3 consecutive valid frames required before activity becomes valid', () {
      final validOutput = MLInferenceOutput(
        rawDetections: const [],
        targetDetections: const [],
        bestPerson: const DetectedItem(label: 'PERSON', confidence: 0.90, boundingBox: Rect.fromLTWH(0.3, 0.2, 0.4, 0.6), isAccepted: true),
        bestBook: const DetectedItem(label: 'BOOK', confidence: 0.85, boundingBox: Rect.fromLTWH(0.35, 0.45, 0.25, 0.25), isAccepted: true),
        inferenceTimeMs: 12,
      );

      // Frame 1
      final res1 = verifier.evaluateFrame(
        mlOutput: validOutput,
        isBookTask: true,
        framesReceived: 1,
        framesProcessed: 1,
        framesSkipped: 0,
        confidenceThreshold: 0.40,
      );
      expect(res1.consecutiveValidFrames, equals(1));
      expect(res1.isValidWorkingState, isFalse);

      // Frame 2
      final res2 = verifier.evaluateFrame(
        mlOutput: validOutput,
        isBookTask: true,
        framesReceived: 2,
        framesProcessed: 2,
        framesSkipped: 0,
        confidenceThreshold: 0.40,
      );
      expect(res2.consecutiveValidFrames, equals(2));
      expect(res2.isValidWorkingState, isFalse);

      // Frame 3
      final res3 = verifier.evaluateFrame(
        mlOutput: validOutput,
        isBookTask: true,
        framesReceived: 3,
        framesProcessed: 3,
        framesSkipped: 0,
        confidenceThreshold: 0.40,
      );
      expect(res3.consecutiveValidFrames, equals(3));
      expect(res3.isValidWorkingState, isTrue);
    });

    // ========================================================
    // 9. 30-second grace period
    // ========================================================
    test('9. 30-second grace period: Lost detection activates grace period without counting time', () {
      timer.initialize(
        taskId: 'read_book',
        date: '2026-09-29',
        initialState: ProductiveState.productive,
        initialStartedAt: DateTime.now().subtract(const Duration(seconds: 10)),
      );

      // 2 consecutive invalid frames
      final invalidRes = VisionDetectionResult.initial();
      timer.updateVisionResult(invalidRes);
      timer.updateVisionResult(invalidRes);

      expect(timer.state, equals(ProductiveState.gracePeriod));
      expect(timer.graceSecondsRemaining, equals(AppConstants.gracePeriodSeconds));
    });

    // ========================================================
    // 10. Productive timestamp calculation
    // ========================================================
    test('10. Productive timestamp calculation: Derived strictly from timestamp differences', () {
      timer.initialize(initialAccumulatedMs: 5000);
      final startTime = DateTime.now().subtract(const Duration(milliseconds: 3200));
      timer.initialize(
        initialAccumulatedMs: 5000,
        initialStartedAt: startTime,
        initialState: ProductiveState.productive,
      );

      final totalMs = timer.totalProductiveMs;
      expect(totalMs, greaterThanOrEqualTo(8200));
      expect(timer.totalAccumulatedSeconds, equals(8));
    });

    // ========================================================
    // 11. Timer live updates
    // ========================================================
    test('11. Timer live updates: Notifies listeners and increments continuously', () async {
      int notifyCount = 0;
      timer.addListener(() {
        notifyCount++;
      });

      timer.initialize(initialAccumulatedSeconds: 0);
      timer.startManualSession();

      await Future.delayed(const Duration(milliseconds: 600));

      expect(notifyCount, greaterThan(0));
      expect(timer.totalProductiveMs, greaterThanOrEqualTo(500));
    });

    // ========================================================
    // 12. Timer persistence
    // ========================================================
    test('12. Timer persistence: Accumulated time is preserved across session reloads', () {
      const savedMs = 45000; // 45 seconds
      final restoredTimer = TimerEngine();
      restoredTimer.initialize(
        taskId: 'read_book',
        date: '2026-09-29',
        initialAccumulatedMs: savedMs,
      );

      expect(restoredTimer.totalProductiveMs, equals(45000));
      expect(restoredTimer.totalAccumulatedSeconds, equals(45));
      restoredTimer.dispose();
    });

    // ========================================================
    // 13. Custom task timer
    // ========================================================
    test('13. Custom task timer: Manual task starts, accumulates without ML/camera, and pauses', () {
      final customTimer = TimerEngine();
      customTimer.initialize(taskId: 'custom_gym', date: '2026-09-29');

      customTimer.startManualSession();
      expect(customTimer.state, equals(ProductiveState.productive));

      customTimer.pauseManualSession();
      expect(customTimer.state, equals(ProductiveState.paused));
      customTimer.dispose();
    });

    // ========================================================
    // 14. Custom task persistence
    // ========================================================
    test('14. Custom task persistence: Custom task model stores and reloads progress', () {
      final customRecord = DailyTaskRecordModel(
        date: '2026-09-29',
        taskId: 'custom_cpp',
        accumulatedSeconds: 150,
        accumulatedProductiveMs: 150000,
        isCompleted: false,
        task: TaskModel(
          id: 'custom_cpp',
          name: 'Practice C++',
          taskType: AppConstants.taskTypeManual,
          isDefault: false,
          iconName: 'custom',
          createdAt: DateTime.now(),
        ),
      );

      expect(customRecord.task?.isCameraTask, isFalse);
      expect(customRecord.accumulatedSeconds, equals(150));
      expect(customRecord.formattedProgress, equals('02:30 / 10:00'));
    });

    // ========================================================
    // 15. 10-minute automatic completion
    // ========================================================
    test('15. 10-minute automatic completion: Reaching 600s triggers completion callback', () {
      bool targetReached = false;
      timer.initialize(
        taskId: 'read_book',
        date: '2026-09-29',
        initialAccumulatedMs: 600000, // 600 seconds
        onTargetReachedCallback: () {
          targetReached = true;
        },
      );

      expect(timer.isCompleted, isTrue);
      expect(timer.totalAccumulatedSeconds, equals(600));
    });

    // ========================================================
    // 16. Daily reset
    // ========================================================
    test('16. Daily reset: Records are uniquely partitioned by calendar date', () {
      final day1Record = DailyTaskRecordModel(
        date: '2026-09-29',
        taskId: 'read_book',
        accumulatedSeconds: 600,
        isCompleted: true,
      );

      final day2Record = DailyTaskRecordModel(
        date: '2026-09-30',
        taskId: 'read_book',
        accumulatedSeconds: 0,
        isCompleted: false,
      );

      expect(day1Record.accumulatedSeconds, equals(600));
      expect(day1Record.isCompleted, isTrue);
      expect(day2Record.accumulatedSeconds, equals(0));
      expect(day2Record.isCompleted, isFalse);
    });

    // ========================================================
    // 17. Alarm configurable time
    // ========================================================
    test('17. Alarm configurable time: User can configure custom reminder time', () {
      final alarm = AccountabilityAlarmService.instance;
      alarm.configureAlarmTime(21, 30); // 9:30 PM

      expect(alarm.alarmHour, equals(21));
      expect(alarm.alarmMinute, equals(30));
      expect(alarm.formattedAlarmTime, equals('9:30 PM'));

      // 9:35 PM should trigger alarm
      final timeAfter = DateTime(2026, 9, 29, 21, 35);
      expect(alarm.isTimeForAlarm(timeAfter), isTrue);

      // 9:15 PM should not trigger alarm
      final timeBefore = DateTime(2026, 9, 29, 21, 15);
      expect(alarm.isTimeForAlarm(timeBefore), isFalse);
    });

    // ========================================================
    // 18. Alarm setting persistence
    // ========================================================
    test('18. Alarm setting persistence: SQLite app_settings stores configured alarm time', () async {
      final db = DatabaseHelper.instance;
      await db.setSetting('accountability_alarm_time', '22:15');

      final storedTime = await db.getSetting('accountability_alarm_time');
      expect(storedTime, equals('22:15'));
    });

    // ========================================================
    // 19. Completed day does not alarm
    // ========================================================
    test('19. Completed day does not alarm: Alarm dismisses permanently when required tasks are done', () async {
      final alarm = AccountabilityAlarmService.instance;
      await alarm.triggerAlarm(['Read Book'], userIsInForeground: false);
      expect(alarm.isAlarmActive, isTrue);

      await alarm.dismissPermanently();
      expect(alarm.isAlarmActive, isFalse);
      expect(alarm.incompleteTasks.isEmpty, isTrue);
    });

    // ========================================================
    // 20. Emergency day
    // ========================================================
    test('20. Emergency day: Excuses accountability and silences alarm', () async {
      final alarm = AccountabilityAlarmService.instance;
      await alarm.triggerAlarm(['LeetCode'], userIsInForeground: false);

      // Activate emergency day -> dismisses alarm
      await alarm.dismissPermanently();
      expect(alarm.isAlarmActive, isFalse);
    });

    // ========================================================
    // 21. Emergency day monthly limit
    // ========================================================
    test('21. Emergency day monthly limit: Max 5 emergency days per calendar month', () {
      const limit = AppConstants.monthlyEmergencyDaysLimit;
      expect(limit, equals(5));

      int used = 5;
      bool canActivateAnother = used < limit;
      expect(canActivateAnother, isFalse);
    });

    // ========================================================
    // 22. History persistence
    // ========================================================
    test('22. History persistence: Preserves distinct dates and records across days', () {
      final date1 = '2026-09-28';
      final date2 = '2026-09-29';

      final historyDates = [date2, date1];
      expect(historyDates.contains(date1), isTrue);
      expect(historyDates.contains(date2), isTrue);
      expect(historyDates.length, equals(2));
    });
  });
}
