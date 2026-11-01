import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/theme/tokens.dart';
import '../core/widgets/mt_widgets.dart';

/// On-device capture for packaging verification. Barcode/QR and OCR run locally (ML Kit); only the
/// extracted text/code is sent to the server for matching, never the photo.
abstract class ScanService {
  Future<String?> scanBarcode(BuildContext context);
  Future<String?> readPackagingText();
}

class DeviceScanService implements ScanService {
  @override
  Future<String?> scanBarcode(BuildContext context) => Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const _BarcodePage()));

  @override
  Future<String?> readPackagingText() async {
    final shot = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 2000);
    if (shot == null) return null;
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(InputImage.fromFile(File(shot.path)));
      return result.text.trim();
    } finally {
      await recognizer.close();
      try {
        await File(shot.path).delete(); // the photo never needs to outlive recognition
      } catch (_) {}
    }
  }
}

class _BarcodePage extends StatefulWidget {
  const _BarcodePage();
  @override
  State<_BarcodePage> createState() => _BarcodePageState();
}

class _BarcodePageState extends State<_BarcodePage> {
  bool _done = false;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          MobileScanner(
            onDetect: (capture) {
              final code = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
              if (code != null && !_done) {
                _done = true;
                Navigator.of(context).pop(code);
              }
            },
            errorBuilder: (c, e) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('The camera is not available. Check the camera permission.', style: const TextStyle(color: Colors.white, fontSize: 18), textAlign: TextAlign.center))),
          ),
          SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: BackHeader('Scan the barcode', onBack: () => Navigator.pop(context)))),
          Center(child: Container(width: 260, height: 260, decoration: BoxDecoration(border: Border.all(color: Mt.blue, width: 3), borderRadius: BorderRadius.circular(24)))),
          const Positioned(left: 0, right: 0, bottom: 48, child: Text('Hold the barcode inside the frame', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600))),
        ]),
      );
}
