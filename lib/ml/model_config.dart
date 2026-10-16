/// Configuration constants for the MobList Object Detection model and pipeline.
class MLModelConfig {
  /// Asset path to the bundled TensorFlow Lite object detection model
  static const String modelAssetPath = 'assets/models/detect.tflite';

  /// Asset path to the bundled label map
  static const String labelMapAssetPath = 'assets/models/labelmap.txt';

  /// Required model input tensor dimensions
  static const int inputWidth = 300;
  static const int inputHeight = 300;
  static const int inputChannels = 3; // RGB
  static const int inputTensorSize = inputWidth * inputHeight * inputChannels; // 270,000 bytes

  /// Verified class indices from the SSD MobileNet v1 COCO label map
  /// 0: person
  /// 72: laptop
  /// 83: book
  static const int personClassIndex = 0;
  static const int laptopClassIndex = 72;
  static const int bookClassIndex = 83;

  /// Verified class labels
  static const String personLabel = 'person';
  static const String laptopLabel = 'laptop';
  static const String bookLabel = 'book';

  /// Default confidence threshold
  static const double defaultConfidenceThreshold = 0.40;

  /// Debug-configurable confidence thresholds
  static const List<double> availableConfidenceThresholds = [
    0.30,
    0.40,
    0.50,
    0.60,
    0.70,
  ];

  /// Number of consecutive valid frames required before activity is verified
  static const int requiredConsecutiveValidFrames = 3;

  /// Grace period in seconds when valid activity disappears temporarily
  static const int gracePeriodSeconds = 30;

  /// Frame sampling rate: process 1 in every N camera frames (~7-8 fps)
  static const int frameSamplingStride = 4;

  /// Stricter book validation parameters to reject random background noise
  static const double bookMinBoxArea = 0.008; // at least ~0.8% of screen area
  static const double bookMaxBoxArea = 0.70; // at most 70% of screen area
  static const double bookMinAspectRatio = 0.30;
  static const double bookMaxAspectRatio = 3.0;
  static const double bookMaxCenterDisplacement = 0.40; // Max allowed center jump between frames
  static const double bookReadingZonePaddingX = 0.30; // Person reach horizontally
  static const double bookReadingZonePaddingY = 0.45; // Person reach downward into desk/lap zone

  /// Helper to check if a label or class index is one of our 3 targets (person, laptop, book)
  static bool isTargetClass(String label, [int? classIndex]) {
    final lower = label.toLowerCase();
    return lower == personLabel ||
        lower == laptopLabel ||
        lower == bookLabel ||
        classIndex == personClassIndex ||
        classIndex == laptopClassIndex ||
        classIndex == bookClassIndex;
  }
}
