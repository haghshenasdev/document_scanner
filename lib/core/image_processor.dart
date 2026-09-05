import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../models/document_corners.dart';
import 'document_detector.dart';
import 'image_enhancer.dart';
import 'perspective_corrector.dart';

/// ============================================================
/// تنظیمات اصلی Performance / Quality
/// ============================================================

/// حداکثر اندازه ضلع بزرگ برای تشخیص سند.
///
/// Detection فقط روی این نسخه کوچک انجام می‌شود.
/// هرچه این عدد کمتر باشد، تشخیص سریع‌تر است.
///
/// 800 برای گوشی‌های معمولی مقدار مناسبی است.
const int _baseDetectionSize = 800;

/// حداقل اندازه Detection.
///
/// برای عکس‌های خیلی کوچک، تصویر را بیش از حد کوچک نمی‌کنیم.
const int _minDetectionSize = 600;

/// حداکثر اندازه خروجی.
///
/// تصویر اصلی برای Perspective استفاده می‌شود، اما اگر دوربین
/// رزولوشن بسیار بالایی داشته باشد، برای جلوگیری از مصرف بیش
/// از حد RAM و CPU سقف منطقی داریم.
///
/// برای عکس 12MP معمولاً خروجی بدون افت محسوس خواهد بود.
const int _maxOutputSize = 3000;

/// حداقل اندازه خروجی.
const int _minOutputSize = 1600;

/// کیفیت JPEG نهایی.
const int _jpegQuality = 95;

/// ============================================================
/// Process Full Image
/// ============================================================

/// پردازش کامل عکس گرفته‌شده از دوربین.
///
/// این تابع باید با compute اجرا شود:
///
/// compute(
///   processImageInIsolate,
///   {
///     'bytes': bytes,
///     'filterIndex': filterIndex,
///   },
/// );
Future<Map<String, dynamic>> processImageInIsolate(
  Map<String, dynamic> args,
) async {
  final Uint8List bytes = args['bytes'] as Uint8List;

  final int filterIndex = _readFilterIndex(args);

  // ------------------------------------------------------------
  // 1. Decode تصویر اصلی
  // ------------------------------------------------------------

  final img.Image? decoded = img.decodeImage(bytes);

  if (decoded == null) {
    throw Exception('فرمت تصویر قابل تشخیص نیست');
  }

  // اصلاح EXIF Orientation
  final img.Image fixed = img.bakeOrientation(decoded);

  final int originalWidth = fixed.width;
  final int originalHeight = fixed.height;

  // ------------------------------------------------------------
  // 2. Detection روی نسخه کوچک
  // ------------------------------------------------------------

  final int detectionSize = _calculateDetectionSize(
    originalWidth,
    originalHeight,
  );

  final double detectionScale = _calculateScale(
    originalWidth,
    originalHeight,
    detectionSize,
  );

  final img.Image detectionImage;

  if (detectionScale < 1.0) {
    detectionImage = img.copyResize(
      fixed,
      width: _scaledDimension(originalWidth, detectionScale),
      height: _scaledDimension(originalHeight, detectionScale),
      interpolation: img.Interpolation.linear,
    );
  } else {
    detectionImage = fixed;
  }

  // ------------------------------------------------------------
  // 3. پیدا کردن گوشه‌ها
  // ------------------------------------------------------------

  final DocumentCorners? detected = DocumentDetector.detect(detectionImage);

  final DocumentCorners corners;

  if (detected != null) {
    // برگرداندن مختصات از نسخه کوچک به تصویر اصلی
    corners = _scaleCorners(detected, 1.0 / detectionScale);
  } else {
    corners = _defaultCorners(fixed);
  }

  // ------------------------------------------------------------
  // 4. آماده‌سازی تصویر High Quality
  // ------------------------------------------------------------

  //
  // نکته مهم:
  //
  // Detection روی تصویر کوچک انجام شد،
  // اما از اینجا به بعد دوباره روی تصویر با کیفیت بالا
  // کار می‌کنیم.
  //

  final int outputSize = _calculateOutputSize(originalWidth, originalHeight);

  final double outputScale = _calculateScale(
    originalWidth,
    originalHeight,
    outputSize,
  );

  final img.Image processingImage;

  if (outputScale < 1.0) {
    processingImage = img.copyResize(
      fixed,
      width: _scaledDimension(originalWidth, outputScale),
      height: _scaledDimension(originalHeight, outputScale),
      interpolation: img.Interpolation.linear,
    );
  } else {
    processingImage = fixed;
  }

  // مختصات Detection که در اندازه اصلی هستند
  // را به اندازه processingImage تبدیل می‌کنیم.
  final DocumentCorners processingCorners = _scaleCorners(corners, outputScale);

  // ------------------------------------------------------------
  // 5. Perspective Correction
  // ------------------------------------------------------------

  final img.Image rectified = PerspectiveCorrector.rectify(
    processingImage,
    processingCorners,
  );

  // ------------------------------------------------------------
  // 6. Filter / Enhancement
  // ------------------------------------------------------------

  final ScanFilter filter = _filterFromIndex(filterIndex);

  final img.Image enhanced;

  // اگر Original انتخاب شده، هیچ Enhancement اضافی انجام نمی‌دهیم.
  if (filter == ScanFilter.original) {
    enhanced = rectified;
  } else {
    enhanced = ImageEnhancer.apply(rectified, filter);
  }

  // ------------------------------------------------------------
  // 7. Encode خروجی نهایی
  // ------------------------------------------------------------

  final Uint8List processedBytes = Uint8List.fromList(
    img.encodeJpg(enhanced, quality: _jpegQuality),
  );

  // ------------------------------------------------------------
  // 8. Original Bytes
  // ------------------------------------------------------------

  //
  // برای Editor به نسخه Orientation-correct شده نیاز داریم.
  //
  // اما آن را با رزولوشن کامل JPEG ذخیره نمی‌کنیم اگر تصویر
  // بسیار بزرگ باشد؛ چون باعث مصرف RAM و زمان زیاد می‌شود.
  //
  // در اکثر گوشی‌ها همان تصویر اصلی یا حداکثر 3000px برمی‌گردد.
  //

  final img.Image originalForEditor;

  if (outputScale < 1.0) {
    originalForEditor = processingImage;
  } else {
    originalForEditor = fixed;
  }

  final Uint8List originalBytes = Uint8List.fromList(
    img.encodeJpg(originalForEditor, quality: _jpegQuality),
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

/// پردازش مجدد تصویر بعد از اینکه کاربر گوشه‌ها را در CropEditor
/// تغییر داده است.
///
/// این تابع نیز باید با compute اجرا شود.
Future<Map<String, dynamic>> processCropInIsolate(
  Map<String, dynamic> args,
) async {
  final Uint8List bytes = args['bytes'] as Uint8List;

  final int filterIndex = _readFilterIndex(args);

  // ------------------------------------------------------------
  // 1. Read Corners
  // ------------------------------------------------------------

  final double topLeftX = _readDouble(args, 'topLeftX');

  final double topLeftY = _readDouble(args, 'topLeftY');

  final double topRightX = _readDouble(args, 'topRightX');

  final double topRightY = _readDouble(args, 'topRightY');

  final double bottomRightX = _readDouble(args, 'bottomRightX');

  final double bottomRightY = _readDouble(args, 'bottomRightY');

  final double bottomLeftX = _readDouble(args, 'bottomLeftX');

  final double bottomLeftY = _readDouble(args, 'bottomLeftY');

  // ------------------------------------------------------------
  // 2. Decode
  // ------------------------------------------------------------

  final img.Image? decoded = img.decodeImage(bytes);

  if (decoded == null) {
    throw Exception('فرمت تصویر قابل تشخیص نیست');
  }

  final img.Image fixed = img.bakeOrientation(decoded);

  final int originalWidth = fixed.width;
  final int originalHeight = fixed.height;

  // ------------------------------------------------------------
  // 3. High Quality Processing Image
  // ------------------------------------------------------------

  final int outputSize = _calculateOutputSize(originalWidth, originalHeight);

  final double outputScale = _calculateScale(
    originalWidth,
    originalHeight,
    outputSize,
  );

  final img.Image processingImage;

  if (outputScale < 1.0) {
    processingImage = img.copyResize(
      fixed,
      width: _scaledDimension(originalWidth, outputScale),
      height: _scaledDimension(originalHeight, outputScale),
      interpolation: img.Interpolation.linear,
    );
  } else {
    processingImage = fixed;
  }

  // ------------------------------------------------------------
  // 4. Corners
  // ------------------------------------------------------------

  final DocumentCorners corners = DocumentCorners(
    topLeft: Offset(topLeftX * outputScale, topLeftY * outputScale),
    topRight: Offset(topRightX * outputScale, topRightY * outputScale),
    bottomRight: Offset(bottomRightX * outputScale, bottomRightY * outputScale),
    bottomLeft: Offset(bottomLeftX * outputScale, bottomLeftY * outputScale),
  );

  // ------------------------------------------------------------
  // 5. Perspective
  // ------------------------------------------------------------

  final img.Image rectified = PerspectiveCorrector.rectify(
    processingImage,
    corners,
  );

  // ------------------------------------------------------------
  // 6. Filter
  // ------------------------------------------------------------

  final ScanFilter filter = _filterFromIndex(filterIndex);

  final img.Image enhanced;

  if (filter == ScanFilter.original) {
    enhanced = rectified;
  } else {
    enhanced = ImageEnhancer.apply(rectified, filter);
  }

  // ------------------------------------------------------------
  // 7. Encode
  // ------------------------------------------------------------

  final Uint8List processedBytes = Uint8List.fromList(
    img.encodeJpg(enhanced, quality: _jpegQuality),
  );

  return <String, dynamic>{'processedBytes': processedBytes};
}

/// ============================================================
/// Detection Size
/// ============================================================

/// اندازه Detection را بر اساس رزولوشن عکس تعیین می‌کند.
///
/// هدف این است که روی گوشی‌های مختلف:
///
/// 8MP  -> حدود 700-800px
/// 12MP -> حدود 800px
/// 16MP -> حدود 800-900px
/// 48MP -> همچنان محدود شود
///
/// بنابراین Detection هیچ‌وقت بی‌دلیل روی تصویر بزرگ اجرا نمی‌شود.
int _calculateDetectionSize(int width, int height) {
  final int largestSide = width > height ? width : height;

  if (largestSide <= _baseDetectionSize) {
    return largestSide;
  }

  // برای تصاویر خیلی کوچک
  if (largestSide < _minDetectionSize) {
    return largestSide;
  }

  return _baseDetectionSize;
}

/// ============================================================
/// Output Size
/// ============================================================

/// اندازه مناسب برای پردازش نهایی.
///
/// برای گوشی‌های مختلف خودکار تنظیم می‌شود.
///
/// نکته:
/// Detection همیشه کوچک است.
///
/// اما خروجی با رزولوشن بالا ساخته می‌شود.
int _calculateOutputSize(int width, int height) {
  final int largestSide = width > height ? width : height;

  // اگر تصویر از سقف کوچک‌تر است،
  // هیچ Resize انجام نمی‌دهیم.
  if (largestSide <= _maxOutputSize) {
    return largestSide;
  }

  // تصاویر خیلی کوچک
  if (largestSide < _minOutputSize) {
    return largestSide;
  }

  return _maxOutputSize;
}

/// ============================================================
/// Scale
/// ============================================================

double _calculateScale(int width, int height, int maxSize) {
  final int largestSide = width > height ? width : height;

  if (largestSide <= maxSize) {
    return 1.0;
  }

  return maxSize / largestSide;
}

/// ============================================================
/// Dimension
/// ============================================================

int _scaledDimension(int value, double scale) {
  final int result = (value * scale).round();

  return result < 1 ? 1 : result;
}

/// ============================================================
/// Scale Corners
/// ============================================================

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

/// ============================================================
/// Default Corners
/// ============================================================

/// اگر DocumentDetector نتوانست سند را پیدا کند،
/// به صورت پیش‌فرض حاشیه 6 درصد انتخاب می‌شود.
DocumentCorners _defaultCorners(img.Image image) {
  final double marginX = image.width * 0.06;
  final double marginY = image.height * 0.06;

  return DocumentCorners(
    topLeft: Offset(marginX, marginY),
    topRight: Offset(image.width - marginX, marginY),
    bottomRight: Offset(image.width - marginX, image.height - marginY),
    bottomLeft: Offset(marginX, image.height - marginY),
  );
}

/// ============================================================
/// Filter Index
/// ============================================================

int _readFilterIndex(Map<String, dynamic> args) {
  final dynamic value = args['filterIndex'];

  if (value is int) {
    return value.clamp(0, ScanFilter.values.length - 1);
  }

  if (value is num) {
    return value.toInt().clamp(0, ScanFilter.values.length - 1);
  }

  return 0;
}

/// ============================================================
/// Filter
/// ============================================================

ScanFilter _filterFromIndex(int index) {
  final int safeIndex = index.clamp(0, ScanFilter.values.length - 1);

  return ScanFilter.values[safeIndex];
}

/// ============================================================
/// Read Double
/// ============================================================

double _readDouble(Map<String, dynamic> args, String key) {
  final dynamic value = args[key];

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
