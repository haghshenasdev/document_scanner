import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../models/document_corners.dart';
import 'document_detector.dart';
import 'image_enhancer.dart';
import 'perspective_corrector.dart';

/// ============================================================
/// PERFORMANCE
/// ============================================================

/// Detection فقط یک بار و در همین اندازه انجام می‌شود.
/// DocumentDetector هم حداکثر 640 را استفاده می‌کند.
const int _detectionSize = 640;

/// حداکثر اندازه Preview.
/// فایل نهایی با رزولوشن کامل تولید می‌شود.
const int _previewMaxDimension = 1400;

/// کیفیت Preview
const int _previewJpegQuality = 82;

/// کیفیت فایل نهایی
const int _finalJpegQuality = 92;

/// ============================================================
/// DETECTION
/// ============================================================

Future<Map<String, dynamic>> detectImageInIsolate(
  Map<String, dynamic> args,
) async {
  final Uint8List bytes = args['bytes'] as Uint8List;

  final decoded = img.decodeImage(bytes);

  if (decoded == null) {
    throw Exception('فرمت تصویر قابل تشخیص نیست');
  }

  final fixed = img.bakeOrientation(decoded);

  final int originalWidth = fixed.width;

  final int originalHeight = fixed.height;

  final int largestSide = originalWidth > originalHeight
      ? originalWidth
      : originalHeight;

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

  final DocumentCorners? detected = DocumentDetector.detect(detectionImage);

  final DocumentCorners corners;

  if (detected != null) {
    corners = _scaleCorners(detected, 1.0 / scale);
  } else {
    corners = _defaultCorners(fixed);
  }

  return <String, dynamic>{
    'topLeftX': corners.topLeft.dx,
    'topLeftY': corners.topLeft.dy,

    'topRightX': corners.topRight.dx,
    'topRightY': corners.topRight.dy,

    'bottomRightX': corners.bottomRight.dx,
    'bottomRightY': corners.bottomRight.dy,

    'bottomLeftX': corners.bottomLeft.dx,
    'bottomLeftY': corners.bottomLeft.dy,

    'imageWidth': fixed.width,

    'imageHeight': fixed.height,
  };
}

/// ============================================================
/// FULL PROCESS
/// ============================================================
///
/// این تابع هم Preview و هم خروجی نهایی را انجام می‌دهد.
///
/// preview = true
///     → حداکثر 1400px
///     → JPEG 82
///
/// preview = false
///     → رزولوشن کامل
///     → JPEG 92
///
/// progressPort اختیاری است.
/// اگر ارسال شود، وضعیت هر مرحله را به UI می‌فرستد.
///

Future<Map<String, dynamic>> processImageInIsolate(
  Map<String, dynamic> args,
) async {
  final progressPort = args['progressPort'];

  void sendProgress(String stage, {String state = 'start', int? elapsedMs}) {
    if (progressPort is SendPort) {
      progressPort.send({
        'type': 'stage',
        'stage': stage,
        'state': state,
        'elapsedMs': elapsedMs,
      });
    }
  }

  final Map<String, int> timings = <String, int>{};

  final bool preview = args['preview'] == true;

  final int rotationQuarterTurns = _readRotation(args);

  final stopwatch = Stopwatch();

  // ==========================================================
  // DECODE
  // ==========================================================

  stopwatch
    ..reset()
    ..start();

  sendProgress('Decode');

  final Uint8List bytes = args['bytes'] as Uint8List;

  final decoded = img.decodeImage(bytes);

  if (decoded == null) {
    throw Exception('فرمت تصویر قابل تشخیص نیست');
  }

  stopwatch.stop();

  timings['Decode'] = stopwatch.elapsedMilliseconds;

  sendProgress(
    'Decode',
    state: 'done',
    elapsedMs: stopwatch.elapsedMilliseconds,
  );

  // ==========================================================
  // ORIENTATION
  // ==========================================================

  stopwatch
    ..reset()
    ..start();

  sendProgress('Orientation');

  img.Image fixed = img.bakeOrientation(decoded);

  stopwatch.stop();

  timings['Orientation'] = stopwatch.elapsedMilliseconds;

  sendProgress(
    'Orientation',
    state: 'done',
    elapsedMs: stopwatch.elapsedMilliseconds,
  );

  // ==========================================================
  // ROTATION
  // ==========================================================

  if (rotationQuarterTurns != 0) {
    stopwatch
      ..reset()
      ..start();

    sendProgress('Rotation');

    fixed = img.copyRotate(
      fixed,
      angle: rotationQuarterTurns * 90,
      interpolation: img.Interpolation.nearest,
    );

    stopwatch.stop();

    timings['Rotation'] = stopwatch.elapsedMilliseconds;

    sendProgress(
      'Rotation',
      state: 'done',
      elapsedMs: stopwatch.elapsedMilliseconds,
    );
  }

  // ==========================================================
  // RESIZE PREVIEW
  // ==========================================================

  if (preview) {
    final largestSide = fixed.width > fixed.height ? fixed.width : fixed.height;

    if (largestSide > _previewMaxDimension) {
      stopwatch
        ..reset()
        ..start();

      sendProgress('Resize');

      final scale = _previewMaxDimension / largestSide;

      fixed = img.copyResize(
        fixed,
        width: _scaledDimension(fixed.width, scale),
        height: _scaledDimension(fixed.height, scale),
        interpolation: img.Interpolation.linear,
      );

      stopwatch.stop();

      timings['Resize'] = stopwatch.elapsedMilliseconds;

      sendProgress(
        'Resize',
        state: 'done',
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
    }
  }

  // ==========================================================
  // CORNERS
  // ==========================================================

  final corners = DocumentCorners(
    topLeft: Offset(
      _readDouble(args, 'topLeftX'),
      _readDouble(args, 'topLeftY'),
    ),
    topRight: Offset(
      _readDouble(args, 'topRightX'),
      _readDouble(args, 'topRightY'),
    ),
    bottomRight: Offset(
      _readDouble(args, 'bottomRightX'),
      _readDouble(args, 'bottomRightY'),
    ),
    bottomLeft: Offset(
      _readDouble(args, 'bottomLeftX'),
      _readDouble(args, 'bottomLeftY'),
    ),
  );

  // ==========================================================
  // SCALE CORNERS FOR PREVIEW
  // ==========================================================

  final originalWidth = args['sourceWidth'] is num
      ? (args['sourceWidth'] as num).toDouble()
      : fixed.width.toDouble();

  final originalHeight = args['sourceHeight'] is num
      ? (args['sourceHeight'] as num).toDouble()
      : fixed.height.toDouble();

  final cornerScaleX = fixed.width / originalWidth;

  final cornerScaleY = fixed.height / originalHeight;

  final processCorners = DocumentCorners(
    topLeft: Offset(
      corners.topLeft.dx * cornerScaleX,
      corners.topLeft.dy * cornerScaleY,
    ),
    topRight: Offset(
      corners.topRight.dx * cornerScaleX,
      corners.topRight.dy * cornerScaleY,
    ),
    bottomRight: Offset(
      corners.bottomRight.dx * cornerScaleX,
      corners.bottomRight.dy * cornerScaleY,
    ),
    bottomLeft: Offset(
      corners.bottomLeft.dx * cornerScaleX,
      corners.bottomLeft.dy * cornerScaleY,
    ),
  );

  // ==========================================================
  // PERSPECTIVE
  // ==========================================================

  stopwatch
    ..reset()
    ..start();

  sendProgress('Perspective');

  final rectified = PerspectiveCorrector.rectify(
    fixed,
    processCorners,
    preview: preview,
  );

  stopwatch.stop();

  timings['Perspective'] = stopwatch.elapsedMilliseconds;

  sendProgress(
    'Perspective',
    state: 'done',
    elapsedMs: stopwatch.elapsedMilliseconds,
  );

  // ==========================================================
  // FILTER
  // ==========================================================

  final filterIndex = _readFilterIndex(args);

  final filter = _filterFromIndex(filterIndex);

  final img.Image enhanced;

  if (filter == ScanFilter.original) {
    enhanced = rectified;
  } else {
    stopwatch
      ..reset()
      ..start();

    sendProgress('Filter');

    enhanced = ImageEnhancer.apply(rectified, filter);

    stopwatch.stop();

    timings['Filter'] = stopwatch.elapsedMilliseconds;

    sendProgress(
      'Filter',
      state: 'done',
      elapsedMs: stopwatch.elapsedMilliseconds,
    );
  }

  // ==========================================================
  // JPEG
  // ==========================================================

  stopwatch
    ..reset()
    ..start();

  sendProgress('JPEG Encode');

  final processedBytes = Uint8List.fromList(
    img.encodeJpg(
      enhanced,
      quality: preview ? _previewJpegQuality : _finalJpegQuality,
    ),
  );

  stopwatch.stop();

  timings['JPEG Encode'] = stopwatch.elapsedMilliseconds;

  sendProgress(
    'JPEG Encode',
    state: 'done',
    elapsedMs: stopwatch.elapsedMilliseconds,
  );

  return <String, dynamic>{
    'processedBytes': processedBytes,
    'stageTimes': timings,
  };
}

/// ============================================================
/// CROP PROCESS
/// ============================================================

Future<Map<String, dynamic>> processCropInIsolate(
  Map<String, dynamic> args,
) async {
  final progressPort = args['progressPort'];

  final result = await processImageInIsolate({
    ...args,
    'preview': false,
    'progressPort': progressPort,
  });

  return result;
}

/// ============================================================
/// HELPERS
/// ============================================================

int _readRotation(Map<String, dynamic> args) {
  final value = args['rotationQuarterTurns'];

  if (value is int) {
    return value % 4;
  }

  if (value is num) {
    return value.toInt() % 4;
  }

  return 0;
}

int _scaledDimension(int value, double scale) {
  final result = (value * scale).round();

  return result < 1 ? 1 : result;
}

DocumentCorners _scaleCorners(DocumentCorners corners, double scale) {
  return DocumentCorners(
    topLeft: Offset(corners.topLeft.dx * scale, corners.topLeft.dy * scale),
    topRight: Offset(corners.topRight.dx * scale, corners.topRight.dy * scale),
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

DocumentCorners _defaultCorners(img.Image image) {
  final marginX = image.width * .06;

  final marginY = image.height * .06;

  return DocumentCorners(
    topLeft: Offset(marginX, marginY),
    topRight: Offset(image.width - marginX, marginY),
    bottomRight: Offset(image.width - marginX, image.height - marginY),
    bottomLeft: Offset(marginX, image.height - marginY),
  );
}

int _readFilterIndex(Map<String, dynamic> args) {
  final value = args['filterIndex'];

  if (value is int) {
    return value.clamp(0, ScanFilter.values.length - 1);
  }

  if (value is num) {
    return value.toInt().clamp(0, ScanFilter.values.length - 1);
  }

  return 0;
}

ScanFilter _filterFromIndex(int index) {
  final safeIndex = index.clamp(0, ScanFilter.values.length - 1);

  return ScanFilter.values[safeIndex];
}

double _readDouble(Map<String, dynamic> args, String key) {
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

  throw Exception('مختصات $key معتبر نیست');
}
