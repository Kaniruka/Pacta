// ignore_for_file: avoid_print

import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final subdir = Platform.environment['UI_EVIDENCE_SUBDIR'] ?? '';
    final base = subdir.isEmpty
        ? 'build/ui-layout-evidence'
        : 'build/ui-layout-evidence/$subdir';
    final directory = Directory(base);
    await directory.create(recursive: true);
    await File('${directory.path}/$name.png').writeAsBytes(bytes);
    print('[ui-layout-evidence] ${directory.path}/$name.png');
    return true;
  },
);
