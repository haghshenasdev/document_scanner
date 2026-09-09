import 'package:image/image.dart' as img;

enum ScanFilter { original, document, grayscale, blackWhite }

class ImageEnhancer {
  ImageEnhancer._();

  static img.Image apply(img.Image source, ScanFilter filter) {
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

  // ==========================================================
  // DOCUMENT
  // ==========================================================

  static img.Image _document(img.Image source) {
    /// قبلاً بعد از adjustColor یک حلقه کامل
    /// روی تمام پیکسل‌ها اجرا می‌شد.
    ///
    /// این قسمت حذف شده تا سرعت بسیار بهتر شود.

    return img.adjustColor(
      source,
      brightness: 1.04,
      contrast: 1.10,
      saturation: 0.82,
    );
  }

  // ==========================================================
  // GRAYSCALE
  // ==========================================================

  static img.Image _grayscale(img.Image source) {
    return img.grayscale(source);
  }

  // ==========================================================
  // BLACK & WHITE
  // ==========================================================

  static img.Image _blackWhite(img.Image source) {
    final gray = img.grayscale(source);

    /// Threshold واقعی.
    ///
    /// قبلاً blackWhite در عمل فقط
    /// grayscale دوباره تولید می‌کرد.
    return img.luminanceThreshold(gray, threshold: .58, outputColor: false);
  }
}
