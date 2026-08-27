import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'document_corners.dart';

class ScannedPage {
  final String id;

  /// تصویر اصلی
  final Uint8List originalBytes;

  /// تصویر Decode شده اصلی
  final img.Image originalImage;

  /// گوشه‌های فعلی سند
  DocumentCorners corners;

  /// تصویر Crop شده
  Uint8List? croppedBytes;

  /// تصویر نهایی بعد از فیلتر
  Uint8List? finalBytes;

  ScannedPage({
    required this.id,
    required this.originalBytes,
    required this.originalImage,
    required this.corners,
    this.croppedBytes,
    this.finalBytes,
  });

  Uint8List get previewBytes {
    return finalBytes ?? croppedBytes ?? originalBytes;
  }

  bool get hasCrop {
    return croppedBytes != null;
  }
}