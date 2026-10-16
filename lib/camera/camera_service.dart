import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import '../ml/model_config.dart';

class CameraService {
  CameraController? _controller;
  bool _isInitializing = false;
  bool _isStreaming = false;
  List<CameraDescription> _availableCameras = [];
  int _selectedCameraIndex = 0;

  CameraController? get controller => _controller;
  bool get isInitialized => _controller != null && _controller!.value.isInitialized;
  bool get isStreaming => _isStreaming;
  CameraDescription? get currentCamera =>
      _availableCameras.isNotEmpty && _selectedCameraIndex < _availableCameras.length
          ? _availableCameras[_selectedCameraIndex]
          : null;

  int get sensorOrientation => currentCamera?.sensorOrientation ?? 0;
  bool get isFrontCamera => currentCamera?.lensDirection == CameraLensDirection.front;

  Future<void> initializeCameras() async {
    try {
      _availableCameras = await availableCameras();
      // Default to front camera if available (best for laptop/reading task verification),
      // otherwise fallback to back camera.
      final frontIdx = _availableCameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
      );
      if (frontIdx != -1) {
        _selectedCameraIndex = frontIdx;
      } else {
        _selectedCameraIndex = 0;
      }
    } catch (e) {
      debugPrint('[CameraService] Error getting available cameras: $e');
    }
  }

  Future<bool> startCamera({
    required Function(CameraImage image) onFrame,
    Function(String error)? onError,
  }) async {
    if (_isInitializing || isInitialized) return true;
    _isInitializing = true;

    try {
      if (_availableCameras.isEmpty) {
        await initializeCameras();
      }

      if (_availableCameras.isEmpty) {
        onError?.call('No cameras available on this device.');
        _isInitializing = false;
        return false;
      }

      final camera = _availableCameras[_selectedCameraIndex];
      // Use Medium resolution (approx 720p or 480p) to optimize battery & processing speed
      _controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: !kIsWeb && Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await _controller!.initialize();

      int frameCounter = 0;
      await _controller!.startImageStream((CameraImage image) {
        // Frame throttling: sample 1 in every N frames (~7-8 fps)
        frameCounter++;
        if (frameCounter % MLModelConfig.frameSamplingStride == 0) {
          onFrame(image);
        }
      });

      _isStreaming = true;
      _isInitializing = false;
      return true;
    } catch (e) {
      debugPrint('[CameraService] Error starting camera: $e');
      onError?.call('Camera error: $e');
      await stopCamera();
      _isInitializing = false;
      return false;
    }
  }

  Future<void> switchCamera({
    required Function(CameraImage image) onFrame,
    Function(String error)? onError,
  }) async {
    if (_availableCameras.length <= 1) return;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _availableCameras.length;
    await stopCamera();
    await startCamera(onFrame: onFrame, onError: onError);
  }

  Future<void> stopCamera() async {
    try {
      _isStreaming = false;
      if (_controller != null) {
        if (_controller!.value.isStreamingImages) {
          await _controller!.stopImageStream();
        }
        await _controller!.dispose();
        _controller = null;
      }
    } catch (e) {
      debugPrint('[CameraService] Error disposing camera: $e');
      _controller = null;
    } finally {
      _isInitializing = false;
    }
  }
}
