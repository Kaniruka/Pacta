import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/sync/source_device_info.dart';

void main() {
  group('来源标签只显示型号/设备名与平台', () {
    test('Android 使用型号加平台', () {
      expect(
        SourceDeviceInfo.labelFor(
          platform: SourceDevicePlatform.android,
          hostName: 'localhost',
          model: 'Pixel 7',
        ),
        'Pixel 7（Android）',
      );
    });

    test('Android 缺少型号时显示未知来源，不回退到主机名', () {
      for (final model in <String?>[null, '', '   ', 'unknown', 'Unknown']) {
        expect(
          SourceDeviceInfo.labelFor(
            platform: SourceDevicePlatform.android,
            hostName: 'localhost',
            model: model,
          ),
          '未知型号（Android）',
        );
      }
    });

    test('Windows 使用设备名加平台', () {
      expect(
        SourceDeviceInfo.labelFor(
          platform: SourceDevicePlatform.windows,
          hostName: 'DESKTOP-ABC',
          model: 'Some Model',
        ),
        'DESKTOP-ABC（Windows）',
      );
    });

    test('Windows 缺少设备名时显示未知来源', () {
      expect(
        SourceDeviceInfo.labelFor(
          platform: SourceDevicePlatform.windows,
          hostName: '   ',
        ),
        '未知设备名（Windows）',
      );
    });

    test('其他平台保持主机名，不虚构平台括注', () {
      expect(
        SourceDeviceInfo.labelFor(
          platform: SourceDevicePlatform.other,
          hostName: 'macbook',
          model: 'Mac',
        ),
        'macbook',
      );
    });
  });
}
