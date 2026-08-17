import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

String? extractImei(String raw) {
  final match = RegExp(r'\d{15}').firstMatch(raw.replaceAll(' ', ''));
  return match?.group(0);
}

bool isValidImei(String value) {
  if (!RegExp(r'^\d{15}$').hasMatch(value)) return false;
  var sum = 0;
  for (var index = 0; index < value.length; index++) {
    var digit = int.parse(value[index]);
    if (index.isOdd) {
      digit *= 2;
      if (digit > 9) digit -= 9;
    }
    sum += digit;
  }
  return sum % 10 == 0;
}

class ScanCodePage extends StatefulWidget {
  const ScanCodePage({
    super.key,
    this.title = 'Quét mã bằng camera',
    this.hint = 'Đưa mã vạch vào giữa khung hình',
  });

  final String title;
  final String hint;

  @override
  State<ScanCodePage> createState() => _ScanCodePageState();
}

class _ScanCodePageState extends State<ScanCodePage> {
  final controller = MobileScannerController(
    formats: const [
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.itf,
      BarcodeFormat.qrCode,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
    ],
  );
  bool completed = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void onDetect(BarcodeCapture capture) {
    if (completed) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim() ?? '';
      if (value.isEmpty) continue;
      completed = true;
      HapticFeedback.mediumImpact();
      Navigator.pop(context, value);
      return;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text(widget.title),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              tooltip: 'Bật / tắt đèn',
              onPressed: () => controller.toggleTorch(),
              icon: const Icon(Icons.flashlight_on_outlined),
            ),
            IconButton(
              tooltip: 'Đổi camera',
              onPressed: () => controller.switchCamera(),
              icon: const Icon(Icons.cameraswitch_outlined),
            ),
          ],
        ),
        body: Stack(children: [
          MobileScanner(controller: controller, onDetect: onDetect),
          const _ScannerFrame(),
          Positioned(
            left: 20,
            right: 20,
            bottom: 38,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  widget.hint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ),
          ),
        ]),
      );
}

class ImeiBatchScannerPage extends StatefulWidget {
  const ImeiBatchScannerPage({super.key});

  @override
  State<ImeiBatchScannerPage> createState() => _ImeiBatchScannerPageState();
}

class _ImeiBatchScannerPageState extends State<ImeiBatchScannerPage> {
  final controller = MobileScannerController(
    formats: const [BarcodeFormat.code128, BarcodeFormat.code39, BarcodeFormat.qrCode],
  );
  final imeis = <String>[];
  final lastDetectedAt = <String, DateTime>{};
  String message = 'Đưa mã vạch IMEI đầu tiên vào khung';

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void onDetect(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue ?? '';
      final imei = extractImei(raw);
      if (imei == null) {
        if (mounted) setState(() => message = 'Không tìm thấy IMEI 15 số');
        continue;
      }
      final now = DateTime.now();
      final previous = lastDetectedAt[imei];
      if (previous != null && now.difference(previous).inSeconds < 2) return;
      lastDetectedAt[imei] = now;
      if (!isValidImei(imei)) {
        if (mounted) setState(() => message = 'IMEI $imei không hợp lệ');
        HapticFeedback.vibrate();
        return;
      }
      if (imeis.contains(imei)) {
        if (mounted) setState(() => message = 'IMEI $imei đã được quét');
        return;
      }
      HapticFeedback.mediumImpact();
      if (mounted) {
        setState(() {
          imeis.add(imei);
          message = 'Đã thêm $imei • Tiếp tục quét máy kế tiếp';
        });
      }
      return;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text('Quét nhiều IMEI (${imeis.length})'),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              tooltip: 'Bật / tắt đèn',
              onPressed: () => controller.toggleTorch(),
              icon: const Icon(Icons.flashlight_on_outlined),
            ),
          ],
        ),
        body: Stack(children: [
          MobileScanner(controller: controller, onDetect: onDetect),
          const _ScannerFrame(),
          Positioned(
            left: 14,
            right: 14,
            bottom: 18,
            child: Card(
              color: Colors.black87,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white)),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: imeis.isEmpty
                            ? null
                            : () => setState(() {
                                  message = 'Đã bỏ ${imeis.removeLast()}';
                                }),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white),
                        child: const Text('Bỏ mã cuối'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: imeis.isEmpty
                            ? null
                            : () => Navigator.pop(
                                context, List<String>.from(imeis)),
                        child: Text('Xong (${imeis.length})'),
                      ),
                    ),
                  ]),
                ]),
              ),
            ),
          ),
        ]),
      );
}

class _ScannerFrame extends StatelessWidget {
  const _ScannerFrame();

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Center(
          child: Container(
            width: MediaQuery.sizeOf(context).width * 0.82,
            height: 170,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.lightBlueAccent, width: 3),
              borderRadius: BorderRadius.circular(18),
              color: Colors.transparent,
            ),
          ),
        ),
      );
}
