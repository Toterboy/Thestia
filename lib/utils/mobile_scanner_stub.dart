// EXPERIMENTAL: Stub for mobile_scanner on non-mobile platforms
// (web/desktop). The real mobile_scanner is imported on Android/iOS via
// the conditional import in qr_scan_screen.dart. Keeps the conditional
// import graph compileable on all targets.
import 'package:flutter/material.dart';

class MobileScannerController {
  MobileScannerController();
  Future<void> dispose() async {}
}

class MobileScanner extends StatelessWidget {
  const MobileScanner({super.key, this.controller, this.onDetect});

  final MobileScannerController? controller;
  final void Function(dynamic capture)? onDetect;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
