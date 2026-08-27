import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'core/document_detector.dart';
import 'core/image_enhancer.dart';
import 'core/perspective_corrector.dart';
import 'models/document_corners.dart';

Future<void> main() async {
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
      title: 'اسکنر سند',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: const ScannerPage(),
    );
  }
}

// ============================================================
// SCAN ITEM
// ============================================================

class ScanItem {
  Uint8List originalBytes;

  img.Image originalImage;

  DocumentCorners corners;

  Uint8List processedBytes;

  img.Image processedImage;

  ScanItem({
    required this.originalBytes,
    required this.originalImage,
    required this.corners,
    required this.processedBytes,
    required this.processedImage,
  });
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
  // ==========================================================
  // CAMERA
  // ==========================================================

  CameraController? _cameraController;

  List<CameraDescription> _cameras = [];

  bool cameraAvailable = false;

  bool cameraInitializing = true;

  bool takingPicture = false;

  // ==========================================================
  // SCANS
  // ==========================================================

  final List<ScanItem> scans = [];

  ScanFilter selectedFilter = ScanFilter.document;

  bool processing = false;

  String status = 'دوربین در حال آماده‌سازی است...';

  // ==========================================================
  // INIT
  // ==========================================================

  @override
  void initState() {
    super.initState();

    _initializeCamera();
  }

  // ==========================================================
  // CAMERA INIT
  // ==========================================================

  Future<void> _initializeCamera() async {
    try {
      if (mounted) {
        setState(() {
          cameraInitializing = true;
          status = 'در حال شناسایی دوربین...';
        });
      }

      _cameras = await availableCameras();

      if (_cameras.isEmpty) {
        if (!mounted) return;

        setState(() {
          cameraAvailable = false;
          cameraInitializing = false;
          status = 'دوربینی در دسترس نیست';
        });

        return;
      }

      // --------------------------------------------------------
      // انتخاب دوربین پشت
      // --------------------------------------------------------

      CameraDescription selectedCamera = _cameras.first;

      for (final camera in _cameras) {
        if (camera.lensDirection == CameraLensDirection.back) {
          selectedCamera = camera;
          break;
        }
      }

      // --------------------------------------------------------
      // Controller
      // --------------------------------------------------------

      final controller = CameraController(
        selectedCamera,
        ResolutionPreset.max,
        enableAudio: false,
      );

      _cameraController = controller;

      await controller.initialize();

      if (!mounted) return;

      setState(() {
        cameraAvailable = true;
        cameraInitializing = false;

        status = scans.isEmpty
            ? 'سند را مقابل دوربین قرار دهید'
            : '${scans.length} صفحه اسکن شده';
      });
    } catch (e) {
      debugPrint('Camera initialization error: $e');

      if (!mounted) return;

      setState(() {
        cameraAvailable = false;
        cameraInitializing = false;
        status = 'دوربین در دسترس نیست؛ فایل انتخاب کنید';
      });
    }
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // ==================================================
            // TOP BAR
            // ==================================================
            _buildTopBar(),

            // ==================================================
            // CAMERA
            // ==================================================
            Expanded(child: _buildCameraArea()),

            // ==================================================
            // STATUS BAR
            // ==================================================
            _buildStatusBar(),

            // ==================================================
            // BOTTOM CONTROLS
            // ==================================================
            _buildBottomControls(),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // TOP BAR
  // ==========================================================

  Widget _buildTopBar() {
    return SizedBox(
      height: 58,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        child: Row(
          children: [
            // --------------------------------------------------
            // CLOSE
            // --------------------------------------------------
            _glassButton(
              icon: Icons.close,
              onPressed: () {
                Navigator.of(context).maybePop();
              },
            ),

            const Spacer(),

            // --------------------------------------------------
            // TITLE
            // --------------------------------------------------
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(.12)),
              ),
              child: Text(
                scans.isEmpty ? 'اسکن سند' : '${scans.length} صفحه',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const Spacer(),

            // --------------------------------------------------
            // SETTINGS
            // --------------------------------------------------
            _glassButton(icon: Icons.settings_outlined, onPressed: () {}),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // CAMERA AREA
  // ==========================================================

  Widget _buildCameraArea() {
    if (cameraInitializing) {
      return Container(
        width: double.infinity,
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    if (cameraAvailable &&
        _cameraController != null &&
        _cameraController!.value.isInitialized) {
      return _buildCameraPreview();
    }

    return _buildFileFallback();
  }

  // ==========================================================
  // CAMERA PREVIEW
  // ==========================================================

  Widget _buildCameraPreview() {
    final controller = _cameraController!;

    return Container(
      width: double.infinity,
      color: Colors.black,
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width:
              controller.value.previewSize?.height ??
              MediaQuery.of(context).size.width,
          height:
              controller.value.previewSize?.width ??
              MediaQuery.of(context).size.height,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  // ==========================================================
  // FILE FALLBACK
  // ==========================================================

  Widget _buildFileFallback() {
    return Container(
      width: double.infinity,
      color: const Color(0xff111111),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.teal.withOpacity(.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.document_scanner_outlined,
                  size: 55,
                  color: Colors.teal,
                ),
              ),

              const SizedBox(height: 20),

              const Text(
                'دوربین در دسترس نیست',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'تصویر سند را از کامپیوتر انتخاب کنید',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),

              const SizedBox(height: 22),

              FilledButton.icon(
                onPressed: processing ? null : pickImages,
                icon: const Icon(Icons.folder_open),
                label: const Text('انتخاب تصویر'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // STATUS BAR
  // ==========================================================

  Widget _buildStatusBar() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 42, maxHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xff101010),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(.08)),
          bottom: BorderSide(color: Colors.white.withOpacity(.08)),
        ),
      ),
      child: Center(
        child: Text(
          status,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ),
    );
  }

  // ==========================================================
  // BOTTOM CONTROLS
  // ==========================================================

  Widget _buildBottomControls() {
    return Container(
      width: double.infinity,
      height: 112,
      color: const Color(0xff080808),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ====================================================
          // FILE PICKER
          // ====================================================
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: _buildFileButton(),
            ),
          ),

          // ====================================================
          // SHUTTER
          // ====================================================
          Expanded(child: Center(child: _buildShutterButton())),

          // ====================================================
          // SCAN STACK
          // ====================================================
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: scans.isEmpty
                  ? const SizedBox(width: 78, height: 78)
                  : _buildScanStack(),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // FILE BUTTON
  // ==========================================================

  Widget _buildFileButton() {
    return GestureDetector(
      onTap: processing ? null : pickImages,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.08),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24, width: 1),
            ),
            child: const Icon(
              Icons.photo_library_outlined,
              color: Colors.white,
              size: 27,
            ),
          ),

          const SizedBox(height: 4),

          const Text(
            'فایل',
            style: TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // SHUTTER
  // ==========================================================

  Widget _buildShutterButton() {
    return GestureDetector(
      onTap: cameraAvailable && !takingPicture && !processing
          ? capturePhoto
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 78,
        height: 78,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: cameraAvailable ? Colors.white : Colors.white24,
          border: Border.all(color: Colors.white70, width: 4),
          boxShadow: const [
            BoxShadow(color: Colors.black54, blurRadius: 12, spreadRadius: 2),
          ],
        ),
        child: takingPicture
            ? const Padding(
                padding: EdgeInsets.all(23),
                child: CircularProgressIndicator(strokeWidth: 3),
              )
            : Icon(
                Icons.camera_alt,
                color: cameraAvailable ? Colors.black87 : Colors.white38,
                size: 32,
              ),
      ),
    );
  }

  // ==========================================================
  // SCAN STACK
  // ==========================================================

  Widget _buildScanStack() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: processing
          ? null
          : () {
              _openSavePreview();
            },
      child: SizedBox(
        width: 86,
        height: 82,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // --------------------------------------------------
            // BACK IMAGE 1
            // --------------------------------------------------
            if (scans.length >= 3)
              Positioned(
                left: 0,
                top: 8,
                child: _thumbnailCard(
                  scans[scans.length - 3],
                  53,
                  65,
                  rotation: -.10,
                ),
              ),

            // --------------------------------------------------
            // BACK IMAGE 2
            // --------------------------------------------------
            if (scans.length >= 2)
              Positioned(
                left: 8,
                top: 4,
                child: _thumbnailCard(
                  scans[scans.length - 2],
                  57,
                  69,
                  rotation: -.05,
                ),
              ),

            // --------------------------------------------------
            // LAST IMAGE
            // --------------------------------------------------
            Positioned(
              left: 17,
              top: 0,
              child: _thumbnailCard(scans.last, 61, 74),
            ),

            // --------------------------------------------------
            // COUNT
            // --------------------------------------------------
            Positioned(
              right: -4,
              bottom: -2,
              child: Container(
                width: 31,
                height: 31,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.teal,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [
                    BoxShadow(color: Colors.black54, blurRadius: 5),
                  ],
                ),
                child: Text(
                  '${scans.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // THUMBNAIL
  // ==========================================================

  Widget _thumbnailCard(
    ScanItem item,
    double width,
    double height, {
    double rotation = 0,
  }) {
    return Transform.rotate(
      angle: rotation,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)],
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.memory(item.processedBytes, fit: BoxFit.cover),
      ),
    );
  }

  // ==========================================================
  // GLASS BUTTON
  // ==========================================================

  Widget _glassButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.black54,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24),
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white, size: 21),
      ),
    );
  }

  // ==========================================================
  // CAPTURE PHOTO
  // ==========================================================

  Future<void> capturePhoto() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        takingPicture ||
        processing) {
      return;
    }

    try {
      setState(() {
        takingPicture = true;
        status = 'در حال گرفتن تصویر...';
      });

      final XFile file = await _cameraController!.takePicture();

      final bytes = await file.readAsBytes();

      await _processAndAddImage(bytes);
    } catch (e) {
      debugPrint('Capture error: $e');

      if (!mounted) return;

      setState(() {
        status = 'خطا در گرفتن تصویر';
      });
    } finally {
      if (mounted) {
        setState(() {
          takingPicture = false;
        });
      }
    }
  }

  // ==========================================================
  // PICK IMAGES
  // ==========================================================

  Future<void> pickImages() async {
    if (processing) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'bmp'],
        allowMultiple: true,
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      for (final selected in result.files) {
        Uint8List? bytes = selected.bytes;

        if (bytes == null && selected.path != null) {
          bytes = await File(selected.path!).readAsBytes();
        }

        if (bytes == null) {
          continue;
        }

        await _processAndAddImage(bytes);
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        status = 'خطا در انتخاب تصویر: $e';
      });
    }
  }

  // ==========================================================
  // PROCESS IMAGE
  // ==========================================================

  Future<void> _processAndAddImage(Uint8List bytes) async {
    try {
      setState(() {
        processing = true;
        status = 'در حال تشخیص و برش سند...';
      });

      // ------------------------------------------------------
      // Decode
      // ------------------------------------------------------

      final decoded = img.decodeImage(bytes);

      if (decoded == null) {
        throw Exception('فرمت تصویر قابل تشخیص نیست');
      }

      // ------------------------------------------------------
      // EXIF
      // ------------------------------------------------------

      final fixed = img.bakeOrientation(decoded);

      final fixedBytes = Uint8List.fromList(img.encodeJpg(fixed, quality: 95));

      // ------------------------------------------------------
      // Detect
      // ------------------------------------------------------

      final detected = await Future(() {
        return DocumentDetector.detect(fixed);
      });

      final detectedCorners = detected ?? _defaultCorners(fixed);

      // ------------------------------------------------------
      // Perspective
      // ------------------------------------------------------

      final rectified = await Future(() {
        return PerspectiveCorrector.rectify(fixed, detectedCorners);
      });

      // ------------------------------------------------------
      // Enhancement
      // ------------------------------------------------------

      final enhanced = await Future(() {
        return ImageEnhancer.apply(rectified, selectedFilter);
      });

      final processedBytes = Uint8List.fromList(
        img.encodeJpg(enhanced, quality: 100),
      );

      // ------------------------------------------------------
      // Add
      // ------------------------------------------------------

      if (!mounted) return;

      setState(() {
        scans.add(
          ScanItem(
            originalBytes: fixedBytes,
            originalImage: fixed,
            corners: detectedCorners,
            processedBytes: processedBytes,
            processedImage: enhanced,
          ),
        );

        processing = false;

        status = '${scans.length} صفحه آماده است';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        processing = false;
        status = 'خطا در پردازش تصویر: $e';
      });
    }
  }

  // ==========================================================
  // DEFAULT CORNERS
  // ==========================================================

  DocumentCorners _defaultCorners(img.Image image) {
    final marginX = image.width * .08;
    final marginY = image.height * .08;

    return DocumentCorners(
      topLeft: Offset(marginX, marginY),
      topRight: Offset(image.width - marginX, marginY),
      bottomRight: Offset(image.width - marginX, image.height - marginY),
      bottomLeft: Offset(marginX, image.height - marginY),
    );
  }

  // ==========================================================
  // OPEN SAVE PREVIEW
  // ==========================================================

  Future<void> _openSavePreview() async {
    if (scans.isEmpty || processing) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SavePreviewPage(
          scans: scans,
          onEdit: _editScan,
          onDelete: _deleteScan,
        ),
      ),
    );

    if (!mounted) return;

    setState(() {
      status = scans.isEmpty
          ? 'سند را مقابل دوربین قرار دهید'
          : '${scans.length} صفحه آماده است';
    });
  }

  // ==========================================================
  // EDIT SCAN
  // ==========================================================

  Future<void> _editScan(int index) async {
    if (index < 0 || index >= scans.length) {
      return;
    }

    final item = scans[index];

    final result = await Navigator.of(context).push<ScanItem>(
      MaterialPageRoute(
        builder: (_) => CropEditorPage(item: item, filter: selectedFilter),
      ),
    );

    if (result == null || !mounted) {
      return;
    }

    setState(() {
      scans[index] = result;

      status = '${scans.length} صفحه آماده است';
    });
  }

  // ==========================================================
  // DELETE SCAN
  // ==========================================================

  void _deleteScan(int index) {
    if (index < 0 || index >= scans.length) {
      return;
    }

    setState(() {
      scans.removeAt(index);

      status = scans.isEmpty
          ? 'سند را مقابل دوربین قرار دهید'
          : '${scans.length} صفحه آماده است';
    });
  }

  // ==========================================================
  // DISPOSE
  // ==========================================================

  @override
  void dispose() {
    _cameraController?.dispose();

    super.dispose();
  }
}

// ============================================================
// CROP EDITOR PAGE
// ============================================================

class CropEditorPage extends StatefulWidget {
  final ScanItem item;

  final ScanFilter filter;

  const CropEditorPage({super.key, required this.item, required this.filter});

  @override
  State<CropEditorPage> createState() => _CropEditorPageState();
}

class _CropEditorPageState extends State<CropEditorPage> {
  late DocumentCorners corners;

  late img.Image image;

  bool processing = false;

  int? activeCorner;

  static const double zoomSize = 135;

  static const double zoomFactor = 4;

  @override
  void initState() {
    super.initState();

    image = widget.item.originalImage;
    corners = widget.item.corners.copy();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,

      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('تنظیم برش'),
        actions: [
          TextButton.icon(
            onPressed: processing ? null : _applyChanges,
            icon: const Icon(Icons.check),
            label: const Text('اعمال'),
          ),
        ],
      ),

      body: processing
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _editor(),

      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'گوشه‌های سند را جابه‌جا کنید',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withOpacity(.8)),
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // EDITOR
  // ==========================================================

  Widget _editor() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final imageWidth = image.width.toDouble();

        final imageHeight = image.height.toDouble();

        double displayWidth = constraints.maxWidth;

        double displayHeight = displayWidth * imageHeight / imageWidth;

        if (displayHeight > constraints.maxHeight) {
          displayHeight = constraints.maxHeight;

          displayWidth = displayHeight * imageWidth / imageHeight;
        }

        final scaleX = displayWidth / imageWidth;

        final scaleY = displayHeight / imageHeight;

        final displayCorners = DocumentCorners(
          topLeft: Offset(
            corners.topLeft.dx * scaleX,
            corners.topLeft.dy * scaleY,
          ),
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

  // ==========================================================
  // HANDLES
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
                BoxShadow(color: Colors.black45, blurRadius: 7),
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
  // MOVE CORNER
  // ==========================================================

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
      updated.dx.clamp(0, image.width.toDouble()),
      updated.dy.clamp(0, image.height.toDouble()),
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

  // ==========================================================
  // ZOOM
  // ==========================================================

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
        image: image,
        point: originalPoint,
        size: zoomSize,
        zoom: zoomFactor,
      ),
    );
  }

  // ==========================================================
  // APPLY
  // ==========================================================

  Future<void> _applyChanges() async {
    try {
      setState(() {
        processing = true;
      });

      final rectified = await Future(() {
        return PerspectiveCorrector.rectify(image, corners);
      });

      final enhanced = await Future(() {
        return ImageEnhancer.apply(rectified, widget.filter);
      });

      final bytes = Uint8List.fromList(img.encodeJpg(enhanced, quality: 100));

      final updated = ScanItem(
        originalBytes: widget.item.originalBytes,
        originalImage: image,
        corners: corners,
        processedBytes: bytes,
        processedImage: enhanced,
      );

      if (!mounted) return;

      Navigator.of(context).pop(updated);
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
}

// ============================================================
// SAVE PREVIEW PAGE
// ============================================================

class SavePreviewPage extends StatefulWidget {
  final List<ScanItem> scans;

  final Future<void> Function(int index) onEdit;

  final void Function(int index) onDelete;

  const SavePreviewPage({
    super.key,
    required this.scans,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<SavePreviewPage> createState() => _SavePreviewPageState();
}

class _SavePreviewPageState extends State<SavePreviewPage> {
  late TextEditingController nameController;

  bool saving = false;

  @override
  void initState() {
    super.initState();

    nameController = TextEditingController(text: _defaultFileName());
  }

  String _defaultFileName() {
    final now = DateTime.now();

    String two(int value) => value.toString().padLeft(2, '0');

    return 'scan_${now.year}'
        '${two(now.month)}'
        '${two(now.day)}_'
        '${two(now.hour)}'
        '${two(now.minute)}'
        '${two(now.second)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('پیش‌نمایش و ذخیره')),

      body: Column(
        children: [
          // ----------------------------------------------------
          // FILE NAME
          // ----------------------------------------------------
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: TextField(
              controller: nameController,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: 'نام فایل',
                prefixIcon: const Icon(Icons.edit),
                suffixText: widget.scans.length == 1 ? '.jpg' : '.pdf',
                border: const OutlineInputBorder(),
              ),
            ),
          ),

          // ----------------------------------------------------
          // INFO
          // ----------------------------------------------------
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(
              children: [
                Text(
                  '${widget.scans.length} صفحه',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  widget.scans.length == 1 ? 'JPG' : 'PDF',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // ----------------------------------------------------
          // PREVIEW
          // ----------------------------------------------------
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: widget.scans.length,
              itemBuilder: (context, index) {
                final scan = widget.scans[index];

                return _buildPreviewItem(index, scan);
              },
            ),
          ),
        ],
      ),

      // --------------------------------------------------------
      // SAVE BUTTON
      // --------------------------------------------------------
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: saving ? null : _save,
            icon: saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save),
            label: Text(saving ? 'در حال ذخیره...' : 'ذخیره'),
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // PREVIEW ITEM
  // ==========================================================

  Widget _buildPreviewItem(int index, ScanItem scan) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await widget.onEdit(index);

          if (mounted) {
            setState(() {});
          }
        },
        child: SizedBox(
          height: 190,
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.memory(scan.processedBytes, fit: BoxFit.contain),
              ),

              // ------------------------------------------------
              // PAGE NUMBER
              // ------------------------------------------------
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    'صفحه ${index + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              // ------------------------------------------------
              // DELETE
              // ------------------------------------------------
              Positioned(
                top: 5,
                right: 5,
                child: IconButton.filledTonal(
                  onPressed: () {
                    setState(() {
                      widget.onDelete(index);
                    });
                  },
                  icon: const Icon(Icons.delete_outline),
                ),
              ),

              // ------------------------------------------------
              // EDIT
              // ------------------------------------------------
              Positioned(
                bottom: 8,
                right: 8,
                child: FilledButton.tonalIcon(
                  onPressed: () async {
                    await widget.onEdit(index);

                    if (mounted) {
                      setState(() {});
                    }
                  },
                  icon: const Icon(Icons.crop),
                  label: const Text('اصلاح برش'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // SAVE
  // ==========================================================

  Future<void> _save() async {
    if (widget.scans.isEmpty) return;

    try {
      setState(() {
        saving = true;
      });

      String filename = nameController.text.trim();

      if (filename.isEmpty) {
        filename = _defaultFileName();
      }

      filename = _sanitizeFileName(filename);

      final directory = await getApplicationDocumentsDirectory();

      final scanDirectory = Directory(
        path.join(directory.path, 'scanned_documents'),
      );

      if (!await scanDirectory.exists()) {
        await scanDirectory.create(recursive: true);
      }

      // --------------------------------------------------------
      // SINGLE IMAGE
      // --------------------------------------------------------

      if (widget.scans.length == 1) {
        final outputPath = path.join(scanDirectory.path, '$filename.jpg');

        final file = File(outputPath);

        await file.writeAsBytes(widget.scans.first.processedBytes, flush: true);

        if (!mounted) return;

        await _showSavedDialog(outputPath);

        return;
      }

      // --------------------------------------------------------
      // MULTIPLE -> PDF
      // --------------------------------------------------------

      final document = pw.Document();

      for (final scan in widget.scans) {
        final imageProvider = pw.MemoryImage(scan.processedBytes);

        document.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(0),
            build: (context) {
              return pw.Center(
                child: pw.Image(imageProvider, fit: pw.BoxFit.contain),
              );
            },
          ),
        );
      }

      final pdfBytes = await document.save();

      final outputPath = path.join(scanDirectory.path, '$filename.pdf');

      final file = File(outputPath);

      await file.writeAsBytes(pdfBytes, flush: true);

      if (!mounted) return;

      await _showSavedDialog(outputPath);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطا در ذخیره فایل: $e')));
    } finally {
      if (mounted) {
        setState(() {
          saving = false;
        });
      }
    }
  }

  // ==========================================================
  // SANITIZE
  // ==========================================================

  String _sanitizeFileName(String value) {
    return value.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }

  // ==========================================================
  // SAVED DIALOG
  // ==========================================================

  Future<void> _showSavedDialog(String outputPath) async {
    setState(() {
      saving = false;
    });

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('ذخیره شد'),
            ],
          ),
          content: Text(
            'فایل با موفقیت ذخیره شد.\n\n$outputPath',
            textDirection: TextDirection.ltr,
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();

                Navigator.of(context).pop();
              },
              child: const Text('باشه'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    nameController.dispose();
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

    if (points.length != 4) return;

    final documentPath = Path()
      ..moveTo(points[0].dx, points[0].dy)
      ..lineTo(points[1].dx, points[1].dy)
      ..lineTo(points[2].dx, points[2].dy)
      ..lineTo(points[3].dx, points[3].dy)
      ..close();

    canvas.drawPath(
      documentPath,
      Paint()
        ..color = Colors.teal.withOpacity(.12)
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
            Image.memory(bytes!, fit: BoxFit.cover)
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
