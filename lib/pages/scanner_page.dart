import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/document_detector.dart';
import '../core/image_enhancer.dart';
import '../core/perspective_corrector.dart';
import '../models/document_corners.dart';
import '../models/scan_item.dart';
import 'camera_page.dart';
import 'crop_editor_page.dart';
import 'scan_preview_page.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() =>
      _ScannerPageState();
}

class _ScannerPageState
    extends State<ScannerPage> {
  List<CameraDescription> cameras = [];

  final List<ScanItem> scans = [];

  bool cameraAvailable = false;
  bool processing = false;

  String fileName = '';

  ScanFilter selectedFilter =
      ScanFilter.document;

  @override
  void initState() {
    super.initState();

    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final available =
          await availableCameras();

      if (!mounted) return;

      setState(() {
        cameras = available;
        cameraAvailable =
            available.isNotEmpty;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        cameraAvailable = false;
      });
    }
  }

  String _defaultFileName() {
    final now = DateTime.now();

    String two(int value) =>
        value.toString().padLeft(2, '0');

    return 'scan_'
        '${now.year}-'
        '${two(now.month)}-'
        '${two(now.day)}_'
        '${two(now.hour)}-'
        '${two(now.minute)}-'
        '${two(now.second)}';
  }

  Future<void> _openCamera() async {
    if (!cameraAvailable ||
        processing) {
      return;
    }

    final bytes =
        await Navigator.of(context)
            .push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => CameraPage(
          cameras: cameras,
        ),
      ),
    );

    if (bytes == null) {
      return;
    }

    await _processImage(bytes);
  }

  Future<void> _pickImage() async {
    if (processing) {
      return;
    }

    try {
      final result =
          await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowMultiple: true,
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
        return;
      }

      for (final selected
          in result.files) {
        Uint8List? bytes =
            selected.bytes;

        if (bytes == null &&
            selected.path != null) {
          bytes = await File(
            selected.path!,
          ).readAsBytes();
        }

        if (bytes == null) {
          continue;
        }

        await _processImage(bytes);
      }
    } catch (e) {
      if (!mounted) return;

      _showError(
        'خطا در انتخاب تصویر: $e',
      );
    }
  }

  Future<void> _processImage(
    Uint8List bytes,
  ) async {
    try {
      setState(() {
        processing = true;
      });

      final decoded =
          img.decodeImage(bytes);

      if (decoded == null) {
        throw Exception(
          'فرمت تصویر قابل تشخیص نیست',
        );
      }

      /// اصلاح EXIF
      final fixed =
          img.bakeOrientation(
        decoded,
      );

      final fixedBytes =
          Uint8List.fromList(
        img.encodeJpg(
          fixed,
          quality: 95,
        ),
      );

      /// تشخیص سند
      final detected =
          await Future(() {
        return DocumentDetector.detect(
          fixed,
        );
      });

      final corners =
          detected ??
              _defaultCorners(
                fixed,
              );

      /// برش اولیه
      final rectified =
          await Future(() {
        return PerspectiveCorrector.rectify(
          fixed,
          corners,
        );
      });

      /// اعمال فیلتر
      final enhanced =
          await Future(() {
        return ImageEnhancer.apply(
          rectified,
          selectedFilter,
        );
      });

      final previewBytes =
          Uint8List.fromList(
        img.encodeJpg(
          enhanced,
          quality: 100,
        ),
      );

      final item = ScanItem(
        id: DateTime.now()
            .microsecondsSinceEpoch
            .toString(),
        originalBytes:
            fixedBytes,
        originalImage: fixed,
        corners: corners,
        previewBytes:
            previewBytes,
        processedImage:
            enhanced,
      );

      if (!mounted) return;

      setState(() {
        scans.add(item);
        processing = false;

        if (fileName.isEmpty) {
          fileName =
              _defaultFileName();
        }
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        processing = false;
      });

      _showError(
        'خطا در پردازش تصویر: $e',
      );
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

  Future<void> _editScan(
    int index,
  ) async {
    final result =
        await Navigator.of(context)
            .push<ScanItem>(
      MaterialPageRoute(
        builder: (_) =>
            CropEditorPage(
          item: scans[index],
        ),
      ),
    );

    if (result == null ||
        !mounted) {
      return;
    }

    setState(() {
      scans[index] = result;
    });
  }

  void _removeScan(
    int index,
  ) {
    setState(() {
      scans.removeAt(index);
    });

    if (scans.isEmpty) {
      setState(() {
        fileName = '';
      });
    }
  }

  Future<void> _save() async {
    if (scans.isEmpty ||
        processing) {
      return;
    }

    final controller =
        TextEditingController(
      text: fileName.isEmpty
          ? _defaultFileName()
          : fileName,
    );

    final result =
        await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'نام فایل',
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            textDirection:
                TextDirection.ltr,
            decoration:
                const InputDecoration(
              labelText:
                  'نام فایل',
              hintText:
                  'مثلاً scan_1405-06-05_13-55-20',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(
                context,
              ),
              child:
                  const Text('لغو'),
            ),
            FilledButton(
              onPressed: () {
                final value =
                    controller.text
                        .trim();

                Navigator.pop(
                  context,
                  value.isEmpty
                      ? _defaultFileName()
                      : value,
                );
              },
              child:
                  const Text('تأیید'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (result == null ||
        result.trim().isEmpty) {
      return;
    }

    setState(() {
      fileName = result.trim();
      processing = true;
    });

    try {
      final directory =
          await getApplicationDocumentsDirectory();

      final scanDirectory =
          Directory(
        path.join(
          directory.path,
          'scanned_documents',
        ),
      );

      if (!await scanDirectory
          .exists()) {
        await scanDirectory.create(
          recursive: true,
        );
      }

      if (scans.length == 1) {
        await _saveJpg(
          scanDirectory,
          result,
        );
      } else {
        await _savePdf(
          scanDirectory,
          result,
        );
      }

      if (!mounted) return;

      setState(() {
        processing = false;
      });

      _showSavedDialog(
        scans.length == 1
            ? 'JPG'
            : 'PDF',
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        processing = false;
      });

      _showError(
        'خطا در ذخیره فایل: $e',
      );
    }
  }

  Future<void> _saveJpg(
    Directory directory,
    String name,
  ) async {
    final safeName =
        _sanitizeFileName(name);

    final outputPath =
        path.join(
      directory.path,
      '$safeName.jpg',
    );

    final file =
        File(outputPath);

    await file.writeAsBytes(
      scans.first.previewBytes,
      flush: true,
    );
  }

  Future<void> _savePdf(
    Directory directory,
    String name,
  ) async {
    final pdf =
        pw.Document();

    for (final scan
        in scans) {
      final image =
          pw.MemoryImage(
        scan.previewBytes,
      );

      pdf.addPage(
        pw.Page(
          pageFormat:
              PdfPageFormat.a4,
          margin:
              const pw.EdgeInsets.all(
            0,
          ),
          build: (context) {
            return pw.Center(
              child: pw.Image(
                image,
                fit:
                    pw.BoxFit.contain,
              ),
            );
          },
        ),
      );
    }

    final safeName =
        _sanitizeFileName(name);

    final outputPath =
        path.join(
      directory.path,
      '$safeName.pdf',
    );

    final file =
        File(outputPath);

    await file.writeAsBytes(
      await pdf.save(),
      flush: true,
    );
  }

  String _sanitizeFileName(
    String name,
  ) {
    var value =
        name.trim();

    if (value.isEmpty) {
      value =
          _defaultFileName();
    }

    value =
        value.replaceAll(
      RegExp(r'[<>:"/\\|?*]'),
      '_',
    );

    value =
        value.replaceAll(
      RegExp(r'\s+'),
      '_',
    );

    if (value
        .toLowerCase()
        .endsWith('.jpg')) {
      value = value.substring(
        0,
        value.length - 4,
      );
    }

    if (value
        .toLowerCase()
        .endsWith('.jpeg')) {
      value = value.substring(
        0,
        value.length - 5,
      );
    }

    if (value
        .toLowerCase()
        .endsWith('.pdf')) {
      value = value.substring(
        0,
        value.length - 4,
      );
    }

    return value;
  }

  void _showSavedDialog(
    String format,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          icon: const Icon(
            Icons.check_circle,
            color: Colors.green,
            size: 48,
          ),
          title: const Text(
            'ذخیره شد',
          ),
          content: Text(
            'فایل با فرمت $format با موفقیت ذخیره شد.',
          ),
          actions: [
            FilledButton(
              onPressed: () =>
                  Navigator.pop(
                context,
              ),
              child:
                  const Text('باشه'),
            ),
          ],
        );
      },
    );
  }

  void _showError(
    String message,
  ) {
    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(message),
        behavior:
            SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('اسکنر سند'),
        centerTitle: true,
        actions: [
          if (scans.isNotEmpty)
            IconButton(
              tooltip: 'پیش‌نمایش',
              onPressed:
                  processing
                      ? null
                      : () {
                          _openPreview();
                        },
              icon: Badge(
                label: Text(
                  scans.length
                      .toString(),
                ),
                child:
                    const Icon(
                  Icons.layers_outlined,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child:
                scans.isEmpty
                    ? _emptyState()
                    : _scannerWorkspace(),
          ),
          if (scans.isNotEmpty)
            _bottomBar(),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding:
            const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Icon(
              Icons
                  .document_scanner_outlined,
              size: 100,
              color:
                  Theme.of(context)
                      .colorScheme
                      .primary,
            ),
            const SizedBox(
              height: 20,
            ),
            const Text(
              'اسکنر سند',
              style: TextStyle(
                fontSize: 26,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
            const SizedBox(
              height: 10,
            ),
            const Text(
              'برای شروع، یک تصویر انتخاب کنید یا با دوربین عکس بگیرید.',
              textAlign:
                  TextAlign.center,
            ),
            const SizedBox(
              height: 30,
            ),
            if (cameraAvailable)
              SizedBox(
                width: 260,
                child:
                    FilledButton.icon(
                  onPressed:
                      processing
                          ? null
                          : _openCamera,
                  icon: const Icon(
                    Icons
                        .photo_camera_outlined,
                  ),
                  label:
                      const Text(
                    'اسکن با دوربین',
                  ),
                ),
              ),
            const SizedBox(
              height: 12,
            ),
            SizedBox(
              width: 260,
              child:
                  OutlinedButton.icon(
                onPressed:
                    processing
                        ? null
                        : _pickImage,
                icon: const Icon(
                  Icons.folder_open,
                ),
                label:
                    const Text(
                  'انتخاب تصویر',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scannerWorkspace() {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding:
                const EdgeInsets.all(
              12,
            ),
            child: _mainPreview(),
          ),
        ),

        _thumbnailBar(),
      ],
    );
  }

  Widget _mainPreview() {
    final scan =
        scans.last;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius:
            BorderRadius.circular(
          18,
        ),
      ),
      clipBehavior:
          Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 5,
              child: Center(
                child:
                    Image.memory(
                  scan.previewBytes,
                  fit:
                      BoxFit.contain,
                  filterQuality:
                      FilterQuality.high,
                ),
              ),
            ),
          ),

          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 7,
              ),
              decoration:
                  BoxDecoration(
                color:
                    Colors.black54,
                borderRadius:
                    BorderRadius.circular(
                  20,
                ),
              ),
              child: Text(
                'صفحه ${scans.length}',
                style:
                    const TextStyle(
                  color: Colors.white,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _thumbnailBar() {
    return SizedBox(
      height: 105,
      child: Row(
        children: [
          const SizedBox(
            width: 8,
          ),

          Expanded(
            child:
                ListView.separated(
              scrollDirection:
                  Axis.horizontal,
              itemCount:
                  scans.length,
              separatorBuilder:
                  (_, __) =>
                      const SizedBox(
                width: 8,
              ),
              itemBuilder:
                  (context, index) {
                return _thumbnail(
                  index,
                );
              },
            ),
          ),

          const SizedBox(
            width: 8,
          ),

          _addPageButton(),
        ],
      ),
    );
  }

  Widget _thumbnail(
    int index,
  ) {
    final scan =
        scans[index];

    final selected =
        index ==
            scans.length - 1;

    return GestureDetector(
      onTap: () =>
          _editScan(index),
      child: Container(
        width: 78,
        height: 92,
        decoration:
            BoxDecoration(
          borderRadius:
              BorderRadius.circular(
            12,
          ),
          border: Border.all(
            color: selected
                ? Theme.of(context)
                    .colorScheme
                    .primary
                : Colors.black12,
            width:
                selected ? 3 : 1,
          ),
        ),
        clipBehavior:
            Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(
              scan.previewBytes,
              fit: BoxFit.cover,
            ),

            Positioned(
              left: 4,
              top: 4,
              child: Container(
                padding:
                    const EdgeInsets
                        .symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration:
                    BoxDecoration(
                  color:
                      Colors.black54,
                  borderRadius:
                      BorderRadius.circular(
                    8,
                  ),
                ),
                child: Text(
                  '${index + 1}',
                  style:
                      const TextStyle(
                    color:
                        Colors.white,
                    fontSize: 11,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ),
            ),

            Positioned(
              right: 0,
              top: 0,
              child:
                  GestureDetector(
                onTap: () =>
                    _removeScan(
                  index,
                ),
                child: Container(
                  width: 25,
                  height: 25,
                  decoration:
                      const BoxDecoration(
                    color:
                        Colors.red,
                    borderRadius:
                        BorderRadius.only(
                      bottomLeft:
                          Radius.circular(
                        10,
                      ),
                    ),
                  ),
                  child:
                      const Icon(
                    Icons.close,
                    color:
                        Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _addPageButton() {
    return Padding(
      padding:
          const EdgeInsets.only(
        right: 8,
      ),
      child: Column(
        mainAxisAlignment:
            MainAxisAlignment.center,
        children: [
          IconButton.filledTonal(
            tooltip:
                'افزودن صفحه',
            onPressed:
                processing
                    ? null
                    : () {
                        _showAddPageMenu();
                      },
            icon:
                const Icon(
              Icons.add,
            ),
          ),
          const Text(
            'صفحه جدید',
            style:
                TextStyle(
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  void _showAddPageMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              if (cameraAvailable)
                ListTile(
                  leading:
                      const Icon(
                    Icons
                        .photo_camera,
                  ),
                  title:
                      const Text(
                    'اسکن با دوربین',
                  ),
                  onTap: () {
                    Navigator.pop(
                      context,
                    );
                    _openCamera();
                  },
                ),
              ListTile(
                leading:
                    const Icon(
                  Icons.folder_open,
                ),
                title:
                    const Text(
                  'انتخاب از فایل',
                ),
                onTap: () {
                  Navigator.pop(
                    context,
                  );
                  _pickImage();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _bottomBar() {
    return SafeArea(
      child: Padding(
        padding:
            const EdgeInsets.fromLTRB(
          12,
          8,
          12,
          12,
        ),
        child: Row(
          children: [
            Expanded(
              child:
                  OutlinedButton.icon(
                onPressed:
                    processing
                        ? null
                        : _showAddPageMenu,
                icon: const Icon(
                  Icons.add_a_photo,
                ),
                label:
                    const Text(
                  'صفحه جدید',
                ),
              ),
            ),
            const SizedBox(
              width: 10,
            ),
            Expanded(
              child:
                  FilledButton.icon(
                onPressed:
                    processing
                        ? null
                        : _openPreview,
                icon: const Icon(
                  Icons
                      .preview_outlined,
                ),
                label:
                    Text(
                  'پیش‌نمایش '
                  '(${scans.length})',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openPreview() async {
    if (scans.isEmpty) {
      return;
    }

    await Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) =>
            ScanPreviewPage(
          scans: scans,
          initialFileName:
              fileName.isEmpty
                  ? _defaultFileName()
                  : fileName,
        ),
      ),
    );
  }
}