import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/notifications/windows_notification_adapter.dart';

/// The Windows notification boundary is a platform channel owned by the
/// runner. These tests pin the wire contract from the Dart side: the identity
/// the process actually registered, the 100 ns-safe UTC due time, the payload
/// carried by a click, and the fact that nothing here can deregister the
/// product identity.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(RunnerWindowsNotificationAdapter.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late Object? Function(MethodCall call) handler;
  late RunnerWindowsNotificationAdapter adapter;

  setUp(() {
    calls = [];
    handler = (call) => null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return handler(call);
    });
    adapter = RunnerWindowsNotificationAdapter(channel: channel);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'initialize asserts the process identity and reports real readiness',
    () async {
      handler = (call) => {
        'ready': true,
        'aumid': 'Pacta.Desktop.Focus',
        'identitySource': 'product',
      };

      expect(await adapter.initialize(), isTrue);
      final initialize = calls.single;
      expect(initialize.method, 'initialize');
      expect(initialize.arguments, {'expectedAumid': 'Pacta.Desktop.Focus'});
    },
  );

  test(
    'initialize reports a failed registration instead of pretending',
    () async {
      handler = (call) => {'ready': false};
      expect(await adapter.initialize(), isFalse);

      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'aumid_mismatch', message: 'identity');
      });
      expect(await adapter.initialize(), isFalse);
    },
  );

  test('schedule sends the UTC due time and opaque payload', () async {
    handler = (call) => call.method == 'initialize' ? {'ready': true} : null;
    await adapter.initialize();

    await adapter.schedule(
      id: 2203,
      title: '专注已完成',
      body: '任务：整理发布材料',
      at: DateTime.utc(2026, 11, 16, 2, 13),
      payload: 'session:abc',
    );

    final schedule = calls.last;
    expect(schedule.method, 'schedule');
    final arguments = schedule.arguments as Map<Object?, Object?>;
    expect(arguments['id'], 2203);
    expect(
      arguments['dueUnixMs'],
      DateTime.utc(2026, 11, 16, 2, 13).millisecondsSinceEpoch,
    );
    expect(arguments['payload'], 'session:abc');
    expect(arguments['title'], '专注已完成');
  });

  test('schedule is a no-op when the OS registration was refused', () async {
    handler = (call) => {'ready': false};
    await adapter.initialize();
    final before = calls.length;

    await adapter.schedule(
      id: 1,
      title: 't',
      body: 'b',
      at: DateTime.utc(2026, 11, 16, 2),
    );

    expect(calls.length, before);
  });

  test(
    'cancel and pendingIds keep the OS queue as the source of truth',
    () async {
      handler = (call) => switch (call.method) {
        'initialize' => {'ready': true},
        'pendingIds' => [2202, 2203],
        _ => null,
      };
      await adapter.initialize();

      expect(await adapter.pendingIds(), [2202, 2203]);
      await adapter.cancel(2203);
      expect(calls.last.method, 'cancel');
      expect(calls.last.arguments, {'id': 2203});
    },
  );

  test(
    'a delivered click reaches the response callback with its payload',
    () async {
      handler = (call) => {'ready': true};
      final responses = <NotificationResponse>[];
      await adapter.initialize(onResponse: responses.add);

      await messenger.handlePlatformMessage(
        RunnerWindowsNotificationAdapter.channelName,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('notificationClicked', 'schedule-reminder:s1'),
        ),
        (_) {},
      );

      expect(responses.single.payload, 'schedule-reminder:s1');
      expect(
        responses.single.notificationResponseType,
        NotificationResponseType.selectedNotification,
      );
    },
  );

  test('dispose detaches Dart and never deregisters the identity', () async {
    handler = (call) => {'ready': true};
    await adapter.initialize();
    await adapter.dispose();

    expect(calls.where((call) => call.method == 'dispose').length, 1);
    expect(
      calls.where((call) => call.method == 'unregisterAllForTestIdentity'),
      isEmpty,
    );
  });

  test('the test-only teardown is explicit and separate', () async {
    handler = (call) => {'ready': true};
    await adapter.initialize();
    await adapter.unregisterAllForTestIdentity();
    expect(calls.last.method, 'unregisterAllForTestIdentity');
  });
}
