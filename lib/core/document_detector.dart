import 'dart:math' as math;
import 'dart:ui';

import 'package:image/image.dart' as img;

import '../models/document_corners.dart';
import 'edge_detector.dart';

class DocumentDetector {
  static DocumentCorners? detect(img.Image original) {
    /*
     * برای سرعت، تصویر تشخیص را کوچک می‌کنیم.
     */
    final working = _resizeForDetection(original);

    final gray = EdgeDetector.grayscale(working);

    final edges = EdgeDetector.sobel(gray);

    /*
     * چند threshold مختلف را امتحان می‌کنیم.
     * این باعث می‌شود در تصاویر مختلف
     * شانس تشخیص بالاتر برود.
     */
    const thresholds = [45.0, 60.0, 75.0, 90.0, 110.0];

    DocumentCorners? best;
    double bestScore = double.negativeInfinity;

    for (final threshold in thresholds) {
      final binary = EdgeDetector.threshold(edges, threshold: threshold);

      final points = EdgeDetector.edgePoints(binary);

      if (points.length < 100) {
        continue;
      }

      final candidate = _findCandidate(points, working.width, working.height);

      if (candidate == null) {
        continue;
      }

      final score = _scoreCandidate(candidate, working.width, working.height);

      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }

    if (best == null) {
      return null;
    }

    /*
     * برگرداندن مختصات از تصویر کوچک
     * به تصویر اصلی
     */
    final scaleX = original.width / working.width;

    final scaleY = original.height / working.height;

    return DocumentCorners(
      topLeft: Offset(best.topLeft.dx * scaleX, best.topLeft.dy * scaleY),
      topRight: Offset(best.topRight.dx * scaleX, best.topRight.dy * scaleY),
      bottomRight: Offset(
        best.bottomRight.dx * scaleX,
        best.bottomRight.dy * scaleY,
      ),
      bottomLeft: Offset(
        best.bottomLeft.dx * scaleX,
        best.bottomLeft.dy * scaleY,
      ),
    );
  }

  static img.Image _resizeForDetection(img.Image image) {
    const maxSize = 1000;

    if (image.width <= maxSize && image.height <= maxSize) {
      return image;
    }

    final ratio = maxSize / math.max(image.width, image.height);

    return img.copyResize(
      image,
      width: (image.width * ratio).round(),
      height: (image.height * ratio).round(),
      interpolation: img.Interpolation.linear,
    );
  }

  static DocumentCorners? _findCandidate(
    List<PixelPoint> points,
    int width,
    int height,
  ) {
    /*
     * تصویر را به چهار ناحیه تقسیم می‌کنیم.
     */
    final centerX = width / 2;
    final centerY = height / 2;

    final topLeft = <PixelPoint>[];
    final topRight = <PixelPoint>[];
    final bottomLeft = <PixelPoint>[];
    final bottomRight = <PixelPoint>[];

    for (final point in points) {
      if (point.x < centerX && point.y < centerY) {
        topLeft.add(point);
      } else if (point.x >= centerX && point.y < centerY) {
        topRight.add(point);
      } else if (point.x < centerX && point.y >= centerY) {
        bottomLeft.add(point);
      } else {
        bottomRight.add(point);
      }
    }

    if (topLeft.isEmpty ||
        topRight.isEmpty ||
        bottomLeft.isEmpty ||
        bottomRight.isEmpty) {
      return null;
    }

    /*
     * برای هر گوشه، نقاطی را انتخاب می‌کنیم
     * که از نظر هندسی نزدیک گوشه تصویر باشند.
     */
    final tl = _findExtreme(topLeft, width, height, Corner.topLeft);

    final tr = _findExtreme(topRight, width, height, Corner.topRight);

    final br = _findExtreme(bottomRight, width, height, Corner.bottomRight);

    final bl = _findExtreme(bottomLeft, width, height, Corner.bottomLeft);

    if (tl == null || tr == null || br == null || bl == null) {
      return null;
    }

    return DocumentCorners(
      topLeft: Offset(tl.x.toDouble(), tl.y.toDouble()),
      topRight: Offset(tr.x.toDouble(), tr.y.toDouble()),
      bottomRight: Offset(br.x.toDouble(), br.y.toDouble()),
      bottomLeft: Offset(bl.x.toDouble(), bl.y.toDouble()),
    );
  }

  static PixelPoint? _findExtreme(
    List<PixelPoint> points,
    int width,
    int height,
    Corner corner,
  ) {
    if (points.isEmpty) {
      return null;
    }

    PixelPoint best = points.first;

    double bestScore = _cornerDistance(best, width, height, corner);

    /*
     * فقط بخش نزدیک به گوشه را بررسی می‌کنیم.
     */
    for (final point in points) {
      final score = _cornerDistance(point, width, height, corner);

      if (score < bestScore) {
        best = point;
        bestScore = score;
      }
    }

    return best;
  }

  static double _cornerDistance(
    PixelPoint p,
    int width,
    int height,
    Corner corner,
  ) {
    double dx;
    double dy;

    switch (corner) {
      case Corner.topLeft:
        dx = p.x.toDouble();
        dy = p.y.toDouble();
        break;

      case Corner.topRight:
        dx = width - p.x.toDouble();
        dy = p.y.toDouble();
        break;

      case Corner.bottomRight:
        dx = width - p.x.toDouble();
        dy = height - p.y.toDouble();
        break;

      case Corner.bottomLeft:
        dx = p.x.toDouble();
        dy = height - p.y.toDouble();
        break;
    }

    return dx * dx + dy * dy;
  }

  static double _scoreCandidate(DocumentCorners c, int width, int height) {
    if (!c.isValid) {
      return -double.infinity;
    }

    /*
     * برگه نباید بیش از حد کوچک باشد.
     */
    final imageArea = width * height;

    final areaRatio = c.area / imageArea;

    double score = 0;

    if (areaRatio > 0.15) {
      score += 30;
    }

    if (areaRatio > 0.30) {
      score += 20;
    }

    if (areaRatio > 0.50) {
      score += 20;
    }

    /*
     * بررسی زوایا.
     */
    final angle1 = _angle(c.topLeft, c.topRight, c.bottomRight);

    final angle2 = _angle(c.topRight, c.bottomRight, c.bottomLeft);

    final angle3 = _angle(c.bottomRight, c.bottomLeft, c.topLeft);

    final angle4 = _angle(c.bottomLeft, c.topLeft, c.topRight);

    final angleError =
        (angle1 - math.pi / 2).abs() +
        (angle2 - math.pi / 2).abs() +
        (angle3 - math.pi / 2).abs() +
        (angle4 - math.pi / 2).abs();

    score -= angleError * 20;

    /*
     * برگه خیلی باریک یا خیلی عجیب نباشد.
     */
    final width1 = _distance(c.topLeft, c.topRight);

    final width2 = _distance(c.bottomLeft, c.bottomRight);

    final height1 = _distance(c.topLeft, c.bottomLeft);

    final height2 = _distance(c.topRight, c.bottomRight);

    final avgWidth = (width1 + width2) / 2;

    final avgHeight = (height1 + height2) / 2;

    if (avgWidth <= 0 || avgHeight <= 0) {
      return -double.infinity;
    }

    final aspect = avgWidth / avgHeight;

    /*
     * A4:
     * 210 / 297 = 0.707
     *
     * A5:
     * 148 / 210 = 0.705
     *
     * بنابراین برای حالت portrait
     * نسبت تقریباً 0.7 است.
     */
    final portraitError = (aspect - 0.707).abs();

    final landscapeError = (aspect - 1.414).abs();

    final aspectError = math.min(portraitError, landscapeError);

    score -= aspectError * 30;

    return score;
  }

  static double _angle(Offset a, Offset b, Offset c) {
    final ab = a - b;
    final cb = c - b;

    final dot = ab.dx * cb.dx + ab.dy * cb.dy;

    final denominator = ab.distance * cb.distance;

    if (denominator == 0) {
      return 0;
    }

    final value = (dot / denominator).clamp(-1.0, 1.0);

    return math.acos(value);
  }

  static double _distance(Offset a, Offset b) {
    return (a - b).distance;
  }
}

enum Corner { topLeft, topRight, bottomRight, bottomLeft }
