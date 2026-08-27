import 'dart:math' as math;
import 'dart:ui';

import 'package:image/image.dart' as img;

import '../models/document_corners.dart';

class PerspectiveCorrector {
  static img.Image rectify(img.Image source, DocumentCorners corners) {
    final tl = corners.topLeft;
    final tr = corners.topRight;
    final br = corners.bottomRight;
    final bl = corners.bottomLeft;

    // ==========================================================
    // 1. اندازه واقعی چهار ضلع
    // ==========================================================

    final double topWidth = _distance(tl, tr);

    final double bottomWidth = _distance(bl, br);

    final double leftHeight = _distance(tl, bl);

    final double rightHeight = _distance(tr, br);

    // ==========================================================
    // 2. اندازه خروجی
    //
    // از میانگین دو ضلع استفاده می‌کنیم، نه max.
    // این باعث می‌شود نسبت تصویر طبیعی‌تر شود.
    // ==========================================================

    final double outputWidth = (topWidth + bottomWidth) / 2.0;

    final double outputHeight = (leftHeight + rightHeight) / 2.0;

    // ==========================================================
    // 3. نسبت واقعی برگه
    // ==========================================================

    final double aspectRatio = outputWidth / outputHeight;

    // ==========================================================
    // 4. محدود کردن رزولوشن خروجی
    //
    // برای عکس‌های موبایل از تولید تصویر خیلی بزرگ
    // جلوگیری می‌کنیم.
    // ==========================================================

    const int maxDimension = 3000;

    int width;
    int height;

    if (outputWidth >= outputHeight) {
      width = math.min(outputWidth.round(), maxDimension);

      height = (width / aspectRatio).round();
    } else {
      height = math.min(outputHeight.round(), maxDimension);

      width = (height * aspectRatio).round();
    }

    // حداقل اندازه
    width = math.max(width, 100);
    height = math.max(height, 100);

    // ==========================================================
    // 5. جلوگیری از خروجی غیرمنطقی
    // ==========================================================

    final double finalRatio = width / height;

    if (finalRatio < 0.3 || finalRatio > 3.5) {
      // اگر چهار گوشه به‌شدت اشتباه باشند،
      // نسبت غیرطبیعی تولید نکن.
      throw Exception('نسبت گوشه‌های انتخاب‌شده غیرطبیعی است');
    }

    // ==========================================================
    // 6. ساخت تصویر مقصد
    // ==========================================================

    final destination = img.Image(
      width: width,
      height: height,
      numChannels: source.numChannels,
    );

    // ==========================================================
    // 7. Perspective Rectification
    //
    // نکته مهم:
    // اینجا toImage را مشخص می‌کنیم.
    //
    // در نتیجه copyRectify دیگر از اندازه تصویر اصلی
    // استفاده نمی‌کند.
    // ==========================================================

    return img.copyRectify(
      source,

      topLeft: img.Point(tl.dx, tl.dy),

      topRight: img.Point(tr.dx, tr.dy),

      bottomLeft: img.Point(bl.dx, bl.dy),

      bottomRight: img.Point(br.dx, br.dy),

      interpolation: img.Interpolation.cubic,

      toImage: destination,
    );
  }

  // ==========================================================
  // Distance between two points
  // ==========================================================

  static double _distance(Offset a, Offset b) {
    final dx = a.dx - b.dx;
    final dy = a.dy - b.dy;

    return math.sqrt(dx * dx + dy * dy);
  }
}
