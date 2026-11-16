// ignore_for_file: avoid_print

import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Writes Android acceptance screenshots under
/// `build/android-acceptance-evidence/<ANDROID_EVIDENCE_SUBDIR>`.
Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final subdir = Platform.environment['ANDROID_EVIDENCE_SUBDIR'] ?? '';
    final strict =
        Platform.environment['ANDROID_EVIDENCE_FAIL_ON_EXIST'] == '1';
    final base = subdir.isEmpty
        ? 'build/android-acceptance-evidence'
        : 'build/android-acceptance-evidence/$subdir';
    final directory = Directory(base);
    await directory.create(recursive: true);
    final file = File('${directory.path}/$name.png');
    if (strict && await file.exists()) {
      throw StateError(
        'refusing to overwrite existing screenshot: ${file.absolute.path}',
      );
    }
    await file.writeAsBytes(bytes);
    print('[android-acceptance] ${file.absolute.path}');
    return true;
  },
);
