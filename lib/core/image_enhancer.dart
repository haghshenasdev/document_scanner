import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// ============================================================
/// SCAN FILTER
/// ============================================================

enum ScanFilter {
  original,
  document,
  grayscale,
  blackWhite,
}

/// ============================================================
/// IMAGE ENHANCER
/// ============================================================

class ImageEnhancer {
  ImageEnhancer._();

  static img.Image apply(
    img.Image source,
    ScanFilter filter,
  ) {
    switch (filter) {
      case ScanFilter.original:
        return source;

      case ScanFilter.document:
        return _document(source);

      case ScanFilter.grayscale:
        return _grayscale(source);

      case ScanFilter.blackWhite:
        return _blackWhite(source);
    }
  }

  /// ==========================================================
  /// DOCUMENT
  /// ==========================================================
  ///
  /// مناسب برای نامه، برگه و اسناد.
  ///
  /// هدف:
  /// - سفیدتر شدن کاغذ
  /// - خواناتر شدن متن
  /// - حفظ جزئیات
  /// - جلوگیری از سفید شدن بیش از حد متن
  static img.Image _document(
    img.Image source,
  ) {
    final result = img.adjustColor(
      source,
      brightness: 1.04,
      contrast: 1.08,
      saturation: 0.88,
    );

    /// سفید کردن نرم پس‌زمینه.
    ///
    /// فقط پیکسل‌هایی که روشن هستند تحت تأثیر قرار می‌گیرند.
    /// پیکسل‌های تیره مربوط به متن هستند و تقریباً دست‌نخورده
    /// باقی می‌مانند.
    for (int y = 0; y < result.height; y++) {
      for (int x = 0; x < result.width; x++) {
        final pixel = result.getPixel(x, y);

        final r = pixel.r.toDouble();
        final g = pixel.g.toDouble();
        final b = pixel.b.toDouble();

        /// روشنایی تقریبی
        final luminance =
            0.299 * r +
            0.587 * g +
            0.114 * b;

        /// میزان اختلاف رنگ.
        final maxChannel = math.max(
          r,
          math.max(g, b),
        );

        final minChannel = math.min(
          r,
          math.min(g, b),
        );

        final chroma =
            maxChannel - minChannel;

        /// فقط نواحی نسبتاً سفید/روشن.
        if (luminance > 175 && chroma < 55) {
          /// هرچه روشن‌تر باشد، سفید شدن بیشتر.
          final amount =
              ((luminance - 175) / 80)
                  .clamp(0.0, 1.0);

          final strength =
              0.18 + (amount * 0.42);

          final nr =
              r + (255.0 - r) * strength;

          final ng =
              g + (255.0 - g) * strength;

          final nb =
              b + (255.0 - b) * strength;

          pixel
            ..r = nr.round().clamp(0, 255)
            ..g = ng.round().clamp(0, 255)
            ..b = nb.round().clamp(0, 255);
        }
      }
    }

    return result;
  }

  /// ==========================================================
  /// GRAYSCALE
  /// ==========================================================

  static img.Image _grayscale(
    img.Image source,
  ) {
    return img.grayscale(source);
  }

  /// ==========================================================
  /// BLACK & WHITE
  /// ==========================================================

  static img.Image _blackWhite(
    img.Image source,
  ) {
    final gray = img.grayscale(source);

    /// کنتراست قبل از Threshold
    final adjusted = img.adjustColor(
      gray,
      contrast: 1.18,
      brightness: 1.02,
    );

    return img.grayscale(
      adjusted,
    );
  }
}