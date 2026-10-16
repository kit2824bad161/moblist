import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:moblist/core/constants/app_constants.dart';
import 'package:moblist/ml/ml_object_detector.dart';
import 'package:moblist/ml/moblist_task_verifier.dart';
import 'package:moblist/models/vision_state.dart';
import 'package:moblist/services/timer_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MOBLIST MASTER SPECIFICATION TESTS (TEST 1 to TEST 15)', () {
    late MLObjectDetector detector;
    late MobListTaskVerifier verifier;
    late TimerEngine timer;

    setUp(() {
      detector = MLObjectDetector();
      verifier = MobListTaskVerifier();
      timer = TimerEngine();
    });

    tearDown(() {
      timer.dispose();
      detector.dispose();
    });

    // ========================================================
    // 1. Person detection parsing
    // ========================================================
    test('TEST 1: Person detection parsing', () {
      final rawOutputs = detector.parseRawOutputs(
        numDetections: 1,
        locations: [
          [0.10, 0.20, 0.80, 0.70] // [ymin, xmin, ymax, xmax]
        ],
        classes: [0.0], // class 0 = person
        scores: [0.91],
        threshold: 0.40,
        inferenceTimeMs: 12,
      );

      expect(rawOutputs.isPersonDetected, isTrue);
      expect(rawOutputs.personConfidence, equals(0.91));
      expect(rawOutputs.bestPerson, isNotNull);
      expect(rawOutputs.bestPerson!.label, equals('PERSON'));
      expect(rawOutputs.bestPerson!.classIndex, equals(0));
      expect(
        rawOutputs.bestPerson!.boundingBox,
        equals(const Rect.fromLTRB(0.20, 0.10, 0.70, 0.80)),
      );
    });

    // ========================================================
    // 2. Laptop detection parsing
    // ========================================================
    test('TEST 2: Laptop detection parsing', () {
      final rawOutputs = detector.parseRawOutputs(
        numDetections: 1,
        locations: [
          [0.40, 0.25, 0.85, 0.75]
        ],
        classes: [72.0], // class 72 = laptop
        scores: [0.84],
        threshold: 0.40,
        inferenceTimeMs: 14,
      );

      expect(rawOutputs.isLaptopDetected, isTrue);
      expect(rawOutputs.laptopConfidence, equals(0.84));
      expect(rawOutputs.bestLaptop, isNotNull);
      expect(rawOutputs.bestLaptop!.label, equals('LAPTOP'));
      expect(rawOutputs.bestLaptop!.classIndex, equals(72));
      expect(
        rawOutputs.bestLaptop!.boundingBox,
        equals(const Rect.fromLTRB(0.25, 0.40, 0.75, 0.85)),
      );
    });

    // ========================================================
    // 3. Book detection parsing
    // ========================================================
    test('TEST 3: Book detection parsing', () {
      final rawOutputs = detector.parseRawOutputs(
        numDetections: 1,
        locations: [
          [0.50, 0.30, 0.90, 0.70]
        ],
        classes: [83.0], // class 83 = book
        scores: [0.79],
        threshold: 0.40,
        inferenceTimeMs: 11,
      );

      expect(rawOutputs.isBookDetected, isTrue);
      expect(rawOutputs.bookConfidence, equals(0.79));
      expect(rawOutputs.bestBook, isNotNull);
      expect(rawOutputs.bestBook!.label, equals('BOOK'));
      expect(rawOutputs.bestBook!.classIndex, equals(83));
      expect(
        rawOutputs.bestBook!.boundingBox,
        equals(const Rect.fromLTRB(0.30, 0.50, 0.70, 0.90)),
      );
    });

    // ========================================================
    // 4. Unknown class filtering
    // ========================================================
    test('TEST 4: Unknown class filtering', () {
      final rawOutputs = detector.parseRawOutputs(
        numDetections: 3,
        locations: [
          [0.1, 0.1, 0.5, 0.5],
          [0.2, 0.2, 0.6, 0.6],
          [0.3, 0.3, 0.7, 0.7],
        ],
        classes: [1.0, 15.0, 61.0], // bicycle, bird, chair
        scores: [0.95, 0.88, 0.92],
        threshold: 0.40,
        inferenceTimeMs: 15,
      );

      // Raw detections are captured for debug visibility
      expect(rawOutputs.rawDetections.length, equals(3));
      // But none are accepted as target objects (PERSON, LAPTOP, BOOK)
      expect(rawOutputs.targetDetections, isEmpty);
      expect(rawOutputs.isPersonDetected, isFalse);
      expect(rawOutputs.isLaptopDetected, isFalse);
      expect(rawOutputs.isBookDetected, isFalse);
    });

    // ========================================================
    // 5. Confidence filtering
    // ========================================================
    test('TEST 5: Confidence filtering', () {
      // Below threshold (0.35 < 0.40)
      final belowThreshold = detector.parseRawOutputs(
        numDetections: 1,
        locations: [
          [0.1, 0.2, 0.8, 0.7]
        ],
        classes: [0.0], // person
        scores: [0.35],
        threshold: 0.40,
        inferenceTimeMs: 10,
      );
      expect(belowThreshold.isPersonDetected, isFalse);
      expect(belowThreshold.targetDetections, isEmpty);

      // Above threshold (0.45 >= 0.40)
      final aboveThreshold = detector.parseRawOutputs(
        numDetections: 1,
        locations: [
          [0.1, 0.2, 0.8, 0.7]
        ],
        classes: [0.0], // person
        scores: [0.45],
        threshold: 0.40,
        inferenceTimeMs: 10,
      );
      expect(aboveThreshold.isPersonDetected, isTrue);
      expect(aboveThreshold.targetDetections.length, equals(1));
    });

    // ========================================================
    // 6. Bounding box parsing
    // ========================================================
    test('TEST 6: Bounding box parsing coordinates clamping', () {
      final rawOutputs = detector.parseRawOutputs(
        numDetections: 1,
        locations: [
          [-0.2, -0.1, 1.5, 1.2] // out of bounds coordinates
        ],
        classes: [0.0],
        scores: [0.90],
        threshold: 0.40,
        inferenceTimeMs: 10,
      );

      final box = rawOutputs.bestPerson!.boundingBox;
      expect(box.left, equals(0.0));
      expect(box.top, equals(0.0));
      expect(box.right, equals(1.0));
      expect(box.bottom, equals(1.0));
    });

    // ========================================================
    // 7. Three-frame validation
    // ========================================================
    test('TEST 7: Three-frame validation', () {
      final validML = MLInferenceOutput(
        rawDetections: const [],
        targetDetections: const [],
        bestPerson: const DetectedItem(
          label: 'PERSON',
          confidence: 0.90,
          boundingBox: Rect.fromLTWH(0.2, 0.1, 0.5, 0.7),
          isAccepted: true,
        ),
        bestLaptop: const DetectedItem(
          label: 'LAPTOP',
          confidence: 0.85,
          boundingBox: Rect.fromLTWH(0.3, 0.4, 0.4, 0.4),
          isAccepted: true,
        ),
        inferenceTimeMs: 12,
      );

      final invalidML = const MLInferenceOutput(
        rawDetections: [],
        targetDetections: [],
        inferenceTimeMs: 10,
      );

      // Frame 1: valid -> 1/3
      final res1 = verifier.evaluateFrame(
        mlOutput: validML,
        isBookTask: false,
        framesReceived: 1,
        framesProcessed: 1,
        framesSkipped: 0,
        confidenceThreshold: 0.40,
      );
      expect(res1.consecutiveValidFrames, equals(1));
      expect(res1.isValidWorkingState, isFalse);

      // Frame 2: valid -> 2/3
      final res2 = verifier.evaluateFrame(
        mlOutput: validML,
        isBookTask: false,
        framesReceived: 2,
        framesProcessed: 2,
        framesSkipped: 0,
        confidenceThreshold: 0.40,
      );
      expect(res2.consecutiveValidFrames, equals(2));
      expect(res2.isValidWorkingState, isFalse);

      // Frame 3: valid -> 3/3 => VALID!
      final res3 = verifier.evaluateFrame(
        mlOutput: validML,
        isBookTask: false,
        framesReceived: 3,
        framesProcessed: 3,
        framesSkipped: 0,
        confidenceThreshold: 0.40,
      );
      expect(res3.consecutiveValidFrames, equals(3));
      expect(res3.isValidWorkingState, isTrue);

      // Frame 4: invalid -> resets to 0
      final res4 = verifier.evaluateFrame(
        mlOutput: invalidML,
        isBookTask: false,
        framesReceived: 4,
        framesProcessed: 4,
        framesSkipped: 0,
        confidenceThreshold: 0.40,
      );
      expect(res4.consecutiveValidFrames, equals(0));
      expect(res4.isValidWorkingState, isFalse);
    });

    // ========================================================
    // 8. Person + laptop valid activity
    // ========================================================
    test('TEST 8: Person + laptop valid activity for laptop task', () {
      final validLaptopTaskOutput = MLInferenceOutput(
        rawDetections: const [],
        targetDetections: const [],
        bestPerson: const DetectedItem(
          label: 'PERSON',
          confidence: 0.92,
          boundingBox: Rect.fromLTWH(0.2, 0.1, 0.5, 0.7),
          isAccepted: true,
        ),
        bestLaptop: const DetectedItem(
          label: 'LAPTOP',
          confidence: 0.88,
          boundingBox: Rect.fromLTWH(0.3, 0.4, 0.4, 0.4),
          isAccepted: true,
        ),
        inferenceTimeMs: 14,
      );

      final result = verifier.evaluateFrame(
        mlOutput: validLaptopTaskOutput,
        isBookTask: false, // Laptop task
        framesReceived: 1,
        framesProcessed: 1,
        framesSkipped: 0,
        confidenceThreshold: 0.40,
      );

      expect(result.isPersonDetected, isTrue);
      expect(result.isLaptopDetected, isTrue);
      expect(result.isTargetObjectDetected, isTrue);
      expect(result.consecutiveValidFrames, equals(1));
    });

    // ========================================================
    // 9. Person + book valid activity
    // ========================================================
    test('TEST 9: Person + book valid activity for book task', () {
      final validBookTaskOutput = MLInferenceOutput(
        rawDetections: const [],
        targetDetections: const [],
        bestPerson: const DetectedItem(
          label: 'PERSON',
          confidence: 0.91,
          boundingBox: Rect.fromLTWH(0.2, 0.1, 0.5, 0.7),
          isAccepted: true,
        ),
        bestBook: const DetectedItem(
          label: 'BOOK',
          confidence: 0.82,
          boundingBox: Rect.fromLTWH(0.3, 0.4, 0.3, 0.3),
          isAccepted: true,
        ),
        inferenceTimeMs: 13,
      );

      final result = verifier.evaluateFrame(
        mlOutput: validBookTaskOutput,
        isBookTask: true, // Book task
        framesReceived: 1,
        framesProcessed: 1,
        framesSkipped: 0,
        confidenceThreshold: 0.40,
      );

      expect(result.isPersonDetected, isTrue);
      expect(result.isBookDetected, isTrue);
      expect(result.isTargetObjectDetected, isTrue);
      expect(result.consecutiveValidFrames, equals(1));
    });

    // ========================================================
    // 10. Person without laptop invalid
    // ========================================================
    test('TEST 10: Person without laptop invalid for laptop task', () {
      final personOnlyOutput = MLInferenceOutput(
        rawDetections: const [],
        targetDetections: const [],
        bestPerson: const DetectedItem(
          label: 'PERSON',
          confidence: 0.95,
          boundingBox: Rect.fromLTWH(0.2, 0.1, 0.5, 0.7),
          isAccepted: true,
        ),
        bestLaptop: null, // No laptop
        inferenceTimeMs: 12,
      );

      final result = verifier.evaluateFrame(
        mlOutput: personOnlyOutput,
        isBookTask: false,
        framesReceived: 1,
        framesProcessed: 1,
        framesSkipped: 0,
        confidenceThreshold: 0.40,
      );

      expect(result.isPersonDetected, isTrue);
      expect(result.isLaptopDetected, isFalse);
      expect(result.isTargetObjectDetected, isFalse);
      expect(result.consecutiveValidFrames, equals(0));
      expect(result.isValidWorkingState, isFalse);
    });

    // ========================================================
    // 11. Person without book invalid
    // ========================================================
    test('TEST 11: Person without book invalid for book task', () {
      final personOnlyOutput = MLInferenceOutput(
        rawDetections: const [],
        targetDetections: const [],
        bestPerson: const DetectedItem(
          label: 'PERSON',
          confidence: 0.95,
          boundingBox: Rect.fromLTWH(0.2, 0.1, 0.5, 0.7),
          isAccepted: true,
        ),
        bestBook: null, // No book
        inferenceTimeMs: 12,
      );

      final result = verifier.evaluateFrame(
        mlOutput: personOnlyOutput,
        isBookTask: true,
        framesReceived: 1,
        framesProcessed: 1,
        framesSkipped: 0,
        confidenceThreshold: 0.40,
      );

      expect(result.isPersonDetected, isTrue);
      expect(result.isBookDetected, isFalse);
      expect(result.isTargetObjectDetected, isFalse);
      expect(result.consecutiveValidFrames, equals(0));
      expect(result.isValidWorkingState, isFalse);
    });

    // ========================================================
    // 12. Grace period
    // ========================================================
    test('TEST 12: Grace period activates when detection is lost', () {
      timer.initialize(
        taskId: 'leetcode',
        date: '2026-09-28',
        initialState: ProductiveState.productive,
        initialStartedAt: DateTime.now(),
      );

      expect(timer.state, equals(ProductiveState.productive));

      // Emit 2 consecutive invalid detection frames to trigger grace period
      final invalidResult = VisionDetectionResult.initial();
      timer.updateVisionResult(invalidResult);
      timer.updateVisionResult(invalidResult);

      expect(timer.state, equals(ProductiveState.gracePeriod));
      expect(timer.graceSecondsRemaining, equals(AppConstants.gracePeriodSeconds));
    });

    // ========================================================
    // 13. Timer pause
    // ========================================================
    test('TEST 13: Timer pause when grace period is exceeded or session paused', () {
      timer.initialize(
        taskId: 'leetcode',
        date: '2026-09-28',
        initialState: ProductiveState.productive,
        initialStartedAt: DateTime.now().subtract(const Duration(seconds: 15)),
      );

      timer.pauseSession();
      expect(timer.state, equals(ProductiveState.paused));
      expect(timer.totalAccumulatedSeconds, greaterThanOrEqualTo(15));
    });

    // ========================================================
    // 14. Timer resume
    // ========================================================
    test('TEST 14: Timer resumes from pause after 3 valid frames', () {
      timer.initialize(
        taskId: 'leetcode',
        date: '2026-09-28',
        initialState: ProductiveState.paused,
        initialAccumulatedSeconds: 45,
      );

      final validFrame = VisionDetectionResult(
        isPersonDetected: true,
        isLaptopDetected: true,
        isTargetObjectDetected: true,
        confidence: 0.90,
        statusDescription: 'Valid',
        timestamp: DateTime.now(),
      );

      // Frame 1
      timer.updateVisionResult(validFrame);
      expect(timer.state, equals(ProductiveState.paused));

      // Frame 2
      timer.updateVisionResult(validFrame);
      expect(timer.state, equals(ProductiveState.paused));

      // Frame 3 -> resumes productive state!
      timer.updateVisionResult(validFrame);
      expect(timer.state, equals(ProductiveState.productive));
      expect(timer.totalAccumulatedSeconds, equals(45));
    });

    // ========================================================
    // 15. Completion at 600 seconds
    // ========================================================
    test('TEST 15: Completion at 600 seconds', () {
      bool completionCallbackCalled = false;

      timer.initialize(
        taskId: 'leetcode',
        date: '2026-09-28',
        initialAccumulatedSeconds: 599,
        initialStartedAt: DateTime.now().subtract(const Duration(milliseconds: 1500)),
        initialState: ProductiveState.productive,
        onTargetReachedCallback: () {
          completionCallbackCalled = true;
        },
      );

      // Trigger evaluation of time
      expect(timer.totalAccumulatedSeconds, greaterThanOrEqualTo(600));
      expect(timer.isCompleted, isTrue);

      // Verify callback trigger on vision update
      timer.updateVisionResult(VisionDetectionResult(
        isPersonDetected: true,
        isLaptopDetected: true,
        isTargetObjectDetected: true,
        confidence: 0.90,
        statusDescription: 'Valid',
        timestamp: DateTime.now(),
      ));
      expect(completionCallbackCalled, isTrue);
    });
  });
}
