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

Color? _cellColor(WidgetTester tester, DateTime day) {
  final container = tester.widget<Container>(
    find
        .descendant(
          of: find.byKey(_dayKey(day)),
          matching: find.byType(Container),
        )
        .first,
  );
  return (container.decoration as BoxDecoration?)?.color;
}

BoxBorder? _cellOuterBorder(WidgetTester tester, DateTime day) {
  final container = tester.widget<Container>(
    find
        .descendant(
          of: find.byKey(_dayKey(day)),
          matching: find.byType(Container),
        )
        .first,
  );
  return (container.foregroundDecoration as BoxDecoration?)?.border;
}

Color? _borderColor(BoxBorder? border) =>
    border is Border ? border.top.color : null;

Color? _markerColor(WidgetTester tester, DateTime day) {
  final finder = find.byKey(_dotKey(day));
  if (finder.evaluate().isEmpty) return null;
  final container = tester.widget<Container>(finder);
  return (container.decoration as BoxDecoration?)?.color;
}

Color? _selectedRingColor(WidgetTester tester, DateTime day) {
  final finder = find.byKey(_selectedRingKey(day));
  if (finder.evaluate().isEmpty) return null;
  final container = tester.widget<Container>(finder);
  return _borderColor(
    (container.foregroundDecoration as BoxDecoration?)?.border,
  );
}

Future<void> _tapDay(WidgetTester tester, DateTime day) async {
  await tester.tap(find.byKey(_dayKey(day)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('日格状态、边框与微标识按优先级呈现', (tester) async {
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
      expect(_cellColor(tester, today), colors.selectedBackground);
      expect(_borderColor(_cellOuterBorder(tester, today)), colors.todayBorder);
      expect(_selectedRingColor(tester, today), colors.selectedBorder);
      expect(_markerColor(tester, today), colors.selectedForeground);
      expect(find.byKey(_checkKey(today)), findsNothing);
      expect(_cellColor(tester, hasPlans), colors.hasPlansBackground);
      expect(_borderColor(_cellOuterBorder(tester, hasPlans)), isNull);
      expect(_markerColor(tester, hasPlans), colors.hasPlansForeground);
      expect(_cellColor(tester, allComplete), colors.allCompleteBackground);
      expect(find.byKey(_checkKey(allComplete)), findsOneWidget);
      expect(find.byKey(_dotKey(allComplete)), findsNothing);
      expect(_cellColor(tester, mixed), colors.hasPlansBackground);
      expect(find.byKey(_dotKey(mixed)), findsOneWidget);
      expect(_cellColor(tester, noPlans), isNull);
      expect(find.byKey(_dotKey(noPlans)), findsNothing);
      expect(find.byKey(_checkKey(noPlans)), findsNothing);

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

      await _tapDay(tester, noPlans);
      expect(_cellColor(tester, today), colors.hasPlansBackground);
      expect(_borderColor(_cellOuterBorder(tester, today)), colors.todayBorder);
      expect(_selectedRingColor(tester, today), isNull);
      expect(_markerColor(tester, today), colors.hasPlansForeground);
      expect(_cellColor(tester, noPlans), colors.selectedBackground);
      expect(
        _borderColor(_cellOuterBorder(tester, noPlans)),
        colors.selectedBorder,
      );
      expect(_selectedRingColor(tester, noPlans), isNull);

      await _tapDay(tester, allComplete);
      expect(_cellColor(tester, allComplete), colors.selectedBackground);
      expect(
        _borderColor(_cellOuterBorder(tester, allComplete)),
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
      expect(_cellColor(tester, today), colors.selectedBackground);
      expect(_borderColor(_cellOuterBorder(tester, today)), colors.todayBorder);
      expect(_selectedRingColor(tester, today), colors.selectedBorder);
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

  testWidgets('放假日与有安排/选中同时存在时保留标签且紫蓝可辨', (tester) async {
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

      var colors = PactaCalendarColors.light;
      expect(_cellColor(tester, holiday), colors.hasPlansBackground);
      expect(
        _borderColor(_cellOuterBorder(tester, holiday)),
        colors.todayBorder,
      );
      expect(find.byKey(_dotKey(holiday)), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(_dayKey(holiday)),
          matching: find.text('雨水'),
        ),
        findsOneWidget,
        reason: '放假日短标签与安排底色同时可辨',
      );
      var data = tester
          .getSemantics(find.byKey(_dayKey(holiday)))
          .getSemanticsData();
      expect(data.label, contains('有安排'));
      expect(data.label, contains('今天'));
      expect(_cellColor(tester, otherHoliday), colors.holidayBackground);
      expect(_borderColor(_cellOuterBorder(tester, otherHoliday)), isNull);

      await _tapDay(tester, holiday);
      expect(_cellColor(tester, holiday), colors.selectedBackground);
      expect(
        _borderColor(_cellOuterBorder(tester, holiday)),
        colors.todayBorder,
        reason: '今天+选中时外框保留今天中性色',
      );
      expect(_selectedRingColor(tester, holiday), colors.selectedBorder);
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

      await host.pump(
        tester,
        holiday,
        size: const Size(411, 1200),
        almanac: _assetAlmanac(),
        today: DateTime(2026, 2, 20),
      );
      colors = PactaCalendarColors.light;
      expect(_cellColor(tester, holiday), colors.selectedBackground);
      expect(
        _borderColor(_cellOuterBorder(tester, holiday)),
        colors.selectedBorder,
      );
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
