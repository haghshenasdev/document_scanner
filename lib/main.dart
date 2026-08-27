import 'package:flutter/material.dart';

import 'pages/scanner_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const DocumentScannerApp());
}

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
