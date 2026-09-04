import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;

import '../models/document_corners.dart';

class DocumentDetector {
  // ---------------------------------------------------------------------------
  // تنظیمات Performance
  // ---------------------------------------------------------------------------

  /// اندازه تصویر مورد استفاده برای تشخیص.
  ///
  /// 800 برای موبایل سرعت خوبی می‌دهد.
  /// اگر دقت در گوشی‌های ضعیف مشکل داشت، آن را به 900 یا 1000 افزایش بده.
  static const int maxDetectionSize = 800;

  /// حداکثر تعداد نقاط مرزی که برای Line Fitting استفاده می‌شود.
  static const int maxRefinePoints = 1600;

  /// حداقل نسبت مساحت Component نسبت به کل تصویر.
  static const double minComponentRatio = 0.10;

  /// حداکثر تعداد تلاش در حالت عادی.
  static const int fastThresholdCount = 3;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  static DocumentCorners? detect(img.Image original) {
    if (original.width < 100 || original.height < 100) {
      return null;
    }

    // -------------------------------------------------------
    // Resize
    // -------------------------------------------------------

    final working = _resizeForDetection(original);

    final width = working.width;
    final height = working.height;

    // -------------------------------------------------------
    // Grayscale
    // -------------------------------------------------------

    final gray = _grayscale(working);

    // -------------------------------------------------------
    // Otsu
    // -------------------------------------------------------

    final otsu = _otsuThreshold(gray);

    // -------------------------------------------------------
    // ابتدا فقط 3 threshold نزدیک Otsu
    //
    // در اکثر تصاویر یکی از این‌ها جواب می‌دهد.
    // اگر جواب نگرفت، مرحله دوم فعال می‌شود.
    // -------------------------------------------------------

    final fastThresholds = <int>{
      (otsu - 15).clamp(40, 230),
      otsu.clamp(40, 230),
      (otsu + 15).clamp(40, 230),
    }.toList();

    DocumentCorners? best;
    double bestScore = double.negativeInfinity;

    // -------------------------------------------------------
    // مرحله اول - سریع
    // -------------------------------------------------------

    for (final threshold in fastThresholds) {
      final candidate = _detectWithThreshold(gray, width, height, threshold);

      if (candidate == null) {
        continue;
      }

      final score = _scoreCandidate(
        candidate.corners,
        candidate.component.area,
        width,
        height,
      );

      if (score > bestScore) {
        bestScore = score;
        best = candidate.corners;
      }

      // اگر نتیجه خیلی خوب است دیگر Thresholdهای دیگر لازم نیستند.
      if (score >= 72) {
        break;
      }
    }

    // -------------------------------------------------------
    // مرحله دوم - فقط در صورت شکست
    //
    // این قسمت باعث می‌شود تصاویر معمولی سریع باشند ولی
    // تصاویر سخت همچنان شانس تشخیص داشته باشند.
    // -------------------------------------------------------

    if (best == null) {
      final fallbackThresholds = <int>{
        (otsu - 30).clamp(40, 230),
        (otsu - 20).clamp(40, 230),
        (otsu - 10).clamp(40, 230),
        (otsu + 10).clamp(40, 230),
        (otsu + 20).clamp(40, 230),
        (otsu + 30).clamp(40, 230),
      }.toList();

      for (final threshold in fallbackThresholds) {
        final candidate = _detectWithThreshold(gray, width, height, threshold);

        if (candidate == null) {
          continue;
        }

        final score = _scoreCandidate(
          candidate.corners,
          candidate.component.area,
          width,
          height,
        );

        if (score > bestScore) {
          bestScore = score;
          best = candidate.corners;
        }

        if (score >= 72) {
          break;
        }
      }
    }

    if (best == null) {
      return null;
    }

    // -------------------------------------------------------
    // Scale corners back to original image
    // -------------------------------------------------------

    final scaleX = original.width / width;
    final scaleY = original.height / height;

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
  // Detect using one threshold
  // ---------------------------------------------------------------------------

  static _DetectionResult? _detectWithThreshold(
    Uint8List gray,
    int width,
    int height,
    int threshold,
  ) {
    final binary = _threshold(gray, threshold);

    final component = _largestComponent(binary, width, height);

    if (component == null) {
      return null;
    }

    final rough = _componentToCorners(component, width, height);

    if (rough == null) {
      return null;
    }

    // -------------------------------------------------------
    // Refine
    // -------------------------------------------------------

    final refined = _refineCorners(rough, component.boundary, width, height);

    return _DetectionResult(corners: refined ?? rough, component: component);
  }

  // ---------------------------------------------------------------------------
  // Resize
  // ---------------------------------------------------------------------------

  static img.Image _resizeForDetection(img.Image image) {
    final largest = math.max(image.width, image.height);

    if (largest <= maxDetectionSize) {
      return image;
    }

    final ratio = maxDetectionSize / largest;

    final newWidth = math.max(1, (image.width * ratio).round());

    final newHeight = math.max(1, (image.height * ratio).round());

    return img.copyResize(
      image,
      width: newWidth,
      height: newHeight,
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

        // به جای toDouble و clamp غیرضروری،
        // مستقیماً مقدار را محاسبه می‌کنیم.
        final value = (0.299 * pixel.r) + (0.587 * pixel.g) + (0.114 * pixel.b);

        result[index++] = value.round();
      }
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // Otsu Threshold
  // ---------------------------------------------------------------------------

  static int _otsuThreshold(Uint8List gray) {
    final histogram = Int32List(256);

    for (int i = 0; i < gray.length; i++) {
      histogram[gray[i]]++;
    }

    final total = gray.length;

    int sum = 0;

    for (int i = 0; i < 256; i++) {
      sum += i * histogram[i];
    }

    int sumBackground = 0;
    int weightBackground = 0;

    int bestThreshold = 128;

    // به جای double variance،
    // از double فقط در محاسبه نهایی استفاده می‌کنیم.
    double maxVariance = -1;

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
    final length = binary.length;

    final visited = Uint8List(length);

    final queue = Int32List(length);

    _Component? best;

    final imageArea = width * height;

    // برای جلوگیری از بررسی Componentهای بسیار کوچک
    // حداقل مساحت لازم را از قبل حساب می‌کنیم.
    final minArea = (imageArea * minComponentRatio).round();

    for (int y = 0; y < height; y++) {
      int index = y * width;

      for (int x = 0; x < width; x++, index++) {
        if (binary[index] == 0 || visited[index] != 0) {
          continue;
        }

        // ---------------------------------------------------
        // BFS
        // ---------------------------------------------------

        int head = 0;
        int tail = 0;

        queue[tail++] = index;
        visited[index] = 1;

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

        // ---------------------------------------------------
        // Boundary
        //
        // معمولاً تعداد نقاط مرزی زیاد است.
        // سقف می‌گذاریم تا حافظه و Fit سریع‌تر شود.
        // ---------------------------------------------------

        final boundary = <Offset>[];

        while (head < tail) {
          final current = queue[head++];

          // به جای % و ~/ در هر پیکسل،
          // از تقسیم فقط یک بار استفاده می‌کنیم.
          final py = current ~/ width;
          final px = current - py * width;

          area++;

          if (px < minX) minX = px;
          if (px > maxX) maxX = px;
          if (py < minY) minY = py;
          if (py > maxY) maxY = py;

          // -------------------------------------------------
          // Rough corners
          // -------------------------------------------------

          final sum = px + py;

          if (sum < tlX + tlY) {
            tlX = px;
            tlY = py;
          }

          final diff = px - py;

          if (diff > trX - trY) {
            trX = px;
            trY = py;
          }

          if (sum > brX + brY) {
            brX = px;
            brY = py;
          }

          if (diff < blX - blY) {
            blX = px;
            blY = py;
          }

          // -------------------------------------------------
          // Boundary
          // -------------------------------------------------

          bool isBoundary = false;

          if (py == 0 || binary[current - width] == 0) {
            isBoundary = true;
          } else if (py == height - 1 || binary[current + width] == 0) {
            isBoundary = true;
          } else if (px == 0 || binary[current - 1] == 0) {
            isBoundary = true;
          } else if (px == width - 1 || binary[current + 1] == 0) {
            isBoundary = true;
          }

          if (isBoundary) {
            // اگر تعداد خیلی زیاد شد، همه را نگه نمی‌داریم.
            //
            // اینجا با sampling ساده بخشی از نقاط حفظ می‌شوند.
            if (boundary.length < 5000) {
              boundary.add(Offset(px.toDouble(), py.toDouble()));
            } else if ((area & 3) == 0) {
              // حدوداً هر 4 نقطه یکی
              boundary.add(Offset(px.toDouble(), py.toDouble()));
            }
          }

          // -------------------------------------------------
          // Neighbor - Up
          // -------------------------------------------------

          if (py > 0) {
            final next = current - width;

            if (binary[next] != 0 && visited[next] == 0) {
              visited[next] = 1;
              queue[tail++] = next;
            }
          }

          // -------------------------------------------------
          // Neighbor - Down
          // -------------------------------------------------

          if (py < height - 1) {
            final next = current + width;

            if (binary[next] != 0 && visited[next] == 0) {
              visited[next] = 1;
              queue[tail++] = next;
            }
          }

          // -------------------------------------------------
          // Neighbor - Left
          // -------------------------------------------------

          if (px > 0) {
            final next = current - 1;

            if (binary[next] != 0 && visited[next] == 0) {
              visited[next] = 1;
              queue[tail++] = next;
            }
          }

          // -------------------------------------------------
          // Neighbor - Right
          // -------------------------------------------------

          if (px < width - 1) {
            final next = current + 1;

            if (binary[next] != 0 && visited[next] == 0) {
              visited[next] = 1;
              queue[tail++] = next;
            }
          }
        }

        // ---------------------------------------------------
        // Component خیلی کوچک است
        // ---------------------------------------------------

        if (area < minArea) {
          continue;
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

    if (candidateRatio < minComponentRatio) {
      return false;
    }

    if (current == null) {
      return true;
    }

    final currentRatio = current.area / imageArea;

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

    final candidateScore = candidateRatio * 100 - candidateAspectError * 20;

    final currentScore = currentRatio * 100 - currentAspectError * 20;

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
  // Refine corners
  // ---------------------------------------------------------------------------

  static DocumentCorners? _refineCorners(
    DocumentCorners rough,
    List<Offset> boundary,
    int width,
    int height,
  ) {
    if (boundary.length < 40) {
      return null;
    }

    final points = _samplePoints(boundary, maxRefinePoints);

    final minDimension = math.min(width, height);

    final maxDistance = math.max(7.0, minDimension * 0.032);

    // -------------------------------------------------------
    // پیدا کردن نقاط نزدیک هر ضلع
    // -------------------------------------------------------

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

    if (topPoints.length < 8 ||
        rightPoints.length < 8 ||
        bottomPoints.length < 8 ||
        leftPoints.length < 8) {
      return null;
    }

    // -------------------------------------------------------
    // Fit
    // -------------------------------------------------------

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

    // -------------------------------------------------------
    // Intersection
    // -------------------------------------------------------

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

    // -------------------------------------------------------
    // جلوگیری از حرکت غیرمنطقی گوشه‌ها
    // -------------------------------------------------------

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

    final result = <Offset>[
      // نقطه‌ها را به صورت تقریبی یکنواخت برمی‌داریم.
    ];

    final step = points.length / maxPoints;

    double index = 0;

    while (index < points.length && result.length < maxPoints) {
      result.add(points[index.floor()]);

      index += step;
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // Find points near segment
  // ---------------------------------------------------------------------------

  static List<Offset> _pointsNearSegment(
    List<Offset> points,
    Offset a,
    Offset b,
    double maxDistance,
  ) {
    final result = <Offset>[];

    final abx = b.dx - a.dx;
    final aby = b.dy - a.dy;

    final lengthSquared = abx * abx + aby * aby;

    if (lengthSquared <= 0.000001) {
      return result;
    }

    final maxDistanceSquared = maxDistance * maxDistance;

    for (final point in points) {
      final apx = point.dx - a.dx;
      final apy = point.dy - a.dy;

      var t = (apx * abx + apy * aby) / lengthSquared;

      if (t < 0) {
        t = 0;
      } else if (t > 1) {
        t = 1;
      }

      final projectionX = a.dx + abx * t;

      final projectionY = a.dy + aby * t;

      final dx = point.dx - projectionX;

      final dy = point.dy - projectionY;

      final distanceSquared = dx * dx + dy * dy;

      if (distanceSquared <= maxDistanceSquared) {
        result.add(point);
      }
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // Fit line using PCA
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

    final inverseCount = 1.0 / points.length;

    meanX *= inverseCount;
    meanY *= inverseCount;

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

    if (xx + yy <= 0.000001) {
      return null;
    }

    final angle = 0.5 * math.atan2(2 * xy, xx - yy);

    final dx = math.cos(angle);

    final dy = math.sin(angle);

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
    final points = <Offset>[c.topLeft, c.topRight, c.bottomRight, c.bottomLeft];

    final maxX = width * 1.05;

    final maxY = height * 1.05;

    final minX = -width * 0.05;

    final minY = -height * 0.05;

    for (final p in points) {
      if (!p.dx.isFinite || !p.dy.isFinite) {
        return false;
      }

      if (p.dx < minX || p.dy < minY || p.dx > maxX || p.dy > maxY) {
        return false;
      }
    }

    // -------------------------------------------------------
    // Area
    // -------------------------------------------------------

    final area = _polygonArea(points);

    if (area < width * height * 0.10) {
      return false;
    }

    // -------------------------------------------------------
    // Edge lengths
    // -------------------------------------------------------

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

    // -------------------------------------------------------
    // Convexity
    // -------------------------------------------------------

    final cross1 = _cross(c.topLeft, c.topRight, c.bottomRight);

    final cross2 = _cross(c.topRight, c.bottomRight, c.bottomLeft);

    final cross3 = _cross(c.bottomRight, c.bottomLeft, c.topLeft);

    final cross4 = _cross(c.bottomLeft, c.topLeft, c.topRight);

    final allPositive = cross1 > 0 && cross2 > 0 && cross3 > 0 && cross4 > 0;

    final allNegative = cross1 < 0 && cross2 < 0 && cross3 < 0 && cross4 < 0;

    return allPositive || allNegative;
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

    double score = areaRatio * 100;

    // -------------------------------------------------------
    // Width / Height
    // -------------------------------------------------------

    final width1 = _distance(c.topLeft, c.topRight);

    final width2 = _distance(c.bottomLeft, c.bottomRight);

    final height1 = _distance(c.topLeft, c.bottomLeft);

    final height2 = _distance(c.topRight, c.bottomRight);

    final avgWidth = (width1 + width2) * 0.5;

    final avgHeight = (height1 + height2) * 0.5;

    if (avgHeight <= 0) {
      return double.negativeInfinity;
    }

    final aspect = avgWidth / avgHeight;

    final portraitError = (aspect - 0.707).abs();

    final landscapeError = (aspect - 1.414).abs();

    final aspectError = math.min(portraitError, landscapeError);

    score -= aspectError * 35;

    // -------------------------------------------------------
    // Parallel edges
    // -------------------------------------------------------

    final maxWidth = math.max(width1, width2);

    final maxHeight = math.max(height1, height2);

    if (maxWidth > 0) {
      score -= ((width1 - width2).abs() / maxWidth) * 20;
    }

    if (maxHeight > 0) {
      score -= ((height1 - height2).abs() / maxHeight) * 20;
    }

    // -------------------------------------------------------
    // زاویه‌ها
    //
    // فقط زمانی محاسبه می‌کنیم که score هنوز منطقی است.
    // -------------------------------------------------------

    if (score > 20) {
      final angle1 = _angle(c.topLeft, c.topRight, c.bottomRight);

      final angle2 = _angle(c.topRight, c.bottomRight, c.bottomLeft);

      final angle3 = _angle(c.bottomRight, c.bottomLeft, c.topLeft);

      final angle4 = _angle(c.bottomLeft, c.topLeft, c.topRight);

      final target = math.pi / 2;

      final angleError =
          (angle1 - target).abs() +
          (angle2 - target).abs() +
          (angle3 - target).abs() +
          (angle4 - target).abs();

      score -= angleError * 20;
    }

    return score;
  }

  // ---------------------------------------------------------------------------
  // Distance
  // ---------------------------------------------------------------------------

  static double _distance(Offset a, Offset b) {
    final dx = a.dx - b.dx;

    final dy = a.dy - b.dy;

    return math.sqrt(dx * dx + dy * dy);
  }

  // ---------------------------------------------------------------------------
  // Angle
  // ---------------------------------------------------------------------------

  static double _angle(Offset a, Offset b, Offset c) {
    final abx = a.dx - b.dx;

    final aby = a.dy - b.dy;

    final cbx = c.dx - b.dx;

    final cby = c.dy - b.dy;

    final abLength = math.sqrt(abx * abx + aby * aby);

    final cbLength = math.sqrt(cbx * cbx + cby * cby);

    final denominator = abLength * cbLength;

    if (denominator <= 0) {
      return 0;
    }

    final dot = abx * cbx + aby * cby;

    final value = (dot / denominator).clamp(-1.0, 1.0);

    return math.acos(value);
  }

  // ---------------------------------------------------------------------------
  // Cross
  // ---------------------------------------------------------------------------

  static double _cross(Offset a, Offset b, Offset c) {
    return (b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx);
  }

  // ---------------------------------------------------------------------------
  // Polygon Area
  // ---------------------------------------------------------------------------

  static double _polygonArea(List<Offset> points) {
    double area = 0;

    for (int i = 0; i < points.length; i++) {
      final a = points[i];

      final b = points[(i + 1) % points.length];

      area += a.dx * b.dy - b.dx * a.dy;
    }

    return area.abs() * 0.5;
  }
}

// =============================================================================
// Detection Result
// =============================================================================

class _DetectionResult {
  final DocumentCorners corners;
  final _Component component;

  const _DetectionResult({required this.corners, required this.component});
}

// =============================================================================
// Component
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

  const _Component({
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

// =============================================================================
// Line
// =============================================================================

class _Line {
  final double a;
  final double b;
  final double c;

  const _Line({required this.a, required this.b, required this.c});
}
