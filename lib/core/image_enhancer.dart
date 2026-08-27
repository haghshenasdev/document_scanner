import 'package:image/image.dart' as img;

enum ScanFilter { original, document, sharp, grayscale, blackWhite, magicColor }

class ImageEnhancer {
  static img.Image apply(img.Image source, ScanFilter filter) {
    // یک کپی می‌گیریم تا تصویر اصلی تغییر نکند
    img.Image result = img.copyResize(
      source,
      width: source.width,
      height: source.height,
      interpolation: img.Interpolation.nearest,
    );

    switch (filter) {
      case ScanFilter.original:
        return result;

      case ScanFilter.document:
        return _document(result);

      case ScanFilter.sharp:
        return _sharp(result);

      case ScanFilter.grayscale:
        return _grayscale(result);

      case ScanFilter.blackWhite:
        return _blackWhite(result);

      case ScanFilter.magicColor:
        return _magicColor(result);
    }
  }

  // ============================================================
  // DOCUMENT
  // ============================================================

  static img.Image _document(img.Image image) {
    // کمی افزایش کنتراست
    var result = img.adjustColor(
      image,
      contrast: 1.15,
      brightness: 1.04,
      saturation: 0.92,
    );

    // سفیدتر شدن زمینه
    result = _whitenPaper(result, strength: 0.20);

    // شارپ ملایم
    result = img.convolution(result, filter: [0, -1, 0, -1, 5, -1, 0, -1, 0]);

    return result;
  }

  // ============================================================
  // SHARP
  // ============================================================

  static img.Image _sharp(img.Image image) {
    var result = img.adjustColor(image, contrast: 1.12, brightness: 1.02);

    result = img.convolution(result, filter: [0, -1, 0, -1, 5.5, -1, 0, -1, 0]);

    return result;
  }

  // ============================================================
  // GRAYSCALE
  // ============================================================

  static img.Image _grayscale(img.Image image) {
    return img.grayscale(image);
  }

  // ============================================================
  // BLACK & WHITE
  // ============================================================

  static img.Image _blackWhite(img.Image image) {
    var result = img.grayscale(image);

    result = img.adjustColor(result, contrast: 1.35, brightness: 1.05);

    // threshold
    for (final pixel in result) {
      final gray = pixel.luminance;

      if (gray > 185) {
        pixel.r = 255;
        pixel.g = 255;
        pixel.b = 255;
      } else {
        pixel.r = 0;
        pixel.g = 0;
        pixel.b = 0;
      }
    }

    return result;
  }

  // ============================================================
  // MAGIC COLOR
  // ============================================================

  static img.Image _magicColor(img.Image image) {
    var result = img.adjustColor(
      image,
      brightness: 1.05,
      contrast: 1.10,
      saturation: 0.95,
    );

    result = _whitenPaper(result, strength: 0.12);

    result = img.convolution(result, filter: [0, -1, 0, -1, 5, -1, 0, -1, 0]);

    return result;
  }

  // ============================================================
  // PAPER WHITENING
  // ============================================================

  static img.Image _whitenPaper(img.Image image, {double strength = 0.15}) {
    for (final pixel in image) {
      final r = pixel.r.toDouble();
      final g = pixel.g.toDouble();
      final b = pixel.b.toDouble();

      // روشنایی تقریبی
      final luminance = 0.299 * r + 0.587 * g + 0.114 * b;

      // فقط قسمت‌های نسبتاً روشن تصویر را
      // به سمت سفید می‌بریم.
      if (luminance > 150) {
        final amount = ((luminance - 150) / 105).clamp(0.0, 1.0) * strength;

        pixel.r = _lerp(r, 255, amount).round();

        pixel.g = _lerp(g, 255, amount).round();

        pixel.b = _lerp(b, 255, amount).round();
      }
    }

    return image;
  }

  // ============================================================
  // LERP
  // ============================================================

  static double _lerp(double a, double b, double t) {
    return a + (b - a) * t;
  }
}
