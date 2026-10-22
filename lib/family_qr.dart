import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'family.dart';
import 'theme.dart';

/// The family code as a QR code, to be scanned by a new device.
class FamilyQrCode extends StatelessWidget {
  const FamilyQrCode({super.key, required this.familyId, this.size = 220});
  final String familyId;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white, // a QR code needs a light quiet zone around it
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kPurple, width: 3),
      ),
      child: QrImageView(
        data: FamilyService.qrPayload(familyId),
        size: size,
        eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: kInk),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: kInk,
        ),
      ),
    );
  }
}

/// Opens the camera to read a family QR code. Returns the family code, or
/// null if the user went back.
Future<String?> scanFamilyCode(BuildContext context) => Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _ScanScreen()),
    );

class _ScanScreen extends StatefulWidget {
  const _ScanScreen();

  @override
  State<_ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<_ScanScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false; // a code was found: ignore the next detections
  bool _wrongCode = false; // a QR code was seen, but not a family one

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final barcode in capture.barcodes) {
      final code = FamilyService.codeFromQr(barcode.rawValue);
      if (code != null) {
        _done = true;
        Navigator.of(context).pop(code);
        return;
      }
    }
    if (!_wrongCode) setState(() => _wrongCode = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan the family QR code'),
        actions: [
          IconButton(
            tooltip: 'Other camera',
            onPressed: _controller.switchCamera,
            icon: const Icon(Icons.cameraswitch_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: MobileScanner(controller: _controller, onDetect: _onDetect)),
          // Frame showing where to put the code.
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 4),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 32,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _wrongCode
                    ? 'This is not a Pitchoune Timer family code.\n'
                        'On the other device: family button on the home screen.'
                    : 'On a device of the family, open the family button of the home screen, '
                        'then point this camera at its QR code.\n'
                        'No camera? Go back and type the code.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _wrongCode ? Colors.orangeAccent : Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
