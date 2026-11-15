import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

import '../support/fake_auth_repository.dart';

/// 计划页的"今天"来自共享 displayClock，而不是系统时钟：
/// 同一份 fixture 在任意日期运行都看到同一个月份与选中日。
const _user = 'plan-display-clock';

class _Harness {
  _Harness(this.database, {required this.clock});

  final PactaDatabase database;
  final DateTime Function() clock;
  late LocalScheduleRepository schedules;

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    schedules = LocalScheduleRepository(
      database: database,
      userId: _user,
      now: clock,
    );
    await tester.pumpWidget(
      PactaApp(
        authRepository: FakeAuthRepository()..signedInUser = _user,
        scheduleRepositoryFactory: (_) => schedules,
        displayClock: clock,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await schedules.dispose().timeout(
      const Duration(seconds: 10),
      onTimeout: () {},
    );
    await database.close().timeout(
      const Duration(seconds: 10),
      onTimeout: () {},
    );
  }
}

Future<void> _openCalendar(WidgetTester tester) async {
  final bar = find.byType(NavigationBar);
  final host = bar.evaluate().isNotEmpty ? bar : find.byType(NavigationRail);
  await tester.tap(find.descendant(of: host, matching: find.text('计划')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('日历'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('计划日历的今天与可见月份来自共享 displayClock', (tester) async {
    DateTime clock() => DateTime.utc(2027, 2, 10, 9);
    final harness = _Harness(
      PactaDatabase(NativeDatabase.memory()),
      clock: clock,
    );
    try {
      await harness.pump(tester);
      await _openCalendar(tester);

      expect(find.text('2027年2月'), findsOneWidget);
      expect(find.textContaining('2月10日 · 0 项安排'), findsOneWidget);
    } finally {
      await harness.dispose(tester);
    }
  });
}
