// ignore_for_file: avoid_print

import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Writes screenshots under `build/ui-layout-evidence/<UI_EVIDENCE_SUBDIR>`.
///
/// `UI_EVIDENCE_FAIL_ON_EXIST=1` makes a repeated file name fail the run so one
/// evidence directory can only hold one build's images. Other entrypoints keep
/// the historical overwrite behaviour when the flag is absent.
Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final subdir = Platform.environment['UI_EVIDENCE_SUBDIR'] ?? '';
    final strict = Platform.environment['UI_EVIDENCE_FAIL_ON_EXIST'] == '1';
    final base = subdir.isEmpty
        ? 'build/ui-layout-evidence'
        : 'build/ui-layout-evidence/$subdir';
    final directory = Directory(base);
    await directory.create(recursive: true);
    final file = File('${directory.path}/$name.png');
    if (strict && await file.exists()) {
      throw StateError(
        'refusing to overwrite existing screenshot: ${file.absolute.path}',
      );
    }
    await file.writeAsBytes(bytes);
    print('[ui-layout-evidence] ${file.absolute.path}');
    return true;
  },
);
