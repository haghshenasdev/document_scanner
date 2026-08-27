import 'dart:math' as math;
import 'dart:ui';

double distance(Offset a, Offset b) {
  return (a - b).distance;
}

Offset midpoint(Offset a, Offset b) {
  return Offset(
    (a.dx + b.dx) / 2,
    (a.dy + b.dy) / 2,
  );
}

double cross(
  Offset a,
  Offset b,
  Offset c,
) {
  return
      (b.dx - a.dx) * (c.dy - a.dy) -
      (b.dy - a.dy) * (c.dx - a.dx);
}

double dot(
  Offset a,
  Offset b,
) {
  return a.dx * b.dx + a.dy * b.dy;
}

double angleBetween(
  Offset a,
  Offset b,
) {
  final denominator =
      a.distance * b.distance;

  if (denominator == 0) {
    return 0;
  }

  final value =
      (dot(a, b) / denominator)
          .clamp(-1.0, 1.0);

  return math.acos(value);
}

List<Offset> sortCorners(
  List<Offset> points,
) {
  if (points.length != 4) {
    return points;
  }

  final center = Offset(
    points.map((p) => p.dx).reduce((a, b) => a + b) / 4,
    points.map((p) => p.dy).reduce((a, b) => a + b) / 4,
  );

  final sorted = List<Offset>.from(points);

  sorted.sort((a, b) {
    final angleA =
        math.atan2(
      a.dy - center.dy,
      a.dx - center.dx,
    );

    final angleB =
        math.atan2(
      b.dy - center.dy,
      b.dx - center.dx,
    );

    return angleA.compareTo(angleB);
  });

  Offset topLeft = sorted.reduce(
    (a, b) {
      final sa = a.dx + a.dy;
      final sb = b.dx + b.dy;

      return sa < sb ? a : b;
    },
  );

  Offset bottomRight = sorted.reduce(
    (a, b) {
      final sa = a.dx + a.dy;
      final sb = b.dx + b.dy;

      return sa > sb ? a : b;
    },
  );

  Offset topRight = sorted.reduce(
    (a, b) {
      final sa = a.dy - a.dx;
      final sb = b.dy - b.dx;

      return sa < sb ? a : b;
    },
  );

  Offset bottomLeft = sorted.reduce(
    (a, b) {
      final sa = a.dy - a.dx;
      final sb = b.dy - b.dx;

      return sa > sb ? a : b;
    },
  );

  return [
    topLeft,
    topRight,
    bottomRight,
    bottomLeft,
  ];
}