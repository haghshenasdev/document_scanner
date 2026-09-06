import 'package:image/image.dart' as img;

enum ScanFilter { original, document, sharp, grayscale, blackWhite, magicColor }

class ImageEnhancer {
  // ============================================================
  // Public API
  // ============================================================

  static img.Image apply(img.Image source, ScanFilter filter) {
    switch (filter) {
      case ScanFilter.original:
        return source;

      case ScanFilter.document:
        return _document(source);

      case ScanFilter.sharp:
        return _sharp(source);

      case ScanFilter.grayscale:
        return img.grayscale(source);

      case ScanFilter.blackWhite:
        return _blackWhite(source);

      case ScanFilter.magicColor:
        return _magicColor(source);
    }
  }

  // ============================================================
  // Document
  // ============================================================
  //
  // مهم:
  //
  // قبلاً:
  //
  // adjustColor
  // +
  // whitenPaper
  // +
  // convolution
  //
  // انجام می‌شد.
  //
  // الان فقط adjustColor انجام می‌شود.
  //
  // این کار برای سرعت بسیار بهتر است.
  // ============================================================

  static img.Image _document(img.Image image) {
    return img.adjustColor(
      image,
      contrast: 1.12,
      brightness: 1.04,
      saturation: 0.94,
    );
  }

  // ============================================================
  // Sharp
  // ============================================================

  static img.Image _sharp(img.Image image) {
    var result = img.adjustColor(image, contrast: 1.10, brightness: 1.02);

    // فقط در صورت انتخاب صریح Sharp
    // عملیات convolution انجام می‌شود.
    result = img.convolution(
      result,
      filter: const [0, -1, 0, -1, 5, -1, 0, -1, 0],
    );

    return result;
  }

  // ============================================================
  // Black & White
  // ============================================================

  static img.Image _blackWhite(img.Image image) {
    var result = img.grayscale(image);

    result = img.adjustColor(result, contrast: 1.30, brightness: 1.04);

    for (final pixel in result) {
      final luminance = pixel.luminance;

      if (luminance > 185) {
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
  // Magic Color
  // ============================================================

  static img.Image _magicColor(img.Image image) {
    return img.adjustColor(
      image,
      brightness: 1.04,
      contrast: 1.08,
      saturation: 0.96,
    );
  }
}
