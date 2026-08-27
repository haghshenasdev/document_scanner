import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'document_corners.dart';

class ScanItem {
  final String id;

  /// تصویر اصلی بعد از اصلاح EXIF
  Uint8List originalBytes;

  /// تصویر اصلی Decode شده
  img.Image originalImage;

  /// گوشه‌های فعلی سند
  DocumentCorners corners;

  /// تصویر برش خورده فعلی
  Uint8List previewBytes;

  /// تصویر Decode شده برش خورده
  img.Image? processedImage;

  ScanItem({
    required this.id,
    required this.originalBytes,
    required this.originalImage,
    required this.corners,
    required this.previewBytes,
    this.processedImage,
  });

  ScanItem copyWith({
    Uint8List? originalBytes,
    img.Image? originalImage,
    DocumentCorners? corners,
    Uint8List? previewBytes,
    img.Image? processedImage,
  }) {
    return ScanItem(
      id: id,
      originalBytes: originalBytes ?? this.originalBytes,
      originalImage: originalImage ?? this.originalImage,
      corners: corners ?? this.corners,
      previewBytes: previewBytes ?? this.previewBytes,
      processedImage: processedImage ?? this.processedImage,
    );
  }
}