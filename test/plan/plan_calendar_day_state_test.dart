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
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
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

/// 日期格里的公历数字颜色。
Color? _dayNumberColor(WidgetTester tester, DateTime day) {
  final finder = find.descendant(
    of: find.byKey(_dayKey(day)),
    matching: find.text('${day.day}'),
  );
  return tester.widget<Text>(finder.first).style?.color;
}

/// 日期格第二行的农历/节气短标签颜色；没有副标签时返回 null。
Color? _subLabelColor(WidgetTester tester, DateTime day) {
  final finder = find.descendant(
    of: find.byKey(_dayKey(day)),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Text &&
          widget.data != null &&
          widget.data != '${day.day}' &&
          widget.data != '今',
    ),
  );
  if (finder.evaluate().isEmpty) return null;
  return tester.widget<Text>(finder.first).style?.color;
}

Rect _dayNumberRect(WidgetTester tester, DateTime day) => tester.getRect(
  find
      .descendant(
        of: find.byKey(_dayKey(day)),
        matching: find.text('${day.day}'),
      )
      .first,
);

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
      expect(_cellColor(tester, noPlans), colors.heat0Background);
      expect(_cellBorder(tester, noPlans), isNull);
      expect(_dayNumberColor(tester, noPlans), colors.heat0Foreground);
      expect(_subLabelColor(tester, noPlans), colors.heat0Foreground);
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
      expect(_cellColor(tester, noPlans), colors.heat0Background);
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

      // 360dp 七列每列 51.43dp，统一 2dp 外间隙后日格仍有 47.43dp 宽、
      // 64dp 高；视觉间隙与看板热力月历一致，且不产生任何溢出。
      final cellRect = tester.getRect(find.byKey(_dayKey(hasPlans)));
      expect(cellRect.width, closeTo(360 / 7 - 4, 0.01));
      expect(cellRect.height, greaterThanOrEqualTo(64));

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
      expect(_cellColor(tester, noPlans), colors.heat0Background);
      expect(_dayNumberColor(tester, noPlans), colors.heat0Foreground);
      expect(_subLabelColor(tester, noPlans), colors.heat0Foreground);
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
  testWidgets('真实 PactaApp 在 360 宽下统一间隙后日格仍不小于 44×64dp', (tester) async {
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
      // 页面在 360dp 下给日历 12dp 页边距：(360-24)/7 = 48dp 列宽，
      // 再让出 2dp×2 的视觉间隙后仍有 44×64dp 的命中区，且零溢出。
      expect(rect.width, greaterThanOrEqualTo(44 - 0.01));
      expect(rect.height, greaterThanOrEqualTo(64));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      const limit = Duration(seconds: 10);
      await schedules.dispose().timeout(limit, onTimeout: () {});
      await tasks.dispose().timeout(limit, onTimeout: () {});
      await database.close().timeout(limit, onTimeout: () {});
    }
  });

  testWidgets('普通日统一 heat0 底块、统一间隙与底部居中指示槽', (tester) async {
    final host = _Host.create();
    try {
      final mixed = DateTime(2026, 11, 16);
      final allComplete = DateTime(2026, 11, 17);
      final today = DateTime(2026, 11, 18);
      final ordinary = DateTime(2026, 11, 19);
      final hasPlans = DateTime(2026, 11, 20);
      final completed = DateTime(2026, 11, 21);
      final ordinaryEnd = DateTime(2026, 11, 22);
      await host.addSchedule(mixed, title: '已完成一项', completed: true);
      await host.addSchedule(mixed, title: '未完成一项');
      await host.addSchedule(allComplete, title: '全部完成', completed: true);
      await host.addSchedule(hasPlans, title: '只有未完成');
      await host.addSchedule(completed, title: '另一天完成', completed: true);
      await host.pump(tester, today, size: const Size(364, 1200), today: today);
      const colors = PactaCalendarColors.light;

      // 普通有效日也铺中性 heat0 底块（不再是 null/白底），公历数字与
      // 农历副标签都取 heat0 前景。
      expect(_cellColor(tester, ordinary), colors.heat0Background);
      expect(_dayNumberColor(tester, ordinary), colors.heat0Foreground);
      expect(_subLabelColor(tester, ordinary), colors.heat0Foreground);
      expect(_cellColor(tester, ordinaryEnd), colors.heat0Background);

      // 七列统一 2dp 外间隙：364/7 = 52dp 列宽，日格 48dp，相邻列间隔 4dp。
      final week = <DateTime>[
        mixed,
        allComplete,
        today,
        ordinary,
        hasPlans,
        completed,
        ordinaryEnd,
      ];
      final widths = <double>[];
      final heights = <double>[];
      final centers = <double>[];
      for (final day in week) {
        final rect = tester.getRect(find.byKey(_dayKey(day)));
        widths.add(rect.width);
        heights.add(rect.height);
        centers.add(_dayNumberRect(tester, day).center.dy);
      }
      for (final width in widths) {
        expect(width, closeTo(364 / 7 - 4, 0.01), reason: '统一 2dp 外间隙');
      }
      // 未选中的日格必须完全等高；今天/选中日只多出 2dp 描边的上下内缩
      // （4dp），内容中心不变，指示槽本身高度恒定。
      final staticHeights = {
        for (var index = 0; index < week.length; index++)
          if (week[index] != today) heights[index],
      };
      expect(staticHeights.length, 1, reason: '恒定底部指示槽让无描边日格等高：$heights');
      expect(
        heights[week.indexOf(today)] - staticHeights.first,
        closeTo(4, 0.01),
        reason: '选中/今天只多出 2dp 描边内缩：$heights',
      );
      final lowestCenter = centers.reduce((a, b) => a < b ? a : b);
      final highestCenter = centers.reduce((a, b) => a > b ? a : b);
      expect(
        highestCenter - lowestCenter,
        lessThanOrEqualTo(0.5),
        reason: '有无状态点的日期数字基线必须齐平：$centers',
      );
      expect(
        tester.getRect(find.byKey(_dayKey(allComplete))).left -
            tester.getRect(find.byKey(_dayKey(mixed))).right,
        closeTo(4, 0.01),
        reason: '相邻日格视觉间隙为 2dp + 2dp',
      );

      // '今' 独占 12dp 顶栏并水平居中，位于公历数字上方。
      final todayCell = tester.getRect(find.byKey(_dayKey(today)));
      final todayLabel = tester.getRect(
        find.descendant(
          of: find.byKey(_dayKey(today)),
          matching: find.text('今'),
        ),
      );
      final todayNumber = _dayNumberRect(tester, today);
      expect(todayLabel.center.dx, closeTo(todayCell.center.dx, 0.5));
      expect(todayLabel.top, greaterThanOrEqualTo(todayCell.top));
      expect(todayLabel.bottom, lessThanOrEqualTo(todayNumber.top));

      // 未完成圆点：5dp，落在底部指示槽的水平中心，且位于日期数字下方。
      final dot = tester.getRect(find.byKey(_dotKey(mixed)));
      final mixedCell = tester.getRect(find.byKey(_dayKey(mixed)));
      final mixedNumber = _dayNumberRect(tester, mixed);
      expect(dot.size, const Size(5, 5));
      expect(dot.center.dx, closeTo(mixedCell.center.dx, 0.5));
      expect(dot.top, greaterThanOrEqualTo(mixedNumber.bottom - 0.01));
      expect(dot.bottom, lessThanOrEqualTo(mixedCell.bottom));
      expect(_markerColor(tester, mixed), colors.hasPlansForeground);

      // 全部完成勾：8dp，完整落在 8dp 槽内（不会上下各溢出 1dp）。
      final check = tester.getRect(find.byKey(_checkKey(allComplete)));
      final completeCell = tester.getRect(find.byKey(_dayKey(allComplete)));
      final completeNumber = _dayNumberRect(tester, allComplete);
      expect(check.size, const Size(8, 8));
      expect(check.center.dx, closeTo(completeCell.center.dx, 0.5));
      expect(check.top, greaterThanOrEqualTo(completeNumber.bottom - 0.01));
      expect(check.bottom, lessThanOrEqualTo(completeCell.bottom));
      expect(
        tester.widget<Icon>(find.byKey(_checkKey(allComplete))).color,
        colors.allCompleteForeground,
      );

      // 普通日没有点/勾，但仍保留同样的底部槽：格子高度与今天/完成日一致。
      expect(find.byKey(_dotKey(ordinary)), findsNothing);
      expect(find.byKey(_checkKey(ordinary)), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await host.dispose(tester);
    }
  });

  testWidgets('320/360 宽与亮暗主题零溢出，农历副标签固定单行', (tester) async {
    final host = _Host.create();
    try {
      final today = DateTime(2026, 2, 17);
      await host.addSchedule(DateTime(2026, 2, 18), title: '假期安排');
      for (final brightness in Brightness.values) {
        for (final width in <double>[320, 360]) {
          await host.pump(
            tester,
            today,
            size: Size(width, 1000),
            brightness: brightness,
            almanac: _assetAlmanac(),
            today: today,
            textScale: 2,
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '$width × $brightness 不允许溢出',
          );
          final label = tester.widget<Text>(
            find.descendant(
              of: find.byKey(_dayKey(today)),
              matching: find.text('春节'),
            ),
          );
          expect(label.maxLines, 1);
          expect(label.softWrap, isFalse);
          expect(label.overflow, TextOverflow.ellipsis);
          final columnWidth = width / 7;
          final cell = tester.getRect(find.byKey(_dayKey(today)));
          expect(
            cell.width,
            closeTo(columnWidth - (columnWidth >= 46 ? 4 : 2), 0.01),
            reason: '$width 宽下统一间隙后的日格宽度',
          );
          expect(cell.height, greaterThanOrEqualTo(64));
        }
      }
    } finally {
      await host.dispose(tester);
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
        // 普通有效日铺 heat0 中性底块：公历数字、农历副标签与 '今' 微字
        // 都必须在这个新底块上达到 AA。
        (colors.heat0Background, colors.heat0Foreground),
        (colors.heat0Background, colors.todayLabelColor),
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
        colors.heat0Background,
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
