import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/plan/calendar_almanac.dart';
import 'package:pacta/src/plan/plan_calendar_view.dart';
import 'package:pacta/src/schedules/schedule_models.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_repository.dart';
import 'package:pacta/src/theme/pacta_calendar_colors.dart';

import '../support/fake_auth_repository.dart';

const _user = 'plan-calendar-day-state';

CalendarAlmanac _assetAlmanac() {
  final entries = <CalendarHoliday>[];
  for (var year = 2020; year <= 2027; year++) {
    final json = jsonDecode(
      File('assets/holidays/$year.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    entries.addAll(CalendarHoliday.listFromJson(json));
  }
  return CalendarAlmanac(entries);
}

ValueKey<String> _dayKey(DateTime day) => ValueKey(
  'plan-day-${day.year.toString().padLeft(4, '0')}-'
  '${day.month.toString().padLeft(2, '0')}-'
  '${day.day.toString().padLeft(2, '0')}',
);

ValueKey<String> _dotKey(DateTime day) => ValueKey(
  'plan-day-dot-${day.year.toString().padLeft(4, '0')}-'
  '${day.month.toString().padLeft(2, '0')}-'
  '${day.day.toString().padLeft(2, '0')}',
);

ValueKey<String> _checkKey(DateTime day) => ValueKey(
  'plan-day-check-${day.year.toString().padLeft(4, '0')}-'
  '${day.month.toString().padLeft(2, '0')}-'
  '${day.day.toString().padLeft(2, '0')}',
);

ValueKey<String> _selectedRingKey(DateTime day) => ValueKey(
  'plan-day-selected-ring-${day.year.toString().padLeft(4, '0')}-'
  '${day.month.toString().padLeft(2, '0')}-'
  '${day.day.toString().padLeft(2, '0')}',
);

class _Host {
  _Host(this.database, this.repository);

  final PactaDatabase database;
  final LocalScheduleRepository repository;

  static _Host create() {
    final database = PactaDatabase(NativeDatabase.memory());
    return _Host(
      database,
      LocalScheduleRepository(database: database, userId: _user),
    );
  }

  Future<Schedule> addSchedule(
    DateTime day, {
    required String title,
    bool completed = false,
  }) async {
    final schedule = await repository.createSchedule(
      ScheduleDraft(
        title: title,
        window: ScheduleWindow.timed(
          startsAt: DateTime.utc(day.year, day.month, day.day, 1),
          endsAt: DateTime.utc(day.year, day.month, day.day, 2),
        ),
      ),
    );
    if (completed) {
      await repository.setScheduleCompletion(schedule.id, isCompleted: true);
    }
    return schedule;
  }

  Future<void> pump(
    WidgetTester tester,
    DateTime day, {
    required Size size,
    Brightness brightness = Brightness.light,
    CalendarAlmanac? almanac,
    DateTime? today,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    await tester.pumpWidget(
      MaterialApp(
        theme: pactaTheme(brightness),
        home: Scaffold(
          body: SingleChildScrollView(
            child: PlanCalendarView(
              key: ValueKey(
                'calendar-${brightness.name}-${day.toIso8601String()}-${today?.toIso8601String()}',
              ),
              repository: repository,
              goals: const [],
              displayTimeZoneId: 'Asia/Shanghai',
              initialDay: day,
              now: () => DateTime(
                (today ?? day).year,
                (today ?? day).month,
                (today ?? day).day,
                9,
              ),
              almanac: almanac ?? CalendarAlmanac(const []),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    const limit = Duration(seconds: 10);
    await repository.dispose().timeout(limit, onTimeout: () {});
    await database.close().timeout(limit, onTimeout: () {});
  }
}

BoxDecoration _cellDecoration(WidgetTester tester, DateTime day) {
  final ink = tester.widget<Ink>(
    find
        .descendant(of: find.byKey(_dayKey(day)), matching: find.byType(Ink))
        .first,
  );
  return ink.decoration! as BoxDecoration;
}

Color? _cellColor(WidgetTester tester, DateTime day) =>
    _cellDecoration(tester, day).color;

/// 三层规范只有一层描边：日格自己的 [Ink] 上那一层。
Border? _cellBorder(WidgetTester tester, DateTime day) =>
    _cellDecoration(tester, day).border as Border?;

Color? _borderColor(Border? border) => border?.top.color;

double? _borderWidth(Border? border) => border?.top.width;

int _borderedLayerCount(WidgetTester tester, DateTime day) => find
    .descendant(
      of: find.byKey(_dayKey(day)),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            (widget.decoration as BoxDecoration?)?.border != null,
      ),
    )
    .evaluate()
    .length;

Color? _markerColor(WidgetTester tester, DateTime day) {
  final finder = find.byKey(_dotKey(day));
  if (finder.evaluate().isEmpty) return null;
  final container = tester.widget<Container>(finder);
  return (container.decoration as BoxDecoration?)?.color;
}

/// 已废弃的双层内嵌选中环：三层规范落地后必须彻底消失。
Color? _selectedRingColor(WidgetTester tester, DateTime day) {
  final finder = find.byKey(_selectedRingKey(day));
  if (finder.evaluate().isEmpty) return null;
  final container = tester.widget<Container>(finder);
  final decoration = container.foregroundDecoration as BoxDecoration?;
  return _borderColor(decoration?.border as Border?);
}

Future<void> _tapDay(WidgetTester tester, DateTime day) async {
  await tester.tap(find.byKey(_dayKey(day)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('日格背景只表达业务，选中与今天只改单层描边', (tester) async {
    final host = _Host.create();
    try {
      final today = DateTime(2026, 11, 18);
      final hasPlans = DateTime(2026, 11, 19);
      final allComplete = DateTime(2026, 11, 20);
      final mixed = DateTime(2026, 11, 21);
      final noPlans = DateTime(2026, 11, 22);
      await host.addSchedule(today, title: '今日安排');
      await host.addSchedule(hasPlans, title: '明天安排');
      await host.addSchedule(allComplete, title: '已完成安排', completed: true);
      await host.addSchedule(mixed, title: '已完成一项', completed: true);
      await host.addSchedule(mixed, title: '未完成一项');
      await host.pump(tester, today, size: const Size(360, 1200));

      final semanticHandle = tester.ensureSemantics();
      var colors = PactaCalendarColors.light;
      // 今天且默认选中：业务底色原样保留，描边与普通选中日完全相同（2dp
      // 主蓝单层），另有独立 '今' 角标，不再是“今天框套选中框”的双层。
      expect(_cellColor(tester, today), colors.hasPlansBackground);
      expect(_borderColor(_cellBorder(tester, today)), colors.selectedBorder);
      expect(_borderWidth(_cellBorder(tester, today)), 2);
      expect(
        find.descendant(
          of: find.byKey(_dayKey(today)),
          matching: find.text('今'),
        ),
        findsOneWidget,
      );
      expect(_borderedLayerCount(tester, today), 0, reason: '不允许第二层内嵌描边');
      expect(_selectedRingColor(tester, today), isNull);
      expect(_markerColor(tester, today), colors.hasPlansForeground);
      expect(find.byKey(_checkKey(today)), findsNothing);
      // 未选中普通日：有安排黄 / 全部完成绿，均不画描边。
      expect(_cellColor(tester, hasPlans), colors.hasPlansBackground);
      expect(_cellBorder(tester, hasPlans), isNull);
      expect(_cellColor(tester, allComplete), colors.allCompleteBackground);
      expect(find.byKey(_checkKey(allComplete)), findsOneWidget);
      expect(find.byKey(_dotKey(allComplete)), findsNothing);
      expect(_cellColor(tester, mixed), colors.hasPlansBackground);
      expect(find.byKey(_dotKey(mixed)), findsOneWidget);
      expect(_cellColor(tester, noPlans), isNull);
      expect(_cellBorder(tester, noPlans), isNull);
      expect(find.byKey(_dotKey(noPlans)), findsNothing);

      var data = tester
          .getSemantics(find.byKey(_dayKey(today)))
          .getSemanticsData();
      expect(data.label, contains('有安排'));
      expect(data.label, contains('今天'));
      final completeData = tester
          .getSemantics(find.byKey(_dayKey(allComplete)))
          .getSemanticsData();
      expect(completeData.label, contains('安排已全部完成'));
      semanticHandle.dispose();

      // 选中无业务底色的日子：不铺蓝色实底，只有一层 2dp 主蓝描边。
      await _tapDay(tester, noPlans);
      expect(
        _cellColor(tester, today),
        colors.hasPlansBackground,
        reason: '今天回到未选中仍保留黄色底',
      );
      expect(_borderColor(_cellBorder(tester, today)), colors.todayBorder);
      expect(_cellColor(tester, noPlans), isNull);
      expect(_borderColor(_cellBorder(tester, noPlans)), colors.selectedBorder);
      expect(_borderWidth(_cellBorder(tester, noPlans)), 2);
      expect(_borderedLayerCount(tester, noPlans), 0);
      expect(_selectedRingColor(tester, noPlans), isNull);

      // 选中“全部完成”：绿色业务底色保留，蓝色描边取代中性描边。
      await _tapDay(tester, allComplete);
      expect(_cellColor(tester, allComplete), colors.allCompleteBackground);
      expect(
        _borderColor(_cellBorder(tester, allComplete)),
        colors.selectedBorder,
      );
      expect(find.byKey(_checkKey(allComplete)), findsOneWidget);

      final cellRect = tester.getRect(find.byKey(_dayKey(hasPlans)));
      expect(cellRect.width, greaterThanOrEqualTo(48));
      expect(cellRect.height, greaterThanOrEqualTo(48));

      await host.pump(
        tester,
        today,
        size: const Size(360, 1200),
        brightness: Brightness.dark,
      );
      colors = PactaCalendarColors.dark;
      // 重新挂载后默认选中今天：暗色同样是业务黄底 + 2dp 主蓝单层框。
      expect(_cellColor(tester, today), colors.hasPlansBackground);
      expect(_borderColor(_cellBorder(tester, today)), colors.selectedBorder);
      expect(
        find.descendant(
          of: find.byKey(_dayKey(today)),
          matching: find.text('今'),
        ),
        findsOneWidget,
      );
      expect(_cellColor(tester, hasPlans), colors.hasPlansBackground);
      expect(_cellColor(tester, allComplete), colors.allCompleteBackground);
      expect(
        Theme.of(tester.element(find.byType(PlanCalendarView))).brightness,
        Brightness.dark,
      );
    } finally {
      await host.dispose(tester);
    }
  });

  testWidgets('放假日与有安排/选中同时存在时保留标签且单层描边可辨', (tester) async {
    final host = _Host.create();
    try {
      final holiday = DateTime(2026, 2, 18);
      final selected = DateTime(2026, 2, 17);
      final otherHoliday = DateTime(2026, 2, 19);
      await host.addSchedule(holiday, title: '假期安排');
      await host.pump(
        tester,
        selected,
        size: const Size(411, 1200),
        almanac: _assetAlmanac(),
        today: holiday,
      );

      final colors = PactaCalendarColors.light;
      // 放假日 + 有安排 + 今天：黄底、单层中性描边、'今' 与节气短标签同时可辨。
      expect(_cellColor(tester, holiday), colors.hasPlansBackground);
      expect(_borderColor(_cellBorder(tester, holiday)), colors.todayBorder);
      expect(
        find.descendant(
          of: find.byKey(_dayKey(holiday)),
          matching: find.text('雨水'),
        ),
        findsOneWidget,
        reason: '放假日短标签与安排底色同时可辨',
      );
      expect(
        find.descendant(
          of: find.byKey(_dayKey(holiday)),
          matching: find.text('今'),
        ),
        findsOneWidget,
      );
      var data = tester
          .getSemantics(find.byKey(_dayKey(holiday)))
          .getSemanticsData();
      expect(data.label, contains('有安排'));
      expect(data.label, contains('今天'));
      // 无安排的放假日只有薰衣草底色，不画描边。
      expect(_cellColor(tester, otherHoliday), colors.holidayBackground);
      expect(_cellBorder(tester, otherHoliday), isNull);

      // 选中今天：业务黄底保留，描边换成与普通选中日完全相同的 2dp 主蓝单层框。
      await _tapDay(tester, holiday);
      expect(_cellColor(tester, holiday), colors.hasPlansBackground);
      expect(_borderColor(_cellBorder(tester, holiday)), colors.selectedBorder);
      expect(_borderWidth(_cellBorder(tester, holiday)), 2);
      expect(_borderedLayerCount(tester, holiday), 0);
      expect(_selectedRingColor(tester, holiday), isNull);
      expect(
        find.descendant(
          of: find.byKey(_dayKey(holiday)),
          matching: find.text('雨水'),
        ),
        findsOneWidget,
      );
      data = tester
          .getSemantics(find.byKey(_dayKey(holiday)))
          .getSemanticsData();
      expect(data.label, contains('有安排'));

      // 今天过去之后，选中日仍是黄底 + 蓝色单层描边。
      await host.pump(
        tester,
        holiday,
        size: const Size(411, 1200),
        almanac: _assetAlmanac(),
        today: DateTime(2026, 2, 20),
      );
      expect(_cellColor(tester, holiday), colors.hasPlansBackground);
      expect(_borderColor(_cellBorder(tester, holiday)), colors.selectedBorder);
      expect(_selectedRingColor(tester, holiday), isNull);
      expect(
        find.descendant(
          of: find.byKey(_dayKey(holiday)),
          matching: find.text('雨水'),
        ),
        findsOneWidget,
      );
    } finally {
      await host.dispose(tester);
    }
  });
  testWidgets('真实 PactaApp 在 360 宽下日格命中区不小于 48dp', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final database = PactaDatabase(NativeDatabase.memory());
    final fixed = DateTime(2026, 11, 18, 9);
    final schedules = LocalScheduleRepository(
      database: database,
      userId: 'calendar-app',
      now: () => fixed,
    );
    final tasks = LocalTaskRepository(
      database: database,
      userId: 'calendar-app',
      remote: InMemoryTaskRemote(),
      cloudSyncEnabled: false,
      now: () => fixed,
    );
    try {
      await tester.pumpWidget(
        PactaApp(
          authRepository: FakeAuthRepository()..signedInUser = 'calendar-app',
          scheduleRepositoryFactory: (_) => schedules,
          taskRepositoryFactory: (_) => tasks,
          displayClock: () => fixed,
        ),
      );
      Future<void> settle() async {
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      // 计划日历加载态有持续动画，不能用 pumpAndSettle 等无限帧。
      await settle();
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('计划'),
        ),
      );
      await settle();
      await tester.tap(find.text('日历'));
      await settle();
      final rect = tester.getRect(find.byKey(_dayKey(DateTime(2026, 11, 18))));
      expect(rect.width, greaterThanOrEqualTo(48));
      expect(rect.height, greaterThanOrEqualTo(48));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      const limit = Duration(seconds: 10);
      await schedules.dispose().timeout(limit, onTimeout: () {});
      await tasks.dispose().timeout(limit, onTimeout: () {});
      await database.close().timeout(limit, onTimeout: () {});
    }
  });

  test('日历状态色与边框在亮暗主题达到对比度门槛', () {
    for (final brightness in Brightness.values) {
      final colors = brightness == Brightness.dark
          ? PactaCalendarColors.dark
          : PactaCalendarColors.light;
      final theme = pactaTheme(brightness);
      for (final pair in [
        (colors.hasPlansBackground, colors.hasPlansForeground),
        (colors.selectedBackground, colors.selectedForeground),
        (colors.allCompleteBackground, colors.allCompleteForeground),
        (colors.holidayBackground, colors.holidayForeground),
        (colors.hasPlansBackground, colors.holidayForeground),
        (colors.allCompleteBackground, colors.holidayForeground),
        (colors.selectedBackground, colors.holidayForeground),
      ]) {
        final ratio = _contrast(pair.$1, pair.$2);
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: '背景 ${pair.$1} 与前景 ${pair.$2} 的对比度应为 AA，实际 $ratio',
        );
      }
      for (final background in [
        theme.scaffoldBackgroundColor,
        colors.hasPlansBackground,
        colors.selectedBackground,
        colors.allCompleteBackground,
        colors.holidayBackground,
      ]) {
        final ratio = _contrast(colors.todayBorder, background);
        expect(
          ratio,
          greaterThanOrEqualTo(3.0),
          reason: '今天描边 ${colors.todayBorder} 与 $background 对比度不足，实际 $ratio',
        );
      }
      expect(
        _contrast(colors.selectedBorder, colors.selectedBackground),
        greaterThanOrEqualTo(4.5),
      );
    }
  });
}

double _contrast(Color a, Color b) {
  final luminanceA = a.computeLuminance();
  final luminanceB = b.computeLuminance();
  final lighter = luminanceA > luminanceB ? luminanceA : luminanceB;
  final darker = luminanceA > luminanceB ? luminanceB : luminanceA;
  return (lighter + 0.05) / (darker + 0.05);
}
