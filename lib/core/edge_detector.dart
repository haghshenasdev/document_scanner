import 'dart:math' as math;

import 'package:image/image.dart' as img;

class EdgeDetector {
  /// تبدیل تصویر به grayscale
  static List<List<double>> grayscale(
    img.Image image,
  ) {
    final width = image.width;
    final height = image.height;

    final result = List.generate(
      height,
      (_) => List<double>.filled(
        width,
        0,
      ),
    );

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = image.getPixel(x, y);

        final r = pixel.r.toDouble();
        final g = pixel.g.toDouble();
        final b = pixel.b.toDouble();

        result[y][x] =
            0.299 * r +
            0.587 * g +
            0.114 * b;
      }
    }

    return result;
  }

  /// Sobel Edge Detection
  static List<List<double>> sobel(
    List<List<double>> gray,
  ) {
    final height = gray.length;
    final width = gray[0].length;

    final result = List.generate(
      height,
      (_) => List<double>.filled(
        width,
        0,
      ),
    );

    const gx = [
      [-1.0, 0.0, 1.0],
      [-2.0, 0.0, 2.0],
      [-1.0, 0.0, 1.0],
    ];

    const gy = [
      [-1.0, -2.0, -1.0],
      [0.0, 0.0, 0.0],
      [1.0, 2.0, 1.0],
    ];

    double maxValue = 0;

    for (int y = 1; y < height - 1; y++) {
      for (int x = 1; x < width - 1; x++) {
        double sumX = 0;
        double sumY = 0;

        for (int ky = -1; ky <= 1; ky++) {
          for (int kx = -1; kx <= 1; kx++) {
            final value =
                gray[y + ky][x + kx];

            sumX +=
                value *
                gx[ky + 1][kx + 1];

            sumY +=
                value *
                gy[ky + 1][kx + 1];
          }
        }

        final magnitude =
            math.sqrt(
          sumX * sumX +
              sumY * sumY,
        );

        result[y][x] = magnitude;

        if (magnitude > maxValue) {
          maxValue = magnitude;
        }
      }
    }

    if (maxValue == 0) {
      return result;
    }

    /*
     * Normalize 0..255
     */
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        result[y][x] =
            result[y][x] /
                maxValue *
                255;
      }
    }

    return result;
  }

  /// تبدیل Edge به Binary
  static List<List<bool>> threshold(
    List<List<double>> edges, {
    double threshold = 70,
  }) {
    final height = edges.length;
    final width = edges[0].length;

    return List.generate(
      height,
      (y) => List.generate(
        width,
        (x) => edges[y][x] >= threshold,
      ),
    );
  }

  /// پیدا کردن نقاط Edge
  static List<PixelPoint> edgePoints(
    List<List<bool>> edges,
  ) {
    final result = <PixelPoint>[];

    final height = edges.length;
    final width = edges[0].length;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        if (edges[y][x]) {
          result.add(
            PixelPoint(x, y),
          );
        }
      }
    }

    return result;
  }
}

class PixelPoint {
  final int x;
  final int y;

  PixelPoint(
    this.x,
    this.y,
  );
}