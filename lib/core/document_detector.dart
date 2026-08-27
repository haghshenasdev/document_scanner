import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;

import '../models/document_corners.dart';

class DocumentDetector {
  static const int maxDetectionSize = 1000;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  static DocumentCorners? detect(img.Image original) {
    if (original.width < 100 || original.height < 100) {
      return null;
    }

    final working = _resizeForDetection(original);

    final gray = _grayscale(working);

    final otsu = _otsuThreshold(gray);

    final thresholds = <int>{
      (otsu - 30).clamp(40, 230),
      (otsu - 20).clamp(40, 230),
      (otsu - 10).clamp(40, 230),
      otsu.clamp(40, 230),
      (otsu + 10).clamp(40, 230),
      (otsu + 20).clamp(40, 230),
      (otsu + 30).clamp(40, 230),
    }.toList();

    DocumentCorners? best;
    double bestScore = double.negativeInfinity;

    for (final threshold in thresholds) {
      final binary = _threshold(gray, threshold);

      final component = _largestComponent(
        binary,
        working.width,
        working.height,
      );

      if (component == null) {
        continue;
      }

      final rough = _componentToCorners(
        component,
        working.width,
        working.height,
      );

      if (rough == null) {
        continue;
      }

      // -------------------------------------------------------
      // مرحله مهم:
      // اصلاح گوشه‌ها با Fit کردن خطوط واقعی اضلاع
      // -------------------------------------------------------

      final refined = _refineCorners(
        rough,
        component.boundary,
        working.width,
        working.height,
      );

      final candidate = refined ?? rough;

      final score = _scoreCandidate(
        candidate,
        component.area,
        working.width,
        working.height,
      );

      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }

    if (best == null) {
      return null;
    }

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

  // ---------------------------------------------------------------------------
  // Resize
  // ---------------------------------------------------------------------------

  static img.Image _resizeForDetection(img.Image image) {
    if (image.width <= maxDetectionSize && image.height <= maxDetectionSize) {
      return image;
    }

    final ratio = maxDetectionSize / math.max(image.width, image.height);

    return img.copyResize(
      image,
      width: math.max(1, (image.width * ratio).round()),
      height: math.max(1, (image.height * ratio).round()),
      interpolation: img.Interpolation.linear,
    );
  }

  // ---------------------------------------------------------------------------
  // Grayscale
  // ---------------------------------------------------------------------------

  static Uint8List _grayscale(img.Image image) {
    final width = image.width;
    final height = image.height;

    final result = Uint8List(width * height);

    int index = 0;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = image.getPixel(x, y);

        final r = pixel.r.toDouble();
        final g = pixel.g.toDouble();
        final b = pixel.b.toDouble();

        result[index++] = (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(
          0,
          255,
        );
      }
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // Otsu
  // ---------------------------------------------------------------------------

  static int _otsuThreshold(Uint8List gray) {
    final histogram = Int64List(256);

    for (final value in gray) {
      histogram[value]++;
    }

    final total = gray.length;

    double sum = 0;

    for (int i = 0; i < 256; i++) {
      sum += i * histogram[i];
    }

    double sumBackground = 0;

    int weightBackground = 0;

    double maxVariance = -1;

    int bestThreshold = 128;

    for (int threshold = 0; threshold < 256; threshold++) {
      weightBackground += histogram[threshold];

      if (weightBackground == 0) {
        continue;
      }

      final weightForeground = total - weightBackground;

      if (weightForeground == 0) {
        break;
      }

      sumBackground += threshold * histogram[threshold];

      final meanBackground = sumBackground / weightBackground;

      final meanForeground = (sum - sumBackground) / weightForeground;

      final difference = meanBackground - meanForeground;

      final variance =
          weightBackground * weightForeground * difference * difference;

      if (variance > maxVariance) {
        maxVariance = variance;
        bestThreshold = threshold;
      }
    }

    return bestThreshold;
  }

  // ---------------------------------------------------------------------------
  // Binary
  // ---------------------------------------------------------------------------

  static Uint8List _threshold(Uint8List gray, int threshold) {
    final result = Uint8List(gray.length);

    for (int i = 0; i < gray.length; i++) {
      result[i] = gray[i] >= threshold ? 1 : 0;
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // Largest connected component
  // ---------------------------------------------------------------------------

  static _Component? _largestComponent(
    Uint8List binary,
    int width,
    int height,
  ) {
    final visited = Uint8List(binary.length);

    final queue = Int32List(binary.length);

    _Component? best;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final start = y * width + x;

        if (binary[start] == 0 || visited[start] != 0) {
          continue;
        }

        int head = 0;
        int tail = 0;

        queue[tail++] = start;

        visited[start] = 1;

        int area = 0;

        int minX = x;
        int maxX = x;

        int minY = y;
        int maxY = y;

        int tlX = x;
        int tlY = y;

        int trX = x;
        int trY = y;

        int brX = x;
        int brY = y;

        int blX = x;
        int blY = y;

        final boundary = <Offset>[];

        while (head < tail) {
          final index = queue[head++];

          final px = index % width;

          final py = index ~/ width;

          area++;

          minX = math.min(minX, px);

          maxX = math.max(maxX, px);

          minY = math.min(minY, py);

          maxY = math.max(maxY, py);

          // ---------------------------------------------------
          // تقریبی‌ترین چهار گوشه
          // ---------------------------------------------------

          if (px + py < tlX + tlY) {
            tlX = px;
            tlY = py;
          }

          if (px - py > trX - trY) {
            trX = px;
            trY = py;
          }

          if (px + py > brX + brY) {
            brX = px;
            brY = py;
          }

          if (px - py < blX - blY) {
            blX = px;
            blY = py;
          }

          // ---------------------------------------------------
          // آیا این Pixel روی مرز Component است؟
          // ---------------------------------------------------

          bool isBoundary = false;

          // بالا
          if (py == 0) {
            isBoundary = true;
          } else if (binary[index - width] == 0) {
            isBoundary = true;
          }

          // پایین
          if (!isBoundary) {
            if (py == height - 1) {
              isBoundary = true;
            } else if (binary[index + width] == 0) {
              isBoundary = true;
            }
          }

          // چپ
          if (!isBoundary) {
            if (px == 0) {
              isBoundary = true;
            } else if (binary[index - 1] == 0) {
              isBoundary = true;
            }
          }

          // راست
          if (!isBoundary) {
            if (px == width - 1) {
              isBoundary = true;
            } else if (binary[index + 1] == 0) {
              isBoundary = true;
            }
          }

          if (isBoundary) {
            boundary.add(Offset(px.toDouble(), py.toDouble()));
          }

          // ---------------------------------------------------
          // BFS - بالا
          // ---------------------------------------------------

          if (py > 0) {
            final next = index - width;

            if (binary[next] != 0 && visited[next] == 0) {
              visited[next] = 1;
              queue[tail++] = next;
            }
          }

          // ---------------------------------------------------
          // BFS - پایین
          // ---------------------------------------------------

          if (py < height - 1) {
            final next = index + width;

            if (binary[next] != 0 && visited[next] == 0) {
              visited[next] = 1;
              queue[tail++] = next;
            }
          }

          // ---------------------------------------------------
          // BFS - چپ
          // ---------------------------------------------------

          if (px > 0) {
            final next = index - 1;

            if (binary[next] != 0 && visited[next] == 0) {
              visited[next] = 1;
              queue[tail++] = next;
            }
          }

          // ---------------------------------------------------
          // BFS - راست
          // ---------------------------------------------------

          if (px < width - 1) {
            final next = index + 1;

            if (binary[next] != 0 && visited[next] == 0) {
              visited[next] = 1;
              queue[tail++] = next;
            }
          }
        }

        final component = _Component(
          area: area,

          minX: minX,
          maxX: maxX,

          minY: minY,
          maxY: maxY,

          topLeft: Offset(tlX.toDouble(), tlY.toDouble()),

          topRight: Offset(trX.toDouble(), trY.toDouble()),

          bottomRight: Offset(brX.toDouble(), brY.toDouble()),

          bottomLeft: Offset(blX.toDouble(), blY.toDouble()),

          boundary: boundary,
        );

        if (_isBetterComponent(component, best, width, height)) {
          best = component;
        }
      }
    }

    return best;
  }

  // ---------------------------------------------------------------------------
  // Component selection
  // ---------------------------------------------------------------------------

  static bool _isBetterComponent(
    _Component candidate,
    _Component? current,
    int width,
    int height,
  ) {
    final imageArea = width * height;

    final candidateRatio = candidate.area / imageArea;

    if (candidateRatio < 0.10) {
      return false;
    }

    if (current == null) {
      return true;
    }

    final currentRatio = current.area / imageArea;

    double candidateScore = candidateRatio * 100;

    double currentScore = currentRatio * 100;

    final candidateWidth = candidate.maxX - candidate.minX + 1;

    final candidateHeight = candidate.maxY - candidate.minY + 1;

    final currentWidth = current.maxX - current.minX + 1;

    final currentHeight = current.maxY - current.minY + 1;

    final candidateAspect = candidateWidth / candidateHeight;

    final currentAspect = currentWidth / currentHeight;

    final candidateAspectError = math.min(
      (candidateAspect - 0.707).abs(),
      (candidateAspect - 1.414).abs(),
    );

    final currentAspectError = math.min(
      (currentAspect - 0.707).abs(),
      (currentAspect - 1.414).abs(),
    );

    candidateScore -= candidateAspectError * 20;

    currentScore -= currentAspectError * 20;

    return candidateScore > currentScore;
  }

  // ---------------------------------------------------------------------------
  // Rough corners
  // ---------------------------------------------------------------------------

  static DocumentCorners? _componentToCorners(
    _Component component,
    int width,
    int height,
  ) {
    final corners = DocumentCorners(
      topLeft: component.topLeft,
      topRight: component.topRight,
      bottomRight: component.bottomRight,
      bottomLeft: component.bottomLeft,
    );

    if (!_pointsValid(corners, width, height)) {
      return null;
    }

    return corners;
  }

  // ---------------------------------------------------------------------------
  // IMPORTANT:
  // Refine corners using fitted lines
  // ---------------------------------------------------------------------------

  static DocumentCorners? _refineCorners(
    DocumentCorners rough,
    List<Offset> boundary,
    int width,
    int height,
  ) {
    if (boundary.length < 50) {
      return null;
    }

    final points = _samplePoints(boundary, 3000);

    final minDimension = math.min(width, height);

    final maxDistance = math.max(8.0, minDimension * 0.035);

    final topPoints = _pointsNearSegment(
      points,
      rough.topLeft,
      rough.topRight,
      maxDistance,
    );

    final rightPoints = _pointsNearSegment(
      points,
      rough.topRight,
      rough.bottomRight,
      maxDistance,
    );

    final bottomPoints = _pointsNearSegment(
      points,
      rough.bottomLeft,
      rough.bottomRight,
      maxDistance,
    );

    final leftPoints = _pointsNearSegment(
      points,
      rough.topLeft,
      rough.bottomLeft,
      maxDistance,
    );

    if (topPoints.length < 10 ||
        rightPoints.length < 10 ||
        bottomPoints.length < 10 ||
        leftPoints.length < 10) {
      return null;
    }

    final topLine = _fitLine(topPoints);

    final rightLine = _fitLine(rightPoints);

    final bottomLine = _fitLine(bottomPoints);

    final leftLine = _fitLine(leftPoints);

    if (topLine == null ||
        rightLine == null ||
        bottomLine == null ||
        leftLine == null) {
      return null;
    }

    final topLeft = _intersection(topLine, leftLine);

    final topRight = _intersection(topLine, rightLine);

    final bottomRight = _intersection(bottomLine, rightLine);

    final bottomLeft = _intersection(bottomLine, leftLine);

    if (topLeft == null ||
        topRight == null ||
        bottomRight == null ||
        bottomLeft == null) {
      return null;
    }

    final refined = DocumentCorners(
      topLeft: topLeft,
      topRight: topRight,
      bottomRight: bottomRight,
      bottomLeft: bottomLeft,
    );

    if (!_pointsValid(refined, width, height)) {
      return null;
    }

    // اگر گوشه جدید بیش از حد از گوشه تقریبی فاصله دارد،
    // احتمالاً Fit اشتباه انجام شده است.
    final maxCornerMovement = minDimension * 0.12;

    if ((refined.topLeft - rough.topLeft).distance > maxCornerMovement) {
      return null;
    }

    if ((refined.topRight - rough.topRight).distance > maxCornerMovement) {
      return null;
    }

    if ((refined.bottomRight - rough.bottomRight).distance >
        maxCornerMovement) {
      return null;
    }

    if ((refined.bottomLeft - rough.bottomLeft).distance > maxCornerMovement) {
      return null;
    }

    return refined;
  }

  // ---------------------------------------------------------------------------
  // Sample boundary points
  // ---------------------------------------------------------------------------

  static List<Offset> _samplePoints(List<Offset> points, int maxPoints) {
    if (points.length <= maxPoints) {
      return points;
    }

    final result = <Offset>[];

    final step = points.length / maxPoints;

    double index = 0;

    while (index < points.length) {
      result.add(points[index.floor()]);

      index += step;
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // Find points near a segment
  // ---------------------------------------------------------------------------

  static List<Offset> _pointsNearSegment(
    List<Offset> points,
    Offset a,
    Offset b,
    double maxDistance,
  ) {
    final result = <Offset>[];

    for (final point in points) {
      final distance = _pointToSegmentDistance(point, a, b);

      if (distance <= maxDistance) {
        result.add(point);
      }
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // Point -> segment distance
  // ---------------------------------------------------------------------------

  static double _pointToSegmentDistance(Offset p, Offset a, Offset b) {
    final ab = b - a;

    final lengthSquared = ab.dx * ab.dx + ab.dy * ab.dy;

    if (lengthSquared == 0) {
      return (p - a).distance;
    }

    final ap = p - a;

    double t = (ap.dx * ab.dx + ap.dy * ab.dy) / lengthSquared;

    t = t.clamp(0.0, 1.0);

    final projection = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);

    return (p - projection).distance;
  }

  // ---------------------------------------------------------------------------
  // Fit infinite line using PCA
  // ---------------------------------------------------------------------------

  static _Line? _fitLine(List<Offset> points) {
    if (points.length < 2) {
      return null;
    }

    double meanX = 0;
    double meanY = 0;

    for (final point in points) {
      meanX += point.dx;
      meanY += point.dy;
    }

    meanX /= points.length;
    meanY /= points.length;

    double xx = 0;
    double yy = 0;
    double xy = 0;

    for (final point in points) {
      final dx = point.dx - meanX;

      final dy = point.dy - meanY;

      xx += dx * dx;
      yy += dy * dy;
      xy += dx * dy;
    }

    if (xx + yy == 0) {
      return null;
    }

    // جهت اصلی خط
    final angle = 0.5 * math.atan2(2 * xy, xx - yy);

    final dx = math.cos(angle);

    final dy = math.sin(angle);

    // خط:
    // ax + by + c = 0
    final a = -dy;
    final b = dx;

    final c = -(a * meanX + b * meanY);

    return _Line(a: a, b: b, c: c);
  }

  // ---------------------------------------------------------------------------
  // Line intersection
  // ---------------------------------------------------------------------------

  static Offset? _intersection(_Line l1, _Line l2) {
    final determinant = l1.a * l2.b - l2.a * l1.b;

    if (determinant.abs() < 0.000001) {
      return null;
    }

    final x = (l1.b * l2.c - l2.b * l1.c) / determinant;

    final y = (l1.c * l2.a - l2.c * l1.a) / determinant;

    if (!x.isFinite || !y.isFinite) {
      return null;
    }

    return Offset(x, y);
  }

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------

  static bool _pointsValid(DocumentCorners c, int width, int height) {
    final points = [c.topLeft, c.topRight, c.bottomRight, c.bottomLeft];

    for (final p in points) {
      if (!p.dx.isFinite || !p.dy.isFinite) {
        return false;
      }

      // کمی اجازه می‌دهیم نقطه از تصویر بیرون برود
      if (p.dx < -width * 0.05 ||
          p.dy < -height * 0.05 ||
          p.dx > width * 1.05 ||
          p.dy > height * 1.05) {
        return false;
      }
    }

    final area = _polygonArea(points);

    if (area < width * height * 0.10) {
      return false;
    }

    final w1 = _distance(c.topLeft, c.topRight);

    final w2 = _distance(c.bottomLeft, c.bottomRight);

    final h1 = _distance(c.topLeft, c.bottomLeft);

    final h2 = _distance(c.topRight, c.bottomRight);

    if (w1 < width * 0.10 ||
        w2 < width * 0.10 ||
        h1 < height * 0.10 ||
        h2 < height * 0.10) {
      return false;
    }

    final crosses = [
      _cross(c.topLeft, c.topRight, c.bottomRight),
      _cross(c.topRight, c.bottomRight, c.bottomLeft),
      _cross(c.bottomRight, c.bottomLeft, c.topLeft),
      _cross(c.bottomLeft, c.topLeft, c.topRight),
    ];

    final positive = crosses.every((value) => value > 0);

    final negative = crosses.every((value) => value < 0);

    return positive || negative;
  }

  // ---------------------------------------------------------------------------
  // Score
  // ---------------------------------------------------------------------------

  static double _scoreCandidate(
    DocumentCorners c,
    int componentArea,
    int width,
    int height,
  ) {
    if (!_pointsValid(c, width, height)) {
      return double.negativeInfinity;
    }

    final imageArea = width * height;

    final areaRatio = c.area / imageArea;

    double score = 0;

    // مساحت
    score += areaRatio * 100;

    // ابعاد
    final width1 = _distance(c.topLeft, c.topRight);

    final width2 = _distance(c.bottomLeft, c.bottomRight);

    final height1 = _distance(c.topLeft, c.bottomLeft);

    final height2 = _distance(c.topRight, c.bottomRight);

    final avgWidth = (width1 + width2) / 2;

    final avgHeight = (height1 + height2) / 2;

    if (avgHeight <= 0) {
      return double.negativeInfinity;
    }

    final aspect = avgWidth / avgHeight;

    final portraitError = (aspect - 0.707).abs();

    final landscapeError = (aspect - 1.414).abs();

    final aspectError = math.min(portraitError, landscapeError);

    score -= aspectError * 35;

    // زاویه‌ها
    final angles = [
      _angle(c.topLeft, c.topRight, c.bottomRight),
      _angle(c.topRight, c.bottomRight, c.bottomLeft),
      _angle(c.bottomRight, c.bottomLeft, c.topLeft),
      _angle(c.bottomLeft, c.topLeft, c.topRight),
    ];

    double angleError = 0;

    for (final angle in angles) {
      angleError += (angle - math.pi / 2).abs();
    }

    score -= angleError * 20;

    // موازی بودن اضلاع
    final widthError = (width1 - width2).abs() / math.max(width1, width2);

    final heightError = (height1 - height2).abs() / math.max(height1, height2);

    score -= widthError * 20;

    score -= heightError * 20;

    return score;
  }

  // ---------------------------------------------------------------------------
  // Geometry
  // ---------------------------------------------------------------------------

  static double _distance(Offset a, Offset b) {
    return (a - b).distance;
  }

  static double _angle(Offset a, Offset b, Offset c) {
    final ab = a - b;
    final cb = c - b;

    final denominator = ab.distance * cb.distance;

    if (denominator == 0) {
      return 0;
    }

    final dot = ab.dx * cb.dx + ab.dy * cb.dy;

    final value = (dot / denominator).clamp(-1.0, 1.0);

    return math.acos(value);
  }

  static double _cross(Offset a, Offset b, Offset c) {
    return (b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx);
  }

  static double _polygonArea(List<Offset> points) {
    double area = 0;

    for (int i = 0; i < points.length; i++) {
      final a = points[i];

      final b = points[(i + 1) % points.length];

      area += a.dx * b.dy - b.dx * a.dy;
    }

    return area.abs() / 2;
  }
}

// =============================================================================
// Models
// =============================================================================

class _Component {
  final int area;

  final int minX;
  final int maxX;

  final int minY;
  final int maxY;

  final Offset topLeft;
  final Offset topRight;

  final Offset bottomRight;
  final Offset bottomLeft;

  final List<Offset> boundary;

  _Component({
    required this.area,
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
    required this.boundary,
  });
}

class _Line {
  final double a;
  final double b;
  final double c;

  _Line({required this.a, required this.b, required this.c});
}
