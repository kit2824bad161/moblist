import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';
import '../models/vision_state.dart';
import 'model_config.dart';

/// Container for the parsed ML inference outputs for a single frame
class MLInferenceOutput {
  final List<DetectedItem> rawDetections;
  final List<DetectedItem> targetDetections;
  final DetectedItem? bestPerson;
  final DetectedItem? bestLaptop;
  final DetectedItem? bestBook;
  final int inferenceTimeMs;
  final String modelStatus;

  const MLInferenceOutput({
    required this.rawDetections,
    required this.targetDetections,
    this.bestPerson,
    this.bestLaptop,
    this.bestBook,
    required this.inferenceTimeMs,
    this.modelStatus = 'READY',
  });

  bool get isPersonDetected => bestPerson != null;
  bool get isLaptopDetected => bestLaptop != null;
  bool get isBookDetected => bestBook != null;

  double get personConfidence => bestPerson?.confidence ?? 0.0;
  double get laptopConfidence => bestLaptop?.confidence ?? 0.0;
  double get bookConfidence => bestBook?.confidence ?? 0.0;
}

/// Production on-device TensorFlow Lite Object Detector for MobList
class MLObjectDetector {
  Interpreter? _interpreter;
  List<String> _labels = [];

  bool _isInitializing = false;
  bool _isInitialized = false;
  String _modelStatus = 'INITIALIZING';
  String? _initError;

  double _confidenceThreshold = MLModelConfig.defaultConfidenceThreshold;

  bool get isInitialized => _isInitialized;
  String get modelStatus => _modelStatus;
  String? get initError => _initError;
  double get confidenceThreshold => _confidenceThreshold;

  void setConfidenceThreshold(double threshold) {
    _confidenceThreshold = threshold;
    debugPrint('[MLObjectDetector] Confidence threshold updated to: $_confidenceThreshold');
  }

  /// Initializes the TFLite Interpreter and loads labels
  Future<void> initialize() async {
    if (_isInitialized || _isInitializing) return;
    _isInitializing = true;
    _modelStatus = 'INITIALIZING';
    _initError = null;

    try {
      // 1. Load label map from assets
      final labelData = await rootBundle.loadString(MLModelConfig.labelMapAssetPath);
      _labels = labelData
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();

      // 2. Initialize TFLite Interpreter
      final options = InterpreterOptions()..threads = 4;
      if (!kIsWeb && Platform.isAndroid) {
        // Use multi-threaded CPU for rock-solid stability across all Android chipsets
        options.useNnApiForAndroid = false;
      }

      _interpreter = await Interpreter.fromAsset(
        MLModelConfig.modelAssetPath,
        options: options,
      );

      // Verify tensor shapes
      final inputTensors = _interpreter!.getInputTensors();
      final outputTensors = _interpreter!.getOutputTensors();

      _isInitialized = true;
      _modelStatus = 'READY';

      final personLabel = _labels.isNotEmpty ? _labels[0] : 'person';
      final laptopLabel = _labels.length > 72 ? _labels[72] : 'laptop';
      final bookLabel = _labels.length > 83 ? _labels[83] : 'book';

      // Mandated diagnostic startup log
      debugPrint('''
==================================================
MODEL LOADED: ${MLModelConfig.modelAssetPath}
MODEL INPUT: ${inputTensors.map((t) => '${t.name} ${t.shape} ${t.type}').join(', ')}
MODEL OUTPUT: ${outputTensors.map((t) => '${t.name} ${t.shape} ${t.type}').join(', ')}
LABEL COUNT: ${_labels.length}
PERSON CLASS: ${MLModelConfig.personClassIndex} ($personLabel)
LAPTOP CLASS: ${MLModelConfig.laptopClassIndex} ($laptopLabel)
BOOK CLASS: ${MLModelConfig.bookClassIndex} ($bookLabel)
==================================================''');
    } catch (e, stack) {
      _isInitialized = false;
      _modelStatus = 'MODEL INITIALIZATION FAILED';
      _initError = e.toString();
      debugPrint('[MLObjectDetector] Initialization failed: $e\n$stack');
    } finally {
      _isInitializing = false;
    }
  }

  /// Runs real ML inference on a 300x300 RGB byte buffer
  Future<MLInferenceOutput> runInference({
    required Uint8List rgbBytes,
    double? thresholdOverride,
  }) async {
    final threshold = thresholdOverride ?? _confidenceThreshold;

    if (!_isInitialized || _interpreter == null) {
      if (_initError != null) {
        return MLInferenceOutput(
          rawDetections: const [],
          targetDetections: const [],
          inferenceTimeMs: 0,
          modelStatus: 'MODEL INITIALIZATION FAILED: $_initError',
        );
      }
      await initialize();
      if (!_isInitialized || _interpreter == null) {
        return const MLInferenceOutput(
          rawDetections: [],
          targetDetections: [],
          inferenceTimeMs: 0,
          modelStatus: 'INITIALIZING',
        );
      }
    }

    final stopwatch = Stopwatch()..start();

    try {
      // 1. Prepare input tensor: [1, 300, 300, 3] UINT8
      // Fast reshape from Uint8List into [1, 300, 300, 3] nested list
      final input = List.generate(
        1,
        (_) => List.generate(
          MLModelConfig.inputHeight,
          (y) => List.generate(
            MLModelConfig.inputWidth,
            (x) {
              final idx = (y * MLModelConfig.inputWidth + x) * 3;
              return [
                rgbBytes[idx],
                rgbBytes[idx + 1],
                rgbBytes[idx + 2],
              ];
            },
          ),
        ),
      );

      // 2. Prepare output tensor buffers:
      // Output 0: Locations [1, 10, 4] (ymin, xmin, ymax, xmax)
      final outputLocations = List.generate(
        1,
        (_) => List.generate(10, (_) => List<double>.filled(4, 0.0)),
      );
      // Output 1: Classes [1, 10]
      final outputClasses = List.generate(
        1,
        (_) => List<double>.filled(10, 0.0),
      );
      // Output 2: Scores [1, 10]
      final outputScores = List.generate(
        1,
        (_) => List<double>.filled(10, 0.0),
      );
      // Output 3: Number of detections [1]
      final numDetections = List<double>.filled(1, 0.0);

      final outputs = {
        0: outputLocations,
        1: outputClasses,
        2: outputScores,
        3: numDetections,
      };

      // 3. Execute genuine on-device ML model inference
      _interpreter!.runForMultipleInputs([input], outputs);

      stopwatch.stop();
      final inferenceDuration = stopwatch.elapsedMilliseconds;
      debugPrint('[ML PIPELINE] Inference time: $inferenceDuration ms');

      // 4. Parse raw detections from model outputs
      final numDet = numDetections[0].toInt().clamp(0, 10);
      final rawLocations = outputLocations[0];
      final rawClasses = outputClasses[0];
      final rawScores = outputScores[0];

      return parseRawOutputs(
        numDetections: numDet,
        locations: rawLocations,
        classes: rawClasses,
        scores: rawScores,
        threshold: threshold,
        inferenceTimeMs: inferenceDuration,
      );
    } catch (e, stack) {
      stopwatch.stop();
      debugPrint('[MLObjectDetector] Inference error: $e\n$stack');
      return MLInferenceOutput(
        rawDetections: const [],
        targetDetections: const [],
        inferenceTimeMs: stopwatch.elapsedMilliseconds,
        modelStatus: 'INFERENCE ERROR: $e',
      );
    }
  }

  /// Parses raw model outputs into structured detections
  MLInferenceOutput parseRawOutputs({
    required int numDetections,
    required List<List<double>> locations,
    required List<double> classes,
    required List<double> scores,
    required double threshold,
    required int inferenceTimeMs,
  }) {
    final List<DetectedItem> rawItems = [];
    final List<DetectedItem> targetItems = [];

    DetectedItem? bestPerson;
    DetectedItem? bestLaptop;
    DetectedItem? bestBook;

    for (int i = 0; i < numDetections; i++) {
      final double score = scores[i];
      // Skip degenerate zero scores
      if (score <= 0.01) continue;

      final int classIdx = classes[i].toInt();
      final boxCoords = locations[i]; // [ymin, xmin, ymax, xmax]

      final double ymin = boxCoords[0].clamp(0.0, 1.0);
      final double xmin = boxCoords[1].clamp(0.0, 1.0);
      final double ymax = boxCoords[2].clamp(0.0, 1.0);
      final double xmax = boxCoords[3].clamp(0.0, 1.0);

      final rect = Rect.fromLTRB(xmin, ymin, xmax, ymax);

      // Label resolution
      String label = 'Class_$classIdx';
      if (_labels.isNotEmpty && classIdx >= 0 && classIdx < _labels.length) {
        label = _labels[classIdx];
      }

      final isPerson = (classIdx == MLModelConfig.personClassIndex) || (label.toLowerCase() == MLModelConfig.personLabel);
      final isLaptop = (classIdx == MLModelConfig.laptopClassIndex) || (label.toLowerCase() == MLModelConfig.laptopLabel);
      final isBook = (classIdx == MLModelConfig.bookClassIndex) || (label.toLowerCase() == MLModelConfig.bookLabel);

      String displayLabel = label;
      if (isPerson) displayLabel = 'PERSON';
      if (isLaptop) displayLabel = 'LAPTOP';
      if (isBook) displayLabel = 'BOOK';

      final bool isTargetClass = isPerson || isLaptop || isBook;
      final bool meetsConfidence = score >= threshold;
      final bool isAccepted = isTargetClass && meetsConfidence;

      final item = DetectedItem(
        label: displayLabel,
        classIndex: classIdx,
        confidence: score,
        boundingBox: rect,
        isAccepted: isAccepted,
      );

      rawItems.add(item);

      if (isAccepted) {
        targetItems.add(item);

        if (isPerson) {
          if (bestPerson == null || score > bestPerson.confidence) {
            bestPerson = item;
          }
        } else if (isLaptop) {
          if (bestLaptop == null || score > bestLaptop.confidence) {
            bestLaptop = item;
          }
        } else if (isBook) {
          if (bestBook == null || score > bestBook.confidence) {
            bestBook = item;
          }
        }
      }
    }

    return MLInferenceOutput(
      rawDetections: rawItems,
      targetDetections: targetItems,
      bestPerson: bestPerson,
      bestLaptop: bestLaptop,
      bestBook: bestBook,
      inferenceTimeMs: inferenceTimeMs,
      modelStatus: 'READY',
    );
  }

  void dispose() {
    try {
      _interpreter?.close();
      _interpreter = null;
      _isInitialized = false;
      _modelStatus = 'DISPOSED';
    } catch (e) {
      debugPrint('[MLObjectDetector] Error disposing interpreter: $e');
    }
  }
}
