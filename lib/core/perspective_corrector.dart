import 'dart:math' as math;
import 'dart:ui';

import 'package:image/image.dart' as img;

import '../models/document_corners.dart';

class PerspectiveCorrector {
  static img.Image rectify(
    img.Image source,
    DocumentCorners corners,
  ) {
    final tl = corners.topLeft;
    final tr = corners.topRight;
    final br = corners.bottomRight;
    final bl = corners.bottomLeft;

    final topWidth =
        (tr - tl).distance;

    final bottomWidth =
        (br - bl).distance;

    final leftHeight =
        (bl - tl).distance;

    final rightHeight =
        (br - tr).distance;

    int width = math.max(
      topWidth,
      bottomWidth,
    ).round();

    int height = math.max(
      leftHeight,
      rightHeight,
    ).round();

    /*
     * محدود کردن خروجی
     */
    const maxDimension = 3000;

    if (width > maxDimension ||
        height > maxDimension) {
      final scale =
          maxDimension /
              math.max(width, height);

      width =
          (width * scale).round();

      height =
          (height * scale).round();
    }

    /*
     * image package برای copyRectify
     * چهار گوشه را دریافت می‌کند.
     */
    return img.copyRectify(
      source,
      topLeft: img.Point(
        tl.dx,
        tl.dy,
      ),
      topRight: img.Point(
        tr.dx,
        tr.dy,
      ),
      bottomRight: img.Point(
        br.dx,
        br.dy,
      ),
      bottomLeft: img.Point(
        bl.dx,
        bl.dy,
      ),
    );
  }
}