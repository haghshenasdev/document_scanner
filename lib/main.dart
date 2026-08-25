import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:opencv_dart/opencv.dart' as cv;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    const MaterialApp(debugShowCheckedModeBanner: false, home: ScannerPage()),
  );
}

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  Uint8List? imageBytes;

  Size? originalImageSize;

  List<Offset> points = [];

  bool loading = false;

  String message = 'یک تصویر انتخاب کنید';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('اسکنر سند'), centerTitle: true),
      body: Column(
        children: [
          Expanded(child: imageBytes == null ? _emptyView() : _imageEditor()),

          _bottomPanel(),
        ],
      ),
    );
  }

  Widget _emptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.document_scanner_outlined,
            size: 100,
            color: Theme.of(context).colorScheme.primary,
          ),

          const SizedBox(height: 20),

          const Text(
            'تصویر برگه را انتخاب کنید',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 10),

          Text(message),

          const SizedBox(height: 30),

          FilledButton.icon(
            onPressed: loading ? null : selectImage,
            icon: const Icon(Icons.folder_open),
            label: const Text('انتخاب تصویر'),
          ),
        ],
      ),
    );
  }

  Widget _bottomPanel() {
    if (imageBytes == null) {
      return const SizedBox.shrink();
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(message, textAlign: TextAlign.center),

            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: loading ? null : selectImage,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('تصویر جدید'),
                  ),
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: FilledButton.icon(
                    onPressed: loading || points.length != 4
                        ? null
                        : rectifyAndSave,
                    icon: loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.crop),
                    label: Text(loading ? 'در حال پردازش...' : 'برش و ذخیره'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> selectImage() async {
    try {
      setState(() {
        loading = true;
        message = 'در حال خواندن تصویر...';
      });

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'bmp'],
        withData: true,
      );

      if (result == null) {
        setState(() {
          loading = false;
          message = 'فایلی انتخاب نشد';
        });

        return;
      }

      final file = result.files.single;

      Uint8List? bytes = file.bytes;

      if (bytes == null && file.path != null) {
        bytes = await File(file.path!).readAsBytes();
      }

      if (bytes == null) {
        throw Exception('خواندن فایل امکان‌پذیر نیست');
      }

      final mat = cv.imdecode(bytes, cv.IMREAD_COLOR);

      // if (mat.empty) {
      //   throw Exception('OpenCV نتوانست تصویر را Decode کند');
      // }

      originalImageSize = Size(mat.cols.toDouble(), mat.rows.toDouble());

      setState(() {
        imageBytes = bytes;
        points = [];
        loading = false;
        message = 'در حال تشخیص لبه‌های برگه...';
      });

      await Future.delayed(const Duration(milliseconds: 50));

      await detectDocument(bytes);
    } catch (e) {
      setState(() {
        loading = false;
        message = 'خطا: $e';
      });
    }
  }

  Future<void> detectDocument(Uint8List bytes) async {
    try {
      final mat = cv.imdecode(bytes, cv.IMREAD_COLOR);

      // if (mat.empty) {
      //   throw Exception('تصویر نامعتبر است');
      // }

      /*
       * برای تشخیص، تصویر را کوچک می‌کنیم.
       * این کار سرعت را خیلی بیشتر می‌کند.
       */
      cv.Mat working = mat;

      const maxWidth = 1400;

      if (mat.cols > maxWidth) {
        final ratio = maxWidth / mat.cols;

        final newHeight = (mat.rows * ratio).round();

        working = cv.resize(mat, (maxWidth, newHeight));
      }

      /*
       * BGR -> Gray
       */
      final gray = cv.cvtColor(working, cv.COLOR_BGR2GRAY);

      /*
       * کاهش نویز
       */
      final blurred = cv.gaussianBlur(gray, (5, 5), 0);

      /*
       * Edge Detection
       */
      final edges = cv.canny(blurred, 75, 200);

      /*
       * طبق همان روشی که در مثال خودت استفاده کردی،
       * نقاط غیر صفر Canny را می‌گیریم.
       */
      final nonZeroMat = cv.findNonZero(edges);

      if (nonZeroMat.isEmpty) {
        setState(() {
          message = 'لبه‌ای پیدا نشد';
        });

        return;
      }

      final edgePoints = <Offset>[];

      for (int i = 0; i < nonZeroMat.rows; i++) {
        final row = nonZeroMat.row(i);

        final x = row.at<int>(0, 0);
        final y = row.at<int>(0, 1);

        edgePoints.add(Offset(x.toDouble(), y.toDouble()));
      }

      /*
       * چهار گوشه را پیدا می‌کنیم.
       */
      final detected = getDocumentCorners(edgePoints);

      if (detected.length != 4) {
        setState(() {
          message = 'چهار گوشه برگه پیدا نشد';
        });

        return;
      }

      /*
       * چون برای تشخیص تصویر را کوچک کرده‌ایم،
       * مختصات را به اندازه تصویر اصلی برمی‌گردانیم.
       */
      final scaleX = originalImageSize!.width / working.cols;

      final scaleY = originalImageSize!.height / working.rows;

      final originalPoints = detected.map((point) {
        return Offset(point.dx * scaleX, point.dy * scaleY);
      }).toList();

      setState(() {
        points = originalPoints;
        message = 'برگه پیدا شد؛ می‌توانید گوشه‌ها را تنظیم کنید';
      });
    } catch (e) {
      setState(() {
        message = 'خطا در تشخیص: $e';
      });
    }
  }

  /*
   * پیدا کردن چهار گوشه از نقاط Canny
   *
   * ترتیب:
   * 0 = Top Left
   * 1 = Top Right
   * 2 = Bottom Right
   * 3 = Bottom Left
   */
  List<Offset> getDocumentCorners(List<Offset> edgePoints) {
    if (edgePoints.isEmpty) {
      return [];
    }

    double minX = double.infinity;
    double maxX = double.negativeInfinity;
    double minY = double.infinity;
    double maxY = double.negativeInfinity;

    for (final p in edgePoints) {
      minX = min(minX, p.dx);
      maxX = max(maxX, p.dx);
      minY = min(minY, p.dy);
      maxY = max(maxY, p.dy);
    }

    final topLeftTarget = Offset(minX, minY);

    final topRightTarget = Offset(maxX, minY);

    final bottomRightTarget = Offset(maxX, maxY);

    final bottomLeftTarget = Offset(minX, maxY);

    /*
     * به جای اینکه فقط نزدیک‌ترین نقطه به
     * bounding box را انتخاب کنیم، تصویر را
     * به چهار ناحیه تقسیم می‌کنیم.
     */
    Offset findCorner(Offset target, bool left, bool top) {
      final candidates = edgePoints.where((p) {
        final horizontal = left
            ? p.dx <= (minX + maxX) / 2
            : p.dx >= (minX + maxX) / 2;

        final vertical = top
            ? p.dy <= (minY + maxY) / 2
            : p.dy >= (minY + maxY) / 2;

        return horizontal && vertical;
      }).toList();

      final list = candidates.isNotEmpty ? candidates : edgePoints;

      return list.reduce((a, b) {
        final da = pow(a.dx - target.dx, 2) + pow(a.dy - target.dy, 2);

        final db = pow(b.dx - target.dx, 2) + pow(b.dy - target.dy, 2);

        return da < db ? a : b;
      });
    }

    return [
      findCorner(topLeftTarget, true, true),
      findCorner(topRightTarget, false, true),
      findCorner(bottomRightTarget, false, false),
      findCorner(bottomLeftTarget, true, false),
    ];
  }

  Widget _imageEditor() {
    if (imageBytes == null || originalImageSize == null) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final imageWidth = originalImageSize!.width;

        final imageHeight = originalImageSize!.height;

        double displayWidth = constraints.maxWidth;

        double displayHeight = displayWidth * imageHeight / imageWidth;

        if (displayHeight > constraints.maxHeight) {
          displayHeight = constraints.maxHeight;

          displayWidth = displayHeight * imageWidth / imageHeight;
        }

        final scaleX = displayWidth / imageWidth;

        final scaleY = displayHeight / imageHeight;

        final displayPoints = points.map((point) {
          return Offset(point.dx * scaleX, point.dy * scaleY);
        }).toList();

        return Center(
          child: SizedBox(
            width: displayWidth,
            height: displayHeight,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.memory(imageBytes!, fit: BoxFit.fill),
                ),

                Positioned.fill(
                  child: CustomPaint(painter: DocumentPainter(displayPoints)),
                ),

                ...List.generate(points.length, (index) {
                  final point = displayPoints[index];

                  return Positioned(
                    left: point.dx - 22,
                    top: point.dy - 22,
                    child: GestureDetector(
                      onPanUpdate: (details) {
                        final dx = details.delta.dx / scaleX;

                        final dy = details.delta.dy / scaleY;

                        movePoint(index, Offset(dx, dy));
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.cyan,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: const [
                            BoxShadow(blurRadius: 5, color: Colors.black45),
                          ],
                        ),
                        child: const Icon(
                          Icons.open_with,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  void movePoint(int index, Offset delta) {
    if (index >= points.length) {
      return;
    }

    final updated = List<Offset>.from(points);

    updated[index] = updated[index] + delta;

    /*
     * اجازه نمی‌دهیم نقطه از تصویر بیرون برود.
     */
    final width = originalImageSize!.width;

    final height = originalImageSize!.height;

    updated[index] = Offset(
      updated[index].dx.clamp(0, width),
      updated[index].dy.clamp(0, height),
    );

    setState(() {
      points = updated;
      message = 'گوشه‌ها را تنظیم کنید';
    });
  }

  Future<void> rectifyAndSave() async {
    if (imageBytes == null || points.length != 4) {
      return;
    }

    try {
      setState(() {
        loading = true;
        message = 'در حال اصلاح پرسپکتیو...';
      });

      final source = cv.imdecode(imageBytes!, cv.IMREAD_COLOR);

      // if (source.empty) {
      //   throw Exception('خطا در Decode تصویر');
      // }

      final p = points;

      /*
       * محاسبه عرض و ارتفاع واقعی سند
       */
      final topWidth = distance(p[0], p[1]);

      final bottomWidth = distance(p[3], p[2]);

      final leftHeight = distance(p[0], p[3]);

      final rightHeight = distance(p[1], p[2]);

      int width = max(topWidth, bottomWidth).round();

      int height = max(leftHeight, rightHeight).round();

      /*
       * برای جلوگیری از خروجی خیلی بزرگ
       */
      const maxOutput = 2500;

      if (width > maxOutput || height > maxOutput) {
        final scale = maxOutput / max(width, height);

        width = (width * scale).round();

        height = (height * scale).round();
      }

      /*
       * نقاط منبع
       */
      final srcPoints = cv.VecPoint.fromList([
        cv.Point(p[0].dx.round(), p[0].dy.round()),
        cv.Point(p[1].dx.round(), p[1].dy.round()),
        cv.Point(p[2].dx.round(), p[2].dy.round()),
        cv.Point(p[3].dx.round(), p[3].dy.round()),
      ]);

      /*
       * نقاط مقصد
       */
      final dstPoints = cv.VecPoint.fromList([
        cv.Point(0, 0),
        cv.Point(width - 1, 0),
        cv.Point(width - 1, height - 1),
        cv.Point(0, height - 1),
      ]);

      /*
       * Homography / Perspective Matrix
       */
      final matrix = cv.getPerspectiveTransform(srcPoints, dstPoints);

      /*
       * Perspective Warp
       */
      final result = cv.warpPerspective(source, matrix, (width, height));

      /*
       * JPG
       */
      final encoded = cv.imencode('.jpg', result);

      if (!encoded.$1) {
        throw Exception('Encode تصویر انجام نشد');
      }

      /*
       * محل ذخیره
       *
       * این روش هم روی Android و هم Windows
       * مسیر معتبر Application Documents را می‌دهد.
       */
      final directory = await getApplicationDocumentsDirectory();

      final scannerDirectory = Directory(
        path.join(directory.path, 'scanned_documents'),
      );

      if (!await scannerDirectory.exists()) {
        await scannerDirectory.create(recursive: true);
      }

      final outputPath = path.join(
        scannerDirectory.path,
        'scan_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      final outputFile = File(outputPath);

      await outputFile.writeAsBytes(encoded.$2, flush: true);

      if (!mounted) {
        return;
      }

      setState(() {
        loading = false;
        message = 'تصویر با موفقیت ذخیره شد';
      });

      await showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('ذخیره شد'),
            content: SelectableText(outputPath),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text('باشه'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        loading = false;
        message = 'خطا در اصلاح تصویر: $e';
      });
    }
  }

  double distance(Offset a, Offset b) {
    return (a - b).distance;
  }
}

class DocumentPainter extends CustomPainter {
  final List<Offset> points;

  DocumentPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length != 4) {
      return;
    }

    final path = Path()
      ..moveTo(points[0].dx, points[0].dy)
      ..lineTo(points[1].dx, points[1].dy)
      ..lineTo(points[2].dx, points[2].dy)
      ..lineTo(points[3].dx, points[3].dy)
      ..close();

    /*
     * ناحیه داخل برگه
     */
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.cyan.withOpacity(0.12)
        ..style = PaintingStyle.fill,
    );

    /*
     * خطوط
     */
    final linePaint = Paint()
      ..color = Colors.cyan
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, linePaint);

    /*
     * خط چین
     */
    drawDashedLine(canvas, points[0], points[1]);

    drawDashedLine(canvas, points[1], points[2]);

    drawDashedLine(canvas, points[2], points[3]);

    drawDashedLine(canvas, points[3], points[0]);
  }

  void drawDashedLine(Canvas canvas, Offset start, Offset end) {
    final delta = end - start;

    final length = delta.distance;

    if (length == 0) {
      return;
    }

    final direction = delta / length;

    const dashLength = 12.0;

    const gapLength = 8.0;

    double distance = 0;

    final paint = Paint()
      ..color = Colors.cyan
      ..strokeWidth = 4;

    while (distance < length) {
      final startPoint = start + direction * distance;

      final endDistance = min(distance + dashLength, length);

      final endPoint = start + direction * endDistance;

      canvas.drawLine(startPoint, endPoint, paint);

      distance += dashLength + gapLength;
    }
  }

  @override
  bool shouldRepaint(covariant DocumentPainter oldDelegate) {
    return true;
  }
}
