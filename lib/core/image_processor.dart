import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../models/document_corners.dart';
import 'document_detector.dart';
import 'image_enhancer.dart';
import 'perspective_corrector.dart';

/// ============================================================
/// Performance Settings
/// ============================================================

/// Detection فقط روی این اندازه انجام می‌شود.
///
/// 640 نسبت به 800 به شکل محسوسی سریع‌تر است.
const int _detectionSize = 640;

/// حداکثر اندازه خروجی نهایی.
///
/// برای اسکن A4 کیفیت مناسبی دارد و از 3000 بسیار سریع‌تر است.
const int _maxOutputSize = 2200;

/// حداقل اندازه خروجی.
const int _minOutputSize = 1200;

/// کیفیت JPEG.
///
/// 92 برای اسکن معمولی کیفیت بسیار خوبی دارد و از 95 سریع‌تر است.
const int _jpegQuality = 92;

/// ============================================================
/// Process Full Image
/// ============================================================

Future<Map<String, dynamic>> processImageInIsolate(
  Map<String, dynamic> args,
) async {
  final Uint8List bytes = args['bytes'] as Uint8List;

  final int filterIndex = _readFilterIndex(args);

  // ------------------------------------------------------------
  // 1. Decode
  // ------------------------------------------------------------

  final img.Image? decoded = img.decodeImage(bytes);

  if (decoded == null) {
    throw Exception('فرمت تصویر قابل تشخیص نیست');
  }

  // ------------------------------------------------------------
  // 2. Orientation
  // ------------------------------------------------------------

  final img.Image fixed = img.bakeOrientation(decoded);

  final int originalWidth = fixed.width;
  final int originalHeight = fixed.height;

  // ------------------------------------------------------------
  // 3. Detection
  // ------------------------------------------------------------

  final double detectionScale = _calculateScale(
    originalWidth,
    originalHeight,
    _detectionSize,
  );

  final img.Image detectionImage;

  if (detectionScale < 1.0) {
    detectionImage = img.copyResize(
      fixed,
      width: _scaledDimension(
        originalWidth,
        detectionScale,
      ),
      height: _scaledDimension(
        originalHeight,
        detectionScale,
      ),
      interpolation: img.Interpolation.linear,
    );
  } else {
    detectionImage = fixed;
  }

  final DocumentCorners? detected = DocumentDetector.detect(
    detectionImage,
  );

  final DocumentCorners corners;

  if (detected != null) {
    corners = _scaleCorners(
      detected,
      1.0 / detectionScale,
    );
  } else {
    corners = _defaultCorners(fixed);
  }

  // ------------------------------------------------------------
  // 4. آماده‌سازی تصویر Perspective
  // ------------------------------------------------------------

  final double outputScale = _calculateScale(
    originalWidth,
    originalHeight,
    _maxOutputSize,
  );

  final img.Image processingImage;

  if (outputScale < 1.0) {
    processingImage = img.copyResize(
      fixed,
      width: _scaledDimension(
        originalWidth,
        outputScale,
      ),
      height: _scaledDimension(
        originalHeight,
        outputScale,
      ),
      interpolation: img.Interpolation.linear,
    );
  } else {
    processingImage = fixed;
  }

  final DocumentCorners processingCorners = _scaleCorners(
    corners,
    outputScale,
  );

  // ------------------------------------------------------------
  // 5. Perspective
  // ------------------------------------------------------------

  final img.Image rectified = PerspectiveCorrector.rectify(
    processingImage,
    processingCorners,
  );

  // ------------------------------------------------------------
  // 6. Filter
  // ------------------------------------------------------------

  final ScanFilter filter = _filterFromIndex(filterIndex);

  final img.Image enhanced;

  if (filter == ScanFilter.original) {
    enhanced = rectified;
  } else {
    enhanced = ImageEnhancer.apply(
      rectified,
      filter,
    );
  }

  // ------------------------------------------------------------
  // 7. Encode processed image
  // ------------------------------------------------------------

  final Uint8List processedBytes = Uint8List.fromList(
    img.encodeJpg(
      enhanced,
      quality: _jpegQuality,
    ),
  );

  // ------------------------------------------------------------
  // 8. Original image for editor
  // ------------------------------------------------------------
  //
  // Editor به تصویر Orientation-correct نیاز دارد.
  //
  // برای اینکه دوباره یک تصویر 4000px یا 6000px را Encode نکنیم،
  // همان processingImage را استفاده می‌کنیم.
  //
  // این بخش فقط یک JPEG Encode دارد.
  // ------------------------------------------------------------

  final Uint8List originalBytes = Uint8List.fromList(
    img.encodeJpg(
      processingImage,
      quality: _jpegQuality,
    ),
  );

  // ------------------------------------------------------------
  // 9. Result
  // ------------------------------------------------------------

  return <String, dynamic>{
    'originalBytes': originalBytes,
    'processedBytes': processedBytes,

    'topLeftX': corners.topLeft.dx,
    'topLeftY': corners.topLeft.dy,

    'topRightX': corners.topRight.dx,
    'topRightY': corners.topRight.dy,

    'bottomRightX': corners.bottomRight.dx,
    'bottomRightY': corners.bottomRight.dy,

    'bottomLeftX': corners.bottomLeft.dx,
    'bottomLeftY': corners.bottomLeft.dy,
  };
}

/// ============================================================
/// Process Crop
/// ============================================================

Future<Map<String, dynamic>> processCropInIsolate(
  Map<String, dynamic> args,
) async {
  final Uint8List bytes = args['bytes'] as Uint8List;

  final int filterIndex = _readFilterIndex(args);

  final double topLeftX = _readDouble(
    args,
    'topLeftX',
  );

  final double topLeftY = _readDouble(
    args,
    'topLeftY',
  );

  final double topRightX = _readDouble(
    args,
    'topRightX',
  );

  final double topRightY = _readDouble(
    args,
    'topRightY',
  );

  final double bottomRightX = _readDouble(
    args,
    'bottomRightX',
  );

  final double bottomRightY = _readDouble(
    args,
    'bottomRightY',
  );

  final double bottomLeftX = _readDouble(
    args,
    'bottomLeftX',
  );

  final double bottomLeftY = _readDouble(
    args,
    'bottomLeftY',
  );

  // ------------------------------------------------------------
  // Decode
  // ------------------------------------------------------------

  final img.Image? decoded = img.decodeImage(bytes);

  if (decoded == null) {
    throw Exception('فرمت تصویر قابل تشخیص نیست');
  }

  final img.Image fixed = img.bakeOrientation(decoded);

  final int originalWidth = fixed.width;
  final int originalHeight = fixed.height;

  // ------------------------------------------------------------
  // Resize
  // ------------------------------------------------------------

  final double outputScale = _calculateScale(
    originalWidth,
    originalHeight,
    _maxOutputSize,
  );

  final img.Image processingImage;

  if (outputScale < 1.0) {
    processingImage = img.copyResize(
      fixed,
      width: _scaledDimension(
        originalWidth,
        outputScale,
      ),
      height: _scaledDimension(
        originalHeight,
        outputScale,
      ),
      interpolation: img.Interpolation.linear,
    );
  } else {
    processingImage = fixed;
  }

  // ------------------------------------------------------------
  // Corners
  // ------------------------------------------------------------

  final DocumentCorners corners = DocumentCorners(
    topLeft: Offset(
      topLeftX * outputScale,
      topLeftY * outputScale,
    ),
    topRight: Offset(
      topRightX * outputScale,
      topRightY * outputScale,
    ),
    bottomRight: Offset(
      bottomRightX * outputScale,
      bottomRightY * outputScale,
    ),
    bottomLeft: Offset(
      bottomLeftX * outputScale,
      bottomLeftY * outputScale,
    ),
  );

  // ------------------------------------------------------------
  // Perspective
  // ------------------------------------------------------------

  final img.Image rectified = PerspectiveCorrector.rectify(
    processingImage,
    corners,
  );

  // ------------------------------------------------------------
  // Filter
  // ------------------------------------------------------------

  final ScanFilter filter = _filterFromIndex(filterIndex);

  final img.Image enhanced;

  if (filter == ScanFilter.original) {
    enhanced = rectified;
  } else {
    enhanced = ImageEnhancer.apply(
      rectified,
      filter,
    );
  }

  // ------------------------------------------------------------
  // Encode
  // ------------------------------------------------------------

  final Uint8List processedBytes = Uint8List.fromList(
    img.encodeJpg(
      enhanced,
      quality: _jpegQuality,
    ),
  );

  return <String, dynamic>{
    'processedBytes': processedBytes,
  };
}

/// ============================================================
/// Helpers
/// ============================================================

double _calculateScale(
  int width,
  int height,
  int maxSize,
) {
  final int largestSide =
      width > height ? width : height;

  if (largestSide <= maxSize) {
    return 1.0;
  }

  return maxSize / largestSide;
}

int _scaledDimension(
  int value,
  double scale,
) {
  final int result =
      (value * scale).round();

  return result < 1 ? 1 : result;
}

DocumentCorners _scaleCorners(
  DocumentCorners corners,
  double scale,
) {
  return DocumentCorners(
    topLeft: Offset(
      corners.topLeft.dx * scale,
      corners.topLeft.dy * scale,
    ),
    topRight: Offset(
      corners.topRight.dx * scale,
      corners.topRight.dy * scale,
    ),
    bottomRight: Offset(
      corners.bottomRight.dx * scale,
      corners.bottomRight.dy * scale,
    ),
    bottomLeft: Offset(
      corners.bottomLeft.dx * scale,
      corners.bottomLeft.dy * scale,
    ),
  );
}

DocumentCorners _defaultCorners(
  img.Image image,
) {
  final double w = image.width.toDouble();
  final double h = image.height.toDouble();

  final double marginX = w * 0.03;
  final double marginY = h * 0.03;

  return DocumentCorners(
    topLeft: Offset(
      marginX,
      marginY,
    ),
    topRight: Offset(
      w - marginX,
      marginY,
    ),
    bottomRight: Offset(
      w - marginX,
      h - marginY,
    ),
    bottomLeft: Offset(
      marginX,
      h - marginY,
    ),
  );
}

int _readFilterIndex(
  Map<String, dynamic> args,
) {
  final value = args['filterIndex'];

  if (value is int) {
    return value;
  }

  return 0;
}

double _readDouble(
  Map<String, dynamic> args,
  String key,
) {
  final value = args[key];

  if (value is num) {
    return value.toDouble();
  }

  throw Exception(
    'مختصات $key معتبر نیست',
  );
}

ScanFilter _filterFromIndex(
  int index,
) {
  if (index < 0 ||
      index >= ScanFilter.values.length) {
    return ScanFilter.original;
  }

  return ScanFilter.values[index];
}