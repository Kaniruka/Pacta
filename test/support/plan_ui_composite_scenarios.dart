import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

import 'fake_auth_repository.dart';

/// 07 计划 UI 组合场景的唯一实现。
///
/// 四个场景（无系统日历 + 自有增改、账号时区与另一台设备写入的冲突、重复
/// 范围与提醒模板、预约准备 5/10/15/自定义与一次交接）在这里写成普通函数，
/// 由两条入口复用同一份代码：
///
/// - `test/plan/windows_plan_composite_fixture_test.dart`：进程内 widget 夹具
///   （`flutter test`），证据标记 [PlanUiScope.widget]。
/// - `integration_test/plan_ui_composite_device_test.dart`：真实 Windows 窗口的
///   `integration_test`，证据标记 [PlanUiScope.native]，含 PNG 与 manifest。
///
/// 两种入口都只用内存 Drift、内存远端与注入时钟；不读用户数据、不碰系统
/// 日历、不连服务。widget 证据不是原生证据：manifest 的 scope 字段必须如实
/// 标注，不能把进程内 JSON 当成 Windows 验收。
const String planUiCompositeUser = 'windows-plan-composite';

/// 证据来源：进程内 widget 测试或真实窗口的 integration_test。
enum PlanUiScope {
  widget('widget', '进程内 widget 夹具（flutter test），不是原生验收'),
  native('native', '真实窗口 integration_test 证据');

  const PlanUiScope(this.id, this.description);

  final String id;
  final String description;
}

/// 另一台设备先写入时区：下一次保存会以远端值为准并报告冲突。
class PlanUiConflictProfileRemote implements ProfileRemote {
  PlanUiConflictProfileRemote({this.zone = 'Asia/Tokyo'}) : revision = 1;

  String zone;
  int revision;

  void anotherDeviceWrote(String value) {
    zone = value;
    revision += 1;
  }

  RemoteProfile _snapshot({bool conflict = false, String? name}) =>
      RemoteProfile(
        displayName: name ?? '夹具用户',
        avatar: null,
        updatedAt: DateTime.utc(2026, 11, 15),
        displayTimeZoneId: zone,
        timeZoneRevision: revision,
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
    if (displayTimeZoneId != null && timeZoneRevision != revision) {
      return _snapshot(conflict: true);
    }
    if (displayTimeZoneId != null) {
      zone = displayTimeZoneId;
      revision += 1;
    }
    return _snapshot(name: displayName);
  }

  @override
  Future<RemoteProfile?> initializeTimeZone({
    required String userId,
    required String displayTimeZoneId,
  }) async => _snapshot();
}

/// 一次运行的夹具：内存数据库、四个仓储、注入时钟、证据目录。
class PlanUiCompositeFixture {
  PlanUiCompositeFixture._({
    required this.scenario,
    required this.runDirectory,
    required this.scope,
  }) : directory = Directory('${runDirectory.path}/$scenario');

  /// 打开一次运行：`runDirectory` 必须是绝对路径且为空；每个场景写入自己的
  /// 子目录，因此四个场景可以共用同一个唯一的运行目录而不覆盖旧证据。
  static PlanUiCompositeFixture open({
    required String scenario,
    required Directory runDirectory,
    required PlanUiScope scope,
  }) {
    if (!runDirectory.isAbsolute) {
      fail('证据目录必须是绝对路径：${runDirectory.path}');
    }
    if (runDirectory.existsSync() && runDirectory.listSync().isNotEmpty) {
      fail('拒绝复用或覆盖已有证据目录：${runDirectory.absolute.path}');
    }
    runDirectory.createSync(recursive: true);
    final fixture = PlanUiCompositeFixture._(
      scenario: scenario,
      runDirectory: runDirectory,
      scope: scope,
    );
    if (fixture.directory.existsSync()) {
      fail('场景目录已存在，拒绝覆盖：${fixture.directory.path}');
    }
    fixture.directory.createSync(recursive: true);
    return fixture;
  }

  final String scenario;
  final Directory runDirectory;
  final Directory directory;
  final PlanUiScope scope;

  var clock = DateTime.utc(2026, 11, 15, 9);
  final remote = PlanUiConflictProfileRemote();
  final boundaryKey = GlobalKey();
  final List<Map<String, Object?>> screenshots = [];
  final List<String> assertions = [];
  Map<String, Object?>? layout;

  late final PactaDatabase database = PactaDatabase(NativeDatabase.memory());
  late final LocalTaskRepository tasks = LocalTaskRepository(
    database: database,
    userId: planUiCompositeUser,
    remote: InMemoryTaskRemote(),
    cloudSyncEnabled: false,
    now: () => clock,
  );
  late final LocalFocusRepository focus = LocalFocusRepository(
    database: database,
    userId: planUiCompositeUser,
    remote: InMemoryFocusRemote(),
    cloudSyncEnabled: false,
    now: () => clock,
  );
  late final LocalScheduleRepository schedules = LocalScheduleRepository(
    database: database,
    userId: planUiCompositeUser,
    now: () => clock,
  );
  late final LocalProfileRepository profiles = LocalProfileRepository(
    database: database,
    userId: planUiCompositeUser,
    remote: remote,
    now: () => clock,
  );

  /// 真实 [PactaApp]：真实主题与 MiSans、假登录、内存仓储。
  ///
  /// 视口与亮暗是显式参数，不跟随宿主：宽度按逻辑像素算成物理像素，
  /// 因此 widget 与 native 两种入口拿到相同的逻辑尺寸。
  Future<void> pump(
    WidgetTester tester, {
    required Size size,
    required Brightness brightness,
  }) async {
    final devicePixelRatio = tester.view.devicePixelRatio;
    tester.view.physicalSize = Size(
      size.width * devicePixelRatio,
      size.height * devicePixelRatio,
    );
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    debugPrint(
      '[plan-ui] pump ${size.width}x${size.height} ${brightness.name}',
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: PactaApp(
          authRepository: FakeAuthRepository()
            ..signedInUser = planUiCompositeUser,
          taskRepositoryFactory: (_) => tasks,
          focusRepositoryFactory: (_) => focus,
          scheduleRepositoryFactory: (_) => schedules,
          profileRepositoryFactory: (_) => profiles,
          displayClock: () => clock,
        ),
      ),
    );
    await settle(tester);
    _recordLayout(tester, size, brightness);
  }

  /// 关掉当前 widget 树再按同一份内存数据重开（验证落库而不是页面内存）。
  Future<void> restart(
    WidgetTester tester, {
    required Size size,
    required Brightness brightness,
  }) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await pump(tester, size: size, brightness: brightness);
  }

  /// 只容忍已知的 pumpAndSettle 超时；其他异常一律上抛，不掩盖真实失败。
  Future<void> settle(WidgetTester tester) => settlePlanUi(tester);

  void _recordLayout(
    WidgetTester tester,
    Size requested,
    Brightness requestedBrightness,
  ) {
    final context = tester.element(find.byType(Scaffold).first);
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);
    layout = {
      'requestedLogicalSize': [requested.width, requested.height],
      'measuredLogicalSize': [media.size.width, media.size.height],
      'devicePixelRatio': tester.view.devicePixelRatio,
      'requestedBrightness': requestedBrightness.name,
      'measuredBrightness': theme.brightness.name,
      'fontFamily': theme.textTheme.bodyMedium?.fontFamily,
      'textScaler': media.textScaler.scale(1),
    };
    expect(
      theme.brightness,
      requestedBrightness,
      reason: '显式主题生效（${requestedBrightness.name}）',
    );
    expect(
      theme.textTheme.bodyMedium?.fontFamily,
      'MiSans',
      reason: '真实 MiSans 生效',
    );
    expect(
      media.size.width,
      moreOrLessEquals(requested.width, epsilon: 0.5),
      reason: '显式视口宽度生效',
    );
    expect(
      media.size.height,
      moreOrLessEquals(requested.height, epsilon: 0.5),
      reason: '显式视口高度生效',
    );
  }

  /// 截取整棵树（RepaintBoundary）；同名文件已存在即失败，绝不覆盖。
  ///
  /// **只有 native 入口出 PNG**：进程内 widget 测试的假异步无法可靠驱动
  /// 引擎光栅化，硬截会卡住；widget 证据只留 manifest 与断言，绝不拿进程内
  /// 截图冒充 Windows 原生验收。
  Future<void> capture(WidgetTester tester, String name) async {
    if (scope == PlanUiScope.widget) {
      debugPrint('[plan-ui] capture skipped (widget scope): $name');
      return;
    }
    final object = boundaryKey.currentContext?.findRenderObject();
    if (object is! RenderRepaintBoundary) {
      fail('截图「$name」未找到 RepaintBoundary');
    }
    final file = File('${directory.path}/$name.png');
    if (file.existsSync()) {
      fail('拒绝覆盖已有截图：${file.absolute.path}');
    }
    debugPrint('[plan-ui] capture $name');
    final png = await _encodePng(tester, object);
    await file.writeAsBytes(png, flush: true);
    screenshots.add({
      'name': name,
      'path': file.absolute.path,
      'bytes': png.length,
    });
    flush();
  }

  /// 原生入口的真实光栅化：直接等引擎返回，20 秒拿不到就失败。
  Future<List<int>> _encodePng(
    WidgetTester tester,
    RenderRepaintBoundary boundary,
  ) async {
    const limit = Duration(seconds: 20);
    final image = await boundary.toImage(pixelRatio: 1).timeout(limit);
    try {
      final data = await image
          .toByteData(format: ui.ImageByteFormat.png)
          .timeout(limit);
      if (data == null) fail('PNG 编码返回空数据');
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  void record(List<String> reached) {
    assertions
      ..clear()
      ..addAll(reached);
    flush();
  }

  /// 把当前证据写成 manifest（原子替换，供 root 独立判读）。
  void flush() {
    final manifest = <String, Object?>{
      'scope': scope.id,
      'scopeDescription': scope.description,
      'scenario': scenario,
      'platform': Platform.operatingSystem,
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'clock': clock.toIso8601String(),
      'layout': layout,
      'screenshots': screenshots,
      'assertions': assertions,
      'isolation': {
        'database': 'in-memory',
        'remotes': 'in-memory',
        'userData': 'none',
        'systemCalendar': 'none',
        'services': 'none',
      },
    };
    final target = File('${directory.path}/manifest.json');
    final temp = File('${target.path}.tmp');
    temp.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(manifest),
      flush: true,
    );
    temp.renameSync(target.path);
  }

  /// 释放：先卸掉 widget 树取消订阅，再逐个关闭仓储与数据库。
  ///
  /// widget 测试的假异步不会自己推进，关闭 async* 流需要配合帧推进；这里
  /// 边推进边等结果，**等不到就抛错**（不允许 `onTimeout` 吞掉超时）。
  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await _pumpUntil(tester, focus.dispose(), 'focus.dispose');
    await _pumpUntil(tester, schedules.dispose(), 'schedules.dispose');
    await _pumpUntil(tester, profiles.dispose(), 'profiles.dispose');
    await _pumpUntil(tester, database.close(), 'database.close');
    tester.view.reset();
    tester.platformDispatcher.clearPlatformBrightnessTestValue();
    flush();
  }
}

/// 只容忍已知的 `pumpAndSettle` 超时：默认它会等 10 分钟，看起来像“还在跑”。
///
/// 这里限定 5 秒，超时退化为一次固定推进，好让真正的红信号尽快出现。
Future<void> settlePlanUi(WidgetTester tester) async {
  try {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );
  } on FlutterError catch (error) {
    if (!error.message.contains('pumpAndSettle timed out')) rethrow;
    await tester.pump(const Duration(milliseconds: 400));
  }
}

/// 在假异步/真实窗口里等待一个 future：一边推进帧一边检查完成。
///
/// 超过 200 帧仍没完成就抛出 [StateError]，让测试失败，而不是用
/// `onTimeout` 把没关闭的资源当成成功。
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

/// 打开计划目的地：宽屏是 NavigationRail，窄屏是 NavigationBar。
Future<void> openPlanDestination(WidgetTester tester) async {
  final bar = find.byType(NavigationBar);
  final host = bar.evaluate().isNotEmpty ? bar : find.byType(NavigationRail);
  await tester.tap(find.descendant(of: host, matching: find.text('计划')));
  await settlePlanUi(tester);
}

/// 打开计划目的地并切到日历视图。
Future<void> openPlanCalendar(
  WidgetTester tester,
  PlanUiCompositeFixture fixture,
) async {
  debugPrint('[plan-ui] open plan calendar');
  await openPlanDestination(tester);
  await tester.tap(find.text('日历'));
  await fixture.settle(tester);
}

Finder planFormField(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

/// 场景一：无系统日历时的导入说明 + 自有安排增改，360×800 暗色。
Future<void> runUnsupportedCalendarScenario(
  WidgetTester tester,
  PlanUiCompositeFixture fixture,
) async {
  await fixture.pump(
    tester,
    size: const Size(360, 800),
    brightness: Brightness.dark,
  );
  await openPlanCalendar(tester, fixture);

  await tester.tap(find.byKey(const ValueKey('plan-import-open')));
  await settlePlanUi(tester);
  expect(find.text('这台设备暂时不能读取系统日历；你自己的安排仍可新建和编辑。'), findsOneWidget);
  await tester.pump(const Duration(seconds: 5));
  await fixture.settle(tester);
  await fixture.capture(tester, 'unsupported-calendar-dark-narrow');

  await tester.tap(find.text('添加事项'));
  await fixture.settle(tester);
  await tester.enterText(planFormField('名称'), '离线整理');
  await tester.tap(find.text('保存'));
  await fixture.settle(tester);

  expect(find.text('离线整理'), findsOneWidget);
  expect((await fixture.schedules.getSchedules()).single.title, '离线整理');
  expect(find.text('新建安排'), findsOneWidget);
  expect(tester.getSize(find.text('新建安排')).height, greaterThan(0));
  expect(tester.takeException(), isNull, reason: '360 宽 + MiSans 不溢出');
  await fixture.capture(tester, 'owned-schedule-dark-narrow');
  fixture.record(const [
    'unsupported-calendar',
    'owned-crud',
    'no-overflow',
    'dark-360x800',
  ]);
}

/// 场景二：账号时区决定 Plan 时间；另一台设备先写入时采用最新值，1280×900 亮色。
Future<void> runAccountZoneScenario(
  WidgetTester tester,
  PlanUiCompositeFixture fixture,
) async {
  await fixture.profiles.ensureDisplayTimeZone(deviceTimeZoneId: 'Asia/Tokyo');
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
  await openPlanCalendar(tester, fixture);

  // 09:00Z 在账号时区东京是 18:00；设备时区固定 UTC，不参与显示。
  expect(find.text('18:00–19:00'), findsOneWidget);
  await fixture.capture(tester, 'account-zone-tokyo-light-wide');

  fixture.remote.anotherDeviceWrote('Europe/London');
  final saved = await fixture.profiles.saveProfile(
    displayName: '夹具用户',
    timeZoneId: 'America/New_York',
  );
  expect(saved.displayTimeZoneId, 'Europe/London');
  await fixture.settle(tester);
  // 冲突时采用账号已接受的最新时区：伦敦 11 月为 UTC+0。
  expect(find.text('09:00–10:00'), findsOneWidget);
  expect(find.text('18:00–19:00'), findsNothing);
  await fixture.capture(tester, 'account-zone-conflict-london-light-wide');
  fixture.record(const [
    'account-zone',
    'conflict-adopts-latest',
    'light-1280x900',
  ]);
}

/// 场景三：重复创建可改范围、提醒配置在重开后保留，1280×1600 亮色。
Future<void> runRecurrenceScenario(
  WidgetTester tester,
  PlanUiCompositeFixture fixture,
) async {
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
    repeat: const ScheduleRepeatSpec(frequency: ScheduleRepeatFrequency.daily),
    timeZoneId: 'Etc/UTC',
  );
  final today = (await fixture.schedules.getSchedules(
    from: DateTime.utc(2026, 11, 15),
    to: DateTime.utc(2026, 11, 16),
  )).single;
  await fixture.schedules.setScheduleReminder(today.id, minutesBefore: 10);
  await fixture.settle(tester);
  await openPlanCalendar(tester, fixture);
  expect(find.text('提前 10 分钟提醒'), findsOneWidget);
  await fixture.capture(tester, 'recurrence-reminder-light-wide');

  final ruleBefore = (await fixture.schedules.getRecurrenceRules()).single;
  await tester.tap(find.text('每日站会'));
  await fixture.settle(tester);
  expect(find.text('仅本次'), findsOneWidget);
  expect(find.text('本次及以后'), findsOneWidget);
  await fixture.capture(tester, 'recurrence-scope-dialog-light-wide');
  await tester.enterText(planFormField('名称'), '每日站会（仅本次）');
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
  await fixture.restart(
    tester,
    size: const Size(1280, 1600),
    brightness: Brightness.light,
  );
  await openPlanCalendar(tester, fixture);
  expect(find.text('提前 10 分钟提醒'), findsOneWidget);

  await tester.tap(find.text('每日站会（仅本次）'));
  await fixture.settle(tester);
  await tester.tap(find.text('本次及以后'));
  await fixture.settle(tester);
  await tester.enterText(planFormField('名称'), '每日站会（新规则）');
  await tester.ensureVisible(find.byType(DropdownButtonFormField<int?>));
  await fixture.settle(tester);
  // 模板当前无提醒：点字段显示的“不提醒”打开菜单。
  await tester.tap(find.text('不提醒').last);
  await fixture.settle(tester);
  await tester.tap(find.text('提前 15 分钟').last);
  await fixture.settle(tester);
  await fixture.capture(tester, 'recurrence-template-reminder-light-wide');
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
    'light-1280x1600',
  ]);
}

/// 场景四：预约准备 5/10/15/自定义可用，准备结束只交接一次，1280×900 亮色。
Future<void> runPreparationScenario(
  WidgetTester tester,
  PlanUiCompositeFixture fixture,
) async {
  await fixture.pump(
    tester,
    size: const Size(1280, 900),
    brightness: Brightness.light,
  );
  final goal = await fixture.tasks.createGoal(
    const GoalDraft(title: '交付', classification: TaskClassification.regular),
  );
  final task = await fixture.tasks.createTask(
    goal.id,
    const TaskDraft(title: '写总结', classification: TaskClassification.regular),
  );
  await fixture.settle(tester);
  await openPlanDestination(tester);

  await tester.tap(find.byTooltip('开始专注'));
  await fixture.settle(tester);
  expect(find.text('预约准备时长'), findsOneWidget);
  for (final label in ['5 分钟', '10 分钟', '15 分钟', '自定义']) {
    expect(find.text(label), findsOneWidget, reason: '准备预设 $label');
  }
  await fixture.capture(tester, 'preparation-presets-light-wide');

  // 自定义：7 分钟准备，先验证落库再取消，不留下第二个活动预约。
  await tester.tap(find.text('自定义'));
  await fixture.settle(tester);
  await tester.enterText(planFormField('自定义准备时长（分钟）'), '7');
  await tester.pump();
  await fixture.capture(tester, 'preparation-custom-light-wide');
  await tester.tap(find.text('开始准备（7分钟）'));
  await fixture.settle(tester);
  final custom = (await fixture.focus.getActiveAppointment())!;
  expect(custom.preparationSeconds, 420);
  await fixture.focus.cancelAppointment(
    appointmentId: custom.id,
    failureReason: '切换准备时长',
  );
  // 取消后重新打开，回到计划页再用预设档开始，避免停留在准备页。
  await fixture.restart(
    tester,
    size: const Size(1280, 900),
    brightness: Brightness.light,
  );
  await openPlanDestination(tester);

  await tester.tap(find.byTooltip('开始专注'));
  await fixture.settle(tester);
  await tester.tap(find.text('5 分钟'));
  await fixture.settle(tester);
  await tester.tap(find.text('开始准备（5分钟）'));
  await fixture.settle(tester);

  final appointment = (await fixture.focus.getActiveAppointment())!;
  expect(appointment.preparationSeconds, 300);
  expect(appointment.taskId, task.id);
  await fixture.capture(tester, 'preparation-active-five-minutes-light-wide');

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
    'preparation-custom-7',
    'single-handoff',
    'light-1280x900',
  ]);
}
