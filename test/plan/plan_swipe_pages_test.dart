import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/plan/plan_calendar_view.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../support/fake_auth_repository.dart';
import '../support/plan_navigation.dart';

/// T2：目标/日历左右滑动，与分段按钮双向同步，两端不循环。
const _user = 'plan-swipe-pages';

class _Harness {
  _Harness(this.database);

  final PactaDatabase database;
  late LocalTaskRepository tasks;
  late LocalFocusRepository focus;
  late LocalNationalFocusRepository nationalFocus;
  late LocalScheduleRepository schedules;

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(411, 731),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tasks = LocalTaskRepository(
      database: database,
      userId: _user,
      remote: InMemoryTaskRemote(),
    );
    focus = LocalFocusRepository(
      database: database,
      userId: _user,
      remote: InMemoryFocusRemote(),
    );
    nationalFocus = LocalNationalFocusRepository(
      database: database,
      userId: _user,
      cloudSyncEnabled: false,
    );
    schedules = LocalScheduleRepository(database: database, userId: _user);
    await tester.pumpWidget(
      PactaApp(
        authRepository: FakeAuthRepository()..signedInUser = _user,
        taskRepositoryFactory: (_) => tasks,
        focusRepositoryFactory: (_) => focus,
        nationalFocusRepositoryFactory: (_) => nationalFocus,
        scheduleRepositoryFactory: (_) => schedules,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    const limit = Duration(seconds: 10);
    await focus.dispose().timeout(limit, onTimeout: () {});
    await nationalFocus.dispose().timeout(limit, onTimeout: () {});
    await database.close().timeout(limit, onTimeout: () {});
  }
}

/// PageView 只构建当前页：日历页未挂载即代表停在目标页。
bool _calendarOnScreen(WidgetTester tester) =>
    find.byType(PlanCalendarView).evaluate().isNotEmpty;

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          (call) async => call.method == 'getLocalTimezone' ? 'Etc/UTC' : null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          null,
        );
  });

  testWidgets('左滑进日历、右滑回目标，分段按钮同步', (tester) async {
    final harness = _Harness(PactaDatabase(NativeDatabase.memory()));
    try {
      await harness.pump(tester);
      await openPlan(tester);
      expect(_calendarOnScreen(tester), isFalse, reason: '初始是目标页');

      await tester.fling(find.byType(PageView), const Offset(-320, 0), 900);
      await tester.pumpAndSettle();
      expect(_calendarOnScreen(tester), isTrue, reason: '左滑进日历');

      // 分段按钮同步：此时点「目标」应能回到目标页（同一份状态）。
      await tester.tap(find.text('目标'));
      await tester.pumpAndSettle();
      expect(_calendarOnScreen(tester), isFalse, reason: '分段按钮与页面同步');
      await tester.fling(find.byType(PageView), const Offset(-320, 0), 900);
      await tester.pumpAndSettle();

      await tester.fling(find.byType(PageView), const Offset(320, 0), 900);
      await tester.pumpAndSettle();
      expect(_calendarOnScreen(tester), isFalse, reason: '右滑回目标');
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('两端停住：目标页继续右滑不会循环到日历', (tester) async {
    final harness = _Harness(PactaDatabase(NativeDatabase.memory()));
    try {
      await harness.pump(tester);
      await openPlan(tester);

      await tester.fling(find.byType(PageView), const Offset(320, 0), 900);
      await tester.pumpAndSettle();
      expect(_calendarOnScreen(tester), isFalse, reason: '首端不回绕');
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('点分段按钮切页；点日期格不误触翻页', (tester) async {
    final harness = _Harness(PactaDatabase(NativeDatabase.memory()));
    try {
      await harness.pump(tester);
      await openPlan(tester);

      await tester.tap(find.text('日历'));
      await tester.pumpAndSettle();
      expect(_calendarOnScreen(tester), isTrue, reason: '分段按钮切到日历');

      final cell = find.byKey(const ValueKey('plan-day-2026-11-16'));
      expect(cell, findsOneWidget);
      await tester.tap(cell);
      await tester.pumpAndSettle();

      expect(_calendarOnScreen(tester), isTrue, reason: '点按日期格不翻页');
      expect(find.textContaining('11月16日'), findsWidgets, reason: '选中日生效');
    } finally {
      await harness.dispose(tester);
    }
  });
}
