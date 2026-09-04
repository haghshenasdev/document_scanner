import 'dart:math' as math;
import 'dart:ui';

import 'package:image/image.dart' as img;

import '../models/document_corners.dart';

class PerspectiveCorrector {
  // ===========================================================================
  // تنظیمات Performance
  // ===========================================================================

  /// حداکثر اندازه تصویر خروجی.
  ///
  /// 3000 قبلی برای موبایل نسبتاً سنگین بود.
  ///
  /// 2200:
  /// - کیفیت مناسب برای اسکن A4
  /// - مصرف RAM کمتر
  /// - Perspective بسیار سریع‌تر
  /// - Enhancement سریع‌تر
  static const int maxDimension = 2200;

  /// حداقل اندازه خروجی
  static const int minDimension = 100;

  // ===========================================================================
  // Public API
  // ===========================================================================

  static img.Image rectify(img.Image source, DocumentCorners corners) {
    final tl = corners.topLeft;
    final tr = corners.topRight;
    final br = corners.bottomRight;
    final bl = corners.bottomLeft;

    // =========================================================================
    // 1. اندازه اضلاع
    // =========================================================================

    final topWidth = _distance(tl, tr);
    final bottomWidth = _distance(bl, br);

    final leftHeight = _distance(tl, bl);
    final rightHeight = _distance(tr, br);

    // اگر اندازه‌ها غیرمنطقی باشند
    if (topWidth <= 1 ||
        bottomWidth <= 1 ||
        leftHeight <= 1 ||
        rightHeight <= 1) {
      throw Exception('اندازه گوشه‌های تصویر معتبر نیست');
    }

    // =========================================================================
    // 2. اندازه متوسط
    // =========================================================================

    final outputWidth = (topWidth + bottomWidth) * 0.5;

    final outputHeight = (leftHeight + rightHeight) * 0.5;

    if (outputWidth <= 1 || outputHeight <= 1) {
      throw Exception('اندازه خروجی غیرمعتبر است');
    }

    // =========================================================================
    // 3. نسبت تصویر
    // =========================================================================

    final aspectRatio = outputWidth / outputHeight;

    if (!aspectRatio.isFinite || aspectRatio <= 0) {
      throw Exception('نسبت تصویر غیرمعتبر است');
    }

    // =========================================================================
    // 4. تعیین اندازه خروجی
    // =========================================================================

    int width;
    int height;

    if (outputWidth >= outputHeight) {
      width = math.min(outputWidth.round(), maxDimension);

      height = math.max(minDimension, (width / aspectRatio).round());
    } else {
      height = math.min(outputHeight.round(), maxDimension);

      width = math.max(minDimension, (height * aspectRatio).round());
    }

    // =========================================================================
    // 5. محدودیت نهایی
    // =========================================================================

    width = math.max(minDimension, width);

    height = math.max(minDimension, height);

    // اگر به خاطر محاسبات بالا یکی از ابعاد دوباره از حد مجاز رد شد
    if (width > maxDimension || height > maxDimension) {
      final scale = maxDimension / math.max(width, height);

      width = math.max(minDimension, (width * scale).round());

      height = math.max(minDimension, (height * scale).round());
    }

    // =========================================================================
    // 6. بررسی نسبت نهایی
    // =========================================================================

    final finalRatio = width / height;

    if (!finalRatio.isFinite || finalRatio < 0.30 || finalRatio > 3.50) {
      throw Exception('نسبت گوشه‌های انتخاب‌شده غیرطبیعی است');
    }

    // =========================================================================
    // 7. ساخت تصویر مقصد
    // =========================================================================

    final destination = img.Image(
      width: width,
      height: height,
      numChannels: source.numChannels,
    );

    // =========================================================================
    // 8. Perspective Correction
    // =========================================================================
    //
    // نکته:
    //
    // copyRectify فقط به اندازه destination پیکسل تولید می‌کند.
    //
    // بنابراین اگر عکس دوربین مثلاً 4000x3000 باشد ولی خروجی
    // 2200x1650 باشد، به جای میلیون‌ها پیکسل اضافه،
    // فقط تصویر مورد نیاز تولید می‌شود.
    //
    // این قسمت یکی از مهم‌ترین بهینه‌سازی‌های این نسخه است.
    // =========================================================================

    return img.copyRectify(
      source,
      topLeft: img.Point(tl.dx, tl.dy),
      topRight: img.Point(tr.dx, tr.dy),
      bottomLeft: img.Point(bl.dx, bl.dy),
      bottomRight: img.Point(br.dx, br.dy),
      interpolation: img.Interpolation.linear,
      toImage: destination,
    );
  }

  // ===========================================================================
  // Distance
  // ===========================================================================

  static double _distance(Offset a, Offset b) {
    final dx = a.dx - b.dx;

    final dy = a.dy - b.dy;

    return math.sqrt(dx * dx + dy * dy);
  }
}
