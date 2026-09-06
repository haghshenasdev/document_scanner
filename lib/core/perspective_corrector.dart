import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../models/document_corners.dart';

class PerspectiveCorrector {
  PerspectiveCorrector._();

  /// ==========================================================
  /// RECTIFY
  /// ==========================================================
  ///
  /// تصویر را با استفاده از چهار گوشه سند صاف می‌کند.
  ///
  /// هیچ Resize اجباری روی تصویر ورودی انجام نمی‌شود.
  /// بنابراین اگر عکس 4000x3000 باشد، Perspective نیز
  /// روی همان رزولوشن انجام می‌شود.
  static img.Image rectify(
    img.Image source,
    DocumentCorners corners,
  ) {
    final points = corners.points;

    if (points.length != 4) {
      return source;
    }

    final topLeft = points[0];
    final topRight = points[1];
    final bottomRight = points[2];
    final bottomLeft = points[3];

    /// --------------------------------------------------------
    /// Calculate output width
    /// --------------------------------------------------------

    final topWidth = _distance(
      topLeft,
      topRight,
    );

    final bottomWidth = _distance(
      bottomLeft,
      bottomRight,
    );

    final outputWidth =
        math.max(
          1,
          math.max(
            topWidth,
            bottomWidth,
          ).round(),
        );

    /// --------------------------------------------------------
    /// Calculate output height
    /// --------------------------------------------------------

    final leftHeight = _distance(
      topLeft,
      bottomLeft,
    );

    final rightHeight = _distance(
      topRight,
      bottomRight,
    );

    final outputHeight =
        math.max(
          1,
          math.max(
            leftHeight,
            rightHeight,
          ).round(),
        );

    /// جلوگیری از خروجی‌های غیرواقعی در صورت Detection اشتباه.
    ///
    /// این سقف مربوط به رزولوشن نیست؛ فقط از ایجاد تصویر
    /// غیرمنطقی در اثر مختصات خراب جلوگیری می‌کند.
    final safeWidth = outputWidth.clamp(
      1,
      source.width * 2,
    );

    final safeHeight = outputHeight.clamp(
      1,
      source.height * 2,
    );

    /// --------------------------------------------------------
    /// Perspective transform
    /// --------------------------------------------------------

    return img.copyRectify(
      source,
      topLeft,
      topRight,
      bottomRight,
      bottomLeft,
      width: safeWidth,
      height: safeHeight,
    );
  }

  static double _distance(
    Offset a,
    Offset b,
  ) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;

    return math.sqrt(
      dx * dx + dy * dy,
    );
  }
}