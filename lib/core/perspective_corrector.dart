import 'dart:math' as math;
import 'dart:ui';

import 'package:image/image.dart' as img;

import '../models/document_corners.dart';

class PerspectiveCorrector {
  static const int minDimension = 100;

  /// برای Preview محدودیت داریم.
  static const int previewMaxDimension = 1400;

  /// برای خروجی نهایی محدودیت نداریم.
  static const int? finalMaxDimension = null;

  static img.Image rectify(
    img.Image source,
    DocumentCorners corners, {
    bool preview = false,
  }) {
    final tl = corners.topLeft;
    final tr = corners.topRight;
    final br = corners.bottomRight;
    final bl = corners.bottomLeft;

    final topWidth = _distance(tl, tr);

    final bottomWidth = _distance(bl, br);

    final leftHeight = _distance(tl, bl);

    final rightHeight = _distance(tr, br);

    if (topWidth <= 1 ||
        bottomWidth <= 1 ||
        leftHeight <= 1 ||
        rightHeight <= 1) {
      throw Exception('اندازه گوشه‌های تصویر معتبر نیست');
    }

    final estimatedWidth = (topWidth + bottomWidth) * .5;

    final estimatedHeight = (leftHeight + rightHeight) * .5;

    if (estimatedWidth <= 1 || estimatedHeight <= 1) {
      throw Exception('اندازه خروجی غیرمعتبر است');
    }

    final aspectRatio = estimatedWidth / estimatedHeight;

    if (!aspectRatio.isFinite || aspectRatio <= 0) {
      throw Exception('نسبت تصویر غیرمعتبر است');
    }

    int width = estimatedWidth.round();

    int height = estimatedHeight.round();

    width = math.max(minDimension, width);

    height = math.max(minDimension, height);

    final int? maxDimension = preview ? previewMaxDimension : finalMaxDimension;

    if (maxDimension != null &&
        (width > maxDimension || height > maxDimension)) {
      final scale = maxDimension / math.max(width, height);

      width = math.max(minDimension, (width * scale).round());

      height = math.max(minDimension, (height * scale).round());
    }

    final finalRatio = width / height;

    if (!finalRatio.isFinite || finalRatio < .30 || finalRatio > 3.50) {
      throw Exception('نسبت گوشه‌های انتخاب‌شده غیرطبیعی است');
    }

    final destination = img.Image(
      width: width,
      height: height,
      numChannels: source.numChannels,
    );

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

  static double _distance(Offset a, Offset b) {
    final dx = a.dx - b.dx;

    final dy = a.dy - b.dy;

    return math.sqrt(dx * dx + dy * dy);
  }
}
