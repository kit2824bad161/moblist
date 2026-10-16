import 'dart:ui';
import '../models/vision_state.dart';
import 'model_config.dart';
import 'ml_object_detector.dart';

/// Verifies MobList tasks against ML inference output and enforces 3 consecutive valid frames
class MobListTaskVerifier {
  final int requiredConsecutiveValid;

  int _consecutiveValidFrames = 0;
  int _consecutiveInvalidFrames = 0;
  Offset? _lastBookCenter;

  int get consecutiveValidFrames => _consecutiveValidFrames;
  int get consecutiveInvalidFrames => _consecutiveInvalidFrames;

  MobListTaskVerifier({
    this.requiredConsecutiveValid = MLModelConfig.requiredConsecutiveValidFrames,
  });

  void reset() {
    _consecutiveValidFrames = 0;
    _consecutiveInvalidFrames = 0;
    _lastBookCenter = null;
  }

  /// Evaluates an inference output for a given task (Book vs Laptop)
  VisionDetectionResult evaluateFrame({
    required MLInferenceOutput mlOutput,
    required bool isBookTask,
    required int framesReceived,
    required int framesProcessed,
    required int framesSkipped,
    required double confidenceThreshold,
    Size? frameSize,
    int sensorRotation = 0,
    String cameraStatus = 'READY',
    String frameStatus = 'RECEIVED',
    String conversionStatus = 'SUCCESS',
  }) {
    final now = DateTime.now();

    final isPerson = mlOutput.isPersonDetected;
    final isTargetObject = isBookTask ? mlOutput.isBookDetected : mlOutput.isLaptopDetected;

    final personBox = mlOutput.bestPerson?.boundingBox;
    final laptopBox = mlOutput.bestLaptop?.boundingBox;
    final bookBox = mlOutput.bestBook?.boundingBox;
    final targetBox = isBookTask ? bookBox : laptopBox;

    final personConf = mlOutput.personConfidence;
    final laptopConf = mlOutput.laptopConfidence;
    final bookConf = mlOutput.bookConfidence;
    final targetConf = isBookTask ? bookConf : laptopConf;

    bool isBoxValid = true;
    bool isSpatialValid = true;
    bool isTemporalValid = true;
    String bookValidationDetails = '';

    bool framePassed = false;

    if (isBookTask) {
      // ========================================================
      // 1. READ BOOK VALIDATION: STRICT CRITERIA
      // ========================================================
      final isBook = mlOutput.isBookDetected && bookBox != null;

      if (isBook && bookBox != null) {
        // A. Bounding Box Sanity Check: Area and Aspect Ratio
        final width = bookBox.width;
        final height = bookBox.height;
        final area = width * height;
        final aspectRatio = height > 0 ? (width / height) : 0.0;

        isBoxValid = area >= MLModelConfig.bookMinBoxArea &&
            area <= MLModelConfig.bookMaxBoxArea &&
            aspectRatio >= MLModelConfig.bookMinAspectRatio &&
            aspectRatio <= MLModelConfig.bookMaxAspectRatio;

        // B. Spatial Relationship Validation: Associated with Person
        if (isPerson && personBox != null && isBoxValid) {
          final bool directOverlap = personBox.overlaps(bookBox);

          // Person's active workspace/reading interaction zone:
          // Extends slightly horizontally and downward into chest/lap/desk level
          final double zoneLeft = (personBox.left - personBox.width * MLModelConfig.bookReadingZonePaddingX).clamp(0.0, 1.0);
          final double zoneRight = (personBox.right + personBox.width * MLModelConfig.bookReadingZonePaddingX).clamp(0.0, 1.0);
          final double zoneTop = (personBox.top + personBox.height * 0.10).clamp(0.0, 1.0);
          final double zoneBottom = (personBox.bottom + personBox.height * MLModelConfig.bookReadingZonePaddingY).clamp(0.0, 1.0);
          final readingZone = Rect.fromLTRB(zoneLeft, zoneTop, zoneRight, zoneBottom);

          final bool inReadingZone = readingZone.contains(bookBox.center) || readingZone.overlaps(bookBox);
          isSpatialValid = directOverlap || inReadingZone;
        } else {
          isSpatialValid = false;
        }

        // C. Temporal Stability: Reject erratic jumping background noise
        if (isBoxValid && isSpatialValid) {
          final currentCenter = bookBox.center;
          if (_lastBookCenter == null) {
            isTemporalValid = true;
            _lastBookCenter = currentCenter;
          } else {
            final displacement = (currentCenter - _lastBookCenter!).distance;
            if (displacement <= MLModelConfig.bookMaxCenterDisplacement) {
              isTemporalValid = true;
              _lastBookCenter = Offset(
                _lastBookCenter!.dx * 0.3 + currentCenter.dx * 0.7,
                _lastBookCenter!.dy * 0.3 + currentCenter.dy * 0.7,
              );
            } else {
              isTemporalValid = false;
              _lastBookCenter = currentCenter;
            }
          }
        } else {
          isTemporalValid = false;
        }
      } else {
        isBoxValid = false;
        isSpatialValid = false;
        isTemporalValid = false;
        _lastBookCenter = null;
      }

      bookValidationDetails = 'Box: ${isBoxValid ? "VALID" : "INVALID"} | '
          'Spatial: ${isSpatialValid ? "VALID" : "INVALID"} | '
          'Temporal: ${isTemporalValid ? "VALID" : "INVALID"}';

      // Read Book requires ALL: Person + Book + Valid Box + Spatial Association + Temporal Stability
      framePassed = isPerson && isBook && isBoxValid && isSpatialValid && isTemporalValid;
    } else {
      // ========================================================
      // 2. LAPTOP TASKS: UNTOUCHED WORKING PIPELINE
      // LeetCode / My Project / SpeakIt: Person + Laptop
      // ========================================================
      framePassed = isPerson && mlOutput.isLaptopDetected;
      isSpatialValid = mlOutput.isLaptopDetected;
      isTemporalValid = mlOutput.isLaptopDetected;
      isBoxValid = mlOutput.isLaptopDetected;
    }

    // Temporal Filter: Require consecutive valid frames (3 frames)
    if (framePassed) {
      _consecutiveValidFrames++;
      _consecutiveInvalidFrames = 0;
    } else {
      _consecutiveInvalidFrames++;
      _consecutiveValidFrames = 0;
      if (isBookTask && _consecutiveInvalidFrames >= 2) {
        _lastBookCenter = null;
      }
    }

    final bool isValidWorkingState = _consecutiveValidFrames >= requiredConsecutiveValid;

    // Construct clear diagnostic status description
    String description;
    if (framePassed && isValidWorkingState) {
      description = isBookTask
          ? 'Reading Verified: Person + Book detected ✓'
          : 'Working Verified: Person + Laptop detected ✓';
    } else if (framePassed && !isValidWorkingState) {
      description = isBookTask
          ? 'Verifying reading activity: $_consecutiveValidFrames / $requiredConsecutiveValid frames...'
          : 'Verifying working activity: $_consecutiveValidFrames / $requiredConsecutiveValid frames...';
    } else {
      if (!isPerson && !isTargetObject) {
        description = isBookTask
            ? 'No person or book detected. Position camera towards reading workspace.'
            : 'No person or laptop detected. Position camera towards workspace.';
      } else if (!isPerson) {
        description = 'No person detected. Position camera towards yourself.';
      } else if (!isTargetObject) {
        description = isBookTask
            ? 'No book detected in view.'
            : 'No laptop detected in view.';
      } else if (isBookTask) {
        if (!isBoxValid) {
          description = 'Detected object has invalid book size/aspect ratio (background noise rejected).';
        } else if (!isSpatialValid) {
          description = 'Book detected outside reading zone. Hold or place book in front of you.';
        } else if (!isTemporalValid) {
          description = 'Book detection unstable. Hold book steady.';
        } else {
          description = 'Verifying book reading position...';
        }
      } else {
        description = 'Adjusting laptop view...';
      }
    }

    final compositeConfidence = (personConf * 0.50) + (targetConf * 0.50);

    return VisionDetectionResult(
      isPersonDetected: isPerson,
      isLaptopDetected: mlOutput.isLaptopDetected,
      isBookDetected: mlOutput.isBookDetected,
      isTargetObjectDetected: isTargetObject,
      personConfidence: personConf,
      laptopConfidence: laptopConf,
      bookConfidence: bookConf,
      objectConfidence: targetConf,
      confidence: compositeConfidence,
      personBoundingBox: personBox,
      laptopBoundingBox: laptopBox,
      bookBoundingBox: bookBox,
      targetBoundingBox: targetBox,
      rawDetections: mlOutput.rawDetections,
      consecutiveValidFrames: _consecutiveValidFrames,
      isValidWorkingState: isValidWorkingState,
      isSpatialRelationValid: isSpatialValid,
      isTemporalStabilityValid: isTemporalValid,
      bookValidationDetails: bookValidationDetails,
      statusDescription: description,
      inferenceTimeMs: mlOutput.inferenceTimeMs,
      framesReceived: framesReceived,
      framesProcessed: framesProcessed,
      framesSkipped: framesSkipped,
      cameraStatus: cameraStatus,
      frameStatus: frameStatus,
      conversionStatus: conversionStatus,
      modelStatus: mlOutput.modelStatus,
      inferenceStatus: mlOutput.modelStatus == 'READY' ? 'RUNNING' : 'ERROR',
      confidenceThreshold: confidenceThreshold,
      frameSize: frameSize,
      sensorRotation: sensorRotation,
      timestamp: now,
    );
  }
}
