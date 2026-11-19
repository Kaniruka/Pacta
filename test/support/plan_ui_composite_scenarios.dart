import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

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
import 'test_database.dart';

/// 07 计划 UI 组合场景的唯一实现。
///
/// 五个场景（无系统日历 + 自有增改、经"我的 → 编辑资料"改城市时的冲突、
/// 重复范围与提醒模板（宽/窄两种视口）、预约准备 5/10/15/自定义与一次交接）
/// 在这里写成普通函数，由两条入口复用同一份代码：
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

  /// 打开一个场景。运行根由**入口整轮校验一次**：native 入口在启动时要求
  /// 绝对路径且为空，随后所有场景共用它；widget 入口每场给一个唯一临时根。
  ///
  /// 这里只负责本场景子目录：已存在就拒绝覆盖（manifest/PNG 都不会被旧证据
  /// 混进来），但运行根在第一个场景写完之后当然不再为空，不能当成错误。
  static PlanUiCompositeFixture open({
    required String scenario,
    required Directory runDirectory,
    required PlanUiScope scope,
  }) {
    if (!runDirectory.isAbsolute) {
      fail('证据目录必须是绝对路径：${runDirectory.path}');
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

  late final PactaDatabase database = openTestDatabase();

  // 仓储按「一次应用挂载」创建，与生产一致：页面卸载时 provider 会 dispose
  // 自己那份实例，重开必须换新实例读同一份数据库，而不是复用已被关闭的。
  late LocalTaskRepository tasks = _newTasks();
  late LocalFocusRepository focus = _newFocus();
  late LocalScheduleRepository schedules = _newSchedules();
  late LocalProfileRepository profiles = _newProfiles();

  LocalTaskRepository _newTasks() => LocalTaskRepository(
    database: database,
    userId: planUiCompositeUser,
    remote: InMemoryTaskRemote(),
    cloudSyncEnabled: false,
    now: () => clock,
  );

  LocalFocusRepository _newFocus() => LocalFocusRepository(
    database: database,
    userId: planUiCompositeUser,
    remote: InMemoryFocusRemote(),
    cloudSyncEnabled: false,
    now: () => clock,
  );

  LocalScheduleRepository _newSchedules() => LocalScheduleRepository(
    database: database,
    userId: planUiCompositeUser,
    now: () => clock,
  );

  LocalProfileRepository _newProfiles() => LocalProfileRepository(
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
    // 上一棵树卸载时 provider 已 dispose 那份仓储：重开用新实例读同一份库。
    tasks = _newTasks();
    focus = _newFocus();
    schedules = _newSchedules();
    profiles = _newProfiles();
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
    // drift 的查询流在关闭时排一个零延迟计时器；再推一帧让它跑完，避免
    // 测试以 “A Timer is still pending” 失败。
    await tester.pump(const Duration(milliseconds: 20));
    tester.view.reset();
    tester.platformDispatcher.clearPlatformBrightnessTestValue();
    flush();
  }
}

/// 只容忍已知的 `pumpAndSettle` 超时：默认它会等 10 分钟，看起来像“还在跑”。
///
/// 这里限定 5 秒，超时退化为一次固定推进，好让真正的红信号尽快出现。
Future<void> settlePlanUi(WidgetTester tester) async {
  for (var round = 0; round < 3; round++) {
    try {
      await tester.pumpAndSettle(
        const Duration(milliseconds: 20),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
    } on FlutterError catch (error) {
      if (!error.message.contains('pumpAndSettle timed out')) rethrow;
      await tester.pump(const Duration(milliseconds: 400));
      continue;
    }
    // 数据库观察的回调是零延迟微任务/计时器：没有待排帧时 pumpAndSettle
    // 会立刻返回，这里再推一帧，保证订阅到的数据真的进了 widget 树。
    await tester.pump(const Duration(milliseconds: 20));
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

/// 打开"我的"目的地：宽屏是 NavigationRail，窄屏是 NavigationBar。
Future<void> openMyDestination(WidgetTester tester) async {
  final bar = find.byType(NavigationBar);
  final host = bar.evaluate().isNotEmpty ? bar : find.byType(NavigationRail);
  await tester.tap(find.descendant(of: host, matching: find.text('我的')));
  await settlePlanUi(tester);
}

/// 把目标滚进可见区：页面 ListView 与对话框内部滚动视图都适用。
Future<void> revealPlanUi(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pump();
}

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

  // 360 宽下每个日期格必须是 ≥48×48 的真命中区，且年月整段单行可读。
  final today = find.byKey(const ValueKey('plan-day-2026-11-15'));
  expect(today, findsOneWidget);
  final todaySize = tester.getSize(today);
  expect(todaySize.width, greaterThanOrEqualTo(48), reason: '日期命中区宽度');
  expect(todaySize.height, greaterThanOrEqualTo(48), reason: '日期命中区高度');
  final monthParagraph = tester.renderObject<RenderParagraph>(
    find.byKey(const ValueKey('plan-month-label')),
  );
  expect(monthParagraph.didExceedMaxLines, isFalse, reason: '360 宽下年月不折行、不省略');
  expect(
    monthParagraph.size.height,
    lessThan((monthParagraph.text.style?.fontSize ?? 16) * 1.8),
    reason: '年月只占一行',
  );
  expect(find.byKey(const ValueKey('plan-import-open')), findsOneWidget);
  expect(find.text('新建安排'), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('plan-day-2026-11-16')));
  await fixture.settle(tester);
  expect(find.textContaining('11月16日'), findsWidgets, reason: '真实触摸换日');
  await tester.tap(today);
  await fixture.settle(tester);
  expect(find.textContaining('11月15日'), findsWidgets);

  // 导入入口：提示先真实可见，再截图——先等 5 秒会让 SnackBar 自己退场，
  // 截出来只是一张空日历。
  await tester.tap(find.byKey(const ValueKey('plan-import-open')));
  await settlePlanUi(tester);
  final unsupportedPrompt = find.text('这台设备暂时不能读取系统日历；你自己的安排仍可新建和编辑。');
  expect(unsupportedPrompt, findsOneWidget);
  await tester.pump();
  await fixture.capture(tester, 'unsupported-calendar-dark-narrow');
  expect(unsupportedPrompt, findsOneWidget, reason: '截图时提示仍真实可见');
  await tester.pump(const Duration(seconds: 5));
  await fixture.settle(tester);
  expect(unsupportedPrompt, findsNothing, reason: '提示按时退场，不残留');

  // 自有安排：新增 → 编辑标题 → 落库与页面同时更新。
  await tester.tap(find.text('新建安排'));
  await fixture.settle(tester);
  await tester.enterText(planFormField('名称'), '离线整理');
  await tester.tap(find.text('保存'));
  await fixture.settle(tester);
  expect(find.text('离线整理'), findsOneWidget);
  expect((await fixture.schedules.getSchedules()).single.title, '离线整理');
  expect(find.text('新建安排'), findsOneWidget);
  expect(tester.getSize(find.text('新建安排')).height, greaterThan(0));

  await tester.tap(find.text('离线整理'));
  await fixture.settle(tester);
  expect(find.text('编辑安排'), findsOneWidget);
  await tester.enterText(planFormField('名称'), '离线整理（已改）');
  await tester.pump();
  expect(find.text('名称'), findsOneWidget, reason: '已填标题时浮动标签完整可见');
  await fixture.capture(tester, 'owned-schedule-editor-dark-narrow');
  await tester.tap(find.text('保存'));
  await fixture.settle(tester);
  expect(
    (await fixture.schedules.getSchedules()).single.title,
    '离线整理（已改）',
    reason: '编辑写入仓储，不只是页面内存',
  );
  expect(find.text('离线整理（已改）'), findsOneWidget);
  expect(find.text('离线整理'), findsNothing, reason: '编辑后旧标题不再显示');
  expect(tester.takeException(), isNull, reason: '360 宽 + MiSans 不溢出');
  await fixture.capture(tester, 'owned-schedule-edited-dark-narrow');
  fixture.record(const [
    'unsupported-calendar',
    'unsupported-prompt-visible',
    'hitbox-48',
    'month-title-single-line',
    'owned-crud',
    'owned-edit',
    'no-overflow',
    'dark-360x800',
  ]);
}

/// 场景二：账号时区决定 Plan 时间；通过"我的 → 编辑资料"改城市，
/// 另一台设备先写入时采用账号最新值并如实反馈，1280×900 亮色。
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

  // 真实入口：我的 → 编辑 → 城市选择（产品自带 ChoiceChip，不是新交互）。
  await openMyDestination(tester);
  await tester.tap(find.widgetWithText(TextButton, '编辑'));
  await fixture.settle(tester);
  expect(find.text('编辑资料'), findsOneWidget);
  final newYork = find.widgetWithText(ChoiceChip, '纽约');
  await revealPlanUi(tester, newYork);
  await tester.tap(newYork);
  await fixture.settle(tester);
  expect(find.text('纽约 · America/New_York'), findsOneWidget);
  await fixture.capture(tester, 'profile-zone-picker-light-wide');

  // 另一台设备先写伦敦：保存时账号存储按修订号保留伦敦，页面必须如实
  // 说明"已采用最新值"，而不是把这次点击说成已生效。
  fixture.remote.anotherDeviceWrote('Europe/London');
  await tester.tap(find.widgetWithText(FilledButton, '保存'));
  await fixture.settle(tester);
  expect(find.text('编辑资料'), findsOneWidget, reason: '冲突不冒充保存成功并退出');
  final conflict = find.textContaining('账号时区已被其他设备更新，已采用最新值：Europe/London。');
  expect(conflict, findsOneWidget);
  expect(
    (await fixture.profiles.getProfile()).displayTimeZoneId,
    'Europe/London',
    reason: '账号存储采用最新接受值',
  );
  await revealPlanUi(tester, conflict);
  await fixture.capture(tester, 'profile-zone-conflict-feedback-light-wide');

  await tester.tap(find.byType(BackButton));
  await fixture.settle(tester);
  await openPlanCalendar(tester, fixture);
  // 伦敦 11 月为 UTC+0：Plan 时间随账号值更新。
  expect(find.text('09:00–10:00'), findsOneWidget);
  expect(find.text('18:00–19:00'), findsNothing);
  await fixture.capture(tester, 'account-zone-conflict-london-light-wide');
  fixture.record(const [
    'account-zone',
    'profile-edit-zone-picker',
    'conflict-adopts-latest',
    'conflict-feedback-visible',
    'plan-time-follows-account-zone',
    'light-1280x900',
  ]);
}

/// 场景三：重复创建可改范围、提醒配置在重开后保留。
///
/// 视口可注入：同一份实现既跑 1280×1600 亮色，也跑 360×800 暗色窄窗；
/// 窄窗下每个字段都先真实滚动到可见再操作，覆盖长表单（两个范围 + 提醒）。
Future<void> runRecurrenceScenario(
  WidgetTester tester,
  PlanUiCompositeFixture fixture, {
  Size size = const Size(1280, 1600),
  Brightness brightness = Brightness.light,
  String label = 'light-wide',
}) async {
  await fixture.pump(tester, size: size, brightness: brightness);
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
  final recurringTile = find.text('每日站会');
  await revealPlanUi(tester, recurringTile);
  expect(find.text('提前 10 分钟提醒'), findsOneWidget);
  await fixture.capture(tester, 'recurrence-reminder-$label');

  final ruleBefore = (await fixture.schedules.getRecurrenceRules()).single;
  await tester.tap(recurringTile);
  await fixture.settle(tester);
  expect(find.text('仅本次'), findsOneWidget);
  expect(find.text('本次及以后'), findsOneWidget);
  await fixture.capture(tester, 'recurrence-scope-dialog-$label');
  await revealPlanUi(tester, planFormField('名称'));
  await tester.enterText(planFormField('名称'), '每日站会（仅本次）');
  await tester.pump();
  expect(find.text('名称'), findsOneWidget, reason: '已填标题时浮动标签可见');
  await revealPlanUi(tester, find.text('保存'));
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
  expect(tester.takeException(), isNull, reason: '$label 无 overflow');

  // 关掉再打开：提醒配置来自持久化数据，不是页面内存。
  await fixture.restart(tester, size: size, brightness: brightness);
  await openPlanCalendar(tester, fixture);
  expect(find.text('提前 10 分钟提醒'), findsOneWidget);

  final exceptionTile = find.text('每日站会（仅本次）');
  await revealPlanUi(tester, exceptionTile);
  await tester.tap(exceptionTile);
  await fixture.settle(tester);
  await revealPlanUi(tester, find.text('本次及以后'));
  expect(find.text('仅本次'), findsOneWidget, reason: '两个范围都可见可选');
  await tester.tap(find.text('本次及以后'));
  await fixture.settle(tester);
  await revealPlanUi(tester, planFormField('名称'));
  await tester.enterText(planFormField('名称'), '每日站会（新规则）');
  await tester.pump();
  expect(find.text('名称'), findsOneWidget, reason: '已填标题时浮动标签可见');
  final reminderField = find.byType(DropdownButtonFormField<int?>);
  await revealPlanUi(tester, reminderField);
  await fixture.settle(tester);
  // 模板当前无提醒：点字段显示的“不提醒”打开菜单。
  await tester.tap(find.text('不提醒').last);
  await fixture.settle(tester);
  // 提醒候选真实可用，不只存在于页面文案。
  expect(find.text('提前 5 分钟').last, findsOneWidget);
  expect(find.text('提前 15 分钟').last, findsOneWidget);
  await tester.tap(find.text('提前 15 分钟').last);
  await fixture.settle(tester);
  await fixture.capture(tester, 'recurrence-template-reminder-$label');
  await revealPlanUi(tester, find.text('保存'));
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
  expect(tester.takeException(), isNull, reason: '$label 无 overflow');
  fixture.record([
    'recurrence-scope',
    'reminder-persisted',
    'reminder-template',
    'floating-labels',
    label,
  ]);
}

/// 场景四：预约准备 5/10/15/自定义可用，准备结束只交接一次，1280×900 亮色。
///
/// 10/15 不只断言 chip 存在：真的选一次、核对写入的准备秒数，再取消清理，
/// 最后用 5 分钟走完唯一一次交接。
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

  // 10/15 分钟：真的选一次并核对写入的准备秒数，逐个取消清理。
  for (final preset in const [('10 分钟', 600), ('15 分钟', 900)]) {
    await tester.tap(find.byTooltip('开始专注'));
    await fixture.settle(tester);
    await tester.tap(find.text(preset.$1));
    await fixture.settle(tester);
    await tester.tap(find.text('开始准备（${preset.$2 ~/ 60}分钟）'));
    await fixture.settle(tester);
    final appointment = (await fixture.focus.getActiveAppointment())!;
    expect(
      appointment.preparationSeconds,
      preset.$2,
      reason: '${preset.$1} 真的写入准备时长',
    );
    await fixture.focus.cancelAppointment(
      appointmentId: appointment.id,
      failureReason: '切换准备时长',
    );
    await fixture.restart(
      tester,
      size: const Size(1280, 900),
      brightness: Brightness.light,
    );
    await openPlanDestination(tester);
  }

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
  expect(
    (await fixture.focus.getActiveAppointment()),
    isNull,
    reason: '交接后不残留第二个活动预约',
  );
  fixture.record(const [
    'preparation-presets',
    'preparation-10',
    'preparation-15',
    'preparation-custom-7',
    'single-handoff',
    'light-1280x900',
  ]);
}
