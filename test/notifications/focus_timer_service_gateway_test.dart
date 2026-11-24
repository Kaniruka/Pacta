import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/notifications/focus_device_preferences.dart';
import 'package:pacta/src/notifications/focus_notification_service.dart';
import 'package:pacta/src/notifications/focus_timer_service_gateway.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 前台计时服务的 Dart 侧线协议：动作名、参数字段、点按回传与冷启动负载。
///
/// 原生侧的实现无法在单测里运行，所以这里锁定"发出去的到底是什么"——字段
/// 少一个，Kotlin 侧就会静默退化成 0 秒进度。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(
    MethodChannelFocusTimerServiceGateway.channelName,
  );
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  FocusTimerRequest request() {
    final startedAt = DateTime.utc(2026, 11, 13, 7);
    return FocusTimerRequest(
      notificationId: 2200,
      titlePrefix: '专注中',
      taskTitle: '写报告',
      modeLabel: '常规',
      startedAt: startedAt,
      endsAt: startedAt.add(const Duration(minutes: 30)),
      totalSeconds: 30 * 60,
      payload: 'session:session-1',
    );
  }

  test('start then update carry the full absolute-time payload', () async {
    final gateway = MethodChannelFocusTimerServiceGateway();
    final value = request();

    await gateway.startOrUpdate(value);
    expect(calls.first.method, 'start');
    expect(calls.first.arguments, {
      'notificationId': 2200,
      'titlePrefix': '专注中',
      'taskTitle': '写报告',
      'modeLabel': '常规',
      'startedAtMs': value.startedAt.millisecondsSinceEpoch,
      'endsAtMs': value.endsAt.millisecondsSinceEpoch,
      'totalSeconds': 1800,
      'payload': 'session:session-1',
    });

    await gateway.startOrUpdate(value);
    expect(calls.last.method, 'update');
    expect(calls.last.arguments, calls.first.arguments);

    await gateway.stop();
    expect(calls.last.method, 'stop');
  });

  test('a stop before any start still reaches the platform', () async {
    final gateway = MethodChannelFocusTimerServiceGateway();
    await gateway.stop();
    expect(calls.single.method, 'stop');
  });

  test('a tapped notification forwards its payload to the listener', () async {
    final gateway = MethodChannelFocusTimerServiceGateway();
    final received = <String>[];
    gateway.attach(onTapped: received.add);
    addTearDown(gateway.detach);

    await messenger.handlePlatformMessage(
      MethodChannelFocusTimerServiceGateway.channelName,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('notificationTapped', 'appointment:appointment-1'),
      ),
      (_) {},
    );

    expect(received, ['appointment:appointment-1']);
  });

  test('an empty or unrelated platform call is ignored', () async {
    final gateway = MethodChannelFocusTimerServiceGateway();
    final received = <String>[];
    gateway.attach(onTapped: received.add);
    addTearDown(gateway.detach);

    for (final call in [
      const MethodCall('notificationTapped', ''),
      const MethodCall('notificationTapped', 42),
      const MethodCall('somethingElse', 'session:session-1'),
    ]) {
      await messenger.handlePlatformMessage(
        MethodChannelFocusTimerServiceGateway.channelName,
        const StandardMethodCodec().encodeMethodCall(call),
        (_) {},
      );
    }

    expect(received, isEmpty);
  });

  test(
    'the cold-start payload is read once and survives a missing host',
    () async {
      const payloadChannel = MethodChannel('focus_timer_test/pending_payload');
      messenger.setMockMethodCallHandler(
        payloadChannel,
        (call) async => call.method == 'takePendingLaunchPayload'
            ? 'appointment:appointment-1'
            : null,
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(payloadChannel, null),
      );

      final gateway = MethodChannelFocusTimerServiceGateway(
        channel: payloadChannel,
      );
      expect(
        await gateway.takePendingLaunchPayload(),
        'appointment:appointment-1',
      );

      // 宿主没有实现该能力时等同于"没有待处理点击"，不能抛出。
      const missing = MethodChannel('focus_timer_test/missing_payload');
      final missingGateway = MethodChannelFocusTimerServiceGateway(
        channel: missing,
      );
      expect(await missingGateway.takePendingLaunchPayload(), isNull);
    },
  );

  test('the no-op gateway never touches a platform channel', () async {
    const gateway = NoopFocusTimerServiceGateway();
    await gateway.startOrUpdate(request());
    await gateway.stop();
    expect(calls, isEmpty);
    expect(Platform.isAndroid, isFalse, reason: '测试运行在桌面宿主');
  });

  test('切号与登出都会停止前台进度服务', () async {
    // 切号/登出只走 releaseUser -> setUserId(null) -> _cancelOwnedNotifications，
    // 不会经过 clear()：漏掉这一步，上一位用户的倒计时通知会留在通知栏。
    final gateway = _RecordingTimerServiceGateway();
    final service = FocusNotificationService(
      preferencesStore: FocusDevicePreferencesStore(
        await SharedPreferences.getInstance(),
      ),
      windowsChannel: const MethodChannel('focus_timer_test/release_status'),
      timerServiceGateway: gateway,
    );
    addTearDown(service.dispose);

    await service.setUserId('user-a');
    // 首次绑定同样释放了一次"无 owner"状态，从切号开始计数。
    gateway.stopCount = 0;

    await service.setUserId('user-b');
    expect(gateway.stopCount, 1, reason: '切号必须先撤下上一位用户的常驻通知');

    await service.releaseUser('user-c');
    expect(gateway.stopCount, 1, reason: '不是当前 owner 的释放必须忽略');

    await service.releaseUser('user-b');
    expect(gateway.stopCount, 2, reason: '登出必须停掉前台服务');
    expect(service.ownerUserId, isNull);
    expect(gateway.requests, isEmpty, reason: '释放路径只停止，不再登记新的计时');
  });
}

/// 只记录"停了几次"：释放路径的契约是幂等的停止，不是重绘。
class _RecordingTimerServiceGateway implements FocusTimerServiceGateway {
  int stopCount = 0;
  final List<FocusTimerRequest> requests = [];

  @override
  Future<void> startOrUpdate(FocusTimerRequest request) async {
    requests.add(request);
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }
}
