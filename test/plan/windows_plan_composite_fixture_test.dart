import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/profile/avatar_image.dart';
import 'package:pacta/src/profile/profile_remote.dart';
import 'package:pacta/src/profile/profile_repository.dart';
import 'package:pacta/src/schedules/schedule_models.dart';
import 'package:pacta/src/schedules/schedule_repeat.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../support/fake_auth_repository.dart';

/// 可复跑的 Windows 内存组合 fixture。
///
/// 一次运行覆盖：无系统日历时的自有安排、账号时区（含另一台设备先写入的
/// 冲突）、重复创建与两种修改范围、提醒配置保留、预约准备 5/10/15/自定义
/// 及一次自动交接。全部使用内存数据库与注入时钟；真实 MiSans、显式亮暗与
/// 窄宽视口，断言落库状态与关键几何，不读取用户数据或系统日历。
const _user = 'windows-plan-composite';

class _ConflictProfileRemote implements ProfileRemote {
  _ConflictProfileRemote() {
    _zone = 'Asia/Tokyo';
    _revision = 1;
  }

  late String _zone;
  late int _revision;

  /// 另一台设备先写入的值；下一次保存会以此为准并报告冲突。
  void anotherDeviceWrote(String zone) {
    _zone = zone;
    _revision += 1;
  }

  RemoteProfile _snapshot({bool conflict = false, String? name}) =>
      RemoteProfile(
        displayName: name ?? '夹具用户',
        avatar: null,
        updatedAt: DateTime.utc(2026, 11, 15),
        displayTimeZoneId: _zone,
        timeZoneRevision: _revision,
        timeZoneConflict: conflict,
      );

  @override
  bool get isAvailable => true;

  @override
  Future<RemoteProfile?> fetch({required String userId}) async => _snapshot();

  @override
  Future<RemoteProfile> save({
    required String userId,
    required String displayName,
    required ProfileAvatar? avatar,
    required DateTime updatedAt,
    String? displayTimeZoneId,
    int? timeZoneRevision,
  }) async {
    if (displayTimeZoneId != null && timeZoneRevision != _revision) {
      return _snapshot(conflict: true);
    }
    if (displayTimeZoneId != null) {
      _zone = displayTimeZoneId;
      _revision += 1;
    }
    return _snapshot(name: displayName);
  }

  @override
  Future<RemoteProfile?> initializeTimeZone({
    required String userId,
    required String displayTimeZoneId,
  }) async => _snapshot();
}

class _CompositeFixture {
  _CompositeFixture({required this.scenario})
    : directory = Directory(
        '${Directory.systemTemp.path}/pacta-windows-plan-$scenario-'
        '${DateTime.now().microsecondsSinceEpoch}',
      )..createSync(recursive: true);

  final String scenario;
  final Directory directory;
  var clock = DateTime.utc(2026, 11, 15, 9);
  final praiseRemote = _ConflictProfileRemote();

  late final PactaDatabase database = PactaDatabase(NativeDatabase.memory());
  late final LocalTaskRepository tasks = LocalTaskRepository(
    database: database,
    userId: _user,
    remote: InMemoryTaskRemote(),
    now: () => clock,
  );
  late final LocalFocusRepository focus = LocalFocusRepository(
    database: database,
    userId: _user,
    remote: InMemoryFocusRemote(),
    now: () => clock,
  );
  late final LocalScheduleRepository schedules = LocalScheduleRepository(
    database: database,
    userId: _user,
    now: () => clock,
  );
  late final LocalProfileRepository profiles = LocalProfileRepository(
    database: database,
    userId: _user,
    remote: praiseRemote,
    now: () => clock,
  );

  Future<void> pump(
    WidgetTester tester, {
    required Size size,
    required Brightness brightness,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(
      PactaApp(
        authRepository: FakeAuthRepository()..signedInUser = _user,
        taskRepositoryFactory: (_) => tasks,
        focusRepositoryFactory: (_) => focus,
        scheduleRepositoryFactory: (_) => schedules,
        profileRepositoryFactory: (_) => profiles,
        displayClock: () => clock,
      ),
    );
    await settle(tester);
  }

  /// 只容忍已知的 pumpAndSettle 超时；其他异常一律上抛，不掩盖真实失败。
  Future<void> settle(WidgetTester tester) async {
    try {
      await tester.pumpAndSettle();
    } on FlutterError catch (error) {
      if (!error.message.contains('pumpAndSettle timed out')) rethrow;
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  void record(List<String> assertions) {
    File('${directory.path}/fixture.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'scenario': scenario,
        'clock': clock.toIso8601String(),
        'assertions': assertions,
      }),
    );
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    const limit = Duration(seconds: 10);
    await focus.dispose().timeout(limit, onTimeout: () {});
    await schedules.dispose().timeout(limit, onTimeout: () {});
    await profiles.dispose().timeout(limit, onTimeout: () {});
    await database.close().timeout(limit, onTimeout: () {});
  }
}

Future<void> _openPlanCalendar(WidgetTester tester) async {
  final bar = find.byType(NavigationBar);
  final host = bar.evaluate().isNotEmpty ? bar : find.byType(NavigationRail);
  await tester.tap(find.descendant(of: host, matching: find.text('计划')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('日历'));
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fontLoader = FontLoader('MiSans')
    ..addFont(rootBundle.load('assets/fonts/MiSans-Regular.ttf'));

  setUpAll(() async {
    await fontLoader.load();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          (call) async => call.method == 'getLocalTimezone' ? 'Etc/UTC' : null,
        );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          null,
        );
  });

  testWidgets('Windows 无系统日历：导入说明可读，自有安排仍可增改', (tester) async {
    final fixture = _CompositeFixture(
      scenario: 'calendar-unsupported-dark-narrow',
    );
    try {
      expect(fixture.directory.isAbsolute, isTrue);
      expect(fixture.directory.existsSync(), isTrue);
      await fixture.pump(
        tester,
        size: const Size(360, 800),
        brightness: Brightness.dark,
      );
      await _openPlanCalendar(tester);

      await tester.tap(find.byKey(const ValueKey('plan-import-open')));
      await tester.pumpAndSettle();
      expect(find.text('这台设备暂时不能读取系统日历；你自己的安排仍可新建和编辑。'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await fixture.settle(tester);

      await tester.tap(find.text('添加事项'));
      await fixture.settle(tester);
      await tester.enterText(_field('名称'), '离线整理');
      await tester.tap(find.text('保存'));
      await fixture.settle(tester);

      expect(find.text('离线整理'), findsOneWidget);
      expect((await fixture.schedules.getSchedules()).single.title, '离线整理');
      expect(find.text('新建安排'), findsOneWidget);
      final newButton = tester.getSize(find.text('新建安排'));
      expect(newButton.height, greaterThan(0));
      expect(tester.takeException(), isNull, reason: '360 宽 + MiSans 不溢出');
      fixture.record(const [
        'owned-crud',
        'unsupported-calendar',
        'no-overflow',
      ]);
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets('账号时区决定 Plan 时间；另一台设备先写入时采用最新值', (tester) async {
    final fixture = _CompositeFixture(
      scenario: 'profile-zone-conflict-light-wide',
    );
    try {
      await fixture.profiles.ensureDisplayTimeZone(
        deviceTimeZoneId: 'Asia/Tokyo',
      );
      await fixture.schedules.createSchedule(
        ScheduleDraft(
          title: '晨会',
          window: ScheduleWindow.timed(
            startsAt: DateTime.utc(2026, 11, 15, 9),
            endsAt: DateTime.utc(2026, 11, 15, 10),
          ),
        ),
      );
      await fixture.pump(
        tester,
        size: const Size(1280, 900),
        brightness: Brightness.light,
      );
      await _openPlanCalendar(tester);

      // 09:00Z 在账号时区东京是 18:00；设备时区固定 UTC，不参与显示。
      expect(find.text('18:00–19:00'), findsOneWidget);

      fixture.praiseRemote.anotherDeviceWrote('Europe/London');
      final saved = await fixture.profiles.saveProfile(
        displayName: '夹具用户',
        timeZoneId: 'America/New_York',
      );
      expect(saved.displayTimeZoneId, 'Europe/London');
      await fixture.settle(tester);
      // 冲突时采用账号已接受的最新时区：伦敦 11 月为 UTC+0。
      expect(find.text('09:00–10:00'), findsOneWidget);
      expect(find.text('18:00–19:00'), findsNothing);
      fixture.record(const [
        'account-zone',
        'conflict-adopts-latest',
        'wide-light',
      ]);
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets('重复创建可改范围，提醒配置在重开后保留', (tester) async {
    final fixture = _CompositeFixture(scenario: 'recurrence-scopes-light-wide');
    try {
      await fixture.pump(
        tester,
        size: const Size(1280, 1600),
        brightness: Brightness.light,
      );
      await fixture.schedules.createRecurringSchedule(
        draft: ScheduleDraft(
          title: '每日站会',
          window: ScheduleWindow.timed(
            startsAt: DateTime.utc(2026, 11, 13, 9),
            endsAt: DateTime.utc(2026, 11, 13, 10),
          ),
        ),
        repeat: const ScheduleRepeatSpec(
          frequency: ScheduleRepeatFrequency.daily,
        ),
        timeZoneId: 'Etc/UTC',
      );
      final today = (await fixture.schedules.getSchedules(
        from: DateTime.utc(2026, 11, 15),
        to: DateTime.utc(2026, 11, 16),
      )).single;
      await fixture.schedules.setScheduleReminder(today.id, minutesBefore: 10);
      await fixture.settle(tester);
      await _openPlanCalendar(tester);
      expect(find.text('提前 10 分钟提醒'), findsOneWidget);

      final ruleBefore = (await fixture.schedules.getRecurrenceRules()).single;
      await tester.tap(find.text('每日站会'));
      await fixture.settle(tester);
      expect(find.text('仅本次'), findsOneWidget);
      expect(find.text('本次及以后'), findsOneWidget);
      await tester.enterText(_field('名称'), '每日站会（仅本次）');
      await tester.tap(find.text('保存'));
      await fixture.settle(tester);
      expect(
        (await fixture.schedules.getRecurrenceRules()).single.id,
        ruleBefore.id,
      );
      final edited = (await fixture.schedules.getSchedules(
        from: DateTime.utc(2026, 11, 15),
        to: DateTime.utc(2026, 11, 16),
      )).single;
      expect(edited.isRecurrenceException, isTrue);
      expect(edited.reminderMinutesBefore, 10, reason: '仅本次不改实例提醒');

      // 关掉再打开：提醒配置来自持久化数据，不是页面内存。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await fixture.pump(
        tester,
        size: const Size(1280, 1600),
        brightness: Brightness.light,
      );
      await _openPlanCalendar(tester);
      expect(find.text('提前 10 分钟提醒'), findsOneWidget);

      await tester.tap(find.text('每日站会（仅本次）'));
      await fixture.settle(tester);
      await tester.tap(find.text('本次及以后'));
      await fixture.settle(tester);
      await tester.enterText(_field('名称'), '每日站会（新规则）');
      await tester.ensureVisible(find.byType(DropdownButtonFormField<int?>));
      await fixture.settle(tester);
      // 模板当前无提醒：点字段显示的"不提醒"打开菜单。
      await tester.tap(find.text('不提醒').last);
      await fixture.settle(tester);
      await tester.tap(find.text('提前 15 分钟').last);
      await fixture.settle(tester);
      await tester.tap(find.text('保存'));
      await fixture.settle(tester);
      final rules = await fixture.schedules.getRecurrenceRules();
      expect(rules, hasLength(2));
      expect(
        rules
            .singleWhere((rule) => rule.firstDate == '2026-11-15')
            .reminderMinutesBefore,
        15,
        reason: '本次及以后把可见提醒写进规则模板',
      );
      fixture.record(const [
        'recurrence-scope',
        'reminder-persisted',
        'reminder-template',
        'wide-light',
      ]);
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets('预约准备 5/10/15/自定义可用，准备结束只交接一次', (tester) async {
    final fixture = _CompositeFixture(
      scenario: 'preparation-handoff-light-wide',
    );
    try {
      await fixture.pump(
        tester,
        size: const Size(1280, 900),
        brightness: Brightness.light,
      );
      final goal = await fixture.tasks.createGoal(
        const GoalDraft(
          title: '交付',
          classification: TaskClassification.regular,
        ),
      );
      final task = await fixture.tasks.createTask(
        goal.id,
        const TaskDraft(
          title: '写总结',
          classification: TaskClassification.regular,
        ),
      );
      await fixture.settle(tester);
      final bar = find.byType(NavigationBar);
      final host = bar.evaluate().isNotEmpty
          ? bar
          : find.byType(NavigationRail);
      await tester.tap(find.descendant(of: host, matching: find.text('计划')));
      await fixture.settle(tester);

      await tester.tap(find.byTooltip('开始专注'));
      await fixture.settle(tester);
      expect(find.text('预约准备时长'), findsOneWidget);
      for (final label in ['5 分钟', '10 分钟', '15 分钟', '自定义']) {
        expect(find.text(label), findsOneWidget, reason: '准备预设 $label');
      }
      // 自定义：7 分钟准备，先验证落库再取消，不留下第二个活动预约。
      await tester.tap(find.text('自定义'));
      await fixture.settle(tester);
      await tester.enterText(_field('自定义准备时长（分钟）'), '7');
      await tester.pump();
      await tester.tap(find.text('开始准备（7分钟）'));
      await fixture.settle(tester);
      final custom = (await fixture.focus.getActiveAppointment())!;
      expect(custom.preparationSeconds, 420);
      await fixture.focus.cancelAppointment(
        appointmentId: custom.id,
        failureReason: '切换准备时长',
      );
      // 取消后重新打开，回到计划页再用预设档开始，避免停留在准备页。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await fixture.pump(
        tester,
        size: const Size(1280, 900),
        brightness: Brightness.light,
      );
      final reopenedBar = find.byType(NavigationBar);
      final reopenedHost = reopenedBar.evaluate().isNotEmpty
          ? reopenedBar
          : find.byType(NavigationRail);
      await tester.tap(
        find.descendant(of: reopenedHost, matching: find.text('计划')),
      );
      await fixture.settle(tester);

      await tester.tap(find.byTooltip('开始专注'));
      await fixture.settle(tester);
      await tester.tap(find.text('5 分钟'));
      await fixture.settle(tester);
      await tester.tap(find.text('开始准备（5分钟）'));
      await fixture.settle(tester);

      final appointment = (await fixture.focus.getActiveAppointment())!;
      expect(appointment.preparationSeconds, 300);
      expect(appointment.taskId, task.id);

      // 准备结束：自动交接一次，重复结算不产生第二个会话。
      fixture.clock = fixture.clock.add(const Duration(minutes: 6));
      await fixture.focus.settleDueAppointments();
      final session = await fixture.focus.getActiveSession();
      expect(session, isNotNull);
      expect(session!.taskId, task.id);
      await fixture.focus.settleDueAppointments();
      expect((await fixture.focus.getActiveSession())!.id, session.id);
      fixture.record(const [
        'preparation-presets',
        'single-handoff',
        'wide-light',
      ]);
    } finally {
      await fixture.dispose(tester);
    }
  });
}
