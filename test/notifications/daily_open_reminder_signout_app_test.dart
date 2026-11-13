import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/notifications/focus_device_preferences.dart';
import 'package:pacta/src/notifications/focus_notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_auth_repository.dart';

const _userA = 'issue95-signout-a';
const _userB = 'issue95-signout-b';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
          (_) async => null,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
          null,
        );
  });

  testWidgets('signing out through the shell releases the daily reminder', (
    tester,
  ) async {
    const channel = MethodChannel('issue95/signout_reminder');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final preferences = await SharedPreferences.getInstance();
    final hourAhead = DateTime.now().add(const Duration(hours: 1));
    await FocusDevicePreferencesStore(preferences, userId: _userA).save(
      FocusDevicePreferences(
        notificationsEnabled: true,
        backgroundRunningEnabled: false,
        dailyOpenReminderEnabled: true,
        dailyOpenReminderMinutesAfterMidnight:
            hourAhead.hour * 60 + hourAhead.minute,
        dailyOpenReminderTimeChosen: true,
      ),
    );

    final timers = <_RecordedTimer>[];
    final auth = _SwitchableAuthRepository()..signedInUser = _userA;
    final service = FocusNotificationService(
      windowsChannel: channel,
      localTimeZone: () async => 'Asia/Shanghai',
      reminderTimers: (delay, callback) {
        final timer = Zone.root.createTimer(delay, callback);
        timers.add(_RecordedTimer(timer));
        return timer;
      },
    );

    await tester.pumpWidget(
      PactaApp(authRepository: auth, focusNotificationService: service),
    );
    await _pumpFrames(tester);
    expect(
      timers.where((recorded) => recorded.timer.isActive),
      hasLength(1),
      reason: "The signed-in user's own reminder must be planned.",
    );

    auth.signOutNow();
    await _pumpFrames(tester);
    expect(find.byType(AuthScreen), findsOneWidget);
    expect(
      timers.where((recorded) => recorded.timer.isActive),
      isEmpty,
      reason: 'Releasing the shell must cancel the daily reminder.',
    );

    auth.switchTo(_userB);
    await _pumpFrames(tester);
    expect(find.byType(AppShell), findsOneWidget);
    expect(
      timers.where((recorded) => recorded.timer.isActive),
      isEmpty,
      reason: 'Another account starts from the documented default (off).',
    );
    expect(
      (await FocusDevicePreferencesStore(
        preferences,
        userId: _userA,
      ).load()).dailyOpenReminderEnabled,
      isTrue,
      reason: "Signing out must not erase the first user's own choice.",
    );

    await service.dispose();
  }, skip: !Platform.isWindows);
}

Future<void> _pumpFrames(WidgetTester tester, {int frames = 30}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

class _RecordedTimer {
  _RecordedTimer(this.timer);

  final Timer timer;
}

class _SwitchableAuthRepository extends FakeAuthRepository {
  final _controller = StreamController<String?>.broadcast();

  @override
  Stream<String?> get authState => _controller.stream;

  void signOutNow() {
    signedInUser = null;
    _controller.add(null);
  }

  void switchTo(String userId) {
    signedInUser = userId;
    _controller.add(userId);
  }
}
