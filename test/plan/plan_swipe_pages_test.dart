import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/plan/plan_calendar_view.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../support/fake_auth_repository.dart';
import '../support/plan_navigation.dart';

/// T2：目标/日历左右滑动，与分段按钮双向同步，两端不循环。
/// 手势门槛按定案：水平位移 >24dp 且 |dx| > 1.5|dy| 才翻页。
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

Future<void> _drag(WidgetTester tester, Offset delta) async {
  await tester.drag(find.byType(PageView), delta);
  await tester.pumpAndSettle();
}

Object? _selectedSegment(WidgetTester tester) {
  final widget = tester.widget(
    find.byWidgetPredicate((w) => w is SegmentedButton),
  );
  return (widget as dynamic).selected;
}

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

      await _drag(tester, const Offset(-260, 0));
      expect(_calendarOnScreen(tester), isTrue, reason: '左滑进日历');
      expect(
        _selectedSegment(tester).toString(),
        contains('calendar'),
        reason: '滑动后分段按钮同步到日历',
      );

      await _drag(tester, const Offset(260, 0));
      expect(_calendarOnScreen(tester), isFalse, reason: '右滑回目标');
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('斜滑不翻页：|dx| 未超过 1.5|dy|', (tester) async {
    final harness = _Harness(PactaDatabase(NativeDatabase.memory()));
    try {
      await harness.pump(tester);
      await openPlan(tester);

      await _drag(tester, const Offset(-200, 180));
      expect(_calendarOnScreen(tester), isFalse, reason: '斜向拖动保留在原页');
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('短拖不翻页：水平位移不超过 24dp', (tester) async {
    final harness = _Harness(PactaDatabase(NativeDatabase.memory()));
    try {
      await harness.pump(tester);
      await openPlan(tester);

      await _drag(tester, const Offset(-20, 0));
      expect(_calendarOnScreen(tester), isFalse, reason: '门槛以下不翻页');
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('两端停住：首端右滑、末端左滑都不循环', (tester) async {
    final harness = _Harness(PactaDatabase(NativeDatabase.memory()));
    try {
      await harness.pump(tester);
      await openPlan(tester);

      await _drag(tester, const Offset(260, 0));
      expect(_calendarOnScreen(tester), isFalse, reason: '首端不回绕');

      await _drag(tester, const Offset(-260, 0));
      expect(_calendarOnScreen(tester), isTrue);
      await _drag(tester, const Offset(-260, 0));
      expect(_calendarOnScreen(tester), isTrue, reason: '末端不回绕');
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

      final monthLabel = tester
          .widget<Text>(find.byKey(const ValueKey('plan-month-label')))
          .data!;
      final match = RegExp(r'(\d{4})年(\d{1,2})月').firstMatch(monthLabel)!;
      final ymd = '${match[1]}-${match[2]!.padLeft(2, '0')}-16';
      final cell = find.byKey(ValueKey('plan-day-$ymd'));
      expect(cell, findsOneWidget, reason: '当月 16 日必须在网格里（$monthLabel）');
      await tester.tap(cell);
      await tester.pumpAndSettle();

      expect(_calendarOnScreen(tester), isTrue, reason: '点按日期格不翻页');
      expect(
        find.textContaining('${match[2]}月16日'),
        findsWidgets,
        reason: '选中日生效',
      );
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('Windows 精确触控板双指横滑切页，斜滑不切换', (tester) async {
    final harness = _Harness(PactaDatabase(NativeDatabase.memory()));
    try {
      await harness.pump(tester);
      await openPlan(tester);
      final center = tester.getCenter(find.byType(PageView));

      // 斜滑：纵向分量压过横向，留在目标页。
      var gesture = await tester.createGesture(
        kind: PointerDeviceKind.trackpad,
      );
      await gesture.panZoomStart(center);
      for (var step = 1; step <= 4; step++) {
        await gesture.panZoomUpdate(
          center,
          pan: Offset(-50.0 * step, -50.0 * step),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.panZoomEnd();
      await tester.pumpAndSettle();
      expect(_calendarOnScreen(tester), isFalse, reason: '斜滑不切页');

      // 纯横向：目标 -> 日历。
      gesture = await tester.createGesture(kind: PointerDeviceKind.trackpad);
      await gesture.panZoomStart(center);
      for (var step = 1; step <= 4; step++) {
        await gesture.panZoomUpdate(center, pan: Offset(-50.0 * step, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.panZoomEnd();
      await tester.pumpAndSettle();
      expect(_calendarOnScreen(tester), isTrue, reason: '双指横滑切到日历');
      expect(_selectedSegment(tester).toString(), contains('calendar'));
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('1280x800 宽屏留白区鼠标横拖跟手切页', (tester) async {
    final harness = _Harness(PactaDatabase(NativeDatabase.memory()));
    try {
      await harness.pump(tester, size: const Size(1280, 800));
      await openPlan(tester);
      final pagerRect = tester.getRect(find.byType(PageView));
      final blankPoint = Offset(pagerRect.left + 4, pagerRect.center.dy);
      final controller = tester
          .widget<PageView>(find.byType(PageView))
          .controller!;

      final gesture = await tester.startGesture(
        blankPoint,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 16));
      for (var step = 0; step < 5; step++) {
        await gesture.moveBy(const Offset(-40, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(controller.page, greaterThan(0.05), reason: '拖动过程中页面跟手位移，不是松手才跳');
      expect(controller.page, lessThan(0.95));

      await tester.pump(const Duration(milliseconds: 200));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(_calendarOnScreen(tester), isTrue, reason: '留白处横拖翻到日历');
      expect(controller.page, 1.0);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('Shift+滚轮与方向键/Ctrl+Tab 切页，两端钳位', (tester) async {
    final harness = _Harness(PactaDatabase(NativeDatabase.memory()));
    try {
      await harness.pump(tester, size: const Size(1280, 800));
      await openPlan(tester);
      final center = tester.getCenter(find.byType(PageView));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: center,
          scrollDelta: const Offset(0, 100),
          kind: PointerDeviceKind.mouse,
        ),
      );
      await tester.pumpAndSettle();
      expect(_calendarOnScreen(tester), isTrue, reason: 'Shift+滚轮进日历');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(_calendarOnScreen(tester), isFalse, reason: '← 回目标页');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(_calendarOnScreen(tester), isTrue, reason: 'Ctrl+Tab 进日历');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(_calendarOnScreen(tester), isTrue, reason: '末端不循环');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(_calendarOnScreen(tester), isFalse, reason: 'Ctrl+Shift+Tab 回目标');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('看板前置时 →/Ctrl+Tab 不会误切后台计划页', (tester) async {
    final harness = _Harness(PactaDatabase(NativeDatabase.memory()));
    try {
      await harness.pump(tester, size: const Size(1280, 800));
      await openPlan(tester);
      await tester.tap(find.text('日历'));
      await tester.pumpAndSettle();
      expect(_calendarOnScreen(tester), isTrue);

      await openBoard(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      await openPlan(tester);
      expect(_calendarOnScreen(tester), isTrue, reason: '后台计划页的可见性守卫挡住隐藏页快捷键');
      expect(_selectedSegment(tester).toString(), contains('calendar'));
    } finally {
      await harness.dispose(tester);
    }
  });
}
