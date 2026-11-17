import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/plan/plan_calendar_view.dart';
import 'package:pacta/src/schedules/schedule_models.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';

/// 可控日程源：测试自己决定什么时候 emit。
class _DeferredSchedules extends UnavailableScheduleRepository {
  final StreamController<List<Schedule>> events =
      StreamController<List<Schedule>>();
  int subscriptions = 0;

  @override
  Stream<List<Schedule>> watchSchedules({DateTime? from, DateTime? to}) {
    subscriptions += 1;
    return events.stream;
  }
}

/// 按订阅次数返回不同流的源：用来模拟"先失败、重试后成功"。
class _ScriptedSchedules extends UnavailableScheduleRepository {
  _ScriptedSchedules(this.script);

  final List<Stream<List<Schedule>> Function()> script;
  int subscriptions = 0;

  @override
  Stream<List<Schedule>> watchSchedules({DateTime? from, DateTime? to}) {
    final index = subscriptions < script.length
        ? subscriptions
        : script.length - 1;
    subscriptions += 1;
    return script[index]();
  }
}

Schedule _row(String title, {String id = 'row-1'}) => Schedule(
  id: id,
  title: title,
  startsAt: DateTime.utc(2026, 11, 15, 9),
  endsAt: DateTime.utc(2026, 11, 15, 10),
  createdAt: DateTime.utc(2026, 11, 15, 9),
  updatedAt: DateTime.utc(2026, 11, 15, 9),
);

Widget _calendar(ScheduleRepository repository, {String zone = 'Etc/UTC'}) {
  return MaterialApp(
    theme: pactaTheme(Brightness.light),
    home: Scaffold(
      body: SingleChildScrollView(
        child: PlanCalendarView(
          repository: repository,
          goals: const [],
          displayTimeZoneId: zone,
          initialDay: DateTime(2026, 11, 15),
          now: () => DateTime.utc(2026, 11, 15, 9),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('换仓储立刻清掉上一 owner 的行，新流 emit 前不显示旧数据', (tester) async {
    final previousOwner = _DeferredSchedules();
    final newOwner = _DeferredSchedules();
    addTearDown(() async {
      await previousOwner.events.close();
      await newOwner.events.close();
    });

    await tester.pumpWidget(_calendar(previousOwner));
    previousOwner.events.add([_row('previous owner item')]);
    await tester.pumpAndSettle();
    expect(find.text('previous owner item'), findsOneWidget);

    // 上一 owner 的事件已排上队，紧接着换源：旧行不能借这一帧回显。
    previousOwner.events.add([_row('late from old owner', id: 'old-2')]);
    await tester.pumpWidget(_calendar(newOwner));
    await tester.pump();
    expect(
      find.text('previous owner item'),
      findsNothing,
      reason: '新流尚未 emit 时不得显示上一 owner 的行',
    );
    expect(find.text('late from old owner'), findsNothing);
    expect(find.text('正在读取安排…'), findsOneWidget);
    expect(find.textContaining('0 项安排'), findsNothing, reason: '读取中不能冒充空内容');
    expect(newOwner.subscriptions, 1);

    newOwner.events.add([_row('new owner item', id: 'new-1')]);
    await tester.pumpAndSettle();
    expect(find.text('new owner item'), findsOneWidget);
    expect(find.text('正在读取安排…'), findsNothing);
    expect(find.textContaining('1 项安排'), findsOneWidget);
  });

  testWidgets('读取失败给出可见失败与只读重试，不冒充空安排；重试后恢复', (tester) async {
    final repository = _ScriptedSchedules([
      () => Stream<List<Schedule>>.error(StateError('storage unavailable')),
      () => Stream<List<Schedule>>.value([_row('重试后的安排', id: 'recovered')]),
    ]);

    await tester.pumpWidget(_calendar(repository));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('plan-schedules-error')), findsOneWidget);
    expect(find.text('暂时不能读取安排。'), findsOneWidget);
    expect(find.textContaining('读取失败'), findsOneWidget);
    expect(find.text('这一天还没有安排。用上方「新建安排」添加。'), findsNothing, reason: '失败不是空内容');
    expect(find.textContaining('0 项安排'), findsNothing);
    expect(repository.subscriptions, 1);

    await tester.ensureVisible(
      find.byKey(const ValueKey('plan-schedules-retry')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('plan-schedules-retry')));
    await tester.pumpAndSettle();
    expect(repository.subscriptions, 2, reason: '重试只重新订阅');
    expect(find.text('暂时不能读取安排。'), findsNothing);
    expect(find.text('重试后的安排'), findsOneWidget);
    expect(find.textContaining('1 项安排'), findsOneWidget);
    expect(find.text('正在读取安排…'), findsNothing);
  });

  testWidgets('正常空内容保留空态文案', (tester) async {
    final repository = _ScriptedSchedules([
      () => Stream<List<Schedule>>.value(const <Schedule>[]),
    ]);
    await tester.pumpWidget(_calendar(repository));
    await tester.pumpAndSettle();
    expect(find.text('这一天还没有安排。用上方「新建安排」添加。'), findsOneWidget);
    expect(find.textContaining('0 项安排'), findsOneWidget);
    expect(find.text('暂时不能读取安排。'), findsNothing);
  });

  testWidgets('换月窗口立刻清掉上一窗口的行，旧窗口迟到事件不回显', (tester) async {
    final november = StreamController<List<Schedule>>();
    final december = StreamController<List<Schedule>>();
    addTearDown(() async {
      await november.close();
      await december.close();
    });
    final repository = _ScriptedSchedules([
      () => november.stream,
      () => december.stream,
    ]);

    await tester.pumpWidget(_calendar(repository));
    november.add([_row('本月安排')]);
    await tester.pumpAndSettle();
    expect(find.text('本月安排'), findsOneWidget);

    await tester.tap(find.byTooltip('下个月'));
    await tester.pump();
    expect(find.text('本月安排'), findsNothing, reason: '换窗口先清空再等新窗口');
    expect(find.text('正在读取安排…'), findsOneWidget);
    expect(repository.subscriptions, 2);

    november.add([_row('old window late', id: 'late')]);
    await tester.pump();
    expect(find.text('old window late'), findsNothing);

    december.add(const <Schedule>[]);
    await tester.pumpAndSettle();
    expect(find.text('本月安排'), findsNothing);
    expect(find.textContaining('0 项安排'), findsOneWidget);
  });
}
