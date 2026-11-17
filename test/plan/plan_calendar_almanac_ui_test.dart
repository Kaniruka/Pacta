import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/plan/calendar_almanac.dart';
import 'package:pacta/src/plan/plan_calendar_view.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

/// T1 的界面断言：日期格第二行与选中日详情都来自随包年度表 + lunar。
const _user = 'plan-calendar-almanac-ui';

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

  Future<void> pump(
    WidgetTester tester,
    DateTime day, {
    required Size size,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: pactaTheme(Brightness.light),
        home: Scaffold(
          body: PlanCalendarView(
            repository: repository,
            goals: const [],
            displayTimeZoneId: 'Asia/Shanghai',
            initialDay: day,
            now: () => day,
            almanac: _assetAlmanac(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 挂载中的 Stream 会让 Drift 的 close 一直等待：先卸载再关闭，并设上限。
  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    const limit = Duration(seconds: 10);
    await repository.dispose().timeout(limit, onTimeout: () {});
    await database.close().timeout(limit, onTimeout: () {});
  }
}

void main() {
  testWidgets('日期格第二行显示节日短标签，选中日显示完整旧历与放假区间', (tester) async {
    final host = _Host.create();
    try {
      await host.pump(
        tester,
        DateTime(2026, 2, 17),
        size: const Size(411, 731),
      );

      expect(find.text('春节'), findsWidgets);
      expect(find.textContaining('正月初一'), findsOneWidget);
      expect(find.textContaining('放假'), findsOneWidget);
      expect(find.textContaining('2月15日–2月23日'), findsOneWidget);
    } finally {
      await host.dispose(tester);
    }
  });

  testWidgets('补班日只在详情说明调休归属，日期格保持旧历', (tester) async {
    final host = _Host.create();
    try {
      await host.pump(
        tester,
        DateTime(2026, 2, 14),
        size: const Size(411, 731),
      );

      expect(find.text('班'), findsNothing, reason: '休/班不进第二行（定案三档）');
      expect(find.textContaining('补班'), findsOneWidget);
    } finally {
      await host.dispose(tester);
    }
  });

  testWidgets('窄屏 360 宽不溢出，节日标签可读', (tester) async {
    final host = _Host.create();
    try {
      await host.pump(tester, DateTime(2026, 4, 5), size: const Size(360, 800));

      expect(find.text('清明'), findsWidgets);
      expect(tester.takeException(), isNull);
    } finally {
      await host.dispose(tester);
    }
  });
}
