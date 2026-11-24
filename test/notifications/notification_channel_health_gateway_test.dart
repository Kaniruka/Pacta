import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/notifications/device_permission_gateway.dart';

/// 渠道健康度是"只读探测 + 直达设置"：读不到就按健康处理，绝不误报降级。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test('a degraded channel list is reported with its ids', () async {
    const channel = MethodChannel('channel_health_test/permissions');
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'getNotificationChannelHealth') return null;
      return <String, Object?>{
        'healthy': false,
        'degradedChannels': [
          'pacta_focus_events_v2',
          7,
          '',
          'pacta_daily_open_reminders_v2',
        ],
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    const gateway = MethodChannelDevicePermissionGateway(channel: channel);
    final health = await gateway.inspectChannelHealth();

    expect(health.healthy, isFalse);
    expect(health.degradedChannelIds, [
      'pacta_focus_events_v2',
      'pacta_daily_open_reminders_v2',
    ]);
  });

  test('a healthy reply and a missing host both count as healthy', () async {
    const channel = MethodChannel('channel_health_test/healthy');
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => <String, Object?>{
        'healthy': true,
        'degradedChannels': <Object?>[],
      },
    );
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    const gateway = MethodChannelDevicePermissionGateway(channel: channel);
    final healthy = await gateway.inspectChannelHealth();
    expect(healthy.healthy, isTrue);
    expect(healthy.degradedChannelIds, isEmpty);

    // 旧宿主没有这个方法：不能把"读不到"解释成"被降级"。
    const missing = MethodChannel('channel_health_test/missing');
    const missingGateway = MethodChannelDevicePermissionGateway(
      channel: missing,
    );
    final fallback = await missingGateway.inspectChannelHealth();
    expect(fallback.healthy, isTrue);
    expect(fallback.degradedChannelIds, isEmpty);
  });

  test('opening a channel passes its id to the platform', () async {
    const channel = MethodChannel('channel_health_test/open_channel');
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    const gateway = MethodChannelDevicePermissionGateway(channel: channel);
    await gateway.openChannelSettings('pacta_focus_events_v2');

    expect(calls.single.method, 'openNotificationChannelSettings');
    expect(calls.single.arguments, {'channelId': 'pacta_focus_events_v2'});
  });

  test('the desktop gateway is always healthy and never calls out', () async {
    const gateway = UnsupportedDevicePermissionGateway();
    final health = await gateway.inspectChannelHealth();
    expect(health.healthy, isTrue);
    expect(health.degradedChannelIds, isEmpty);
    await gateway.openChannelSettings('pacta_focus_events_v2');
    expect(Platform.isAndroid, isFalse, reason: '测试运行在桌面宿主');
  });
}
