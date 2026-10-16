import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'model_config.dart';

/// Result of converting a camera frame into the model's input format
class ImageConversionResult {
  final bool isSuccess;
  final Uint8List? rgbBytes;
  final int width;
  final int height;
  final int rotation;
  final String format;
  final String? errorMessage;

  const ImageConversionResult({
    required this.isSuccess,
    this.rgbBytes,
    required this.width,
    required this.height,
    required this.rotation,
    required this.format,
    this.errorMessage,
  });

  factory ImageConversionResult.success({
    required Uint8List rgbBytes,
    required int width,
    required int height,
    required int rotation,
    required String format,
  }) {
    return ImageConversionResult(
      isSuccess: true,
      rgbBytes: rgbBytes,
      width: width,
      height: height,
      rotation: rotation,
      format: format,
    );
  }

  factory ImageConversionResult.failure({
    required String error,
    int width = 0,
    int height = 0,
    int rotation = 0,
    String format = 'unknown',
  }) {
    return ImageConversionResult(
      isSuccess: false,
      rgbBytes: null,
      width: width,
      height: height,
      rotation: rotation,
      format: format,
      errorMessage: error,
    );
  }
}

/// High-performance converter from live CameraImage to 300x300 RGB tensor
class CameraImageConverter {
  static const int targetW = MLModelConfig.inputWidth;
  static const int targetH = MLModelConfig.inputHeight;
  static const int targetBytesCount = MLModelConfig.inputTensorSize;

  /// Converts a CameraImage into a 300x300 RGB byte buffer
  static ImageConversionResult convertToModelInput({
    required CameraImage image,
    required int sensorRotation,
    required bool isFrontCamera,
  }) {
    try {
      final int srcW = image.width;
      final int srcH = image.height;
      final int planesCount = image.planes.length;
      final formatName = image.format.group.name;

      if (srcW <= 0 || srcH <= 0 || planesCount == 0) {
        return ImageConversionResult.failure(
          error: 'Invalid frame dimensions: ${srcW}x$srcH, planes: $planesCount',
          width: srcW,
          height: srcH,
          rotation: sensorRotation,
          format: formatName,
        );
      }

      final outRgb = Uint8List(targetBytesCount);

      // Branch 1: Android Multi-plane YUV420 / YUV_420_888 (3 planes)
      if (planesCount >= 3) {
        _convertYuv420Planes(
          image: image,
          srcW: srcW,
          srcH: srcH,
          rotation: sensorRotation,
          isFrontCamera: isFrontCamera,
          outRgb: outRgb,
        );
      }
      // Branch 2: Android 2-plane Semi-planar NV21 / NV12
      else if (planesCount == 2) {
        _convertNv21SemiPlanar(
          image: image,
          srcW: srcW,
          srcH: srcH,
          rotation: sensorRotation,
          isFrontCamera: isFrontCamera,
          outRgb: outRgb,
        );
      }
      // Branch 3: Single plane (BGRA8888 on iOS or single-buffer NV21)
      else if (planesCount == 1) {
        final plane = image.planes[0];
        final bytesPerPixel = plane.bytesPerPixel ?? 4;
        if (bytesPerPixel >= 4) {
          _convertBgra8888(
            plane: plane,
            srcW: srcW,
            srcH: srcH,
            rotation: sensorRotation,
            isFrontCamera: isFrontCamera,
            outRgb: outRgb,
          );
        } else {
          // Single-buffer YUV/NV21
          _convertNv21SinglePlane(
            plane: plane,
            srcW: srcW,
            srcH: srcH,
            rotation: sensorRotation,
            isFrontCamera: isFrontCamera,
            outRgb: outRgb,
          );
        }
      }

      return ImageConversionResult.success(
        rgbBytes: outRgb,
        width: srcW,
        height: srcH,
        rotation: sensorRotation,
        format: formatName,
      );
    } catch (e, stack) {
      debugPrint('[CameraImageConverter] Conversion error: $e\n$stack');
      return ImageConversionResult.failure(
        error: 'Image conversion failed: $e',
        width: image.width,
        height: image.height,
        rotation: sensorRotation,
        format: image.format.group.name,
      );
    }
  }

  /// Direct resampling of 3-plane YUV420_888 with rotation
  static void _convertYuv420Planes({
    required CameraImage image,
    required int srcW,
    required int srcH,
    required int rotation,
    required bool isFrontCamera,
    required Uint8List outRgb,
  }) {
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final Uint8List yBytes = yPlane.bytes;
    final Uint8List uBytes = uPlane.bytes;
    final Uint8List vBytes = vPlane.bytes;

    final int yRowStride = yPlane.bytesPerRow;
    final int yPixelStride = yPlane.bytesPerPixel ?? 1;

    final int uRowStride = uPlane.bytesPerRow;
    final int uPixelStride = uPlane.bytesPerPixel ?? 1;

    final int vRowStride = vPlane.bytesPerRow;
    final int vPixelStride = vPlane.bytesPerPixel ?? 1;

    int outIdx = 0;

    for (int y = 0; y < targetH; y++) {
      final double vNorm = y / (targetH - 1);
      for (int x = 0; x < targetW; x++) {
        final double uNorm = x / (targetW - 1);

        double su = uNorm;
        double sv = vNorm;

        // Apply sensor rotation
        if (rotation == 90) {
          su = vNorm;
          sv = 1.0 - uNorm;
        } else if (rotation == 180) {
          su = 1.0 - uNorm;
          sv = 1.0 - vNorm;
        } else if (rotation == 270) {
          su = 1.0 - vNorm;
          sv = uNorm;
        }

        final int srcX = (su * (srcW - 1)).round().clamp(0, srcW - 1);
        final int srcY = (sv * (srcH - 1)).round().clamp(0, srcH - 1);

        final int yIndex = srcY * yRowStride + srcX * yPixelStride;
        final int uvX = srcX >> 1;
        final int uvY = srcY >> 1;

        final int uIndex = uvY * uRowStride + uvX * uPixelStride;
        final int vIndex = uvY * vRowStride + uvX * vPixelStride;

        final int yVal = (yIndex < yBytes.length) ? yBytes[yIndex] : 0;
        final int uVal = (uIndex < uBytes.length) ? uBytes[uIndex] - 128 : 0;
        final int vVal = (vIndex < vBytes.length) ? vBytes[vIndex] - 128 : 0;

        // Fast full-range BT.601 integer conversion
        final int r = (yVal + ((359 * vVal) >> 8)).clamp(0, 255);
        final int g = (yVal - ((88 * uVal + 183 * vVal) >> 8)).clamp(0, 255);
        final int b = (yVal + ((454 * uVal) >> 8)).clamp(0, 255);

        outRgb[outIdx++] = r;
        outRgb[outIdx++] = g;
        outRgb[outIdx++] = b;
      }
    }
  }

  /// 2-plane NV21 semi-planar converter
  static void _convertNv21SemiPlanar({
    required CameraImage image,
    required int srcW,
    required int srcH,
    required int rotation,
    required bool isFrontCamera,
    required Uint8List outRgb,
  }) {
    final yPlane = image.planes[0];
    final uvPlane = image.planes[1];

    final Uint8List yBytes = yPlane.bytes;
    final Uint8List uvBytes = uvPlane.bytes;

    final int yRowStride = yPlane.bytesPerRow;
    final int yPixelStride = yPlane.bytesPerPixel ?? 1;
    final int uvRowStride = uvPlane.bytesPerRow;

    int outIdx = 0;

    for (int y = 0; y < targetH; y++) {
      final double vNorm = y / (targetH - 1);
      for (int x = 0; x < targetW; x++) {
        final double uNorm = x / (targetW - 1);

        double su = uNorm;
        double sv = vNorm;

        if (rotation == 90) {
          su = vNorm;
          sv = 1.0 - uNorm;
        } else if (rotation == 180) {
          su = 1.0 - uNorm;
          sv = 1.0 - vNorm;
        } else if (rotation == 270) {
          su = 1.0 - vNorm;
          sv = uNorm;
        }

        final int srcX = (su * (srcW - 1)).round().clamp(0, srcW - 1);
        final int srcY = (sv * (srcH - 1)).round().clamp(0, srcH - 1);

        final int yIndex = srcY * yRowStride + srcX * yPixelStride;
        final int uvX = srcX >> 1;
        final int uvY = srcY >> 1;
        final int uvIndex = uvY * uvRowStride + (uvX * 2);

        final int yVal = (yIndex < yBytes.length) ? yBytes[yIndex] : 0;
        final int vVal = (uvIndex < uvBytes.length) ? uvBytes[uvIndex] - 128 : 0;
        final int uVal = (uvIndex + 1 < uvBytes.length) ? uvBytes[uvIndex + 1] - 128 : 0;

        final int r = (yVal + ((359 * vVal) >> 8)).clamp(0, 255);
        final int g = (yVal - ((88 * uVal + 183 * vVal) >> 8)).clamp(0, 255);
        final int b = (yVal + ((454 * uVal) >> 8)).clamp(0, 255);

        outRgb[outIdx++] = r;
        outRgb[outIdx++] = g;
        outRgb[outIdx++] = b;
      }
    }
  }

  /// Single-plane NV21 buffer converter
  static void _convertNv21SinglePlane({
    required Plane plane,
    required int srcW,
    required int srcH,
    required int rotation,
    required bool isFrontCamera,
    required Uint8List outRgb,
  }) {
    final Uint8List bytes = plane.bytes;
    final int ySize = srcW * srcH;
    int outIdx = 0;

    for (int y = 0; y < targetH; y++) {
      final double vNorm = y / (targetH - 1);
      for (int x = 0; x < targetW; x++) {
        final double uNorm = x / (targetW - 1);

        double su = uNorm;
        double sv = vNorm;

        if (rotation == 90) {
          su = vNorm;
          sv = 1.0 - uNorm;
        } else if (rotation == 180) {
          su = 1.0 - uNorm;
          sv = 1.0 - vNorm;
        } else if (rotation == 270) {
          su = 1.0 - vNorm;
          sv = uNorm;
        }

        final int srcX = (su * (srcW - 1)).round().clamp(0, srcW - 1);
        final int srcY = (sv * (srcH - 1)).round().clamp(0, srcH - 1);

        final int yIndex = srcY * srcW + srcX;
        final int uvX = srcX >> 1;
        final int uvY = srcY >> 1;
        final int uvIndex = ySize + (uvY * srcW) + (uvX * 2);

        final int yVal = (yIndex < bytes.length) ? bytes[yIndex] : 0;
        final int vVal = (uvIndex < bytes.length) ? bytes[uvIndex] - 128 : 0;
        final int uVal = (uvIndex + 1 < bytes.length) ? bytes[uvIndex + 1] - 128 : 0;

        final int r = (yVal + ((359 * vVal) >> 8)).clamp(0, 255);
        final int g = (yVal - ((88 * uVal + 183 * vVal) >> 8)).clamp(0, 255);
        final int b = (yVal + ((454 * uVal) >> 8)).clamp(0, 255);

        outRgb[outIdx++] = r;
        outRgb[outIdx++] = g;
        outRgb[outIdx++] = b;
      }
    }
  }

  /// iOS BGRA8888 converter
  static void _convertBgra8888({
    required Plane plane,
    required int srcW,
    required int srcH,
    required int rotation,
    required bool isFrontCamera,
    required Uint8List outRgb,
  }) {
    final Uint8List bytes = plane.bytes;
    final int rowStride = plane.bytesPerRow;
    final int pixelStride = plane.bytesPerPixel ?? 4;
    int outIdx = 0;

    for (int y = 0; y < targetH; y++) {
      final double vNorm = y / (targetH - 1);
      for (int x = 0; x < targetW; x++) {
        final double uNorm = x / (targetW - 1);

        double su = uNorm;
        double sv = vNorm;

        if (rotation == 90) {
          su = vNorm;
          sv = 1.0 - uNorm;
        } else if (rotation == 180) {
          su = 1.0 - uNorm;
          sv = 1.0 - vNorm;
        } else if (rotation == 270) {
          su = 1.0 - vNorm;
          sv = uNorm;
        }

        final int srcX = (su * (srcW - 1)).round().clamp(0, srcW - 1);
        final int srcY = (sv * (srcH - 1)).round().clamp(0, srcH - 1);

        final int offset = srcY * rowStride + srcX * pixelStride;

        if (offset + 2 < bytes.length) {
          final int b = bytes[offset];
          final int g = bytes[offset + 1];
          final int r = bytes[offset + 2];
          outRgb[outIdx++] = r;
          outRgb[outIdx++] = g;
          outRgb[outIdx++] = b;
        } else {
          outRgb[outIdx++] = 0;
          outRgb[outIdx++] = 0;
          outRgb[outIdx++] = 0;
        }
      }
    }
  }
}
