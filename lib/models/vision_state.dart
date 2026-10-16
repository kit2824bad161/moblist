import 'dart:ui';

/// Session state of the productive activity timer
enum ProductiveState {
  idle,
  cameraStarting,
  verifying,
  productive,
  gracePeriod,
  paused,
  completed,
  cameraStopped,
  error,
}

/// Represents a single detected object from ML inference
class DetectedItem {
  final String label;
  final int classIndex;
  final double confidence;
  final Rect boundingBox;
  final bool isAccepted;

  const DetectedItem({
    required this.label,
    this.classIndex = -1,
    required this.confidence,
    required this.boundingBox,
    this.isAccepted = false,
  });

  @override
  String toString() =>
      '$label: ${(confidence * 100).toStringAsFixed(1)}% [${boundingBox.left.toInt()}, ${boundingBox.top.toInt()}, ${boundingBox.width.toInt()}, ${boundingBox.height.toInt()}]';
}

/// Comprehensive ML vision detection result for a single frame
class VisionDetectionResult {
  final bool isPersonDetected;
  final bool isLaptopDetected;
  final bool isBookDetected;
  final bool isTargetObjectDetected;

  final double personConfidence;
  final double laptopConfidence;
  final double bookConfidence;
  final double objectConfidence;
  final double confidence;

  final Rect? personBoundingBox;
  final Rect? laptopBoundingBox;
  final Rect? bookBoundingBox;
  final Rect? targetBoundingBox;

  /// All raw detections produced by the ML model before task-specific filtering
  final List<DetectedItem> rawDetections;

  /// Number of consecutive valid frames accumulated
  final int consecutiveValidFrames;

  /// True when required consecutive valid frames are achieved
  final bool isValidWorkingState;

  /// Book-specific strict verification fields
  final bool isSpatialRelationValid;
  final bool isTemporalStabilityValid;
  final String bookValidationDetails;

  final String statusDescription;
  final int inferenceTimeMs;
  final int framesReceived;
  final int framesProcessed;
  final int framesSkipped;

  // ML Debug status indicators
  final String cameraStatus;
  final String frameStatus;
  final String conversionStatus;
  final String modelStatus;
  final String inferenceStatus;

  final String? errorMessage;
  final Size? frameSize;
  final int sensorRotation;
  final double confidenceThreshold;
  final DateTime timestamp;

  const VisionDetectionResult({
    required this.isPersonDetected,
    this.isLaptopDetected = false,
    this.isBookDetected = false,
    required this.isTargetObjectDetected,
    this.personConfidence = 0.0,
    this.laptopConfidence = 0.0,
    this.bookConfidence = 0.0,
    this.objectConfidence = 0.0,
    required this.confidence,
    this.personBoundingBox,
    this.laptopBoundingBox,
    this.bookBoundingBox,
    this.targetBoundingBox,
    this.rawDetections = const [],
    this.consecutiveValidFrames = 0,
    this.isValidWorkingState = false,
    this.isSpatialRelationValid = false,
    this.isTemporalStabilityValid = false,
    this.bookValidationDetails = '',
    required this.statusDescription,
    this.inferenceTimeMs = 0,
    this.framesReceived = 0,
    this.framesProcessed = 0,
    this.framesSkipped = 0,
    this.cameraStatus = 'READY',
    this.frameStatus = 'RECEIVED',
    this.conversionStatus = 'SUCCESS',
    this.modelStatus = 'READY',
    this.inferenceStatus = 'RUNNING',
    this.errorMessage,
    this.frameSize,
    this.sensorRotation = 0,
    this.confidenceThreshold = 0.40,
    required this.timestamp,
  });

  /// Backward-compatible posture getter (ML requires Person + Object)
  bool get isPostureValid => isPersonDetected;
  double get postureConfidence => personConfidence;

  factory VisionDetectionResult.initial() {
    return VisionDetectionResult(
      isPersonDetected: false,
      isLaptopDetected: false,
      isBookDetected: false,
      isTargetObjectDetected: false,
      confidence: 0.0,
      statusDescription: 'Initializing visual verification...',
      cameraStatus: 'READY',
      frameStatus: 'NOT RECEIVED',
      conversionStatus: 'NOT RECEIVED',
      modelStatus: 'INITIALIZING',
      inferenceStatus: 'IDLE',
      timestamp: DateTime.now(),
    );
  }

  factory VisionDetectionResult.error(
    String error, {
    String modelStatus = 'ERROR',
    String conversionStatus = 'ERROR',
    String inferenceStatus = 'ERROR',
  }) {
    return VisionDetectionResult(
      isPersonDetected: false,
      isLaptopDetected: false,
      isBookDetected: false,
      isTargetObjectDetected: false,
      confidence: 0.0,
      statusDescription: error,
      cameraStatus: 'ERROR',
      frameStatus: 'NOT RECEIVED',
      conversionStatus: conversionStatus,
      modelStatus: modelStatus,
      inferenceStatus: inferenceStatus,
      errorMessage: error,
      timestamp: DateTime.now(),
    );
  }
}
