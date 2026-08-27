import 'dart:math' as math;
import 'dart:ui';

class DocumentCorners {
  Offset topLeft;
  Offset topRight;
  Offset bottomRight;
  Offset bottomLeft;

  DocumentCorners({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  List<Offset> get points => [
        topLeft,
        topRight,
        bottomRight,
        bottomLeft,
      ];

  DocumentCorners copy() {
    return DocumentCorners(
      topLeft: topLeft,
      topRight: topRight,
      bottomRight: bottomRight,
      bottomLeft: bottomLeft,
    );
  }

  Rect get boundingBox {
    final xs = points.map((e) => e.dx).toList();
    final ys = points.map((e) => e.dy).toList();

    return Rect.fromLTRB(
      xs.reduce(math.min),
      ys.reduce(math.min),
      xs.reduce(math.max),
      ys.reduce(math.max),
    );
  }

  double get area {
    double result = 0;

    for (int i = 0; i < points.length; i++) {
      final current = points[i];
      final next = points[(i + 1) % points.length];

      result +=
          current.dx * next.dy -
          next.dx * current.dy;
    }

    return result.abs() / 2;
  }

  bool get isValid {
    if (points.length != 4) {
      return false;
    }

    if (area <= 10) {
      return false;
    }

    return true;
  }
}