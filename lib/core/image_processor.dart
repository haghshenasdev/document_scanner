import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;

import '../models/document_corners.dart';
import 'document_detector.dart';
import 'image_enhancer.dart';
import 'perspective_corrector.dart';

/// پردازش کامل تصویر در یک Isolate.
///
/// این تابع باید top-level باشد تا بتوان آن را با compute اجرا کرد.
Future<Map<String, dynamic>> processImageInIsolate(
  Map<String, dynamic> args,
) async {
  final Uint8List bytes = args['bytes'] as Uint8List;
  final int filterIndex = args['filterIndex'] as int;

  final decoded = img.decodeImage(bytes);

  if (decoded == null) {
    throw Exception('فرمت تصویر قابل تشخیص نیست');
  }

  // ==========================================================
  // EXIF ORIENTATION
  // ==========================================================

  final fixed = img.bakeOrientation(decoded);

  // ==========================================================
  // DOCUMENT DETECTION
  // ==========================================================

  final detected = DocumentDetector.detect(fixed);

  final corners = detected ?? _defaultCorners(fixed);

  // ==========================================================
  // PERSPECTIVE
  // ==========================================================

  final rectified = PerspectiveCorrector.rectify(fixed, corners);

  // ==========================================================
  // ENHANCEMENT
  // ==========================================================

  final filters = ScanFilter.values;

  final safeFilterIndex = filterIndex.clamp(0, filters.length - 1);

  final filter = filters[safeFilterIndex];

  final enhanced = ImageEnhancer.apply(rectified, filter);

  // ==========================================================
  // ENCODE ORIGINAL
  // ==========================================================

  final fixedBytes = Uint8List.fromList(img.encodeJpg(fixed, quality: 95));

  // ==========================================================
  // ENCODE PROCESSED
  // ==========================================================

  final processedBytes = Uint8List.fromList(
    img.encodeJpg(enhanced, quality: 95),
  );

  return {
    'originalBytes': fixedBytes,
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

// ============================================================
// CROP / REPROCESS
// ============================================================

Future<Map<String, dynamic>> processCropInIsolate(
  Map<String, dynamic> args,
) async {
  final Uint8List bytes = args['bytes'] as Uint8List;

  final int filterIndex = args['filterIndex'] as int;

  final double topLeftX = args['topLeftX'] as double;
  final double topLeftY = args['topLeftY'] as double;

  final double topRightX = args['topRightX'] as double;
  final double topRightY = args['topRightY'] as double;

  final double bottomRightX = args['bottomRightX'] as double;
  final double bottomRightY = args['bottomRightY'] as double;

  final double bottomLeftX = args['bottomLeftX'] as double;
  final double bottomLeftY = args['bottomLeftY'] as double;

  // ==========================================================
  // DECODE
  // ==========================================================

  final decoded = img.decodeImage(bytes);

  if (decoded == null) {
    throw Exception('تصویر قابل پردازش نیست');
  }

  final fixed = img.bakeOrientation(decoded);

  // ==========================================================
  // CORNERS
  // ==========================================================

  final corners = DocumentCorners(
    topLeft: Offset(topLeftX, topLeftY),
    topRight: Offset(topRightX, topRightY),
    bottomRight: Offset(bottomRightX, bottomRightY),
    bottomLeft: Offset(bottomLeftX, bottomLeftY),
  );

  // ==========================================================
  // PERSPECTIVE
  // ==========================================================

  final rectified = PerspectiveCorrector.rectify(fixed, corners);

  // ==========================================================
  // FILTER
  // ==========================================================

  final filters = ScanFilter.values;

  final safeFilterIndex = filterIndex.clamp(0, filters.length - 1);

  final filter = filters[safeFilterIndex];

  final enhanced = ImageEnhancer.apply(rectified, filter);

  // ==========================================================
  // ENCODE
  // ==========================================================

  final processedBytes = Uint8List.fromList(
    img.encodeJpg(enhanced, quality: 95),
  );

  return {'processedBytes': processedBytes};
}

// ============================================================
// DEFAULT CORNERS
// ============================================================

DocumentCorners _defaultCorners(img.Image image) {
  final marginX = image.width * .08;
  final marginY = image.height * .08;

  return DocumentCorners(
    topLeft: Offset(marginX, marginY),
    topRight: Offset(image.width - marginX, marginY),
    bottomRight: Offset(image.width - marginX, image.height - marginY),
    bottomLeft: Offset(marginX, image.height - marginY),
  );
}
