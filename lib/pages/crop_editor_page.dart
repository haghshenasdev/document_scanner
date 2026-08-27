import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../core/document_detector.dart';
import '../core/image_enhancer.dart';
import '../core/perspective_corrector.dart';
import '../models/document_corners.dart';
import '../models/scan_item.dart';

class CropEditorPage extends StatefulWidget {
  final ScanItem item;

  const CropEditorPage({super.key, required this.item});

  @override
  State<CropEditorPage> createState() => _CropEditorPageState();
}

class _CropEditorPageState extends State<CropEditorPage> {
  late img.Image originalImage;
  late DocumentCorners corners;

  Uint8List? previewBytes;

  bool editing = false;
  bool processing = false;

  int? activeCorner;

  static const double zoomSize = 135;
  static const double zoomFactor = 4.0;

  @override
  void initState() {
    super.initState();

    originalImage = widget.item.originalImage;
    corners = widget.item.corners;

    previewBytes = widget.item.previewBytes;
  }

  Future<void> _apply() async {
    if (processing) return;

    try {
      setState(() {
        processing = true;
      });

      final rectified = await Future(() {
        return PerspectiveCorrector.rectify(originalImage, corners);
      });

      final enhanced = await Future(() {
        return ImageEnhancer.apply(rectified, ScanFilter.document);
      });

      final bytes = Uint8List.fromList(img.encodeJpg(enhanced, quality: 100));

      if (!mounted) return;

      Navigator.of(context).pop(
        widget.item.copyWith(
          corners: corners,
          previewBytes: bytes,
          processedImage: enhanced,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        processing = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطا در اعمال برش: $e')));
    }
  }

  void _moveCorner(int index, Offset delta) {
    final c = corners.copy();

    Offset updated;

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

    updated = Offset(
      updated.dx.clamp(0, originalImage.width.toDouble()),
      updated.dy.clamp(0, originalImage.height.toDouble()),
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
    });
  }

  DocumentCorners _displayCorners(double scaleX, double scaleY) {
    return DocumentCorners(
      topLeft: Offset(corners.topLeft.dx * scaleX, corners.topLeft.dy * scaleY),
      topRight: Offset(
        corners.topRight.dx * scaleX,
        corners.topRight.dy * scaleY,
      ),
      bottomRight: Offset(
        corners.bottomRight.dx * scaleX,
        corners.bottomRight.dy * scaleY,
      ),
      bottomLeft: Offset(
        corners.bottomLeft.dx * scaleX,
        corners.bottomLeft.dy * scaleY,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'اصلاح برش' : 'پیش‌نمایش'),
        centerTitle: true,
        actions: [
          if (!editing)
            IconButton(
              tooltip: 'اصلاح برش',
              onPressed: () {
                setState(() {
                  editing = true;
                });
              },
              icon: const Icon(Icons.crop),
            ),
        ],
      ),
      body: editing ? _editor() : _preview(),
      bottomNavigationBar: editing
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: processing
                            ? null
                            : () {
                                setState(() {
                                  editing = false;
                                  corners = widget.item.corners;
                                });
                              },
                        child: const Text('لغو'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: processing ? null : _apply,
                        icon: processing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check),
                        label: Text(
                          processing ? 'در حال اعمال...' : 'اعمال تغییرات',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _preview() {
    if (previewBytes == null) {
      return const Center(child: Text('پیش‌نمایش وجود ندارد'));
    }

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: InteractiveViewer(
        minScale: 0.5,
        maxScale: 6,
        boundaryMargin: const EdgeInsets.all(30),
        child: Center(
          child: Image.memory(
            previewBytes!,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
      ),
    );
  }

  Widget _editor() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final imageWidth = originalImage.width.toDouble();
        final imageHeight = originalImage.height.toDouble();

        double displayWidth = constraints.maxWidth;
        double displayHeight = displayWidth * imageHeight / imageWidth;

        if (displayHeight > constraints.maxHeight) {
          displayHeight = constraints.maxHeight;
          displayWidth = displayHeight * imageWidth / imageHeight;
        }

        final scaleX = displayWidth / imageWidth;
        final scaleY = displayHeight / imageHeight;

        final displayCorners = _displayCorners(scaleX, scaleY);

        return Center(
          child: SizedBox(
            width: displayWidth,
            height: displayHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: Image.memory(
                    widget.item.originalBytes,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.high,
                  ),
                ),

                Positioned.fill(
                  child: CustomPaint(painter: DocumentPainter(displayCorners)),
                ),

                ..._handles(displayCorners, scaleX, scaleY),

                if (activeCorner != null)
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

  List<Widget> _handles(DocumentCorners c, double scaleX, double scaleY) {
    final points = c.points;

    return List.generate(points.length, (index) {
      final point = points[index];

      final isActive = activeCorner == index;

      return Positioned(
        left: point.dx - 23,
        top: point.dy - 23,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) {
            setState(() {
              activeCorner = index;
            });
          },
          onPanUpdate: (details) {
            _moveCorner(
              index,
              Offset(details.delta.dx / scaleX, details.delta.dy / scaleY),
            );
          },
          onPanEnd: (_) {
            setState(() {
              activeCorner = null;
            });
          },
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

  Widget _buildZoom(
    DocumentCorners displayCorners,
    double scaleX,
    double scaleY,
    double displayWidth,
    double displayHeight,
  ) {
    if (activeCorner == null) {
      return const SizedBox.shrink();
    }

    final originalPoint = corners.points[activeCorner!];

    final displayPoint = Offset(
      originalPoint.dx * scaleX,
      originalPoint.dy * scaleY,
    );

    double left;
    double top;

    if (displayPoint.dx < displayWidth / 2) {
      left = displayPoint.dx + 38;
    } else {
      left = displayPoint.dx - zoomSize - 38;
    }

    if (displayPoint.dy < displayHeight / 2) {
      top = displayPoint.dy + 38;
    } else {
      top = displayPoint.dy - zoomSize - 38;
    }

    left = left.clamp(0, math.max(0, displayWidth - zoomSize));

    top = top.clamp(0, math.max(0, displayHeight - zoomSize));

    return Positioned(
      left: left,
      top: top,
      child: _ZoomPreview(
        image: originalImage,
        point: originalPoint,
        size: zoomSize,
        zoom: zoomFactor,
      ),
    );
  }
}

class DocumentPainter extends CustomPainter {
  final DocumentCorners corners;

  DocumentPainter(this.corners);

  @override
  void paint(Canvas canvas, Size size) {
    final points = corners.points;

    if (points.length != 4) {
      return;
    }

    final documentPath = Path()
      ..moveTo(points[0].dx, points[0].dy)
      ..lineTo(points[1].dx, points[1].dy)
      ..lineTo(points[2].dx, points[2].dy)
      ..lineTo(points[3].dx, points[3].dy)
      ..close();

    canvas.drawPath(
      documentPath,
      Paint()
        ..color = Colors.teal.withOpacity(0.12)
        ..style = PaintingStyle.fill,
    );

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

  Future<void> _prepare() async {
    final cropSize = math.max(10, (widget.size / widget.zoom).round());

    final left = (widget.point.dx - cropSize / 2).round();

    final top = (widget.point.dy - cropSize / 2).round();

    final maxLeft = math.max(0, widget.image.width - cropSize);

    final maxTop = math.max(0, widget.image.height - cropSize);

    final safeLeft = left.clamp(0, maxLeft);

    final safeTop = top.clamp(0, maxTop);

    final safeWidth = math.min(cropSize, widget.image.width - safeLeft);

    final safeHeight = math.min(cropSize, widget.image.height - safeTop);

    if (safeWidth <= 0 || safeHeight <= 0) {
      return;
    }

    final cropped = img.copyCrop(
      widget.image,
      x: safeLeft,
      y: safeTop,
      width: safeWidth,
      height: safeHeight,
    );

    final encoded = Uint8List.fromList(img.encodeJpg(cropped, quality: 95));

    if (!mounted) return;

    setState(() {
      bytes = encoded;
    });
  }

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
          CustomPaint(painter: _ZoomCrosshairPainter()),
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

class _ZoomCrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final paint = Paint()
      ..color = Colors.red
      ..strokeWidth = 1.5;

    canvas.drawLine(
      Offset(center.dx - 20, center.dy),
      Offset(center.dx + 20, center.dy),
      paint,
    );

    canvas.drawLine(
      Offset(center.dx, center.dy - 20),
      Offset(center.dx, center.dy + 20),
      paint,
    );

    canvas.drawCircle(center, 4, Paint()..color = Colors.red);

    canvas.drawCircle(center, 2, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}
