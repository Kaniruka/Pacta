import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/notifications/focus_notification_service.dart';
import 'package:pacta/src/plan/plan_calendar_view.dart';
import 'package:pacta/src/plan/plan_target.dart';
import 'package:pacta/src/schedules/schedule_models.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

import '../support/fake_auth_repository.dart';

const _user = 'plan-target';

LocalScheduleRepository _scheduleRepositoryFor(PactaDatabase database) =>
    LocalScheduleRepository(
      database: database,
      userId: _user,
      now: () => DateTime.utc(2026, 11, 15, 9),
    );

/// 只能被测试闸门放行的仓储：全量读取（`from/to` 都为空）会等到闸门打开，
/// 用来制造「旧数据源的迟到结果」。月视图的窗口读取不经过闸门，否则页面
/// 自己的列表也会被卡住。
class _GatedScheduleRepository extends LocalScheduleRepository {
  _GatedScheduleRepository({
    required super.database,
    required super.userId,
    required this.gate,
  }) : super(now: () => DateTime.utc(2026, 11, 15, 9));

  final Completer<void> gate;

  @override
  Future<List<Schedule>> getSchedules({DateTime? from, DateTime? to}) async {
    if (from == null && to == null) await gate.future;
    return super.getSchedules(from: from, to: to);
  }
}

/// 直接写入一条固定 id 的安排：两个数据源用同一个 id 才能验证迟到的
/// 旧结果会不会把用户带到另一个账号的日期。
Future<void> _insertSchedule(
  PactaDatabase database, {
  required String userId,
  required String id,
  required String title,
  required DateTime startsAt,
  required DateTime endsAt,
}) async {
  await database
      .into(database.localSchedules)
      .insert(
        LocalSchedulesCompanion.insert(
          userId: userId,
          id: id,
          title: title,
          startsAt: startsAt,
          endsAt: endsAt,
          createdAt: DateTime.utc(2026, 11, 1),
          updatedAt: DateTime.utc(2026, 11, 1),
        ),
      );
}

/// 只借用通知点击这条真实入口，其余通知能力全部关闭：不读设备偏好、
/// 不碰平台通道，因此 dispose 立即返回（真实服务的 dispose 会等待后台工作）。
class _NotificationTapProbe extends DisabledFocusNotificationService {
  void tap(String payload) => handleNotificationResponse(
    NotificationResponse(
      notificationResponseType: NotificationResponseType.selectedNotification,
      id: 2206,
      payload: payload,
    ),
  );
}

void main() {
  group('PlanTarget 解析', () {
    test('plan-day 打开账号时区里的日历日', () {
      final target = PlanTarget.tryParse('plan-day:2026-12-03');
      expect(target, isNotNull);
      expect(target!.day, DateTime(2026, 12, 3));
      expect(target.scheduleId, isNull);
    });

    test('plan-item 带上要定位的安排', () {
      final target = PlanTarget.tryParse('plan-item:2026-12-03:schedule-42');
      expect(target!.day, DateTime(2026, 12, 3));
      expect(target.scheduleId, 'schedule-42');
    });

    test('不是 Plan 目标或日期非法时返回 null，交给其他通知分支', () {
      expect(PlanTarget.tryParse('session:abc'), isNull);
      expect(PlanTarget.tryParse('daily-open-reminder:1'), isNull);
      expect(PlanTarget.tryParse('plan-day:2026-02-30'), isNull);
      expect(PlanTarget.tryParse('plan-item:2026-12-03:'), isNull);
      expect(PlanTarget.tryParse('plan-item:2026-12-03'), isNull);
    });
  });

  group('PlanTarget 负载编码', () {
    test('plan-day 使用补零的公民日', () {
      expect(PlanTarget.encodeDay(DateTime(2026, 1, 5)), 'plan-day:2026-01-05');
      expect(
        PlanTarget.tryParse(PlanTarget.encodeDay(DateTime(2026, 1, 5)))!.day,
        DateTime(2026, 1, 5),
      );
    });

    test('安排标识里的冒号与百分号被转义，解码后原样还原', () {
      const opaqueId = 'sched:a%b c/2026';
      final payload = PlanTarget.encodeItem(DateTime(2026, 12, 3), opaqueId);
      expect(payload, startsWith('plan-item:2026-12-03:'));
      expect(payload.contains('sched:a'), isFalse, reason: '冒号不能留在负载里');
      final parsed = PlanTarget.tryParse(payload);
      expect(parsed, isNotNull);
      expect(parsed!.day, DateTime(2026, 12, 3));
      expect(parsed.scheduleId, opaqueId);
      expect(parsed, PlanTarget(day: parsed.day, scheduleId: opaqueId));
    });

    test('opaque 标识的首尾空格与中文/百分号原样往返，不被改写', () {
      const raw = ' id:百分% 中文 ';
      final payload = PlanTarget.encodeItem(DateTime(2026, 11, 16), raw);
      final parsed = PlanTarget.tryParse(payload);
      expect(parsed, isNotNull);
      expect(parsed!.scheduleId, raw, reason: '首尾空格也是标识的一部分');
      expect(parsed.scheduleId, isNot('id:百分% 中文'));
      expect(parsed, PlanTarget(day: DateTime(2026, 11, 16), scheduleId: raw));
    });

    test('非法转义或空标识不是 Plan 目标', () {
      expect(PlanTarget.tryParse('plan-item:2026-12-03:%zz'), isNull);
      expect(PlanTarget.tryParse('plan-item:2026-12-03:%'), isNull);
      expect(PlanTarget.tryParse('plan-item:2026-12-03:%20'), isNull);
      expect(PlanTarget.tryParse('plan-item:2026-12-03:%09'), isNull);
    });

    test('全空白标识不能生成负载，但首尾空格会保留', () {
      expect(
        () => PlanTarget.encodeItem(DateTime(2026, 12, 3), '   '),
        throwsArgumentError,
      );
      expect(
        PlanTarget.tryParse(
          PlanTarget.encodeItem(DateTime(2026, 12, 3), ' a '),
        )!.scheduleId,
        ' a ',
      );
    });
  });

  testWidgets('带 Plan 目标打开日历时直接选中那一天', (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = PactaDatabase(NativeDatabase.memory());
    final repository = _scheduleRepositoryFor(database);
    addTearDown(() async {
      await repository.dispose();
      await database.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: pactaTheme(Brightness.light),
        home: Scaffold(
          body: PlanCalendarView(
            repository: repository,
            goals: const [],
            displayTimeZoneId: 'Etc/UTC',
            now: () => DateTime.utc(2026, 11, 15, 9),
            initialDay: DateTime(2026, 12, 3),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2026年12月'), findsOneWidget);
    expect(find.textContaining('12月3日 · 0 项安排'), findsOneWidget);
  });

  testWidgets('通知定位的安排被强调；改期后跟它当前所在的账号时区日', (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = PactaDatabase(NativeDatabase.memory());
    final repository = _scheduleRepositoryFor(database);
    addTearDown(() async {
      await repository.dispose();
      await database.close();
    });
    final schedule = await repository.createSchedule(
      ScheduleDraft(
        title: '周会',
        window: ScheduleWindow.timed(
          startsAt: DateTime.utc(2026, 11, 16, 9),
          endsAt: DateTime.utc(2026, 11, 16, 10),
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: pactaTheme(Brightness.light),
        home: Scaffold(
          body: PlanCalendarView(
            repository: repository,
            goals: const [],
            displayTimeZoneId: 'Etc/UTC',
            now: () => DateTime.utc(2026, 11, 15, 9),
            // 负载里的日期是安排被改期前的旧值：日历跟安排当前所在的日。
            initialDay: DateTime(2026, 12, 3),
            highlightScheduleId: schedule.id,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2026年11月'), findsOneWidget);
    expect(find.textContaining('11月16日 · 1 项安排'), findsOneWidget);
    expect(
      find.byKey(ValueKey('schedule-highlight-${schedule.id}')),
      findsOneWidget,
    );

    // 用户自己换一天：强调退场，但安排本身不受影响。
    await tester.tap(find.text('17'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('schedule-highlight-${schedule.id}')),
      findsNothing,
    );
    expect(find.textContaining('11月17日 · 0 项安排'), findsOneWidget);
  });

  testWidgets('通知里的安排已不存在时只打开那一天，不猜、不建专注', (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = PactaDatabase(NativeDatabase.memory());
    final repository = _scheduleRepositoryFor(database);
    addTearDown(() async {
      await repository.dispose();
      await database.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: pactaTheme(Brightness.light),
        home: Scaffold(
          body: PlanCalendarView(
            repository: repository,
            goals: const [],
            displayTimeZoneId: 'Etc/UTC',
            now: () => DateTime.utc(2026, 11, 15, 9),
            initialDay: DateTime(2026, 12, 3),
            highlightScheduleId: 'deleted-schedule',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2026年12月'), findsOneWidget);
    expect(find.textContaining('12月3日 · 0 项安排'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('schedule-highlight-deleted-schedule')),
      findsNothing,
    );
  });

  testWidgets('迟到的旧数据源结果不会把已切换账号的安排定位到旧日期', (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const sharedId = 'shared-schedule-id';
    // 本用例故意同时开两个内存数据库（两个账号）；它们各有独立的
    // QueryExecutor，drift 的“多个实例”提示在这里是误报。
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final oldDatabase = PactaDatabase(NativeDatabase.memory());
    final newDatabase = PactaDatabase(NativeDatabase.memory());
    final gate = Completer<void>();
    final oldRepository = _GatedScheduleRepository(
      database: oldDatabase,
      userId: _user,
      gate: gate,
    );
    final newRepository = LocalScheduleRepository(
      database: newDatabase,
      userId: 'plan-target-other-account',
      now: () => DateTime.utc(2026, 11, 15, 9),
    );
    addTearDown(() async {
      if (!gate.isCompleted) gate.complete();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await oldRepository.dispose();
      await newRepository.dispose();
      await oldDatabase.close();
      await newDatabase.close();
    });
    // 同一个 id 在两个账号里是两条不同的安排：旧账号 11 月，新账号 12 月。
    await _insertSchedule(
      oldDatabase,
      userId: _user,
      id: sharedId,
      title: '旧账号安排',
      startsAt: DateTime.utc(2026, 11, 16, 9),
      endsAt: DateTime.utc(2026, 11, 16, 10),
    );
    await _insertSchedule(
      newDatabase,
      userId: 'plan-target-other-account',
      id: sharedId,
      title: '新账号安排',
      startsAt: DateTime.utc(2026, 12, 20, 9),
      endsAt: DateTime.utc(2026, 12, 20, 10),
    );

    Widget build(PlanCalendarView view) => MaterialApp(
      theme: pactaTheme(Brightness.light),
      home: Scaffold(body: view),
    );
    PlanCalendarView viewFor(LocalScheduleRepository repository) =>
        PlanCalendarView(
          repository: repository,
          goals: const [],
          displayTimeZoneId: 'Etc/UTC',
          now: () => DateTime.utc(2026, 11, 15, 9),
          initialDay: DateTime(2026, 11, 16),
          highlightScheduleId: sharedId,
        );

    // 旧数据源的定位读取被闸门挡住，页面先按负载日期显示。
    await tester.pumpWidget(build(viewFor(oldRepository)));
    await tester.pumpAndSettle();
    expect(find.textContaining('11月16日 · 1 项安排'), findsOneWidget);

    // 换成另一个账号的同 id 数据源：应立刻按新源改到 12 月 20 日。
    await tester.pumpWidget(build(viewFor(newRepository)));
    await tester.pumpAndSettle();
    expect(find.text('2026年12月'), findsOneWidget);
    expect(find.textContaining('12月20日 · 1 项安排'), findsOneWidget);
    expect(find.text('新账号安排'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('schedule-highlight-$sharedId')),
      findsOneWidget,
    );

    // 旧数据源的迟到结果不能把页面拉回 11 月。
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('2026年12月'), findsOneWidget);
    expect(find.textContaining('12月20日 · 1 项安排'), findsOneWidget);
    expect(find.textContaining('11月16日 · 1 项安排'), findsNothing);
    expect(find.text('旧账号安排'), findsNothing);
  });

  testWidgets('安排提醒打开计划日历并强调该安排，不创建专注会话或预约', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
          (_) async => null,
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(
              'dev.fluttercommunity.plus/connectivity_status',
            ),
            null,
          ),
    );
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = PactaDatabase(NativeDatabase.memory());
    final schedules = _scheduleRepositoryFor(database);
    final focus = LocalFocusRepository(
      database: database,
      userId: _user,
      remote: InMemoryFocusRemote(),
      cloudSyncEnabled: false,
      now: () => DateTime.utc(2026, 11, 15, 9),
    );
    addTearDown(() async {
      // 先卸掉 widget 树，取消页面对数据库的订阅，再关仓储；关闭 async* 流
      // 需要帧推进，等不到就抛错，不用 onTimeout 兜底。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await _pumpUntil(tester, focus.dispose(), 'focus.dispose');
      await _pumpUntil(tester, schedules.dispose(), 'schedules.dispose');
      await _pumpUntil(tester, database.close(), 'database.close');
    });
    final schedule = await schedules.createSchedule(
      ScheduleDraft(
        title: '取快递',
        window: ScheduleWindow.timed(
          startsAt: DateTime.utc(2026, 11, 16, 9),
          endsAt: DateTime.utc(2026, 11, 16, 10),
        ),
      ),
    );
    final service = _NotificationTapProbe();

    await tester.pumpWidget(
      PactaApp(
        authRepository: FakeAuthRepository()..signedInUser = _user,
        scheduleRepositoryFactory: (_) => schedules,
        focusRepositoryFactory: (_) => focus,
        focusNotificationService: service,
        displayClock: () => DateTime.utc(2026, 11, 15, 9),
      ),
    );
    await _pumpFrames(tester);
    expect(_selectedDestination(tester), 0);

    service.tap(PlanTarget.encodeItem(DateTime(2026, 11, 16), schedule.id));
    await _pumpFrames(tester);

    expect(_selectedDestination(tester), 1, reason: '安排提醒只切到计划目的地');
    expect(find.text('新建安排'), findsOneWidget);
    expect(
      find.byKey(ValueKey('schedule-highlight-${schedule.id}')),
      findsOneWidget,
    );
    expect(await focus.getActiveSession(), isNull);
    expect(await focus.getActiveAppointment(), isNull);
    expect(tester.takeException(), isNull);
  });
}

/// 边推进帧边等待 future；等不到就抛错（不吞超时）。
Future<void> _pumpUntil(
  WidgetTester tester,
  Future<void> future,
  String label,
) async {
  Object? failure;
  var finished = false;
  future.then(
    (_) => finished = true,
    onError: (Object error) {
      failure = error;
      finished = true;
    },
  );
  for (var attempt = 0; attempt < 200 && !finished; attempt++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  if (!finished) {
    throw StateError('$label 在推进 200 帧后仍未完成（不吞超时）');
  }
  if (failure != null) throw failure!;
}

Future<void> _pumpFrames(WidgetTester tester, {int frames = 24}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

int _selectedDestination(WidgetTester tester) {
  final bar = find.byType(NavigationBar);
  if (bar.evaluate().isNotEmpty) {
    return tester.widget<NavigationBar>(bar).selectedIndex;
  }
  return tester
          .widget<NavigationRail>(find.byType(NavigationRail))
          .selectedIndex ??
      0;
}
