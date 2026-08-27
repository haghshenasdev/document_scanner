import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'core/document_detector.dart';
import 'core/perspective_corrector.dart';
import 'models/document_corners.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    const DocumentScannerApp(),
  );
}

class DocumentScannerApp
    extends StatelessWidget {
  const DocumentScannerApp({
    super.key,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Document Scanner',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
      ),
      home: const ScannerPage(),
    );
  }
}

class ScannerPage
    extends StatefulWidget {
  const ScannerPage({
    super.key,
  });

  @override
  State<ScannerPage> createState() =>
      _ScannerPageState();
}

class _ScannerPageState
    extends State<ScannerPage> {
  Uint8List? imageBytes;

  img.Image? decodedImage;

  DocumentCorners? corners;

  bool processing = false;

  String status =
      'یک تصویر انتخاب کنید';

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Document Scanner',
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: imageBytes == null
                ? _emptyState()
                : _editor(),
          ),
          _bottomBar(),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment:
            MainAxisAlignment.center,
        children: [
          Icon(
            Icons.document_scanner_outlined,
            size: 100,
            color: Theme.of(context)
                .colorScheme
                .primary,
          ),

          const SizedBox(height: 20),

          const Text(
            'اسکنر سند',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 10),

          Text(status),

          const SizedBox(height: 30),

          FilledButton.icon(
            onPressed: processing
                ? null
                : pickImage,
            icon: const Icon(
              Icons.folder_open,
            ),
            label: const Text(
              'انتخاب تصویر',
            ),
          ),
        ],
      ),
    );
  }

  Widget _editor() {
    if (imageBytes == null ||
        decodedImage == null) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        final imageWidth =
            decodedImage!.width.toDouble();

        final imageHeight =
            decodedImage!.height.toDouble();

        double displayWidth =
            constraints.maxWidth;

        double displayHeight =
            displayWidth *
                imageHeight /
                imageWidth;

        if (displayHeight >
            constraints.maxHeight) {
          displayHeight =
              constraints.maxHeight;

          displayWidth =
              displayHeight *
                  imageWidth /
                  imageHeight;
        }

        final scaleX =
            displayWidth /
                imageWidth;

        final scaleY =
            displayHeight /
                imageHeight;

        final displayCorners =
            corners == null
                ? null
                : DocumentCorners(
                    topLeft: Offset(
                      corners!
                              .topLeft
                              .dx *
                          scaleX,
                      corners!
                              .topLeft
                              .dy *
                          scaleY,
                    ),
                    topRight: Offset(
                      corners!
                              .topRight
                              .dx *
                          scaleX,
                      corners!
                              .topRight
                              .dy *
                          scaleY,
                    ),
                    bottomRight: Offset(
                      corners!
                              .bottomRight
                              .dx *
                          scaleX,
                      corners!
                              .bottomRight
                              .dy *
                          scaleY,
                    ),
                    bottomLeft: Offset(
                      corners!
                              .bottomLeft
                              .dx *
                          scaleX,
                      corners!
                              .bottomLeft
                              .dy *
                          scaleY,
                    ),
                  );

        return Center(
          child: SizedBox(
            width: displayWidth,
            height: displayHeight,
            child: Stack(
              clipBehavior:
                  Clip.none,
              children: [
                Positioned.fill(
                  child: Image.memory(
                    imageBytes!,
                    fit: BoxFit.fill,
                  ),
                ),

                if (displayCorners != null)
                  Positioned.fill(
                    child: CustomPaint(
                      painter:
                          DocumentPainter(
                        displayCorners,
                      ),
                    ),
                  ),

                if (displayCorners != null)
                  ..._handles(
                    displayCorners,
                    scaleX,
                    scaleY,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _handles(
    DocumentCorners c,
    double scaleX,
    double scaleY,
  ) {
    final points = [
      c.topLeft,
      c.topRight,
      c.bottomRight,
      c.bottomLeft,
    ];

    return List.generate(
      points.length,
      (index) {
        final point = points[index];

        return Positioned(
          left: point.dx - 23,
          top: point.dy - 23,
          child: GestureDetector(
            behavior:
                HitTestBehavior.opaque,
            onPanUpdate: (details) {
              moveCorner(
                index,
                Offset(
                  details.delta.dx / scaleX,
                  details.delta.dy / scaleY,
                ),
              );
            },
            child: Container(
              width: 46,
              height: 46,
              decoration:
                  const BoxDecoration(
                color: Colors.teal,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.open_with,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _bottomBar() {
    return SafeArea(
      child: Padding(
        padding:
            const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(
              status,
              textAlign:
                  TextAlign.center,
            ),

            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        processing
                            ? null
                            : pickImage,
                    icon: const Icon(
                      Icons.folder_open,
                    ),
                    label: const Text(
                      'تصویر جدید',
                    ),
                  ),
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: FilledButton.icon(
                    onPressed:
                        processing ||
                                corners == null
                            ? null
                            : saveScan,
                    icon: processing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child:
                                CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(
                            Icons.crop,
                          ),
                    label: Text(
                      processing
                          ? 'پردازش...'
                          : 'برش و ذخیره',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> pickImage() async {
    try {
      setState(() {
        processing = true;
        status =
            'در حال انتخاب تصویر...';
      });

      final result =
          await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'jpg',
          'jpeg',
          'png',
          'webp',
          'bmp',
        ],
        withData: true,
      );

      if (result == null) {
        setState(() {
          processing = false;
          status =
              'تصویری انتخاب نشد';
        });

        return;
      }

      final selected =
          result.files.single;

      Uint8List? bytes =
          selected.bytes;

      if (bytes == null &&
          selected.path != null) {
        bytes = await File(
          selected.path!,
        ).readAsBytes();
      }

      if (bytes == null) {
        throw Exception(
          'خواندن فایل ممکن نیست',
        );
      }

      final decoded =
          img.decodeImage(bytes);

      if (decoded == null) {
        throw Exception(
          'فرمت تصویر قابل تشخیص نیست',
        );
      }

      /*
       * اصلاح EXIF rotation
       *
       * مخصوصاً برای عکس موبایل مهم است.
       */
      final fixed =
          img.bakeOrientation(
        decoded,
      );

      setState(() {
        imageBytes =
            Uint8List.fromList(
          img.encodeJpg(
            fixed,
            quality: 95,
          ),
        );

        decodedImage = fixed;

        corners = null;

        status =
            'در حال تشخیص برگه...';
      });

      /*
       * کمی بعد پردازش را انجام می‌دهیم
       * تا UI فرصت Render شدن داشته باشد.
       */
      await Future.delayed(
        const Duration(
          milliseconds: 50,
        ),
      );

      final detected =
          await Future(() {
        return DocumentDetector.detect(
          fixed,
        );
      });

      if (!mounted) {
        return;
      }

      setState(() {
        processing = false;

        if (detected != null) {
          corners = detected;

          status =
              'برگه پیدا شد؛ گوشه‌ها را در صورت نیاز تنظیم کنید';
        } else {
          /*
           * اگر تشخیص خودکار شکست خورد،
           * یک مستطیل پیش‌فرض ایجاد می‌کنیم.
           *
           * کاربر می‌تواند چهار نقطه را دستی
           * جابه‌جا کند.
           */
          corners =
              _defaultCorners(
            fixed,
          );

          status =
              'تشخیص خودکار ناموفق بود؛ گوشه‌ها را دستی تنظیم کنید';
        }
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        processing = false;
        status =
            'خطا: $e';
      });
    }
  }

  DocumentCorners _defaultCorners(
    img.Image image,
  ) {
    final marginX =
        image.width * 0.08;

    final marginY =
        image.height * 0.08;

    return DocumentCorners(
      topLeft: Offset(
        marginX,
        marginY,
      ),
      topRight: Offset(
        image.width - marginX,
        marginY,
      ),
      bottomRight: Offset(
        image.width - marginX,
        image.height - marginY,
      ),
      bottomLeft: Offset(
        marginX,
        image.height - marginY,
      ),
    );
  }

  void moveCorner(
    int index,
    Offset delta,
  ) {
    if (corners == null ||
        decodedImage == null) {
      return;
    }

    final c =
        corners!.copy();

    Offset updated;

    switch (index) {
      case 0:
        updated =
            c.topLeft + delta;
        break;

      case 1:
        updated =
            c.topRight + delta;
        break;

      case 2:
        updated =
            c.bottomRight + delta;
        break;

      case 3:
        updated =
            c.bottomLeft + delta;
        break;

      default:
        return;
    }

    updated = Offset(
      updated.dx.clamp(
        0.0,
        decodedImage!.width
            .toDouble(),
      ),
      updated.dy.clamp(
        0.0,
        decodedImage!.height
            .toDouble(),
      ),
    );

    switch (index) {
      case 0:
        c.topLeft = updated;
        break;

      case 1:
        c.topRight = updated;
        break;

      case 2:
        c.bottomRight = updated;
        break;

      case 3:
        c.bottomLeft = updated;
        break;
    }

    setState(() {
      corners = c;
      status =
          'گوشه‌ها را تنظیم کنید';
    });
  }

  Future<void> saveScan() async {
    if (decodedImage == null ||
        corners == null) {
      return;
    }

    try {
      setState(() {
        processing = true;
        status =
            'در حال اصلاح پرسپکتیو...';
      });

      final result =
          await Future(() {
        return PerspectiveCorrector.rectify(
          decodedImage!,
          corners!,
        );
      });

      final jpg =
          Uint8List.fromList(
        img.encodeJpg(
          result,
          quality: 95,
        ),
      );

      final appDirectory =
          await getApplicationDocumentsDirectory();

      final scanDirectory =
          Directory(
        path.join(
          appDirectory.path,
          'scanned_documents',
        ),
      );

      if (!await scanDirectory.exists()) {
        await scanDirectory.create(
          recursive: true,
        );
      }

      final filename =
          'scan_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final outputPath =
          path.join(
        scanDirectory.path,
        filename,
      );

      final file =
          File(outputPath);

      await file.writeAsBytes(
        jpg,
        flush: true,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        processing = false;
        status =
            'تصویر با موفقیت ذخیره شد';
      });

      await showDialog(
        context: context,
        builder: (_) {
          return AlertDialog(
            title: const Text(
              'ذخیره شد',
            ),
            content:
                SelectableText(
              outputPath,
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(
                    context,
                  );
                },
                child: const Text(
                  'باشه',
                ),
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
        processing = false;
        status =
            'خطا در ذخیره: $e';
      });
    }
  }
}

class DocumentPainter
    extends CustomPainter {
  final DocumentCorners corners;

  DocumentPainter(this.corners);

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final points =
        corners.points;

    if (points.length != 4) {
      return;
    }

    final path =
        Path()
          ..moveTo(
            points[0].dx,
            points[0].dy,
          )
          ..lineTo(
            points[1].dx,
            points[1].dy,
          )
          ..lineTo(
            points[2].dx,
            points[2].dy,
          )
          ..lineTo(
            points[3].dx,
            points[3].dy,
          )
          ..close();

    /*
     * ناحیه داخل سند
     */
    canvas.drawPath(
      path,
      Paint()
        ..color =
            Colors.teal.withOpacity(
          0.12,
        )
        ..style =
            PaintingStyle.fill,
    );

    /*
     * خط اصلی
     */
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.teal
        ..strokeWidth = 3
        ..style =
            PaintingStyle.stroke,
    );

    /*
     * نقاط گوشه
     */
    for (final point in points) {
      canvas.drawCircle(
        point,
        5,
        Paint()
          ..color = Colors.white,
      );

      canvas.drawCircle(
        point,
        4,
        Paint()
          ..color = Colors.teal,
      );
    }
  }

  @override
  bool shouldRepaint(
    covariant DocumentPainter oldDelegate,
  ) {
    return true;
  }
}