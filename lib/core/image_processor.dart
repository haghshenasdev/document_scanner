import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../models/document_corners.dart';
import 'document_detector.dart';
import 'image_enhancer.dart';
import 'perspective_corrector.dart';

/// ============================================================
/// PERFORMANCE / QUALITY
/// ============================================================

/// Detection فقط روی تصویر کوچک انجام می‌شود.
const int _detectionSize = 800;

/// کیفیت JPEG نهایی.
/// توجه: عکس اصلی هرگز Encode مجدد نمی‌شود.
const int _jpegQuality = 100;

/// ============================================================
/// DETECTION ONLY
/// ============================================================
///
/// این تابع فقط برای زمان Capture است.
///
/// کارهایی که انجام می‌دهد:
/// 1. Decode
/// 2. اصلاح Orientation
/// 3. Resize کوچک
/// 4. Detection
///
/// کارهایی که انجام نمی‌دهد:
/// - Perspective
/// - Filter
/// - Enhancement
/// - JPEG encode
///
/// بنابراین Capture بسیار سریع‌تر می‌شود.
Future<Map<String, dynamic>> detectImageInIsolate(
  Map<String, dynamic> args,
) async {
  final Uint8List bytes = args['bytes'] as Uint8List;

  final decoded = img.decodeImage(bytes);

  if (decoded == null) {
    throw Exception('فرمت تصویر قابل تشخیص نیست');
  }

  /// Orientation را اصلاح می‌کنیم تا مختصات گوشه‌ها
  /// با تصویری که بعداً پردازش می‌شود هماهنگ باشد.
  final fixed = img.bakeOrientation(decoded);

  final int originalWidth = fixed.width;
  final int originalHeight = fixed.height;

  /// ----------------------------------------------------------
  /// Detection image
  /// ----------------------------------------------------------

  final int largestSide =
      originalWidth > originalHeight ? originalWidth : originalHeight;

  final double scale = largestSide > _detectionSize
      ? _detectionSize / largestSide
      : 1.0;

  final img.Image detectionImage;

  if (scale < 1.0) {
    detectionImage = img.copyResize(
      fixed,
      width: _scaledDimension(originalWidth, scale),
      height: _scaledDimension(originalHeight, scale),
      interpolation: img.Interpolation.linear,
    );
  } else {
    detectionImage = fixed;
  }

  /// ----------------------------------------------------------
  /// Detect
  /// ----------------------------------------------------------

  final DocumentCorners? detected =
      DocumentDetector.detect(detectionImage);

  final DocumentCorners corners;

  if (detected != null) {
    corners = _scaleCorners(
      detected,
      1.0 / scale,
    );
  } else {
    corners = _defaultCorners(fixed);
  }

  /// ----------------------------------------------------------
  /// Result
  /// ----------------------------------------------------------
  ///
  /// مهم:
  /// originalBytes را برنمی‌گردانیم چون همان bytes ورودی
  /// باید در ScannerPage نگه داشته شود.
  ///
  /// فقط مختصات را برمی‌گردانیم.

  return <String, dynamic>{
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
/// PROCESS FULL IMAGE
/// ============================================================
///
/// این تابع دیگر نباید هنگام Capture اجرا شود.
///
/// برای Preview / Save استفاده می‌شود.
///
/// روند:
///
/// Original JPEG
///      ↓
/// Decode
///      ↓
/// Orientation
///      ↓
/// Perspective
///      ↓
/// Filter
///      ↓
/// JPEG 100
///
Future<Map<String, dynamic>> processImageInIsolate(
  Map<String, dynamic> args,
) async {
  final Uint8List bytes = args['bytes'] as Uint8List;

  final int filterIndex = _readFilterIndex(args);

  final double topLeftX = _readDouble(args, 'topLeftX');
  final double topLeftY = _readDouble(args, 'topLeftY');

  final double topRightX = _readDouble(args, 'topRightX');
  final double topRightY = _readDouble(args, 'topRightY');

  final double bottomRightX =
      _readDouble(args, 'bottomRightX');

  final double bottomRightY =
      _readDouble(args, 'bottomRightY');

  final double bottomLeftX =
      _readDouble(args, 'bottomLeftX');

  final double bottomLeftY =
      _readDouble(args, 'bottomLeftY');

  /// ----------------------------------------------------------
  /// Decode original
  /// ----------------------------------------------------------

  final decoded = img.decodeImage(bytes);

  if (decoded == null) {
    throw Exception('فرمت تصویر قابل تشخیص نیست');
  }

  final fixed = img.bakeOrientation(decoded);

  /// ----------------------------------------------------------
  /// Corners
  /// ----------------------------------------------------------

  final corners = DocumentCorners(
    topLeft: Offset(topLeftX, topLeftY),
    topRight: Offset(topRightX, topRightY),
    bottomRight: Offset(
      bottomRightX,
      bottomRightY,
    ),
    bottomLeft: Offset(
      bottomLeftX,
      bottomLeftY,
    ),
  );

  /// ----------------------------------------------------------
  /// Perspective
  /// ----------------------------------------------------------

  final rectified = PerspectiveCorrector.rectify(
    fixed,
    corners,
  );

  /// ----------------------------------------------------------
  /// Filter
  /// ----------------------------------------------------------

  final filter = _filterFromIndex(filterIndex);

  final img.Image enhanced;

  if (filter == ScanFilter.original) {
    enhanced = rectified;
  } else {
    enhanced = ImageEnhancer.apply(
      rectified,
      filter,
    );
  }

  /// ----------------------------------------------------------
  /// Final JPEG
  /// ----------------------------------------------------------

  final processedBytes = Uint8List.fromList(
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
/// PROCESS CROP
/// ============================================================
///
/// برای CropEditor استفاده می‌شود.
///
/// همیشه از originalBytes اصلی دوباره پردازش می‌کند.
/// بنابراین با هر بار تغییر گوشه‌ها افت کیفیت تجمعی نداریم.
Future<Map<String, dynamic>> processCropInIsolate(
  Map<String, dynamic> args,
) async {
  final Uint8List bytes = args['bytes'] as Uint8List;

  final int filterIndex = _readFilterIndex(args);

  final double topLeftX = _readDouble(args, 'topLeftX');
  final double topLeftY = _readDouble(args, 'topLeftY');

  final double topRightX = _readDouble(args, 'topRightX');
  final double topRightY = _readDouble(args, 'topRightY');

  final double bottomRightX =
      _readDouble(args, 'bottomRightX');

  final double bottomRightY =
      _readDouble(args, 'bottomRightY');

  final double bottomLeftX =
      _readDouble(args, 'bottomLeftX');

  final double bottomLeftY =
      _readDouble(args, 'bottomLeftY');

  /// ----------------------------------------------------------
  /// Decode
  /// ----------------------------------------------------------

  final decoded = img.decodeImage(bytes);

  if (decoded == null) {
    throw Exception('فرمت تصویر قابل تشخیص نیست');
  }

  final fixed = img.bakeOrientation(decoded);

  /// ----------------------------------------------------------
  /// Corners
  /// ----------------------------------------------------------

  final corners = DocumentCorners(
    topLeft: Offset(topLeftX, topLeftY),
    topRight: Offset(topRightX, topRightY),
    bottomRight: Offset(
      bottomRightX,
      bottomRightY,
    ),
    bottomLeft: Offset(
      bottomLeftX,
      bottomLeftY,
    ),
  );

  /// ----------------------------------------------------------
  /// Perspective
  /// ----------------------------------------------------------

  final rectified = PerspectiveCorrector.rectify(
    fixed,
    corners,
  );

  /// ----------------------------------------------------------
  /// Filter
  /// ----------------------------------------------------------

  final filter = _filterFromIndex(filterIndex);

  final img.Image enhanced;

  if (filter == ScanFilter.original) {
    enhanced = rectified;
  } else {
    enhanced = ImageEnhancer.apply(
      rectified,
      filter,
    );
  }

  /// ----------------------------------------------------------
  /// Encode
  /// ----------------------------------------------------------

  final processedBytes = Uint8List.fromList(
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
/// HELPERS
/// ============================================================

int _scaledDimension(
  int value,
  double scale,
) {
  final result = (value * scale).round();

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
  final marginX = image.width * 0.06;
  final marginY = image.height * 0.06;

  return DocumentCorners(
    topLeft: Offset(
      marginX,
      marginY,
    ),
    topRight: Offset(
      image.width - marginX,
      marginY,
    ),
    bottomRight: Offset(
      image.width - marginX,
      image.height - marginY,
    ),
    bottomLeft: Offset(
      marginX,
      image.height - marginY,
    ),
  );
}

int _readFilterIndex(
  Map<String, dynamic> args,
) {
  final value = args['filterIndex'];

  if (value is int) {
    return value.clamp(
      0,
      ScanFilter.values.length - 1,
    );
  }

  if (value is num) {
    return value.toInt().clamp(
      0,
      ScanFilter.values.length - 1,
    );
  }

  return 0;
}

ScanFilter _filterFromIndex(
  int index,
) {
  final safeIndex = index.clamp(
    0,
    ScanFilter.values.length - 1,
  );

  return ScanFilter.values[safeIndex];
}

double _readDouble(
  Map<String, dynamic> args,
  String key,
) {
  final value = args[key];

  if (value is double) {
    return value;
  }

  if (value is int) {
    return value.toDouble();
  }

  if (value is num) {
    return value.toDouble();
  }

  throw Exception(
    'مختصات $key معتبر نیست',
  );
}
