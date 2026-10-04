import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/calendar/calendar_models.dart';
import 'package:pacta/src/calendar/calendar_page.dart';
import 'package:pacta/src/calendar/calendar_repository.dart';
import 'package:pacta/src/focus/focus_clock_review_page.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_strengthening_page.dart';
import 'package:pacta/src/notifications/focus_device_preferences.dart';
import 'package:pacta/src/notifications/focus_notification_service.dart';
import 'package:pacta/src/notifications/focus_notification_settings_page.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_calendar_provider.dart';

void main() {
  testWidgets('320 dp / 200% notification time stays reachable', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const channel = MethodChannel('secondary-layout-notifications');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    final service = FocusNotificationService(
      preferencesStore: FocusDevicePreferencesStore(
        await SharedPreferences.getInstance(),
      ),
      windowsChannel: channel,
    );
    addTearDown(() async {
      await service.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    await _mount(tester, FocusNotificationSettingsPage(service: service));
    await _reveal(
      tester,
      find.byKey(const Key('national-focus-reminder-time')),
    );
    expect(find.text('22:00'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const Key('national-focus-reminder-time')))
          .height,
      greaterThanOrEqualTo(48),
    );
    await _scan(tester);
  });

  testWidgets('320 dp / 200% calendar sources and sync remain readable', (
    tester,
  ) async {
    final database = PactaDatabase(NativeDatabase.memory());
    final remote = InMemoryCalendarRemote();
    final repository = LocalCalendarRepository(
      database: database,
      userId: 'layout-user',
      provider: FakeCalendarProvider.unsupported(),
      remote: remote,
    );
    addTearDown(() async {
      await repository.dispose();
      await database.close();
    });
    await remote.upsertSources(
      userId: 'layout-user',
      sources: const [
        CalendarSource(
          id: 'source',
          displayName: '工作与家庭的共享规划日历来源',
          timeZoneId: 'Asia/Shanghai',
        ),
      ],
    );
    await repository.sync();
    await _mount(
      tester,
      CalendarSourcesPage(repository: repository, isAndroid: false),
    );
    await _reveal(tester, find.text('工作与家庭的共享规划日历来源'));
    await _reveal(tester, find.text('刷新本机日历'));
    await _scan(tester);
  });

  testWidgets(
    '320 dp / 200% strengthening header wraps and editor remains accessible',
    (tester) async {
      await _mount(
        tester,
        NationalFocusStrengtheningPage(
          repository: _CardRepository(),
          cardId: 'card',
        ),
      );
      await _reveal(tester, find.text('新建强化等级'));
      final heading = tester.getRect(find.text('强化等级 0/5'));
      final action = tester.getRect(find.text('新建强化等级'));
      expect(action.top, greaterThan(heading.bottom));
      await tester.tap(find.text('新建强化等级'));
      await tester.pumpAndSettle();
      expect(find.text('保存'), findsOneWidget);
      await _reveal(tester, find.byKey(const ValueKey('strengthened-trigger')));
      await tester.enterText(
        find.byKey(const ValueKey('strengthened-trigger')),
        '早餐以后',
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('保存').hitTestable(), findsOneWidget);
      await _scan(tester);
    },
  );

  testWidgets(
    '320 dp / 200% deferred clock review keeps original evidence and decisions',
    (tester) async {
      await _mount(
        tester,
        FocusClockReviewPage(repository: _ClockRepository()),
      );
      expect(find.text('已暂缓'), findsOneWidget);
      await _reveal(tester, find.textContaining('原始设备时间：'));
      await _reveal(tester, find.text('采用连续计时并核对顺序'));
      await _scan(tester);
    },
  );
}

Future<void> _mount(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetViewInsets();
  });
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: page,
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    160,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  final rect = tester.getRect(target);
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(320));
}

Future<void> _scan(WidgetTester tester) async {
  final scroll = find.byType(Scrollable).first;
  for (var i = 0; i < 12; i++) {
    await tester.drag(scroll, const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }
}

class _CardRepository extends UnavailableNationalFocusRepository {
  @override
  Future<NationalFocusCard> getCard(String id) async => NationalFocusCard(
    id: id,
    triggerCondition: '每天早餐结束后',
    action: '整理今天的工作计划',
    isInTree: true,
    state: NationalFocusCardState.lit,
    createdAt: DateTime.utc(2026, 10, 4),
    updatedAt: DateTime.utc(2026, 10, 4),
  );
}

class _ClockRepository extends UnavailableFocusRepository {
  @override
  Stream<List<FocusClockReviewCase>> watchClockReviewCases() => Stream.value([
    FocusClockReviewCase(
      id: 'clock',
      sessionId: 'session-original-source',
      taskId: 'task',
      direction: FocusClockChangeDirection.forward,
      reliableSeconds: 120,
      interval: FocusTimeInterval(
        startedAt: DateTime.utc(2026, 10, 4, 8),
        endedAt: DateTime.utc(2026, 10, 4, 9),
        measuredDurationSeconds: 60,
        clockReviewStatus: FocusClockReviewStatus.deferred,
      ),
    ),
  ]);
}
