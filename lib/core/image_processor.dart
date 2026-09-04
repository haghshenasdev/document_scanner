import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../models/document_corners.dart';
import 'document_detector.dart';
import 'image_enhancer.dart';
import 'perspective_corrector.dart';

/// حداکثر اندازه‌ای که برای تشخیص گوشه‌ها استفاده می‌شود.
///
/// تشخیص روی تصویر کوچک‌تر بسیار سریع‌تر است و بعداً
/// مختصات گوشه‌ها به اندازه اصلی برگردانده می‌شوند.
const int _maxDetectionSize = 900;

/// حداکثر اندازه تصویر برای Perspective و فیلترها.
///
/// نگه داشتن تصویر در حدود 2200px باعث کاهش محسوس زمان
/// پردازش و مصرف RAM می‌شود، بدون اینکه کیفیت اسکن معمولی
/// افت زیادی داشته باشد.
const int _maxProcessingSize = 2200;

/// کیفیت JPEG.
///
/// 92 معمولاً برای اسناد کیفیت بسیار خوبی دارد و نسبت به 95
/// حجم و زمان encode کمتری ایجاد می‌کند.
const int _jpegQuality = 92;

/// پردازش کامل یک عکس گرفته‌شده توسط دوربین.
///
/// این تابع برای اجرا با compute طراحی شده است:
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
  // 1. Decode
  // ------------------------------------------------------------

  final img.Image? decoded = img.decodeImage(bytes);

  if (decoded == null) {
    throw Exception('فرمت تصویر قابل تشخیص نیست');
  }

  // اصلاح EXIF Orientation
  final img.Image fixed = img.bakeOrientation(decoded);

  // ------------------------------------------------------------
  // 2. تشخیص گوشه‌های سند
  // ------------------------------------------------------------

  final double detectionScale = _calculateScale(
    fixed.width,
    fixed.height,
    _maxDetectionSize,
  );

  final img.Image detectionImage;

  if (detectionScale < 1.0) {
    detectionImage = img.copyResize(
      fixed,
      width: (fixed.width * detectionScale).round(),
      height: (fixed.height * detectionScale).round(),
      interpolation: img.Interpolation.linear,
    );
  } else {
    detectionImage = fixed;
  }

  DocumentCorners? detected = DocumentDetector.detect(detectionImage);

  // مختصات تشخیص داده شده در اندازه کوچک را به مختصات
  // تصویر اصلی برمی‌گردانیم.
  DocumentCorners corners;

  if (detected != null) {
    corners = _scaleCorners(detected, 1.0 / detectionScale);
  } else {
    corners = _defaultCorners(fixed);
  }

  // ------------------------------------------------------------
  // 3. کوچک کردن تصویر برای Perspective
  // ------------------------------------------------------------

  final double processingScale = _calculateScale(
    fixed.width,
    fixed.height,
    _maxProcessingSize,
  );

  final img.Image processingImage;

  if (processingScale < 1.0) {
    processingImage = img.copyResize(
      fixed,
      width: (fixed.width * processingScale).round(),
      height: (fixed.height * processingScale).round(),
      interpolation: img.Interpolation.linear,
    );
  } else {
    processingImage = fixed;
  }

  // مختصات گوشه‌ها باید با تصویر processingImage هماهنگ شوند.
  final DocumentCorners processingCorners = _scaleCorners(
    corners,
    processingScale,
  );

  // ------------------------------------------------------------
  // 4. اصلاح Perspective
  // ------------------------------------------------------------

  final img.Image rectified = PerspectiveCorrector.rectify(
    processingImage,
    processingCorners,
  );

  // ------------------------------------------------------------
  // 5. اعمال فیلتر
  // ------------------------------------------------------------

  final ScanFilter filter = _filterFromIndex(filterIndex);

  final img.Image enhanced = ImageEnhancer.apply(rectified, filter);

  // ------------------------------------------------------------
  // 6. Encode
  // ------------------------------------------------------------

  final Uint8List originalBytes = Uint8List.fromList(
    img.encodeJpg(fixed, quality: _jpegQuality),
  );

  final Uint8List processedBytes = Uint8List.fromList(
    img.encodeJpg(enhanced, quality: _jpegQuality),
  );

  // ------------------------------------------------------------
  // 7. نتیجه
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

/// پردازش تصویر بعد از اینکه کاربر گوشه‌های سند را در CropEditor
/// تغییر داده است.
///
/// این تابع نیز باید با compute اجرا شود.
Future<Map<String, dynamic>> processCropInIsolate(
  Map<String, dynamic> args,
) async {
  final Uint8List bytes = args['bytes'] as Uint8List;

  final int filterIndex = _readFilterIndex(args);

  // ------------------------------------------------------------
  // مختصات گوشه‌ها
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
  // 1. Decode
  // ------------------------------------------------------------

  final img.Image? decoded = img.decodeImage(bytes);

  if (decoded == null) {
    throw Exception('فرمت تصویر قابل تشخیص نیست');
  }

  final img.Image fixed = img.bakeOrientation(decoded);

  // ------------------------------------------------------------
  // 2. محدود کردن اندازه پردازش
  // ------------------------------------------------------------

  final double processingScale = _calculateScale(
    fixed.width,
    fixed.height,
    _maxProcessingSize,
  );

  final img.Image processingImage;

  if (processingScale < 1.0) {
    processingImage = img.copyResize(
      fixed,
      width: (fixed.width * processingScale).round(),
      height: (fixed.height * processingScale).round(),
      interpolation: img.Interpolation.linear,
    );
  } else {
    processingImage = fixed;
  }

  // ------------------------------------------------------------
  // 3. ساخت گوشه‌ها
  // ------------------------------------------------------------

  final DocumentCorners corners = DocumentCorners(
    topLeft: Offset(topLeftX * processingScale, topLeftY * processingScale),
    topRight: Offset(topRightX * processingScale, topRightY * processingScale),
    bottomRight: Offset(
      bottomRightX * processingScale,
      bottomRightY * processingScale,
    ),
    bottomLeft: Offset(
      bottomLeftX * processingScale,
      bottomLeftY * processingScale,
    ),
  );

  // ------------------------------------------------------------
  // 4. Perspective Correction
  // ------------------------------------------------------------

  final img.Image rectified = PerspectiveCorrector.rectify(
    processingImage,
    corners,
  );

  // ------------------------------------------------------------
  // 5. Filter
  // ------------------------------------------------------------

  final ScanFilter filter = _filterFromIndex(filterIndex);

  final img.Image enhanced = ImageEnhancer.apply(rectified, filter);

  // ------------------------------------------------------------
  // 6. Encode
  // ------------------------------------------------------------

  final Uint8List processedBytes = Uint8List.fromList(
    img.encodeJpg(enhanced, quality: _jpegQuality),
  );

  return <String, dynamic>{'processedBytes': processedBytes};
}

/// محاسبه ضریب Resize.
///
/// اگر تصویر کوچک‌تر از maxSize باشد، همان تصویر استفاده می‌شود.
double _calculateScale(int width, int height, int maxSize) {
  final int largestSide = width > height ? width : height;

  if (largestSide <= maxSize) {
    return 1.0;
  }

  return maxSize / largestSide;
}

/// تغییر مقیاس مختصات چهار گوشه.
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

/// اگر تشخیص سند موفق نبود، به صورت پیش‌فرض
/// حدود 6 درصد از اطراف تصویر را حذف می‌کنیم.
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

/// خواندن امن filterIndex.
int _readFilterIndex(Map<String, dynamic> args) {
  final dynamic value = args['filterIndex'];

  if (value is int) {
    return value.clamp(0, ScanFilter.values.length - 1);
  }

  return 0;
}

/// تبدیل index به ScanFilter.
ScanFilter _filterFromIndex(int index) {
  final int safeIndex = index.clamp(0, ScanFilter.values.length - 1);

  return ScanFilter.values[safeIndex];
}

/// خواندن عدد double از arguments.
///
/// اگر مقدار وجود نداشته باشد یا معتبر نباشد، خطا ایجاد می‌شود
/// تا پردازش اشتباه و بی‌صدا انجام نشود.
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
