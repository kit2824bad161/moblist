import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import '../models/vision_state.dart';
import 'model_config.dart';
import 'camera_image_converter.dart';
import 'ml_object_detector.dart';
import 'moblist_task_verifier.dart';

/// Clean, unified Camera ML Detection Pipeline for MobList
class MLVisionDetector {
  final MLObjectDetector _detector = MLObjectDetector();
  final MobListTaskVerifier _verifier;

  int _framesProcessed = 0;

  bool get isInitialized => _detector.isInitialized;
  String get modelStatus => _detector.modelStatus;
  String? get initError => _detector.initError;
  double get confidenceThreshold => _detector.confidenceThreshold;
  int get consecutiveValidFrames => _verifier.consecutiveValidFrames;

  MLVisionDetector({
    double confidenceThreshold = MLModelConfig.defaultConfidenceThreshold,
    int requiredConsecutiveValid = MLModelConfig.requiredConsecutiveValidFrames,
  }) : _verifier = MobListTaskVerifier(requiredConsecutiveValid: requiredConsecutiveValid) {
    _detector.setConfidenceThreshold(confidenceThreshold);
  }

  void setConfidenceThreshold(double threshold) {
    _detector.setConfidenceThreshold(threshold);
  }

  void resetTemporalState() {
    _verifier.reset();
  }

  Future<void> initialize() async {
    await _detector.initialize();
  }

  /// Processes live camera frame through genuine on-device ML model
  Future<VisionDetectionResult> processLiveFrame({
    required CameraImage image,
    required int sensorRotation,
    required bool isFrontCamera,
    required bool isBookTask,
    required int framesReceived,
    required int framesSkipped,
  }) async {
    _framesProcessed++;

    // Step 1: Image conversion from CameraImage to 300x300 RGB
    final conversion = CameraImageConverter.convertToModelInput(
      image: image,
      sensorRotation: sensorRotation,
      isFrontCamera: isFrontCamera,
    );

    if (!conversion.isSuccess || conversion.rgbBytes == null) {
      debugPrint('[ML PIPELINE] Image conversion error: ${conversion.errorMessage}');
      return VisionDetectionResult(
        isPersonDetected: false,
        isLaptopDetected: false,
        isBookDetected: false,
        isTargetObjectDetected: false,
        confidence: 0.0,
        statusDescription: 'Image conversion error: ${conversion.errorMessage}',
        cameraStatus: 'READY',
        frameStatus: 'RECEIVED',
        conversionStatus: 'ERROR',
        modelStatus: _detector.modelStatus,
        inferenceStatus: 'ERROR',
        errorMessage: conversion.errorMessage,
        confidenceThreshold: _detector.confidenceThreshold,
        framesReceived: framesReceived,
        framesProcessed: _framesProcessed,
        framesSkipped: framesSkipped,
        frameSize: Size(image.width.toDouble(), image.height.toDouble()),
        sensorRotation: sensorRotation,
        timestamp: DateTime.now(),
      );
    }

    // Step 2: Run genuine TensorFlow Lite inference
    final mlOutput = await _detector.runInference(
      rgbBytes: conversion.rgbBytes!,
      thresholdOverride: _detector.confidenceThreshold,
    );

    // Diagnostic logging of raw detections
    if (mlOutput.rawDetections.isEmpty) {
      debugPrint('[ML PIPELINE] RAW DETECTIONS: 0 objects detected');
    } else {
      debugPrint('[ML PIPELINE] RAW DETECTIONS (${mlOutput.rawDetections.length} total, ${mlOutput.targetDetections.length} target):');
      for (final det in mlOutput.rawDetections) {
        debugPrint('  • ${det.label} ${(det.confidence * 100).toInt()}% [accepted: ${det.isAccepted}] ${det.boundingBox}');
      }
    }

    // Step 3: Evaluate against MobList task requirements and 3-frame gate
    final result = _verifier.evaluateFrame(
      mlOutput: mlOutput,
      isBookTask: isBookTask,
      framesReceived: framesReceived,
      framesProcessed: _framesProcessed,
      framesSkipped: framesSkipped,
      confidenceThreshold: _detector.confidenceThreshold,
      frameSize: Size(image.width.toDouble(), image.height.toDouble()),
      sensorRotation: sensorRotation,
      cameraStatus: 'READY',
      frameStatus: 'RECEIVED',
      conversionStatus: 'SUCCESS',
    );

    return result;
  }

  /// Helper for evaluating raw detections in automated unit tests
  @visibleForTesting
  VisionDetectionResult evaluateRawDetections({
    required List<DetectedItem> detections,
    required bool isBookTask,
  }) {
    final targetItems = detections
        .where((d) => d.isAccepted || MLModelConfig.isTargetClass(d.label, d.classIndex))
        .toList();
    DetectedItem? bestPerson;
    DetectedItem? bestLaptop;
    DetectedItem? bestBook;

    for (final item in targetItems) {
      final lower = item.label.toLowerCase();
      if (lower == 'person' || item.classIndex == MLModelConfig.personClassIndex) {
        if (bestPerson == null || item.confidence > bestPerson.confidence) {
          bestPerson = item;
        }
      } else if (lower == 'laptop' || item.classIndex == MLModelConfig.laptopClassIndex) {
        if (bestLaptop == null || item.confidence > bestLaptop.confidence) {
          bestLaptop = item;
        }
      } else if (lower == 'book' || item.classIndex == MLModelConfig.bookClassIndex) {
        if (bestBook == null || item.confidence > bestBook.confidence) {
          bestBook = item;
        }
      }
    }

    final mlOutput = MLInferenceOutput(
      rawDetections: detections,
      targetDetections: targetItems,
      bestPerson: bestPerson,
      bestLaptop: bestLaptop,
      bestBook: bestBook,
      inferenceTimeMs: 15,
      modelStatus: 'READY',
    );

    return _verifier.evaluateFrame(
      mlOutput: mlOutput,
      isBookTask: isBookTask,
      framesReceived: 1,
      framesProcessed: 1,
      framesSkipped: 0,
      confidenceThreshold: _detector.confidenceThreshold,
    );
  }

  void dispose() {
    _detector.dispose();
  }
}
