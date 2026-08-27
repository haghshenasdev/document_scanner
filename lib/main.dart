import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:document_scanner/core/image_enhancer.dart';
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

  runApp(const DocumentScannerApp());
}

// ============================================================
// APP
// ============================================================

class DocumentScannerApp extends StatelessWidget {
  const DocumentScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Document Scanner',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: const ScannerPage(),
    );
  }
}

// ============================================================
// SCANNER PAGE
// ============================================================

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  ScanFilter selectedFilter = ScanFilter.document;

  img.Image? rectifiedImage;
  img.Image? filteredImage;
  // ----------------------------------------------------------
  // Original image
  // ----------------------------------------------------------

  Uint8List? imageBytes;

  img.Image? decodedImage;

  // ----------------------------------------------------------
  // Detected / manually edited corners
  // ----------------------------------------------------------

  DocumentCorners? corners;

  // ----------------------------------------------------------
  // Saved / processed image
  // ----------------------------------------------------------

  Uint8List? savedImageBytes;

  String? savedImagePath;

  // ----------------------------------------------------------
  // State
  // ----------------------------------------------------------

  bool processing = false;

  String status = 'یک تصویر انتخاب کنید';

  // ----------------------------------------------------------
  // Active corner for zoom
  // ----------------------------------------------------------

  int? activeCorner;

  // ----------------------------------------------------------
  // Zoom configuration
  // ----------------------------------------------------------

  static const double zoomSize = 135;

  static const double zoomFactor = 4.0;

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('اسکنر سند'), centerTitle: true),
      body: Column(
        children: [
          Expanded(
            child: savedImageBytes != null
                ? _savedImagePreview()
                : imageBytes == null
                ? _emptyState()
                : _editor(),
          ),

          _bottomBar(),
        ],
      ),
    );
  }

  // ==========================================================
  // EMPTY STATE
  // ==========================================================

  Widget _emptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
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
              'اسکنر سند',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 10),

            Text(status, textAlign: TextAlign.center),

            const SizedBox(height: 30),

            FilledButton.icon(
              onPressed: processing ? null : pickImage,
              icon: const Icon(Icons.folder_open),
              label: const Text('انتخاب تصویر'),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // EDITOR
  // ==========================================================

  Widget _editor() {
    if (imageBytes == null || decodedImage == null) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final imageWidth = decodedImage!.width.toDouble();

        final imageHeight = decodedImage!.height.toDouble();

        // ----------------------------------------------------
        // Calculate display size
        // ----------------------------------------------------

        double displayWidth = constraints.maxWidth;

        double displayHeight = displayWidth * imageHeight / imageWidth;

        if (displayHeight > constraints.maxHeight) {
          displayHeight = constraints.maxHeight;

          displayWidth = displayHeight * imageWidth / imageHeight;
        }

        final scaleX = displayWidth / imageWidth;

        final scaleY = displayHeight / imageHeight;

        // ----------------------------------------------------
        // Convert original corners to screen coordinates
        // ----------------------------------------------------

        final displayCorners = corners == null
            ? null
            : DocumentCorners(
                topLeft: Offset(
                  corners!.topLeft.dx * scaleX,
                  corners!.topLeft.dy * scaleY,
                ),
                topRight: Offset(
                  corners!.topRight.dx * scaleX,
                  corners!.topRight.dy * scaleY,
                ),
                bottomRight: Offset(
                  corners!.bottomRight.dx * scaleX,
                  corners!.bottomRight.dy * scaleY,
                ),
                bottomLeft: Offset(
                  corners!.bottomLeft.dx * scaleX,
                  corners!.bottomLeft.dy * scaleY,
                ),
              );

        return Center(
          child: SizedBox(
            width: displayWidth,
            height: displayHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // ==================================================
                // IMAGE
                // ==================================================
                Positioned.fill(
                  child: Image.memory(
                    imageBytes!,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.high,
                  ),
                ),

                // ==================================================
                // DOCUMENT AREA
                // ==================================================
                if (displayCorners != null)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: DocumentPainter(displayCorners),
                    ),
                  ),

                // ==================================================
                // HANDLES
                // ==================================================
                if (displayCorners != null)
                  ..._handles(displayCorners, scaleX, scaleY),

                // ==================================================
                // ZOOM
                // ==================================================
                if (displayCorners != null && activeCorner != null)
                  _buildZoom(
                    displayCorners,
                    scaleX,
                    scaleY,
                    displayWidth,
                    displayHeight,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ==========================================================
  // CORNER HANDLES
  // ==========================================================

  List<Widget> _handles(DocumentCorners c, double scaleX, double scaleY) {
    final points = [c.topLeft, c.topRight, c.bottomRight, c.bottomLeft];

    return List.generate(points.length, (index) {
      final point = points[index];

      final isActive = activeCorner == index;

      return Positioned(
        left: point.dx - 23,
        top: point.dy - 23,

        child: GestureDetector(
          behavior: HitTestBehavior.opaque,

          // ------------------------------------------------
          // START DRAG
          // ------------------------------------------------
          onPanStart: (_) {
            setState(() {
              activeCorner = index;
            });
          },

          // ------------------------------------------------
          // MOVE
          // ------------------------------------------------
          onPanUpdate: (details) {
            moveCorner(
              index,
              Offset(details.delta.dx / scaleX, details.delta.dy / scaleY),
            );
          },

          // ------------------------------------------------
          // END DRAG
          // ------------------------------------------------
          onPanEnd: (_) {
            setState(() {
              activeCorner = null;
            });
          },

          // ------------------------------------------------
          // HANDLE UI
          // ------------------------------------------------
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),

            width: isActive ? 52 : 46,
            height: isActive ? 52 : 46,

            decoration: BoxDecoration(
              color: isActive ? Colors.orange : Colors.teal,

              shape: BoxShape.circle,

              border: Border.all(color: Colors.white, width: 2),

              boxShadow: const [
                BoxShadow(
                  color: Colors.black45,
                  blurRadius: 7,
                  spreadRadius: 1,
                ),
              ],
            ),

            child: Icon(
              Icons.open_with,
              color: Colors.white,
              size: isActive ? 25 : 22,
            ),
          ),
        ),
      );
    });
  }

  // ==========================================================
  // ZOOM WINDOW
  // ==========================================================

  Widget _buildZoom(
    DocumentCorners displayCorners,
    double scaleX,
    double scaleY,
    double displayWidth,
    double displayHeight,
  ) {
    if (activeCorner == null || corners == null || decodedImage == null) {
      return const SizedBox.shrink();
    }

    final originalPoint = corners!.points[activeCorner!];

    final displayPoint = Offset(
      originalPoint.dx * scaleX,
      originalPoint.dy * scaleY,
    );

    // --------------------------------------------------------
    // Determine Zoom position
    // --------------------------------------------------------

    double left;

    double top;

    // Horizontal position
    if (displayPoint.dx < displayWidth / 2) {
      left = displayPoint.dx + 38;
    } else {
      left = displayPoint.dx - zoomSize - 38;
    }

    // Vertical position
    if (displayPoint.dy < displayHeight / 2) {
      top = displayPoint.dy + 38;
    } else {
      top = displayPoint.dy - zoomSize - 38;
    }

    // --------------------------------------------------------
    // Keep Zoom inside image
    // --------------------------------------------------------

    left = left.clamp(0.0, math.max(0.0, displayWidth - zoomSize));

    top = top.clamp(0.0, math.max(0.0, displayHeight - zoomSize));

    return Positioned(
      left: left,
      top: top,

      child: _ZoomPreview(
        image: decodedImage!,
        point: originalPoint,
        size: zoomSize,
        zoom: zoomFactor,
      ),
    );
  }

  // ==========================================================
  // BOTTOM BAR
  // ==========================================================

  Widget _bottomBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          children: [
            // ------------------------------------------------
            // STATUS
            // ------------------------------------------------
            Text(
              status,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),

            const SizedBox(height: 10),

            // ------------------------------------------------
            // BUTTONS
            // ------------------------------------------------
            Row(
              children: [
                // --------------------------------------------
                // NEW IMAGE
                // --------------------------------------------
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: processing ? null : pickImage,

                    icon: const Icon(Icons.folder_open),

                    label: const Text('تصویر جدید'),
                  ),
                ),

                const SizedBox(width: 10),

                // --------------------------------------------
                // SAVE
                // --------------------------------------------
                Expanded(
                  child: FilledButton.icon(
                    onPressed: processing || corners == null ? null : saveScan,

                    icon: processing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.crop),

                    label: Text(processing ? 'پردازش...' : 'برش و ذخیره'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // PICK IMAGE
  // ==========================================================

  Future<void> pickImage() async {
    try {
      setState(() {
        processing = true;
        status = 'در حال انتخاب تصویر...';
      });

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'bmp'],
        withData: true,
      );

      // ------------------------------------------------------
      // User cancelled
      // ------------------------------------------------------

      if (result == null) {
        setState(() {
          processing = false;
          status = 'تصویری انتخاب نشد';
        });

        return;
      }

      final selected = result.files.single;

      Uint8List? bytes = selected.bytes;

      // ------------------------------------------------------
      // Windows may return path instead of bytes
      // ------------------------------------------------------

      if (bytes == null && selected.path != null) {
        bytes = await File(selected.path!).readAsBytes();
      }

      if (bytes == null) {
        throw Exception('خواندن فایل ممکن نیست');
      }

      // ------------------------------------------------------
      // Decode image
      // ------------------------------------------------------

      final decoded = img.decodeImage(bytes);

      if (decoded == null) {
        throw Exception('فرمت تصویر قابل تشخیص نیست');
      }

      // ------------------------------------------------------
      // Fix EXIF orientation
      // ------------------------------------------------------

      final fixed = img.bakeOrientation(decoded);

      final fixedBytes = Uint8List.fromList(img.encodeJpg(fixed, quality: 95));

      // ------------------------------------------------------
      // Update UI
      // ------------------------------------------------------

      setState(() {
        imageBytes = fixedBytes;

        decodedImage = fixed;

        corners = null;

        savedImageBytes = null;

        savedImagePath = null;

        activeCorner = null;

        status = 'در حال تشخیص برگه...';
      });

      // ------------------------------------------------------
      // Allow UI to render
      // ------------------------------------------------------

      await Future.delayed(const Duration(milliseconds: 50));

      // ------------------------------------------------------
      // Detect document
      // ------------------------------------------------------

      final detected = await Future(() {
        return DocumentDetector.detect(fixed);
      });

      if (!mounted) {
        return;
      }

      setState(() {
        processing = false;

        if (detected != null) {
          corners = detected;

          status = 'برگه پیدا شد؛ گوشه‌ها را در صورت نیاز تنظیم کنید';
        } else {
          corners = _defaultCorners(fixed);

          status = 'تشخیص خودکار ناموفق بود؛ گوشه‌ها را دستی تنظیم کنید';
        }
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        processing = false;

        status = 'خطا: $e';
      });
    }
  }

  // ==========================================================
  // DEFAULT CORNERS
  // ==========================================================

  DocumentCorners _defaultCorners(img.Image image) {
    final marginX = image.width * 0.08;

    final marginY = image.height * 0.08;

    return DocumentCorners(
      topLeft: Offset(marginX, marginY),

      topRight: Offset(image.width - marginX, marginY),

      bottomRight: Offset(image.width - marginX, image.height - marginY),

      bottomLeft: Offset(marginX, image.height - marginY),
    );
  }

  // ==========================================================
  // MOVE CORNER
  // ==========================================================

  void moveCorner(int index, Offset delta) {
    if (corners == null || decodedImage == null) {
      return;
    }

    final c = corners!.copy();

    Offset updated;

    // --------------------------------------------------------
    // Calculate new position
    // --------------------------------------------------------

    switch (index) {
      case 0:
        updated = c.topLeft + delta;
        break;

      case 1:
        updated = c.topRight + delta;
        break;

      case 2:
        updated = c.bottomRight + delta;
        break;

      case 3:
        updated = c.bottomLeft + delta;
        break;

      default:
        return;
    }

    // --------------------------------------------------------
    // Keep point inside image
    // --------------------------------------------------------

    updated = Offset(
      updated.dx.clamp(0.0, decodedImage!.width.toDouble()),
      updated.dy.clamp(0.0, decodedImage!.height.toDouble()),
    );

    // --------------------------------------------------------
    // Save new point
    // --------------------------------------------------------

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

      status = 'گوشه‌ها را تنظیم کنید';
    });
  }

  // ==========================================================
  // SAVE SCAN
  // ==========================================================

  Future<void> saveScan() async {
    if (decodedImage == null || corners == null) {
      return;
    }

    try {
      setState(() {
        processing = true;

        status = 'در حال اصلاح پرسپکتیو...';
      });

      // ------------------------------------------------------
      // Perspective correction
      // ------------------------------------------------------

      final result = await Future(() {
        return PerspectiveCorrector.rectify(decodedImage!, corners!);
      });

      rectifiedImage = result;

      final enhanced = await Future(() {
        return ImageEnhancer.apply(result, selectedFilter);
      });

      filteredImage = enhanced;

      // ------------------------------------------------------
      // Encode JPG
      // ------------------------------------------------------

      final jpg = Uint8List.fromList(
        img.encodeJpg(filteredImage!, quality: 95),
      );

      // ------------------------------------------------------
      // Application directory
      // ------------------------------------------------------

      final appDirectory = await getApplicationDocumentsDirectory();

      // ------------------------------------------------------
      // Scan directory
      // ------------------------------------------------------

      final scanDirectory = Directory(
        path.join(appDirectory.path, 'scanned_documents'),
      );

      if (!await scanDirectory.exists()) {
        await scanDirectory.create(recursive: true);
      }

      // ------------------------------------------------------
      // Filename
      // ------------------------------------------------------

      final filename = 'scan_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final outputPath = path.join(scanDirectory.path, filename);

      // ------------------------------------------------------
      // Save file
      // ------------------------------------------------------

      final file = File(outputPath);

      await file.writeAsBytes(jpg, flush: true);

      if (!mounted) {
        return;
      }

      // ------------------------------------------------------
      // Show result
      // ------------------------------------------------------

      setState(() {
        savedImageBytes = jpg;

        savedImagePath = outputPath;

        processing = false;

        status = 'تصویر با موفقیت ذخیره شد';
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        processing = false;

        status = 'خطا در ذخیره: $e';
      });
    }
  }

  // ==========================================================
  // SAVED IMAGE PREVIEW
  // ==========================================================

  Widget _savedImagePreview() {
    if (savedImageBytes == null) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        // ----------------------------------------------------
        // Header
        // ----------------------------------------------------
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green),

              const SizedBox(width: 8),

              const Expanded(
                child: Text(
                  'تصویر اسکن‌شده',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                ),
              ),

              // Back to editor
              IconButton(
                tooltip: 'ویرایش دوباره',
                onPressed: processing
                    ? null
                    : () {
                        setState(() {
                          savedImageBytes = null;

                          savedImagePath = null;

                          status = 'گوشه‌ها را تنظیم کنید';
                        });
                      },
                icon: const Icon(Icons.edit),
              ),
            ],
          ),
        ),

        // ----------------------------------------------------
        // Result image
        // ----------------------------------------------------
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),

            decoration: BoxDecoration(
              color: Colors.black12,

              borderRadius: BorderRadius.circular(16),
            ),

            clipBehavior: Clip.antiAlias,

            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 6.0,

              boundaryMargin: const EdgeInsets.all(30),

              child: Center(
                child: Image.memory(
                  savedImageBytes!,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // DISPOSE
  // ==========================================================

  @override
  void dispose() {
    super.dispose();
  }
}

// ============================================================
// DOCUMENT PAINTER
// ============================================================

class DocumentPainter extends CustomPainter {
  final DocumentCorners corners;

  DocumentPainter(this.corners);

  @override
  void paint(Canvas canvas, Size size) {
    final points = corners.points;

    if (points.length != 4) {
      return;
    }

    // --------------------------------------------------------
    // Document path
    // --------------------------------------------------------

    final documentPath = Path()
      ..moveTo(points[0].dx, points[0].dy)
      ..lineTo(points[1].dx, points[1].dy)
      ..lineTo(points[2].dx, points[2].dy)
      ..lineTo(points[3].dx, points[3].dy)
      ..close();

    // --------------------------------------------------------
    // Area inside document
    // --------------------------------------------------------

    canvas.drawPath(
      documentPath,
      Paint()
        ..color = Colors.teal.withOpacity(0.12)
        ..style = PaintingStyle.fill,
    );

    // --------------------------------------------------------
    // Border
    // --------------------------------------------------------

    canvas.drawPath(
      documentPath,
      Paint()
        ..color = Colors.teal
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant DocumentPainter oldDelegate) {
    return true;
  }
}

// ============================================================
// ZOOM PREVIEW
// ============================================================

class _ZoomPreview extends StatefulWidget {
  final img.Image image;

  final Offset point;

  final double size;

  final double zoom;

  const _ZoomPreview({
    required this.image,
    required this.point,
    required this.size,
    required this.zoom,
  });

  @override
  State<_ZoomPreview> createState() => _ZoomPreviewState();
}

// ============================================================
// ZOOM STATE
// ============================================================

class _ZoomPreviewState extends State<_ZoomPreview> {
  Uint8List? bytes;

  @override
  void initState() {
    super.initState();

    _prepare();
  }

  @override
  void didUpdateWidget(covariant _ZoomPreview oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.image != widget.image ||
        oldWidget.point != widget.point ||
        oldWidget.zoom != widget.zoom) {
      _prepare();
    }
  }

  // ==========================================================
  // PREPARE ZOOM IMAGE
  // ==========================================================
  Future<void> _prepare() async {
    // اندازه ناحیه‌ای که از تصویر اصلی برمی‌داریم
    final int cropSize = math
        .max(10, (widget.size / widget.zoom).round())
        .toInt();

    // --------------------------------------------------------
    // Crop position
    // --------------------------------------------------------

    final int left = (widget.point.dx - cropSize / 2).round();

    final int top = (widget.point.dy - cropSize / 2).round();

    // --------------------------------------------------------
    // Keep crop inside image
    // --------------------------------------------------------

    final int maxLeft = math.max(0, widget.image.width - cropSize).toInt();

    final int maxTop = math.max(0, widget.image.height - cropSize).toInt();

    final int safeLeft = left.clamp(0, maxLeft).toInt();

    final int safeTop = top.clamp(0, maxTop).toInt();

    // --------------------------------------------------------
    // Safe crop dimensions
    // --------------------------------------------------------

    final int safeWidth = math
        .min(cropSize, widget.image.width - safeLeft)
        .toInt();

    final int safeHeight = math
        .min(cropSize, widget.image.height - safeTop)
        .toInt();

    if (safeWidth <= 0 || safeHeight <= 0) {
      return;
    }

    // --------------------------------------------------------
    // Crop image
    // --------------------------------------------------------

    final cropped = img.copyCrop(
      widget.image,
      x: safeLeft,
      y: safeTop,
      width: safeWidth,
      height: safeHeight,
    );

    // --------------------------------------------------------
    // Encode
    // --------------------------------------------------------

    final encoded = Uint8List.fromList(img.encodeJpg(cropped, quality: 95));

    if (!mounted) {
      return;
    }

    setState(() {
      bytes = encoded;
    });
  }
  // ==========================================================
  // BUILD ZOOM
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.size,
      height: widget.size,

      decoration: BoxDecoration(
        color: Colors.black,

        shape: BoxShape.circle,

        border: Border.all(color: Colors.white, width: 3),

        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 10, spreadRadius: 2),
        ],
      ),

      clipBehavior: Clip.antiAlias,

      child: Stack(
        fit: StackFit.expand,
        children: [
          // --------------------------------------------------
          // Zoom image
          // --------------------------------------------------
          if (bytes != null)
            Image.memory(
              bytes!,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
            )
          else
            const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),

          // --------------------------------------------------
          // Crosshair
          // --------------------------------------------------
          CustomPaint(painter: _ZoomCrosshairPainter()),

          // --------------------------------------------------
          // Zoom label
          // --------------------------------------------------
          Positioned(
            right: 8,
            bottom: 7,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${widget.zoom.toStringAsFixed(0)}×',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// ZOOM CROSSHAIR
// ============================================================

class _ZoomCrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final paint = Paint()
      ..color = Colors.red
      ..strokeWidth = 1.5;

    // --------------------------------------------------------
    // Horizontal line
    // --------------------------------------------------------

    canvas.drawLine(
      Offset(center.dx - 20, center.dy),
      Offset(center.dx + 20, center.dy),
      paint,
    );

    // --------------------------------------------------------
    // Vertical line
    // --------------------------------------------------------

    canvas.drawLine(
      Offset(center.dx, center.dy - 20),
      Offset(center.dx, center.dy + 20),
      paint,
    );

    // --------------------------------------------------------
    // Center circle
    // --------------------------------------------------------

    canvas.drawCircle(center, 4, Paint()..color = Colors.red);

    canvas.drawCircle(center, 2, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}
