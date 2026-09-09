import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../models/document_corners.dart';
import 'document_detector.dart';
import 'image_enhancer.dart';
import 'perspective_corrector.dart';

/// ============================================================
/// SETTINGS
/// ============================================================

/// اندازه‌ای که تشخیص گوشه روی آن انجام می‌شود.
/// تشخیص روی تصویر کوچک بسیار سریع‌تر است.
const int _detectionMaxDimension = 640;

/// Preview فقط برای نمایش داخل برنامه است.
const int _previewMaxDimension = 1200;

/// کیفیت Preview.
/// چون فقط برای نمایش است، لازم نیست خیلی بالا باشد.
const int _previewJpegQuality = 88;

/// کیفیت خروجی نهایی.
const int _finalJpegQuality = 96;

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

  final double scale = largestSide > _detectionMaxDimension
      ? _detectionMaxDimension / largestSide
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
/// PROCESS
/// ============================================================

Future<Map<String, dynamic>> processImageInIsolate(
  Map<String, dynamic> args,
) async {
  final dynamic progressPortValue = args['progressPort'];

  final SendPort? progressPort = progressPortValue is SendPort
      ? progressPortValue
      : null;

  void sendStage(String stage, {required String state, int? elapsedMs}) {
    progressPort?.send({
      'type': 'stage',
      'stage': stage,
      'state': state,
      'elapsedMs': elapsedMs,
    });
  }

  final Map<String, int> stageTimes = <String, int>{};

  final bool preview = args['preview'] == true;

  final int rotationQuarterTurns = _readRotation(args);

  final Uint8List bytes = args['bytes'] as Uint8List;

  // ==========================================================
  // DECODE
  // ==========================================================

  final decodeWatch = Stopwatch()..start();

  sendStage('Decode', state: 'start');

  final decoded = img.decodeImage(bytes);

  if (decoded == null) {
    throw Exception('فرمت تصویر قابل تشخیص نیست');
  }

  decodeWatch.stop();

  stageTimes['Decode'] = decodeWatch.elapsedMilliseconds;

  sendStage(
    'Decode',
    state: 'done',
    elapsedMs: decodeWatch.elapsedMilliseconds,
  );

  // ==========================================================
  // ORIENTATION
  // ==========================================================

  final orientationWatch = Stopwatch()..start();

  sendStage('Orientation', state: 'start');

  img.Image fixed = img.bakeOrientation(decoded);

  orientationWatch.stop();

  stageTimes['Orientation'] = orientationWatch.elapsedMilliseconds;

  sendStage(
    'Orientation',
    state: 'done',
    elapsedMs: orientationWatch.elapsedMilliseconds,
  );

  // ==========================================================
  // ROTATION
  // ==========================================================

  if (rotationQuarterTurns != 0) {
    final rotationWatch = Stopwatch()..start();

    sendStage('Rotation', state: 'start');

    fixed = img.copyRotate(
      fixed,
      angle: rotationQuarterTurns * 90,
      interpolation: img.Interpolation.nearest,
    );

    rotationWatch.stop();

    stageTimes['Rotation'] = rotationWatch.elapsedMilliseconds;

    sendStage(
      'Rotation',
      state: 'done',
      elapsedMs: rotationWatch.elapsedMilliseconds,
    );
  }

  // ==========================================================
  // RESIZE PREVIEW
  // ==========================================================
  //
  // نکته مهم:
  // Resize فقط در Preview انجام می‌شود.
  // خروجی نهایی هرگز از این تصویر کوچک ساخته نمی‌شود.
  //

  if (preview) {
    final int largestSide = fixed.width > fixed.height
        ? fixed.width
        : fixed.height;

    if (largestSide > _previewMaxDimension) {
      final resizeWatch = Stopwatch()..start();

      sendStage('Resize', state: 'start');

      final double scale = _previewMaxDimension / largestSide;

      fixed = img.copyResize(
        fixed,
        width: _scaledDimension(fixed.width, scale),
        height: _scaledDimension(fixed.height, scale),
        interpolation: img.Interpolation.linear,
      );

      resizeWatch.stop();

      stageTimes['Resize'] = resizeWatch.elapsedMilliseconds;

      sendStage(
        'Resize',
        state: 'done',
        elapsedMs: resizeWatch.elapsedMilliseconds,
      );
    }
  }

  // ==========================================================
  // CORNERS
  // ==========================================================

  final DocumentCorners corners = DocumentCorners(
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
  // SCALE CORNERS
  // ==========================================================

  final double sourceWidth = args['sourceWidth'] is num
      ? (args['sourceWidth'] as num).toDouble()
      : fixed.width.toDouble();

  final double sourceHeight = args['sourceHeight'] is num
      ? (args['sourceHeight'] as num).toDouble()
      : fixed.height.toDouble();

  final double scaleX = fixed.width / sourceWidth;

  final double scaleY = fixed.height / sourceHeight;

  final DocumentCorners processCorners = DocumentCorners(
    topLeft: Offset(corners.topLeft.dx * scaleX, corners.topLeft.dy * scaleY),
    topRight: Offset(
      corners.topRight.dx * scaleX,
      corners.topRight.dy * scaleY,
    ),
    bottomRight: Offset(
      corners.bottomRight.dx * scaleX,
      corners.bottomRight.dy * scaleY,
    ),
    bottomLeft: Offset(
      corners.bottomLeft.dx * scaleX,
      corners.bottomLeft.dy * scaleY,
    ),
  );

  // ==========================================================
  // PERSPECTIVE
  // ==========================================================

  final perspectiveWatch = Stopwatch()..start();

  sendStage('Perspective', state: 'start');

  final img.Image rectified = PerspectiveCorrector.rectify(
    fixed,
    processCorners,
    preview: preview,
  );

  perspectiveWatch.stop();

  stageTimes['Perspective'] = perspectiveWatch.elapsedMilliseconds;

  sendStage(
    'Perspective',
    state: 'done',
    elapsedMs: perspectiveWatch.elapsedMilliseconds,
  );

  // ==========================================================
  // FILTER
  // ==========================================================

  final int filterIndex = _readFilterIndex(args);

  final ScanFilter filter = _filterFromIndex(filterIndex);

  img.Image enhanced;

  if (filter == ScanFilter.original) {
    enhanced = rectified;
  } else {
    final filterWatch = Stopwatch()..start();

    sendStage('Filter', state: 'start');

    enhanced = ImageEnhancer.apply(rectified, filter);

    filterWatch.stop();

    stageTimes['Filter'] = filterWatch.elapsedMilliseconds;

    sendStage(
      'Filter',
      state: 'done',
      elapsedMs: filterWatch.elapsedMilliseconds,
    );
  }

  // ==========================================================
  // JPEG
  // ==========================================================

  final jpegWatch = Stopwatch()..start();

  sendStage('JPEG Encode', state: 'start');

  final int quality = preview ? _previewJpegQuality : _finalJpegQuality;

  final Uint8List processedBytes = Uint8List.fromList(
    img.encodeJpg(enhanced, quality: quality),
  );

  jpegWatch.stop();

  stageTimes['JPEG Encode'] = jpegWatch.elapsedMilliseconds;

  sendStage(
    'JPEG Encode',
    state: 'done',
    elapsedMs: jpegWatch.elapsedMilliseconds,
  );

  return <String, dynamic>{
    'processedBytes': processedBytes,
    'stageTimes': stageTimes,
  };
}

/// ============================================================
/// CROP
/// ============================================================

Future<Map<String, dynamic>> processCropInIsolate(
  Map<String, dynamic> args,
) async {
  return processImageInIsolate({
    ...args,
    'preview': false,
    'progressPort': args['progressPort'],
  });
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
  final int result = (value * scale).round();

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
  final double marginX = image.width * .06;

  final double marginY = image.height * .06;

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
