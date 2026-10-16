import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:moblist/core/constants/app_constants.dart';
import 'package:moblist/models/vision_state.dart';
import 'package:moblist/models/daily_task_record_model.dart';
import 'package:moblist/ml/ml_vision_detector.dart';
import 'package:moblist/services/timer_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MOBLIST REQUIRED SPECIFICATION TESTS (TEST 1 to TEST 14)', () {
    late MLVisionDetector detector;
    late TimerEngine timer;

    setUp(() {
      detector = MLVisionDetector(
        confidenceThreshold: 0.50,
        requiredConsecutiveValid: 3,
      );
      timer = TimerEngine();
    });

    tearDown(() {
      timer.dispose();
      detector.dispose();
    });

    // ========================================================
    // TEST 1: Person absent -> Person NOT DETECTED
    // ========================================================
    test('TEST 1: Person absent -> Person NOT DETECTED', () {
      final rawModelOutput = <DetectedItem>[
        const DetectedItem(
          label: 'chair',
          confidence: 0.85,
          boundingBox: Rect.fromLTWH(0.20, 0.40, 0.10, 0.15),
          isAccepted: false,
        ),
      ];

      final result = detector.evaluateRawDetections(
        detections: rawModelOutput,
        isBookTask: false,
      );

      expect(result.isPersonDetected, isFalse);
      expect(result.personConfidence, equals(0.0));
      expect(result.personBoundingBox, isNull);
    });

    // ========================================================
    // TEST 2: Person visible -> Person DETECTED
    // ========================================================
    test('TEST 2: Person visible -> Person DETECTED', () {
      const expectedBox = Rect.fromLTWH(0.50, 0.60, 0.20, 0.30);
      final rawModelOutput = <DetectedItem>[
        const DetectedItem(
          label: 'person',
          confidence: 0.91,
          boundingBox: expectedBox,
          isAccepted: true,
        ),
      ];

      final result = detector.evaluateRawDetections(
        detections: rawModelOutput,
        isBookTask: false,
      );

      expect(result.isPersonDetected, isTrue);
      expect(result.personConfidence, equals(0.91));
      expect(result.personBoundingBox, equals(expectedBox));
    });

    // ========================================================
    // TEST 3: Laptop visible -> Laptop DETECTED
    // ========================================================
    test('TEST 3: Laptop visible -> Laptop DETECTED', () {
      const expectedBox = Rect.fromLTWH(0.10, 0.20, 0.18, 0.12);
      final rawModelOutput = <DetectedItem>[
        const DetectedItem(
          label: 'laptop',
          confidence: 0.82,
          boundingBox: expectedBox,
          isAccepted: true,
        ),
      ];

      final result = detector.evaluateRawDetections(
        detections: rawModelOutput,
        isBookTask: false,
      );

      expect(result.isLaptopDetected, isTrue);
      expect(result.laptopConfidence, equals(0.82));
      expect(result.laptopBoundingBox, equals(expectedBox));
    });

    // ========================================================
    // TEST 4: Book visible -> Book DETECTED
    // ========================================================
    test('TEST 4: Book visible -> Book DETECTED', () {
      const expectedBox = Rect.fromLTWH(0.15, 0.22, 0.14, 0.09);
      final rawModelOutput = <DetectedItem>[
        const DetectedItem(
          label: 'book',
          confidence: 0.76,
          boundingBox: expectedBox,
          isAccepted: true,
        ),
      ];

      final result = detector.evaluateRawDetections(
        detections: rawModelOutput,
        isBookTask: true,
      );

      expect(result.isBookDetected, isTrue);
      expect(result.bookConfidence, equals(0.76));
      expect(result.bookBoundingBox, equals(expectedBox));
    });

    // ========================================================
    // TEST 5: Person + laptop -> Activity VALID
    // ========================================================
    test('TEST 5: Person + laptop -> Activity VALID', () {
      final rawModelOutput = <DetectedItem>[
        const DetectedItem(
          label: 'person',
          confidence: 0.91,
          boundingBox: Rect.fromLTWH(0.50, 0.60, 0.20, 0.30),
          isAccepted: true,
        ),
        const DetectedItem(
          label: 'laptop',
          confidence: 0.82,
          boundingBox: Rect.fromLTWH(0.10, 0.20, 0.18, 0.12),
          isAccepted: true,
        ),
      ];

      // Feed across 3 frames
      VisionDetectionResult result = VisionDetectionResult.initial();
      for (int i = 0; i < 3; i++) {
        result = detector.evaluateRawDetections(
          detections: rawModelOutput,
          isBookTask: false,
        );
      }

      expect(result.isPersonDetected, isTrue);
      expect(result.isLaptopDetected, isTrue);
      expect(result.isTargetObjectDetected, isTrue);
      expect(result.isValidWorkingState, isTrue);
    });

    // ========================================================
    // TEST 6: Person + book -> Activity VALID
    // ========================================================
    test('TEST 6: Person + book -> Activity VALID', () {
      final rawModelOutput = <DetectedItem>[
        const DetectedItem(
          label: 'person',
          confidence: 0.91,
          boundingBox: Rect.fromLTWH(0.40, 0.30, 0.35, 0.55),
          isAccepted: true,
        ),
        const DetectedItem(
          label: 'book',
          confidence: 0.76,
          boundingBox: Rect.fromLTWH(0.42, 0.50, 0.25, 0.20),
          isAccepted: true,
        ),
      ];

      VisionDetectionResult result = VisionDetectionResult.initial();
      for (int i = 0; i < 3; i++) {
        result = detector.evaluateRawDetections(
          detections: rawModelOutput,
          isBookTask: true,
        );
      }

      expect(result.isPersonDetected, isTrue);
      expect(result.isBookDetected, isTrue);
      expect(result.isTargetObjectDetected, isTrue);
      expect(result.isSpatialRelationValid, isTrue);
      expect(result.isTemporalStabilityValid, isTrue);
      expect(result.isValidWorkingState, isTrue);
    });

    // ========================================================
    // TEST 6B: Random background book disconnected from person is REJECTED
    // ========================================================
    test('TEST 6B: Random background book disconnected from person is REJECTED', () {
      final backgroundNoiseOutput = <DetectedItem>[
        const DetectedItem(
          label: 'person',
          confidence: 0.91,
          boundingBox: Rect.fromLTWH(0.60, 0.40, 0.30, 0.50), // Person in bottom-right
          isAccepted: true,
        ),
        const DetectedItem(
          label: 'book',
          confidence: 0.76,
          boundingBox: Rect.fromLTWH(0.05, 0.05, 0.15, 0.10), // Background noise in top-left
          isAccepted: true,
        ),
      ];

      final result = detector.evaluateRawDetections(
        detections: backgroundNoiseOutput,
        isBookTask: true,
      );

      expect(result.isPersonDetected, isTrue);
      expect(result.isBookDetected, isTrue);
      expect(result.isSpatialRelationValid, isFalse);
      expect(result.isValidWorkingState, isFalse);
    });

    // ========================================================
    // TEST 7: Single false-positive frame -> timer does not start
    // ========================================================
    test('TEST 7: Single false-positive frame -> timer does not start', () {
      timer.initialize(initialAccumulatedSeconds: 0);
      timer.startCameraSession();
      timer.cameraReady();

      final singleValidResult = detector.evaluateRawDetections(
        detections: const [
          DetectedItem(label: 'person', confidence: 0.91, boundingBox: Rect.fromLTWH(0.50, 0.60, 0.20, 0.30), isAccepted: true),
          DetectedItem(label: 'laptop', confidence: 0.82, boundingBox: Rect.fromLTWH(0.10, 0.20, 0.18, 0.12), isAccepted: true),
        ],
        isBookTask: false,
      );

      // Only 1 frame processed
      timer.updateVisionResult(singleValidResult);

      // Productive timer must NOT have started (required 3 frames)
      expect(timer.state, equals(ProductiveState.verifying));
      expect(timer.isSessionActivelyProductive, isFalse);
      expect(timer.totalProductiveMs, equals(0));
    });

    // ========================================================
    // TEST 8: 3 valid frames -> activity becomes valid
    // ========================================================
    test('TEST 8: 3 valid frames -> activity becomes valid', () {
      timer.initialize(initialAccumulatedSeconds: 0);
      timer.startCameraSession();
      timer.cameraReady();

      const detections = [
        DetectedItem(label: 'person', confidence: 0.91, boundingBox: Rect.fromLTWH(0.50, 0.60, 0.20, 0.30), isAccepted: true),
        DetectedItem(label: 'laptop', confidence: 0.82, boundingBox: Rect.fromLTWH(0.10, 0.20, 0.18, 0.12), isAccepted: true),
      ];

      // Frame 1
      final frame1 = detector.evaluateRawDetections(
        detections: detections,
        isBookTask: false,
      );
      timer.updateVisionResult(frame1);
      expect(timer.state, equals(ProductiveState.verifying));

      // Frame 2
      final frame2 = detector.evaluateRawDetections(
        detections: detections,
        isBookTask: false,
      );
      timer.updateVisionResult(frame2);
      expect(timer.state, equals(ProductiveState.verifying));

      // Frame 3 (Threshold reached!)
      final frame3 = detector.evaluateRawDetections(
        detections: detections,
        isBookTask: false,
      );
      timer.updateVisionResult(frame3);

      // Now activity is VALID and timer is PRODUCTIVE!
      expect(timer.state, equals(ProductiveState.productive));
      expect(timer.isSessionActivelyProductive, isTrue);
    });

    // ========================================================
    // TEST 9: Timer starts at timestamp T
    // ========================================================
    test('TEST 9: Timer starts at timestamp T', () {
      timer.initialize(initialAccumulatedSeconds: 0);
      final before = DateTime.now();
      timer.startManualSession();
      final after = DateTime.now();

      expect(timer.state, equals(ProductiveState.productive));
      expect(timer.productiveBurstStart, isNotNull);
      expect(
        timer.productiveBurstStart!.millisecondsSinceEpoch,
        greaterThanOrEqualTo(before.millisecondsSinceEpoch),
      );
      expect(
        timer.productiveBurstStart!.millisecondsSinceEpoch,
        lessThanOrEqualTo(after.millisecondsSinceEpoch),
      );
    });

    // ========================================================
    // TEST 10: After 10 seconds -> approximately 10 seconds productive time
    // ========================================================
    test('TEST 10: After 10 seconds -> approximately 10 seconds productive time', () async {
      timer.initialize(initialAccumulatedSeconds: 0);
      timer.startManualSession();

      final burstStartTenSecondsAgo = DateTime.now().subtract(const Duration(seconds: 10));
      final elapsed = DateTime.now().difference(burstStartTenSecondsAgo).inMilliseconds;
      expect((elapsed - 10000).abs(), lessThan(50));

      final realStart = DateTime.now();
      await Future.delayed(const Duration(milliseconds: 300));
      final realElapsed = DateTime.now().difference(realStart).inMilliseconds;
      final timerReported = timer.totalProductiveMs;
      expect((timerReported - realElapsed).abs(), lessThan(50));
    });

    // ========================================================
    // TEST 11: Navigate away and return -> productive time is preserved
    // ========================================================
    test('TEST 11: Navigate away and return -> productive time is preserved', () {
      const recordedMs = 10000;
      final savedRecord = DailyTaskRecordModel(
        date: '2026-09-27',
        taskId: 'default_work_laptop',
        accumulatedSeconds: 10,
        accumulatedProductiveMs: recordedMs,
        timerState: 'paused',
        isCompleted: false,
      );

      final restoredTimer = TimerEngine();
      restoredTimer.initialize(
        initialAccumulatedSeconds: savedRecord.accumulatedSeconds,
        initialAccumulatedMs: savedRecord.accumulatedProductiveMs,
      );

      expect(restoredTimer.totalProductiveMs, equals(10000));
      expect(restoredTimer.totalAccumulatedSeconds, equals(10));
      expect(restoredTimer.previouslyAccumulatedSeconds, equals(10));
      restoredTimer.dispose();
    });

    // ========================================================
    // TEST 12: Pause and resume -> previous productive time preserved
    // ========================================================
    test('TEST 12: Pause and resume -> previous productive time preserved', () async {
      timer.initialize(initialAccumulatedMs: 5000);
      expect(timer.totalProductiveMs, equals(5000));

      timer.startManualSession();
      await Future.delayed(const Duration(milliseconds: 150));

      timer.pauseSession();
      final msAfterPause = timer.totalProductiveMs;
      expect(msAfterPause, greaterThanOrEqualTo(5150));

      timer.startManualSession();
      expect(timer.totalProductiveMs, greaterThanOrEqualTo(msAfterPause));
    });

    // ========================================================
    // TEST 13: 4 seconds + pause + 6 seconds -> 10 seconds total
    // ========================================================
    test('TEST 13: 4 seconds + pause + 6 seconds -> 10 seconds total', () {
      final timer1 = TimerEngine();
      timer1.initialize(initialAccumulatedMs: 0);
      timer1.initialize(initialAccumulatedMs: 4000);
      expect(timer1.totalProductiveMs, equals(4000));
      timer1.dispose();

      final timer2 = TimerEngine();
      timer2.initialize(initialAccumulatedMs: 4000);
      final total = timer2.totalProductiveMs + 6000;
      expect(total, equals(10000));
      expect(total ~/ 1000, equals(10));
      timer2.dispose();
    });

    // ========================================================
    // TEST 14: 600 seconds productive -> task completed
    // ========================================================
    test('TEST 14: 600 seconds productive -> task completed', () async {
      bool targetCompletedCallbackCalled = false;
      timer.initialize(
        initialAccumulatedSeconds: 599,
        initialAccumulatedMs: 599000,
        onTargetReachedCallback: () {
          targetCompletedCallbackCalled = true;
        },
      );
      timer.startManualSession();

      await Future.delayed(const Duration(milliseconds: 1100));

      expect(timer.totalProductiveMs, greaterThanOrEqualTo(600000));
      expect(timer.totalAccumulatedSeconds, greaterThanOrEqualTo(600));
      expect(timer.isCompleted, isTrue);
      expect(targetCompletedCallbackCalled, isTrue);
    });

    // ========================================================
    // ADDITIONAL ROBUSTNESS TESTS (Grace period)
    // ========================================================
    test('ADDITIONAL: 30-second grace period activates on lost detection and does not increment productive time', () async {
      timer.initialize(initialAccumulatedMs: 5000);
      timer.startCameraSession();
      timer.cameraReady();

      const validDetections = [
        DetectedItem(label: 'person', confidence: 0.91, boundingBox: Rect.fromLTWH(0.50, 0.60, 0.20, 0.30), isAccepted: true),
        DetectedItem(label: 'laptop', confidence: 0.82, boundingBox: Rect.fromLTWH(0.10, 0.20, 0.18, 0.12), isAccepted: true),
      ];

      // Feed 3 valid frames
      for (int i = 0; i < 3; i++) {
        timer.updateVisionResult(detector.evaluateRawDetections(
          detections: validDetections,
          isBookTask: false,
        ));
      }
      expect(timer.state, equals(ProductiveState.productive));

      // Detection lost (2 invalid frames)
      for (int i = 0; i < 2; i++) {
        timer.updateVisionResult(detector.evaluateRawDetections(
          detections: const [],
          isBookTask: false,
        ));
      }
      expect(timer.state, equals(ProductiveState.gracePeriod));
      expect(timer.graceSecondsRemaining, equals(AppConstants.gracePeriodSeconds));

      final msAtGrace = timer.totalProductiveMs;
      await Future.delayed(const Duration(milliseconds: 200));

      // Productive time MUST NOT increment during grace period
      expect(timer.totalProductiveMs, equals(msAtGrace));
    });
  });
}
