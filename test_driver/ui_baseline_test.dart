// ignore_for_file: avoid_print

import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// 把基线截图写到 `build/ui-layout-evidence/<UI_EVIDENCE_SUBDIR>`。
///
/// 同名文件直接失败：一个 run 目录只装一次运行的图，不互相覆盖。
Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final subdir = Platform.environment['UI_EVIDENCE_SUBDIR'] ?? '';
    final base = subdir.isEmpty
        ? 'build/ui-layout-evidence'
        : 'build/ui-layout-evidence/$subdir';
    final directory = Directory(base);
    await directory.create(recursive: true);
    final file = File('${directory.path}/$name.png');
    if (await file.exists()) {
      throw StateError('refusing to overwrite existing screenshot: ${file.path}');
    }
    await file.writeAsBytes(bytes);
    print('[ui-layout-evidence] ${file.absolute.path}');
    return true;
  },
);
