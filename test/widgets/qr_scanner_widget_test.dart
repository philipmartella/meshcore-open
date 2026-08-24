import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/utils/platform_info.dart';
import 'package:meshcore_open/widgets/qr_scanner_widget.dart';

/// The camera guard, exercised on the host that runs the suite.
///
/// This is not a tautology against [PlatformInfo.supportsQrScanning]: what it
/// pins down is that the widget consults the flag *before* constructing a
/// MobileScannerController. Without the guard the failure is a
/// MissingPluginException thrown out of the platform channel — which
/// MobileScanner's own errorBuilder never sees, so nothing renders at all.
void main() {
  testWidgets('renders an explanation instead of a camera where unsupported', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QrScannerWidget(onScanned: (_) {}, instructions: 'point me'),
        ),
      ),
    );

    if (PlatformInfo.supportsQrScanning) {
      // On a platform with a real implementation the camera view is what
      // should appear; the panel must not stand in for it.
      expect(
        find.text('QR scanning is not available on this platform.'),
        findsNothing,
      );
      return;
    }

    expect(
      find.text('QR scanning is not available on this platform.'),
      findsOneWidget,
    );
    // The scan-window overlay and torch/camera controls belong to the camera
    // path; none of them should be built when there is no controller.
    expect(find.text('point me'), findsNothing);
    expect(find.byIcon(Icons.flash_off), findsNothing);
    expect(find.byIcon(Icons.cameraswitch), findsNothing);
  });

  testWidgets('disposes cleanly with no controller', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: QrScannerWidget(onScanned: (_) {})),
      ),
    );
    // A late-initialised controller would throw LateInitializationError here.
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    expect(tester.takeException(), isNull);
  });
}
