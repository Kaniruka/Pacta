import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/src/sync/source_device_info.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reads available Issue 70 source device metadata', (
    tester,
  ) async {
    final info = await SourceDeviceInfo.load();

    final expectedDeviceName =
        '${Platform.localHostname} (${Platform.isAndroid ? 'Android' : 'Windows'})';
    expect(info.deviceName, expectedDeviceName);
    expect(info.manufacturer, anyOf(isNull, isNotEmpty));
    expect(info.model, anyOf(isNull, isNotEmpty));
    // Keep this output limited to the requested identifying fields. No device
    // serial number or other hardware identifier is queried or emitted.
    // ignore: avoid_print
    print(
      'Issue70 device metadata: '
      'name=${info.deviceName}, '
      'manufacturer=${info.manufacturer ?? 'unknown'}, '
      'model=${info.model ?? 'unknown'}',
    );
  });
}
