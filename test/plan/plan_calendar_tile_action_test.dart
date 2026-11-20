import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/plan/calendar_almanac.dart';
import 'package:pacta/src/plan/plan_calendar_view.dart';
import 'package:pacta/src/schedules/schedule_models.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/theme/pacta_theme.dart';

const _user = 'plan-calendar-tile-actions';

final _day = DateTime(2026, 11, 19);

void main() {
  late _Host host;

  setUp(() => host = _Host.create());

  tearDown(() async {
    await host.dispose();
  });

  testWidgets('长按安排弹出与全站一致的操作面板', (tester) async {
    final schedule = await host.addSchedule(title: '晨间阅读');
    await host.pump(tester);

    await tester.longPress(find.text('晨间阅读'));
    await tester.pumpAndSettle();

    // 面板标题就是安排标题；危险操作固定排在最后。
    expect(find.text('晨间阅读'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('pacta-action-edit')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('pacta-action-reschedule')),
      findsOneWidget,
    );
    expect(find.text('标记完成'), findsOneWidget);
    expect(find.byKey(const ValueKey('pacta-action-delete')), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const ValueKey('pacta-action-delete'))).top,
      greaterThan(
        tester.getRect(find.byKey(const ValueKey('pacta-action-edit'))).bottom,
      ),
    );

    await tester.tap(find.text('标记完成'));
    await tester.pumpAndSettle();

    final completed = (await host.repository.getSchedules()).single;
    expect(completed.id, schedule.id);
    expect(completed.isCompleted, isTrue);

    await tester.longPress(find.text('晨间阅读'));
    await tester.pumpAndSettle();
    expect(find.text('标记未完成'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await host.unmount(tester);
  });

  testWidgets('长按删除安排先确认再移除', (tester) async {
    await host.addSchedule(title: '晚间复盘');
    await host.pump(tester);

    await tester.longPress(find.text('晚间复盘'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pacta-action-delete')));
    await tester.pumpAndSettle();

    expect(find.text('删除这条安排？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(await host.repository.getSchedules(), isEmpty);
    expect(find.text('晚间复盘'), findsNothing);
    await host.unmount(tester);
  });

  testWidgets('点按安排仍然直接打开编辑', (tester) async {
    await host.addSchedule(title: '午后散步');
    await host.pump(tester);

    await tester.tap(find.text('午后散步'));
    await tester.pumpAndSettle();

    expect(find.text('编辑安排'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('编辑安排'), findsNothing);
    await host.unmount(tester);
  });
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

  Future<Schedule> addSchedule({required String title}) {
    return repository.createSchedule(
      ScheduleDraft(
        title: title,
        window: ScheduleWindow.timed(
          startsAt: DateTime.utc(_day.year, _day.month, _day.day, 1),
          endsAt: DateTime.utc(_day.year, _day.month, _day.day, 2),
        ),
      ),
    );
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: pactaTheme(Brightness.light),
        home: Scaffold(
          body: SingleChildScrollView(
            child: PlanCalendarView(
              repository: repository,
              goals: const [],
              displayTimeZoneId: 'Asia/Shanghai',
              initialDay: _day,
              now: () => DateTime(2026, 11, 19, 9),
              almanac: CalendarAlmanac(const []),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 在测试体内拆掉整棵树并推进一帧：drift 关闭订阅时排的零时长计时器
  /// 必须在测试结束前消化，否则会以「仍有待处理计时器」失败。
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> dispose() async {
    const limit = Duration(seconds: 10);
    await repository.dispose().timeout(limit, onTimeout: () {});
    await database.close().timeout(limit, onTimeout: () {});
  }
}
