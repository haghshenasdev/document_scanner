import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/scan_item.dart';

class ScanPreviewPage extends StatefulWidget {
  final List<ScanItem> scans;
  final String initialFileName;

  const ScanPreviewPage({
    super.key,
    required this.scans,
    required this.initialFileName,
  });

  @override
  State<ScanPreviewPage> createState() => _ScanPreviewPageState();
}

class _ScanPreviewPageState extends State<ScanPreviewPage> {
  late TextEditingController _nameController;

  bool saving = false;

  @override
  void initState() {
    super.initState();

    _nameController = TextEditingController(text: widget.initialFileName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String _sanitizeFileName(String name) {
    var value = name.trim();

    if (value.isEmpty) {
      value = 'scan';
    }

    value = value.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');

    value = value.replaceAll(RegExp(r'\s+'), '_');

    for (final extension in ['.jpg', '.jpeg', '.pdf']) {
      if (value.toLowerCase().endsWith(extension)) {
        value = value.substring(0, value.length - extension.length);
      }
    }

    return value;
  }

  Future<void> _save() async {
    if (saving || widget.scans.isEmpty) {
      return;
    }

    final name = _sanitizeFileName(_nameController.text);

    setState(() {
      saving = true;
    });

    try {
      final appDirectory = await getApplicationDocumentsDirectory();

      final scanDirectory = Directory(
        path.join(appDirectory.path, 'scanned_documents'),
      );

      if (!await scanDirectory.exists()) {
        await scanDirectory.create(recursive: true);
      }

      String outputPath;

      if (widget.scans.length == 1) {
        outputPath = await _saveJpg(scanDirectory, name);
      } else {
        outputPath = await _savePdf(scanDirectory, name);
      }

      if (!mounted) return;

      setState(() {
        saving = false;
      });

      await showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            icon: const Icon(Icons.check_circle, color: Colors.green, size: 52),
            title: const Text('ذخیره شد'),
            content: SelectableText(
              outputPath,
              textDirection: TextDirection.ltr,
            ),
            actions: [
              FilledButton(
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
      if (!mounted) return;

      setState(() {
        saving = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطا در ذخیره: $e')));
    }
  }

  Future<String> _saveJpg(Directory directory, String name) async {
    final outputPath = path.join(directory.path, '$name.jpg');

    final file = File(outputPath);

    await file.writeAsBytes(widget.scans.first.previewBytes, flush: true);

    return outputPath;
  }

  Future<String> _savePdf(Directory directory, String name) async {
    final document = pw.Document();

    for (final scan in widget.scans) {
      final image = pw.MemoryImage(scan.previewBytes);

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

    final outputPath = path.join(directory.path, '$name.pdf');

    final file = File(outputPath);

    await file.writeAsBytes(await document.save(), flush: true);

    return outputPath;
  }

  @override
  Widget build(BuildContext context) {
    final isPdf = widget.scans.length > 1;

    return Scaffold(
      appBar: AppBar(title: const Text('پیش‌نمایش اسکن'), centerTitle: true),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _nameController,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: 'نام فایل',
                prefixIcon: const Icon(Icons.drive_file_rename_outline),
                suffixText: isPdf ? '.pdf' : '.jpg',
                border: const OutlineInputBorder(),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Icon(isPdf ? Icons.picture_as_pdf : Icons.image),
                const SizedBox(width: 8),
                Text(
                  isPdf ? '${widget.scans.length} صفحه → PDF' : '۱ صفحه → JPG',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),

          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: widget.scans.length,
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final scan = widget.scans[index];

                return Container(
                  height: 420,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: InteractiveViewer(
                          minScale: 0.5,
                          maxScale: 5,
                          child: Center(
                            child: Image.memory(
                              scan.previewBytes,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),

                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
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
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            height: 52,
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
                  : Icon(isPdf ? Icons.picture_as_pdf : Icons.save),
              label: Text(
                saving
                    ? 'در حال ذخیره...'
                    : isPdf
                    ? 'ذخیره PDF'
                    : 'ذخیره JPG',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
