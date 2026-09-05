import 'dart:async';
import 'dart:collection';

import 'dart:io';

import 'dart:math' as math;

import 'dart:typed_data';

import 'package:camera/camera.dart';

import 'package:file_picker/file_picker.dart';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';

import 'package:image/image.dart' as img;

import 'package:path/path.dart' as path;

import 'package:path_provider/path_provider.dart';

import 'package:pdf/pdf.dart';

import 'package:pdf/widgets.dart' as pw;

import 'package:flutter/services.dart';

import 'core/image_processor.dart';

import 'core/image_enhancer.dart';

import 'models/document_corners.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await FastScannerBridge.initialize();

  runApp(const DocumentScannerApp());
}
// ============================================================
// SCAN REQUEST
// ============================================================

class ScanRequest {
  final String? recordId;

  final String? returnPackage;

  final String? returnAction;

  final bool isExternalScan;

  const ScanRequest({
    this.recordId,

    this.returnPackage,

    this.returnAction,

    this.isExternalScan = false,
  });

  factory ScanRequest.fromMap(Map<dynamic, dynamic> map) {
    return ScanRequest(
      recordId: map['record_id']?.toString(),

      returnPackage: map['return_package']?.toString(),

      returnAction: map['return_action']?.toString(),

      isExternalScan: map['is_external_scan'] == true,
    );
  }
}
// ============================================================
// FAST SCANNER BRIDGE
// ============================================================

class FastScannerBridge {
  static const MethodChannel _channel = MethodChannel('fastscanner/intent');

  static ScanRequest? _request;

  static Future<ScanRequest> initialize() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getScanRequest',
      );

      if (result == null) {
        _request = const ScanRequest();

        return _request!;
      }

      _request = ScanRequest.fromMap(result);

      return _request!;
    } catch (e) {
      debugPrint('FastScannerBridge initialize error: $e');

      _request = const ScanRequest();

      return _request!;
    }
  }

  static ScanRequest? get request => _request;

  static Future<bool> completeScan({
    required String outputPath,

    required String mimeType,

    required String recordId,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'completeScan',

        {
          'output_path': outputPath,

          'mime_type': mimeType,

          'record_id': recordId,
        },
      );

      return result?['returned'] == true;
    } catch (e) {
      debugPrint('FastScannerBridge completeScan error: $e');

      return false;
    }
  }

  static Future<void> cancelScan() async {
    try {
      await _channel.invokeMethod('cancelScan');
    } catch (e) {
      debugPrint('FastScannerBridge cancel error: $e');
    }
  }
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
  final Uint8List originalBytes;

  /// تصویر Decode شده را فقط زمانی نگه می‌داریم که لازم باشد.
  ///
  /// برای جلوگیری از Decode مجدد روی UI بعد از هر عکس،
  /// این مقدار می‌تواند null باشد و در زمان ورود به ادیتور Decode شود.

  img.Image? originalImage;

  final DocumentCorners corners;

  final Uint8List processedBytes;

  ScanItem({
    required this.originalBytes,

    required this.originalImage,

    required this.corners,

    required this.processedBytes,
  });
}
// ============================================================
// SCANNER PAGE
// ============================================================

class _PendingCapture {
  final String path;
  final int filterIndex;

  const _PendingCapture({required this.path, required this.filterIndex});
}

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  // ==========================================================
  // CAMERA
  // ==========================================================

  ScanRequest? scanRequest;

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
  // PENDING PHOTO
  // ==========================================================

  String? _pendingPhotoPath;

  // Queue of captured photos waiting for processing.
  final Queue<_PendingCapture> _captureQueue = Queue<_PendingCapture>();

  // Only one heavy image-processing job runs at a time.
  bool _captureWorkerRunning = false;

  // Path of the image currently being processed.
  String? _processingPhotoPath;
  // ==========================================================
  // EXTERNAL SCAN
  // ==========================================================

  bool get isExternalScan {
    return scanRequest?.isExternalScan == true && scanRequest?.recordId != null;
  }

  String? get externalRecordId {
    return scanRequest?.recordId;
  }
  // ==========================================================
  // INIT
  // ==========================================================

  @override
  void initState() {
    super.initState();

    scanRequest = FastScannerBridge.request;

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

      CameraDescription selectedCamera = _cameras.first;

      for (final camera in _cameras) {
        if (camera.lensDirection == CameraLensDirection.back) {
          selectedCamera = camera;

          break;
        }
      }
      // ======================================================
      // PERFORMANCE
      // ======================================================
      //
      // max برای اسکن خیلی سنگین است.
      //
      // high معمولاً برای Document Scanner تعادل بسیار خوبی
      // بین کیفیت، حجم عکس و سرعت پردازش دارد.
      //
      // اگر روی گوشی قدرتمند کیفیت بیشتری خواستی می‌توانی
      // آن را به veryHigh تغییر بدهی.
      //

      final controller = CameraController(
        selectedCamera,

        ResolutionPreset.high,

        enableAudio: false,

        imageFormatGroup: ImageFormatGroup.jpeg,
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
            _buildTopBar(),

            Expanded(child: _buildCameraArea()),

            _buildStatusBar(),

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
            _glassButton(
              icon: Icons.close,

              onPressed: () {
                Navigator.of(context).maybePop();
              },
            ),

            const Spacer(),

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

    final previewSize = controller.value.previewSize;

    if (previewSize == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return Container(
      width: double.infinity,

      color: Colors.black,

      alignment: Alignment.center,

      child: FittedBox(
        fit: BoxFit.contain,

        child: SizedBox(
          width: previewSize.height,

          height: previewSize.width,

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
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,

              child: _buildFileButton(),
            ),
          ),

          Expanded(child: Center(child: _buildShutterButton())),

          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,

              child: scans.isEmpty && _pendingPhotoPath == null
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
    final enabled = cameraAvailable && !takingPicture;

    return GestureDetector(
      onTap: enabled ? capturePhoto : null,

      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),

        width: 78,

        height: 78,

        decoration: BoxDecoration(
          shape: BoxShape.circle,

          color: enabled ? Colors.white : Colors.white24,

          border: Border.all(color: Colors.white70, width: 4),

          boxShadow: const [
            BoxShadow(color: Colors.black54, blurRadius: 12, spreadRadius: 2),
          ],
        ),

        child: takingPicture || processing
            ? const Padding(
                padding: EdgeInsets.all(23),

                child: CircularProgressIndicator(strokeWidth: 3),
              )
            : Icon(
                Icons.camera_alt,

                color: enabled ? Colors.black87 : Colors.white38,

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

      onTap: processing || scans.isEmpty ? null : _openSavePreview,

      child: SizedBox(
        width: 86,

        height: 82,

        child: Stack(
          clipBehavior: Clip.none,

          alignment: Alignment.center,

          children: [
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

            if (scans.isNotEmpty)
              Positioned(
                left: 17,

                top: 0,

                child: _thumbnailCard(scans.last, 61, 74),
              ),

            // ==================================================
            // PENDING PHOTO
            // ==================================================
            if (_pendingPhotoPath != null)
              Positioned(left: 17, top: 0, child: _pendingThumbnail()),

            if (scans.isNotEmpty)
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

            if (_pendingPhotoPath != null)
              Positioned(
                right: -4,

                bottom: -2,

                child: Container(
                  width: 31,

                  height: 31,

                  alignment: Alignment.center,

                  decoration: BoxDecoration(
                    color: Colors.orange,

                    shape: BoxShape.circle,

                    border: Border.all(color: Colors.white, width: 2),
                  ),

                  child: const SizedBox(
                    width: 14,

                    height: 14,

                    child: CircularProgressIndicator(
                      strokeWidth: 2,

                      color: Colors.white,
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
  // PENDING THUMBNAIL
  // ==========================================================

  Widget _pendingThumbnail() {
    final filePath = _pendingPhotoPath;

    if (filePath == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: 61,

      height: 74,

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(7),

        border: Border.all(color: Colors.white, width: 2),

        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)],
      ),

      clipBehavior: Clip.antiAlias,

      child: Image.file(
        File(filePath),

        fit: BoxFit.cover,

        gaplessPlayback: true,

        filterQuality: FilterQuality.low,
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

        child: Image.memory(
          item.processedBytes,

          fit: BoxFit.cover,

          gaplessPlayback: true,

          filterQuality: FilterQuality.low,
        ),
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
    final controller = _cameraController;

    if (controller == null ||
        !controller.value.isInitialized ||
        takingPicture) {
      return;
    }

    try {
      setState(() {
        takingPicture = true;
        status = 'در حال گرفتن تصویر...';
      });

      // Only the camera capture is awaited here.
      // Image processing is queued and runs separately.
      final XFile file = await controller.takePicture();

      if (!mounted) {
        try {
          final tempFile = File(file.path);
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        } catch (_) {}
        return;
      }

      // Store the selected filter with the job. Changing the filter later
      // will not affect photos that are already in the queue.
      final filterIndex = ScanFilter.values.indexOf(selectedFilter);

      setState(() {
        takingPicture = false;
        _pendingPhotoPath = file.path;

        _captureQueue.add(
          _PendingCapture(path: file.path, filterIndex: filterIndex),
        );

        processing = true;
        status = _queueStatus();
      });

      // Do not await this. The camera is immediately available for the next shot.
      _processCaptureQueue();
    } catch (e, stack) {
      debugPrint('Capture error: $e');
      debugPrintStack(stackTrace: stack);

      if (!mounted) return;

      setState(() {
        takingPicture = false;
        status = 'خطا در گرفتن تصویر';
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطا در گرفتن تصویر: $e')));
    }
  }

  String _queueStatus() {
    final waiting = _captureQueue.length;
    final active = _processingPhotoPath != null;

    if (active && waiting > 0) {
      return 'در حال پردازش؛ $waiting عکس در صف';
    }

    if (active) {
      return 'در حال پردازش تصویر...';
    }

    if (waiting > 0) {
      return 'در صف پردازش؛ $waiting عکس';
    }

    return scans.isEmpty
        ? 'سند را مقابل دوربین قرار دهید'
        : '${scans.length} صفحه آماده است';
  }

  Future<void> _processCaptureQueue() async {
    if (_captureWorkerRunning) {
      return;
    }

    _captureWorkerRunning = true;

    try {
      while (_captureQueue.isNotEmpty) {
        final job = _captureQueue.removeFirst();
        _processingPhotoPath = job.path;

        if (mounted) {
          setState(() {
            processing = true;
            status = _queueStatus();
          });
        }

        try {
          // Read the file only when its turn arrives. This keeps all queued
          // high-resolution images out of RAM at the same time.
          final bytes = await File(job.path).readAsBytes();

          final result = await compute(processImageInIsolate, {
            'bytes': bytes,
            'filterIndex': job.filterIndex,
          });

          if (mounted) {
            await _addProcessedResult(result);
          }
        } catch (e, stack) {
          debugPrint('Queued image processing error: $e');
          debugPrintStack(stackTrace: stack);

          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('خطا در پردازش تصویر: $e')));
          }
        } finally {
          // The camera's temporary file is deleted only after processing.
          try {
            final tempFile = File(job.path);
            if (await tempFile.exists()) {
              await tempFile.delete();
            }
          } catch (_) {}

          if (_pendingPhotoPath == job.path) {
            _pendingPhotoPath = null;
          }

          _processingPhotoPath = null;

          if (mounted) {
            setState(() {
              processing = _captureQueue.isNotEmpty;
              status = _queueStatus();
            });
          }
        }
      }
    } finally {
      _captureWorkerRunning = false;

      if (mounted) {
        setState(() {
          processing = _captureQueue.isNotEmpty || _processingPhotoPath != null;
          status = _queueStatus();
        });
      }
    }
  }

  // ==========================================================
  // ADD PROCESSED RESULT
  // ==========================================================

  Future<void> _addProcessedResult(Map<String, dynamic> result) async {
    final originalBytes = result['originalBytes'] as Uint8List;

    final processedBytes = result['processedBytes'] as Uint8List;
    // ========================================================
    // IMPORTANT
    //
    // دیگر اینجا img.decodeImage انجام نمی‌دهیم.
    //
    // قبلاً بعد از پردازش، تصویر اصلی روی UI Decode می‌شد
    // و روی بعضی گوشی‌ها یک مکث کوتاه ایجاد می‌کرد.
    //
    // حالا originalImage = null است و فقط زمانی که کاربر
    // وارد Crop Editor شود Decode خواهد شد.
    // ========================================================

    final corners = DocumentCorners(
      topLeft: Offset(
        (result['topLeftX'] as num).toDouble(),

        (result['topLeftY'] as num).toDouble(),
      ),

      topRight: Offset(
        (result['topRightX'] as num).toDouble(),

        (result['topRightY'] as num).toDouble(),
      ),

      bottomRight: Offset(
        (result['bottomRightX'] as num).toDouble(),

        (result['bottomRightY'] as num).toDouble(),
      ),

      bottomLeft: Offset(
        (result['bottomLeftX'] as num).toDouble(),

        (result['bottomLeftY'] as num).toDouble(),
      ),
    );

    if (!mounted) {
      return;
    }

    setState(() {
      scans.add(
        ScanItem(
          originalBytes: originalBytes,

          originalImage: null,

          corners: corners,

          processedBytes: processedBytes,
        ),
      );
    });
  }
  // ==========================================================
  // PICK IMAGES
  // ==========================================================

  Future<void> pickImages() async {
    if (processing) {
      return;
    }

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
      if (!mounted) {
        return;
      }

      setState(() {
        processing = false;

        status = 'خطا در انتخاب تصویر: $e';
      });
    }
  }
  // ==========================================================
  // PROCESS FILE IMAGE
  // ==========================================================

  Future<void> _processAndAddImage(Uint8List bytes) async {
    if (!mounted) {
      return;
    }

    try {
      setState(() {
        processing = true;

        status = 'در حال پردازش تصویر...';
      });
      // ======================================================
      // ALL HEAVY WORK -> ISOLATE
      // ======================================================

      final filterIndex = ScanFilter.values.indexOf(selectedFilter);

      final result = await compute(processImageInIsolate, {
        'bytes': bytes,

        'filterIndex': filterIndex,
      });

      if (!mounted) {
        return;
      }

      await _addProcessedResult(result);

      if (!mounted) {
        return;
      }

      setState(() {
        processing = false;

        status = '${scans.length} صفحه آماده است';
      });
    } catch (e, stack) {
      debugPrint('File processing error: $e');

      debugPrintStack(stackTrace: stack);

      if (!mounted) {
        return;
      }

      setState(() {
        processing = false;

        status = 'خطا در پردازش تصویر: $e';
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطا در پردازش تصویر: $e')));
    }
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

    if (!mounted) {
      return;
    }

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

    for (final job in _captureQueue) {
      try {
        final file = File(job.path);
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (_) {}
    }
    _captureQueue.clear();

    if (_processingPhotoPath != null) {
      try {
        final file = File(_processingPhotoPath!);
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (_) {}
    }

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

  img.Image? image;

  bool processing = false;

  bool loadingImage = true;

  int? activeCorner;

  static const double zoomSize = 135;

  static const double zoomFactor = 4;

  @override
  void initState() {
    super.initState();

    corners = widget.item.corners.copy();

    _loadImage();
  }
  // ==========================================================
  // LOAD ORIGINAL IMAGE
  // ==========================================================

  Future<void> _loadImage() async {
    try {
      final existing = widget.item.originalImage;

      if (existing != null) {
        if (!mounted) return;

        setState(() {
          image = existing;

          loadingImage = false;
        });

        return;
      }
      // Decode فقط هنگام باز کردن ادیتور انجام می‌شود.

      final decoded = await compute(
        _decodeImageInIsolate,

        widget.item.originalBytes,
      );

      if (!mounted) {
        return;
      }

      if (decoded == null) {
        throw Exception('تصویر اصلی قابل خواندن نیست');
      }
      // ======================================================
      // img.Image را نمی‌توان بین isolateها ارسال کرد.
      //
      // بنابراین این Decode از isolate برمی‌گردد به شکل
      // Uint8List و اینجا دوباره decode می‌کنیم.
      //
      // برای جلوگیری از پیچیدگی غیرضروری، فعلاً همین مسیر
      // را نگه می‌داریم.
      // ======================================================

      final decodedImage = img.decodeImage(decoded);

      if (decodedImage == null) {
        throw Exception('تصویر اصلی قابل خواندن نیست');
      }

      widget.item.originalImage = decodedImage;

      setState(() {
        image = decodedImage;

        loadingImage = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loadingImage = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطا در باز کردن تصویر: $e')));
    }
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
            onPressed: processing || loadingImage ? null : _applyChanges,

            icon: const Icon(Icons.check),

            label: const Text('اعمال'),
          ),
        ],
      ),

      body: loadingImage || image == null
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : processing
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
    final currentImage = image!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final imageWidth = currentImage.width.toDouble();

        final imageHeight = currentImage.height.toDouble();

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

                    filterQuality: FilterQuality.medium,

                    gaplessPlayback: true,
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
    final currentImage = image;

    if (currentImage == null) {
      return;
    }

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
      updated.dx.clamp(0, currentImage.width.toDouble()),

      updated.dy.clamp(0, currentImage.height.toDouble()),
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
    final currentImage = image;

    if (activeCorner == null || currentImage == null) {
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
        image: currentImage,

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
    if (processing || image == null) {
      return;
    }

    try {
      setState(() {
        processing = true;
      });

      final result = await compute(processCropInIsolate, {
        'bytes': widget.item.originalBytes,

        'filterIndex': ScanFilter.values.indexOf(widget.filter),

        'topLeftX': corners.topLeft.dx,

        'topLeftY': corners.topLeft.dy,

        'topRightX': corners.topRight.dx,

        'topRightY': corners.topRight.dy,

        'bottomRightX': corners.bottomRight.dx,

        'bottomRightY': corners.bottomRight.dy,

        'bottomLeftX': corners.bottomLeft.dx,

        'bottomLeftY': corners.bottomLeft.dy,
      });

      final bytes = result['processedBytes'] as Uint8List;

      final updated = ScanItem(
        originalBytes: widget.item.originalBytes,

        originalImage: image,

        corners: corners,

        processedBytes: bytes,
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(updated);
    } catch (e) {
      if (!mounted) {
        return;
      }

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
// DECODE IMAGE ISOLATE
// ============================================================

Uint8List? _decodeImageInIsolate(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);

  if (decoded == null) {
    return null;
  }

  return Uint8List.fromList(img.encodeJpg(decoded, quality: 95));
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
                child: Image.memory(
                  scan.processedBytes,

                  fit: BoxFit.contain,

                  filterQuality: FilterQuality.medium,
                ),
              ),

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
    if (widget.scans.isEmpty) {
      return;
    }

    try {
      setState(() {
        saving = true;
      });

      String filename = nameController.text.trim();

      final request = FastScannerBridge.request;

      final externalScan =
          request?.isExternalScan == true && request?.recordId != null;

      if (externalScan) {
        filename = request!.recordId!;

        debugPrint('External scan for record: $filename');
      } else {
        if (filename.isEmpty) {
          filename = _defaultFileName();
        }

        filename = _sanitizeFileName(filename);
      }
      // ======================================================
      // PDF
      // ======================================================

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
      // ======================================================
      // EXTERNAL
      // ======================================================

      if (externalScan) {
        final externalDirectory = Directory(
          '/storage/emulated/0/Download/FastScanner',
        );

        if (!await externalDirectory.exists()) {
          await externalDirectory.create(recursive: true);
        }

        final outputPath = path.join(externalDirectory.path, '$filename.pdf');

        final file = File(outputPath);

        await file.writeAsBytes(pdfBytes, flush: true);

        if (!await file.exists()) {
          throw Exception('فایل خروجی ایجاد نشد.');
        }

        final fileSize = await file.length();

        if (fileSize <= 0) {
          throw Exception('فایل خروجی خالی است.');
        }

        debugPrint('External scan saved: $outputPath');

        debugPrint('File size: $fileSize');

        final returned = await FastScannerBridge.completeScan(
          outputPath: outputPath,

          mimeType: 'application/pdf',

          recordId: filename,
        );

        if (!returned) {
          throw Exception('نتوانستیم نتیجه اسکن را به دبیرخانه برگردانیم.');
        }

        return;
      }
      // ======================================================
      // NORMAL
      // ======================================================

      final directory = await getApplicationDocumentsDirectory();

      final scanDirectory = Directory(
        path.join(directory.path, 'scanned_documents'),
      );

      if (!await scanDirectory.exists()) {
        await scanDirectory.create(recursive: true);
      }

      final outputPath = path.join(scanDirectory.path, '$filename.pdf');

      final file = File(outputPath);

      await file.writeAsBytes(pdfBytes, flush: true);

      if (!mounted) {
        return;
      }

      await _showSavedDialog(outputPath);
    } catch (e) {
      debugPrint('Save error: $e');

      if (!mounted) {
        return;
      }

      setState(() {
        saving = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطا در ذخیره فایل:\n$e')));
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
    return value.replaceAll(RegExp(r'[<>:"/\\\\|?*]'), '_');
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

    final encoded = Uint8List.fromList(img.encodeJpg(cropped, quality: 85));

    if (!mounted) {
      return;
    }

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

              filterQuality: FilterQuality.low,
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
