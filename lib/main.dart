import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:document_scanner/core/image_enhancer.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'core/document_detector.dart';
import 'core/perspective_corrector.dart';
import 'models/document_corners.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  List<CameraDescription> cameras = [];

  try {
    cameras = await availableCameras();
  } catch (_) {
    cameras = [];
  }

  runApp(DocumentScannerApp(cameras: cameras));
}

// ============================================================
// APP
// ============================================================

class DocumentScannerApp extends StatelessWidget {
  final List<CameraDescription> cameras;

  const DocumentScannerApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'اسکنر سند',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
        fontFamily: 'Tahoma',
      ),
      home: ScannerPage(cameras: cameras),
    );
  }
}

// ============================================================
// SCANNED PAGE MODEL
// ============================================================

class ScannedPage {
  final String id;

  final Uint8List originalBytes;

  final img.Image originalImage;

  DocumentCorners corners;

  Uint8List? previewBytes;

  Uint8List? finalBytes;

  ScannedPage({
    required this.id,
    required this.originalBytes,
    required this.originalImage,
    required this.corners,
    this.previewBytes,
    this.finalBytes,
  });
}

// ============================================================
// SCANNER PAGE
// ============================================================

class ScannerPage extends StatefulWidget {
  final List<CameraDescription> cameras;

  const ScannerPage({super.key, required this.cameras});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  // ==========================================================
  // CAMERA
  // ==========================================================

  CameraController? _cameraController;

  bool cameraAvailable = false;
  bool cameraInitialized = false;

  // ==========================================================
  // STATE
  // ==========================================================

  bool processing = false;

  String status = 'دوربین آماده نیست';

  ScanFilter selectedFilter = ScanFilter.document;

  // ==========================================================
  // SCANNED PAGES
  // ==========================================================

  final List<ScannedPage> pages = [];

  int? editingPageIndex;

  // ==========================================================
  // CAMERA INITIALIZATION
  // ==========================================================

  @override
  void initState() {
    super.initState();

    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (widget.cameras.isEmpty) {
      if (mounted) {
        setState(() {
          cameraAvailable = false;
          cameraInitialized = true;
          status = 'دوربین در دسترس نیست؛ تصویر انتخاب کنید';
        });
      }

      return;
    }

    try {
      CameraDescription selectedCamera = widget.cameras.first;

      // اولویت با دوربین پشت در موبایل
      for (final camera in widget.cameras) {
        if (camera.lensDirection == CameraLensDirection.back) {
          selectedCamera = camera;
          break;
        }
      }

      final controller = CameraController(
        selectedCamera,
        ResolutionPreset.max,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      _cameraController = controller;

      setState(() {
        cameraAvailable = true;
        cameraInitialized = true;
        status = 'دوربین آماده است';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        cameraAvailable = false;
        cameraInitialized = true;
        status = 'دوربین در دسترس نیست؛ تصویر انتخاب کنید';
      });
    }
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildMainContent()),

            _buildBottomPanel(),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // APP BAR
  // ==========================================================

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      centerTitle: true,
      title: const Text(
        'اسکنر سند',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      actions: [
        if (pages.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${pages.length} صفحه',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ==========================================================
  // MAIN CONTENT
  // ==========================================================

  Widget _buildMainContent() {
    if (editingPageIndex != null) {
      return _buildEditor();
    }

    if (pages.isEmpty) {
      return _buildCameraOrEmpty();
    }

    return _buildPreview();
  }

  // ==========================================================
  // CAMERA / EMPTY
  // ==========================================================

  Widget _buildCameraOrEmpty() {
    if (cameraAvailable &&
        cameraInitialized &&
        _cameraController != null &&
        _cameraController!.value.isInitialized) {
      return _buildCamera();
    }

    return _buildEmptyState();
  }

  // ==========================================================
  // CAMERA
  // ==========================================================

  Widget _buildCamera() {
    final controller = _cameraController!;

    return Column(
      children: [
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(12),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(controller),

                // تاریک کردن اطراف
                IgnorePointer(
                  child: CustomPaint(painter: CameraGuidePainter()),
                ),

                // راهنما
                Positioned(
                  left: 20,
                  right: 20,
                  top: 20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'سند را داخل کادر قرار دهید',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ),
                ),

                if (processing)
                  Container(
                    color: Colors.black45,
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // EMPTY STATE
  // ==========================================================

  Widget _buildEmptyState() {
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

            const SizedBox(height: 12),

            Text(
              'دوربین در دسترس نیست.\nمی‌توانید تصویر سند را از روی سیستم انتخاب کنید.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),

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
  // PREVIEW
  // ==========================================================

  Widget _buildPreview() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'پیش‌نمایش اسکن',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),

              Text(
                '${pages.length} صفحه',
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ],
          ),
        ),

        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 260,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: .72,
            ),
            itemCount: pages.length,
            itemBuilder: (context, index) {
              return _buildPageCard(index);
            },
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // PAGE CARD
  // ==========================================================

  Widget _buildPageCard(int index) {
    final page = pages[index];

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 3,
      child: InkWell(
        onTap: processing
            ? null
            : () {
                _openEditor(index);
              },
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                color: Colors.grey.shade100,
                padding: const EdgeInsets.all(8),
                child: page.previewBytes != null
                    ? Image.memory(
                        page.previewBytes!,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      )
                    : const Center(child: CircularProgressIndicator()),
              ),
            ),

            // شماره صفحه
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(.7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            // حذف
            Positioned(
              top: 4,
              left: 4,
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: 'حذف',
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () {
                    _removePage(index);
                  },
                ),
              ),
            ),

            // ویرایش
            Positioned(
              bottom: 8,
              left: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(.65),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.crop, size: 17, color: Colors.white),
                    SizedBox(width: 6),
                    Text(
                      'ویرایش برش',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // BOTTOM PANEL
  // ==========================================================

  Widget _buildBottomPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: const [BoxShadow(blurRadius: 12, color: Colors.black12)],
      ),
      child: Column(
        children: [
          if (status.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                status,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),

          Row(
            children: [
              // انتخاب فایل
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: processing ? null : pickImage,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('انتخاب فایل'),
                ),
              ),

              const SizedBox(width: 10),

              // دوربین / شاتر
              if (cameraAvailable) _buildShutterButton(),

              if (cameraAvailable) const SizedBox(width: 10),

              // ذخیره
              if (pages.isNotEmpty)
                Expanded(
                  child: FilledButton.icon(
                    onPressed: processing ? null : saveAll,
                    icon: const Icon(Icons.save),
                    label: const Text('ذخیره'),
                  ),
                ),
            ],
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
      onTap: processing ? null : capturePhoto,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.primary,
          border: Border.all(color: Colors.white, width: 4),
          boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black26)],
        ),
        child: processing
            ? const Padding(
                padding: EdgeInsets.all(17),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.camera_alt, color: Colors.white, size: 28),
      ),
    );
  }

  // ==========================================================
  // CAPTURE PHOTO
  // ==========================================================

  Future<void> capturePhoto() async {
    if (_cameraController == null) {
      return;
    }

    if (!_cameraController!.value.isInitialized) {
      return;
    }

    if (processing) {
      return;
    }

    try {
      setState(() {
        processing = true;
        status = 'در حال گرفتن تصویر...';
      });

      final XFile file = await _cameraController!.takePicture();

      final bytes = await file.readAsBytes();

      await _processImage(bytes);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        processing = false;
        status = 'خطا در گرفتن تصویر: $e';
      });
    }
  }

  // ==========================================================
  // PICK IMAGE
  // ==========================================================

  Future<void> pickImage() async {
    if (processing) {
      return;
    }

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

      if (result == null) {
        if (!mounted) return;

        setState(() {
          processing = false;
          status = pages.isEmpty ? 'تصویری انتخاب نشد' : 'آماده اسکن صفحه بعدی';
        });

        return;
      }

      final selected = result.files.single;

      Uint8List? bytes = selected.bytes;

      if (bytes == null && selected.path != null) {
        bytes = await File(selected.path!).readAsBytes();
      }

      if (bytes == null) {
        throw Exception('خواندن فایل ممکن نیست');
      }

      await _processImage(bytes);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        processing = false;
        status = 'خطا: $e';
      });
    }
  }

  // ==========================================================
  // PROCESS IMAGE
  // ==========================================================

  Future<void> _processImage(Uint8List bytes) async {
    try {
      setState(() {
        processing = true;
        status = 'در حال آماده‌سازی تصویر...';
      });

      final decoded = img.decodeImage(bytes);

      if (decoded == null) {
        throw Exception('فرمت تصویر قابل تشخیص نیست');
      }

      // EXIF
      final fixed = img.bakeOrientation(decoded);

      final fixedBytes = Uint8List.fromList(img.encodeJpg(fixed, quality: 95));

      setState(() {
        status = 'در حال تشخیص برگه...';
      });

      await Future.delayed(const Duration(milliseconds: 30));

      final detected = await Future(() {
        return DocumentDetector.detect(fixed);
      });

      final documentCorners = detected ?? _defaultCorners(fixed);

      final page = ScannedPage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        originalBytes: fixedBytes,
        originalImage: fixed,
        corners: documentCorners,
      );

      // بلافاصله پیش‌نمایش برش‌خورده
      setState(() {
        pages.add(page);
        status = 'صفحه ${pages.length} آماده است';
      });

      await _generatePreview(page);

      if (!mounted) return;

      setState(() {
        processing = false;
        status = 'صفحه ${pages.length} اضافه شد؛ برای اصلاح روی تصویر بزنید';
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
  // GENERATE PREVIEW
  // ==========================================================

  Future<void> _generatePreview(ScannedPage page) async {
    final result = await Future(() {
      return PerspectiveCorrector.rectify(page.originalImage, page.corners);
    });

    final enhanced = await Future(() {
      return ImageEnhancer.apply(result, selectedFilter);
    });

    final jpg = Uint8List.fromList(img.encodeJpg(enhanced, quality: 95));

    page.previewBytes = jpg;
    page.finalBytes = jpg;

    if (mounted) {
      setState(() {});
    }
  }

  // ==========================================================
  // OPEN EDITOR
  // ==========================================================

  void _openEditor(int index) {
    if (index < 0 || index >= pages.length) {
      return;
    }

    setState(() {
      editingPageIndex = index;
      status = 'گوشه‌های سند را جابه‌جا کنید';
    });
  }

  // ==========================================================
  // EDITOR
  // ==========================================================

  Widget _buildEditor() {
    if (editingPageIndex == null) {
      return const SizedBox.shrink();
    }

    final page = pages[editingPageIndex!];

    return LayoutBuilder(
      builder: (context, constraints) {
        final imageWidth = page.originalImage.width.toDouble();

        final imageHeight = page.originalImage.height.toDouble();

        double displayWidth = constraints.maxWidth - 24;

        double displayHeight = displayWidth * imageHeight / imageWidth;

        if (displayHeight > constraints.maxHeight - 100) {
          displayHeight = constraints.maxHeight - 100;

          displayWidth = displayHeight * imageWidth / imageHeight;
        }

        final scaleX = displayWidth / imageWidth;

        final scaleY = displayHeight / imageHeight;

        final displayCorners = DocumentCorners(
          topLeft: Offset(
            page.corners.topLeft.dx * scaleX,
            page.corners.topLeft.dy * scaleY,
          ),
          topRight: Offset(
            page.corners.topRight.dx * scaleX,
            page.corners.topRight.dy * scaleY,
          ),
          bottomRight: Offset(
            page.corners.bottomRight.dx * scaleX,
            page.corners.bottomRight.dy * scaleY,
          ),
          bottomLeft: Offset(
            page.corners.bottomLeft.dx * scaleX,
            page.corners.bottomLeft.dy * scaleY,
          ),
        );

        return Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'بازگشت',
                    onPressed: processing
                        ? null
                        : () {
                            setState(() {
                              editingPageIndex = null;
                              status = 'برای افزودن صفحه جدید، عکس بگیرید';
                            });
                          },
                    icon: const Icon(Icons.arrow_back),
                  ),

                  const Expanded(
                    child: Text(
                      'اصلاح برش',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),

                  FilledButton.icon(
                    onPressed: processing ? null : () => _applyEditor(page),
                    icon: const Icon(Icons.check),
                    label: const Text('اعمال'),
                  ),
                ],
              ),
            ),

            Expanded(
              child: Center(
                child: SizedBox(
                  width: displayWidth,
                  height: displayHeight,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // IMAGE
                      Positioned.fill(
                        child: Image.memory(
                          page.originalBytes,
                          fit: BoxFit.fill,
                          filterQuality: FilterQuality.high,
                        ),
                      ),

                      // DOCUMENT
                      Positioned.fill(
                        child: CustomPaint(
                          painter: DocumentPainter(displayCorners),
                        ),
                      ),

                      // HANDLES
                      ..._editorHandles(page, displayCorners, scaleX, scaleY),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'نقاط گوشه‌های سند را جابه‌جا کنید',
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ),
          ],
        );
      },
    );
  }

  // ==========================================================
  // EDITOR HANDLES
  // ==========================================================

  List<Widget> _editorHandles(
    ScannedPage page,
    DocumentCorners displayCorners,
    double scaleX,
    double scaleY,
  ) {
    final points = displayCorners.points;

    return List.generate(points.length, (index) {
      final point = points[index];

      return Positioned(
        left: point.dx - 25,
        top: point.dy - 25,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (details) {
            _moveCorner(
              page,
              index,
              Offset(details.delta.dx / scaleX, details.delta.dy / scaleY),
            );
          },
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.teal,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [
                BoxShadow(color: Colors.black45, blurRadius: 8),
              ],
            ),
            child: const Icon(Icons.open_with, color: Colors.white),
          ),
        ),
      );
    });
  }

  // ==========================================================
  // MOVE CORNER
  // ==========================================================

  void _moveCorner(ScannedPage page, int index, Offset delta) {
    final c = page.corners.copy();

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
      updated.dx.clamp(0, page.originalImage.width.toDouble()),
      updated.dy.clamp(0, page.originalImage.height.toDouble()),
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

    page.corners = c;

    setState(() {});
  }

  // ==========================================================
  // APPLY EDITOR
  // ==========================================================

  Future<void> _applyEditor(ScannedPage page) async {
    try {
      setState(() {
        processing = true;
        status = 'در حال اعمال برش...';
      });

      await _generatePreview(page);

      if (!mounted) return;

      setState(() {
        processing = false;
        editingPageIndex = null;
        status = 'برش اعمال شد؛ برای ادامه عکس بگیرید';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        processing = false;
        status = 'خطا در اعمال برش: $e';
      });
    }
  }

  // ==========================================================
  // REMOVE PAGE
  // ==========================================================

  void _removePage(int index) {
    if (index < 0 || index >= pages.length) {
      return;
    }

    setState(() {
      pages.removeAt(index);

      if (pages.isEmpty) {
        status = cameraAvailable ? 'آماده گرفتن تصویر' : 'تصویر انتخاب کنید';
      } else {
        status = '${pages.length} صفحه آماده است';
      }
    });
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
  // SAVE ALL
  // ==========================================================

  Future<void> saveAll() async {
    if (pages.isEmpty) {
      return;
    }

    final defaultName = _defaultFileName();

    final nameController = TextEditingController(text: defaultName);

    final fileName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('ذخیره اسکن'),
          content: TextField(
            controller: nameController,
            autofocus: true,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: 'نام فایل',
              hintText: defaultName,
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context, nameController.text.trim());
              },
              child: const Text('ذخیره'),
            ),
          ],
        );
      },
    );

    nameController.dispose();

    if (fileName == null || fileName.trim().isEmpty) {
      return;
    }

    try {
      setState(() {
        processing = true;
        status = 'در حال آماده‌سازی فایل...';
      });

      final directory = await getApplicationDocumentsDirectory();

      final scanDirectory = Directory(
        path.join(directory.path, 'scanned_documents'),
      );

      if (!await scanDirectory.exists()) {
        await scanDirectory.create(recursive: true);
      }

      if (pages.length == 1) {
        await _saveJpg(scanDirectory, fileName);
      } else {
        await _savePdf(scanDirectory, fileName);
      }

      if (!mounted) return;

      setState(() {
        processing = false;
        status = 'فایل با موفقیت ذخیره شد';
      });

      await _showSavedDialog(fileName, scanDirectory);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        processing = false;
        status = 'خطا در ذخیره: $e';
      });
    }
  }

  // ==========================================================
  // SAVE JPG
  // ==========================================================

  Future<void> _saveJpg(Directory directory, String fileName) async {
    final page = pages.first;

    if (page.finalBytes == null) {
      await _generatePreview(page);
    }

    final outputPath = path.join(directory.path, '$fileName.jpg');

    await File(outputPath).writeAsBytes(page.finalBytes!, flush: true);
  }

  // ==========================================================
  // SAVE PDF
  // ==========================================================

  Future<void> _savePdf(Directory directory, String fileName) async {
    final document = pw.Document();

    for (final page in pages) {
      if (page.finalBytes == null) {
        await _generatePreview(page);
      }

      final image = pw.MemoryImage(page.finalBytes!);

      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(0),
          build: (context) {
            return pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain));
          },
        ),
      );
    }

    final outputPath = path.join(directory.path, '$fileName.pdf');

    await File(outputPath).writeAsBytes(await document.save(), flush: true);
  }

  // ==========================================================
  // DEFAULT FILE NAME
  // ==========================================================

  String _defaultFileName() {
    final now = DateTime.now();

    String two(int value) => value.toString().padLeft(2, '0');

    return 'scan_${now.year}-'
        '${two(now.month)}-'
        '${two(now.day)}_'
        '${two(now.hour)}-'
        '${two(now.minute)}-'
        '${two(now.second)}';
  }

  // ==========================================================
  // SAVED DIALOG
  // ==========================================================

  Future<void> _showSavedDialog(String fileName, Directory directory) async {
    final extension = pages.length == 1 ? 'jpg' : 'pdf';

    final fullPath = path.join(directory.path, '$fileName.$extension');

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
          title: const Text('ذخیره شد'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$fileName.$extension',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 12),

              SelectableText(
                fullPath,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(context);

                setState(() {
                  pages.clear();
                  editingPageIndex = null;

                  status = cameraAvailable
                      ? 'آماده گرفتن تصویر بعدی'
                      : 'تصویر انتخاب کنید';
                });
              },
              child: const Text('اسکن جدید'),
            ),
          ],
        );
      },
    );
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
// CAMERA GUIDE
// ============================================================

class CameraGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(.25)
      ..style = PaintingStyle.fill;

    final documentWidth = size.width * .82;

    final documentHeight = documentWidth * 1.414;

    final left = (size.width - documentWidth) / 2;

    final top = (size.height - documentHeight) / 2;

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, documentWidth, documentHeight),
      const Radius.circular(12),
    );

    // فعلاً فقط کادر راهنما
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawRRect(rect, borderPaint);

    // چهار گوشه
    final cornerPaint = Paint()
      ..color = Colors.tealAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;

    const length = 30.0;

    // top-left
    canvas.drawLine(Offset(left, top), Offset(left + length, top), cornerPaint);

    canvas.drawLine(Offset(left, top), Offset(left, top + length), cornerPaint);

    // top-right
    canvas.drawLine(
      Offset(left + documentWidth, top),
      Offset(left + documentWidth - length, top),
      cornerPaint,
    );

    canvas.drawLine(
      Offset(left + documentWidth, top),
      Offset(left + documentWidth, top + length),
      cornerPaint,
    );

    // bottom-left
    canvas.drawLine(
      Offset(left, top + documentHeight),
      Offset(left + length, top + documentHeight),
      cornerPaint,
    );

    canvas.drawLine(
      Offset(left, top + documentHeight),
      Offset(left, top + documentHeight - length),
      cornerPaint,
    );

    // bottom-right
    canvas.drawLine(
      Offset(left + documentWidth, top + documentHeight),
      Offset(left + documentWidth - length, top + documentHeight),
      cornerPaint,
    );

    canvas.drawLine(
      Offset(left + documentWidth, top + documentHeight),
      Offset(left + documentWidth, top + documentHeight - length),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CameraGuidePainter oldDelegate) {
    return false;
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
