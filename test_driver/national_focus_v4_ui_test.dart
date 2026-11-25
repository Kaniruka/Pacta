import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Host-side screenshot sink for the National Focus v4 six-state fixture.
///
/// Run with:
///   flutter drive --driver=test_driver/national_focus_v4_ui_test.dart \
///     --target=integration_test/national_focus_v4_ui_device_test.dart \
///     -d emulator-5554 --dart-define=NF_V4_THEME=light,dark
///
/// PNGs are written to NF_V4_CAPTURE_DIR (host environment), defaulting to
/// build/nf-v4-evidence. Existing files are never overwritten.
Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final raw = Platform.environment['NF_V4_CAPTURE_DIR'] ?? '';
    final directory = Directory(
      raw.trim().isEmpty ? 'build/nf-v4-evidence' : raw.trim(),
    );
    await directory.create(recursive: true);
    final file = File('${directory.path}${Platform.pathSeparator}$name.png');
    if (await file.exists()) {
      throw StateError(
        'refusing to overwrite existing screenshot: ${file.absolute.path}',
      );
    }
    await file.writeAsBytes(bytes);
    stdout.writeln('[nf-v4] ${file.absolute.path}');
    return true;
  },
);
