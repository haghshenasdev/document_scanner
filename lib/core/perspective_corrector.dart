import 'dart:math' as math;
import 'dart:ui';

import 'package:image/image.dart' as img;

import '../models/document_corners.dart';

class PerspectiveCorrector {
  static const int minDimension = 100;

  /// حداکثر اندازه خروجی Preview
  static const int previewMaxDimension = 1200;

  /// خروجی نهایی محدودیت اندازه ندارد.
  static const int? finalMaxDimension = null;

  static img.Image rectify(
    img.Image source,
    DocumentCorners corners, {
    bool preview = false,
  }) {
    final Offset tl = corners.topLeft;
    final Offset tr = corners.topRight;
    final Offset br = corners.bottomRight;
    final Offset bl = corners.bottomLeft;

    // ==========================================================
    // ESTIMATE OUTPUT SIZE
    // ==========================================================

    final double topWidth = _distance(tl, tr);

    final double bottomWidth = _distance(bl, br);

    final double leftHeight = _distance(tl, bl);

    final double rightHeight = _distance(tr, br);

    if (topWidth <= 1 ||
        bottomWidth <= 1 ||
        leftHeight <= 1 ||
        rightHeight <= 1) {
      throw Exception('اندازه گوشه‌های تصویر معتبر نیست');
    }

    double estimatedWidth = (topWidth + bottomWidth) * .5;

    double estimatedHeight = (leftHeight + rightHeight) * .5;

    if (estimatedWidth <= 1 || estimatedHeight <= 1) {
      throw Exception('اندازه خروجی غیرمعتبر است');
    }

    final double aspectRatio = estimatedWidth / estimatedHeight;

    if (!aspectRatio.isFinite || aspectRatio <= 0) {
      throw Exception('نسبت تصویر غیرمعتبر است');
    }

    int width = estimatedWidth.round();

    int height = estimatedHeight.round();

    width = math.max(minDimension, width);

    height = math.max(minDimension, height);

    // ==========================================================
    // PREVIEW SIZE
    // ==========================================================

    final int? maxDimension = preview ? previewMaxDimension : finalMaxDimension;

    if (maxDimension != null &&
        (width > maxDimension || height > maxDimension)) {
      final double scale = maxDimension / math.max(width, height);

      width = math.max(minDimension, (width * scale).round());

      height = math.max(minDimension, (height * scale).round());
    }

    // ==========================================================
    // SANITY CHECK
    // ==========================================================

    final double finalRatio = width / height;

    if (!finalRatio.isFinite || finalRatio < .30 || finalRatio > 3.50) {
      throw Exception('نسبت گوشه‌های انتخاب‌شده غیرطبیعی است');
    }

    // ==========================================================
    // RECTIFY
    // ==========================================================

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

      // Linear برای سرعت مناسب‌تر است
      // و کیفیت آن برای اسکن سند مناسب است.
      interpolation: img.Interpolation.linear,

      toImage: destination,
    );
  }

  static double _distance(Offset a, Offset b) {
    final double dx = a.dx - b.dx;

    final double dy = a.dy - b.dy;

    return math.sqrt(dx * dx + dy * dy);
  }
}
