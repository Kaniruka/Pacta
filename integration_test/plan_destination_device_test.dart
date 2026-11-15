// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/schedules/schedule_models.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/fake_auth_repository.dart';

/// 票 07「计划目的地」的 Windows 内存截图/交互夹具（可重复运行）。
///
/// 真实 [PactaApp] + 真实 pactaTheme/MiSans + 假登录 + 内存 Drift +
/// 内存远端：不连服务、不碰真实用户数据。时钟固定为 [fixtureNow]，
/// 仓储时间戳因而可复现；计划日历自身的「今天」由视图读取运行当天，
/// 所以断言只覆盖与日期无关的事实（条数、顺序、名称）。
///
/// 覆盖：目标/任务 CRUD、目标折叠与表单浮动标签、置顶与手动顺序、
/// 看板只保留摘要、一条任务两条安排、独立事项编辑/完成/删除，
/// 以及跨天/全天安排的编辑器读数与"已删除任务"链接保留。
///
/// 运行（root 在 Windows 上执行并判读 PNG）：
///   flutter test integration_test/plan_destination_device_test.dart -d windows
///     --dart-define=PLAN_DESTINATION_CAPTURE_DIR=C:/abs/plan-destination-evidence
///
/// 可选 define：
///   PLAN_DESTINATION_THEMES=light,dark  （子集，顺序保留）
///   PLAN_DESTINATION_VIEWS=360,1440     （逻辑宽度）
///   PLAN_DESTINATION_DPR=1              （截图像素比）
///
/// 输出目录必须是绝对路径且不存在或为空：夹具拒绝复用或覆盖旧证据。
const _user = 'plan-destination-windows-fixture';
const _captureDir = String.fromEnvironment('PLAN_DESTINATION_CAPTURE_DIR');
const _themesDefine = String.fromEnvironment(
  'PLAN_DESTINATION_THEMES',
  defaultValue: 'light,dark',
);
const _viewsDefine = String.fromEnvironment(
  'PLAN_DESTINATION_VIEWS',
  defaultValue: '360,1440',
);
const _dprDefine = String.fromEnvironment(
  'PLAN_DESTINATION_DPR',
  defaultValue: '1',
);

/// 固定、彼此一致的夹具时间：仓储写入、看板核对与云检查都用它。
final DateTime fixtureNow = DateTime.utc(2026, 11, 15, 9);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('计划目的地 目标/任务/置顶/安排/看板摘要 真实截图', (tester) async {
    final outputDirectory = _resolveOutputDirectory();
    final themes = _parseThemes();
    final views = _parseViews();
    final dpr = _parseDevicePixelRatio();

    final written = <String>[];
    for (final theme in themes) {
      for (final width in views) {
        written.addAll(
          await _runScenario(
            tester: tester,
            theme: theme,
            width: width,
            devicePixelRatio: dpr,
            outputDirectory: outputDirectory,
          ),
        );
      }
    }

    expect(written, isNotEmpty);
    print(
      '[plan-destination] 完成：${written.length} 张截图，目录 '
      '${outputDirectory.absolute.path}',
    );
    for (final path in written) {
      print('[plan-destination] $path');
    }
  });
}

Directory _resolveOutputDirectory() {
  final raw = _captureDir.trim();
  if (raw.isEmpty) {
    fail(
      '必须提供绝对输出目录：'
      '--dart-define=PLAN_DESTINATION_CAPTURE_DIR=<绝对路径>（例如 C:/abs/evidence）',
    );
  }
  final directory = Directory(raw);
  if (!directory.isAbsolute) {
    fail('输出目录必须是绝对路径，当前为：$raw');
  }
  if (directory.existsSync() && directory.listSync().isNotEmpty) {
    fail('拒绝复用或覆盖已有截图目录：${directory.absolute.path}（请换一个空的唯一目录）');
  }
  return directory;
}

List<Brightness> _parseThemes() {
  final themes = <Brightness>[];
  for (final token in _themesDefine.split(',')) {
    final value = token.trim().toLowerCase();
    if (value.isEmpty) continue;
    switch (value) {
      case 'light':
        if (!themes.contains(Brightness.light)) themes.add(Brightness.light);
      case 'dark':
        if (!themes.contains(Brightness.dark)) themes.add(Brightness.dark);
      case 'system':
      case 'both':
        for (final brightness in Brightness.values) {
          if (!themes.contains(brightness)) themes.add(brightness);
        }
      default:
        fail('无法识别的主题「$value」，可用 light/dark/system。');
    }
  }
  if (themes.isEmpty) fail('PLAN_DESTINATION_THEMES 至少要包含一个主题。');
  return themes;
}

List<int> _parseViews() {
  final views = <int>[];
  for (final token in _viewsDefine.split(',')) {
    final value = token.trim();
    if (value.isEmpty) continue;
    final width = int.tryParse(value);
    if (width == null || width < 320) {
      fail('逻辑宽度必须是不小于 320 的整数，当前为「$value」。');
    }
    if (!views.contains(width)) views.add(width);
  }
  if (views.isEmpty) fail('PLAN_DESTINATION_VIEWS 至少要包含一个宽度。');
  return views;
}

double _parseDevicePixelRatio() {
  final dpr = double.tryParse(_dprDefine.trim());
  if (dpr == null || dpr < 1 || dpr > 4) {
    fail('PLAN_DESTINATION_DPR 必须是 1 到 4 之间的数字，当前为「$_dprDefine」。');
  }
  return dpr;
}

Finder _navigation() {
  final rail = find.byType(NavigationRail);
  return rail.evaluate().isNotEmpty ? rail : find.byType(NavigationBar);
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Finder _goalCard(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(Card));

Finder _scheduleTile(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(ListTile));

double _top(WidgetTester tester, Finder finder) => tester.getTopLeft(finder).dy;

Future<List<String>> _runScenario({
  required WidgetTester tester,
  required Brightness theme,
  required int width,
  required double devicePixelRatio,
  required Directory outputDirectory,
}) async {
  final label = '${theme == Brightness.dark ? 'dark' : 'light'}-${width}w';
  final capturedNames = <String>{};
  final written = <String>[];
  final boundaryKey = GlobalKey();

  SharedPreferences.setMockInitialValues({});
  final database = PactaDatabase(NativeDatabase.memory());
  final tasks = LocalTaskRepository(
    database: database,
    userId: _user,
    remote: InMemoryTaskRemote(),
    now: () => fixtureNow,
  );
  final focus = LocalFocusRepository(
    database: database,
    userId: _user,
    remote: InMemoryFocusRemote(),
    cloudSyncEnabled: false,
    now: () => fixtureNow,
  );
  final tree = LocalNationalFocusRepository(
    database: database,
    userId: _user,
    cloudSyncEnabled: false,
    now: () => fixtureNow,
  );
  final schedules = LocalScheduleRepository(
    database: database,
    userId: _user,
    now: () => fixtureNow,
  );

  Future<void> pumpUi() async {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
  }

  /// 截图前先证明目标确实在可视区域内：只断言「存在」不算可判读状态。
  void expectOnScreen(Finder finder, {required String reason}) {
    expect(finder, findsOneWidget, reason: reason);
    final rect = tester.getRect(finder);
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    const epsilon = 0.5;
    expect(
      rect.top,
      greaterThanOrEqualTo(-epsilon),
      reason: '$reason（顶部 ${rect.top} 超出视口）',
    );
    expect(
      rect.bottom,
      lessThanOrEqualTo(size.height + epsilon),
      reason: '$reason（底部 ${rect.bottom} 超出视口 ${size.height}）',
    );
    expect(
      rect.left,
      greaterThanOrEqualTo(-epsilon),
      reason: '$reason（左侧 ${rect.left} 超出视口）',
    );
    expect(
      rect.right,
      lessThanOrEqualTo(size.width + epsilon),
      reason: '$reason（右侧 ${rect.right} 超出视口 ${size.width}）',
    );
  }

  Future<void> shot(String step, {required String landmark}) async {
    await pumpUi();
    expect(
      find.text(landmark),
      findsOneWidget,
      reason: '截图 $step 应停在 $landmark',
    );
    final name = 'plan-destination-$label-$step';
    if (!capturedNames.add(name)) fail('截图名重复：$name');
    final object = boundaryKey.currentContext?.findRenderObject();
    if (object is! RenderRepaintBoundary) {
      fail('截图「$name」未找到 RepaintBoundary');
    }
    final image = await object.toImage(pixelRatio: devicePixelRatio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) fail('截图「$name」PNG 编码失败');
      await outputDirectory.create(recursive: true);
      final file = File(
        '${outputDirectory.path}${Platform.pathSeparator}$name.png',
      );
      if (await file.exists()) fail('拒绝覆盖截图文件：${file.absolute.path}');
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      written.add(file.absolute.path);
    } finally {
      image.dispose();
    }
    expect(tester.takeException(), isNull, reason: '截图 $name 不应抛异常');
  }

  Future<void> openDestination(String text) async {
    await tester.tap(
      find.descendant(of: _navigation(), matching: find.text(text)),
    );
    await pumpUi();
  }

  Future<void> tapVisible(Finder target) async {
    await tester.ensureVisible(target);
    await pumpUi();
    expectOnScreen(target, reason: '点击前目标应在视口内');
    await tester.tap(target);
    await pumpUi();
  }

  Future<void> saveDialog() async {
    await tapVisible(find.widgetWithText(FilledButton, '保存'));
    await pumpUi();
    expect(find.byType(AlertDialog), findsNothing);
  }

  Future<void> chooseDropdown(String labelText, String option) async {
    final dropdown = find.ancestor(
      of: find.text(labelText),
      matching: find.byType(Scrollable),
    );
    // 先让下拉进入视口，再按标签点击它所在的输入框。
    await tester.ensureVisible(find.text(labelText));
    await pumpUi();
    final field = find.byWidgetPredicate(
      (widget) => widget is DropdownButtonFormField,
      description: '下拉 $labelText',
    );
    expect(dropdown, findsWidgets);
    await tester.tap(
      find.ancestor(of: find.text(labelText), matching: field).first,
      warnIfMissed: false,
    );
    await pumpUi();
    await tester.tap(find.text(option).last);
    await pumpUi();
  }

  tester.view.devicePixelRatio = devicePixelRatio;
  tester.view.physicalSize = Size(
    width * devicePixelRatio,
    (width >= 900 ? 900 : 800) * devicePixelRatio,
  );
  tester.platformDispatcher.platformBrightnessTestValue = theme;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

  await tester.pumpWidget(
    RepaintBoundary(
      key: boundaryKey,
      child: PactaApp(
        authRepository: FakeAuthRepository()..signedInUser = _user,
        taskRepositoryFactory: (_) => tasks,
        focusRepositoryFactory: (_) => focus,
        nationalFocusRepositoryFactory: (_) => tree,
        scheduleRepositoryFactory: (_) => schedules,
        cloudCheckClock: () => fixtureNow,
      ),
    ),
  );
  await pumpUi();

  // 真实主题与强制亮度：先证明主题生效，再谈截图状态。
  final boardContext = tester.element(find.byType(BoardPage));
  final activeTheme = Theme.of(boardContext);
  expect(activeTheme.brightness, theme, reason: '亮度必须被显式强制为 $theme');
  expect(
    activeTheme.textTheme.bodyMedium?.fontFamily,
    'MiSans',
    reason: '截图必须使用真实 MiSans 主题字体',
  );
  expect(
    activeTheme.scaffoldBackgroundColor,
    pactaTheme(theme).scaffoldBackgroundColor,
    reason: '必须是真实 pactaTheme，而不是另建的主题',
  );

  // 1. 看板：空目标时只显示摘要与提示。
  expect(find.byType(BoardPage), findsOneWidget);
  expectOnScreen(find.text('今天先做什么'), reason: '看板标题应在视口内');
  expect(find.text('还没有置顶目标'), findsOneWidget);
  await shot('01-board-empty', landmark: '今天先做什么');

  // 2. 计划：目标视图空态。
  await openDestination('计划');
  expect(find.byType(PlanPage), findsOneWidget);
  expectOnScreen(find.text('目标与任务'), reason: '计划标题应在视口内');
  expect(find.text('还没有目标'), findsOneWidget);
  await shot('02-plan-empty', landmark: '目标与任务');

  // 3. 新建目标表单：浮动标签可见。
  await tapVisible(find.text('新建目标'));
  expect(find.byType(AlertDialog), findsOneWidget);
  expectOnScreen(_field('目标名称'), reason: '目标名称输入框应在视口内');
  expect(find.text('目标名称'), findsOneWidget);
  expect(find.text('描述（可选）'), findsOneWidget);
  await shot('03-goal-form', landmark: '新建目标');

  await tester.enterText(_field('目标名称'), '整理发布材料');
  await pumpUi();
  await saveDialog();
  expect(find.text('整理发布材料'), findsOneWidget);
  expect(find.text('0 项任务 · 暂无任务 · 未完成'), findsOneWidget);
  await shot('04-goal-created', landmark: '整理发布材料');

  // 4. 任务：新建、编辑、完成。
  await tapVisible(find.text('添加任务'));
  expectOnScreen(_field('任务名称'), reason: '任务名称输入框应在视口内');
  await tester.enterText(_field('任务名称'), '写提纲');
  await pumpUi();
  await saveDialog();
  expect(find.text('1 项任务 · 进行中'), findsOneWidget);
  await shot('05-task-created', landmark: '写提纲');

  await tapVisible(find.text('写提纲'));
  expect(find.text('编辑任务'), findsOneWidget);
  expectOnScreen(_field('任务名称'), reason: '任务编辑输入框应在视口内');
  await shot('06-task-edit-form', landmark: '编辑任务');
  await tester.enterText(_field('任务名称'), '写提纲（修订）');
  await pumpUi();
  await saveDialog();
  expect(find.text('写提纲（修订）'), findsOneWidget);

  await tapVisible(
    find.descendant(
      of: find.ancestor(
        of: find.text('写提纲（修订）'),
        matching: find.byType(ListTile),
      ),
      matching: find.byType(Checkbox),
    ),
  );
  expect(find.text('1 项任务 · 已完成'), findsOneWidget);
  await shot('07-task-completed', landmark: '写提纲（修订）');

  // 5. 目标折叠：标题整体是折叠控制，描述仍可读。
  await tapVisible(find.text('整理发布材料'));
  await pumpUi();
  expect(find.text('写提纲（修订）'), findsNothing);
  expect(find.text('添加任务'), findsNothing);
  await shot('08-goal-collapsed', landmark: '整理发布材料');
  await tapVisible(find.text('整理发布材料'));
  await pumpUi();
  expect(find.text('写提纲（修订）'), findsOneWidget);

  // 6. 删除任务（保留目标与其它任务）。
  await tapVisible(
    find.descendant(
      of: find.ancestor(
        of: find.text('写提纲（修订）'),
        matching: find.byType(ListTile),
      ),
      matching: find.byTooltip('删除任务'),
    ),
  );
  expect(find.text('删除任务？'), findsOneWidget);
  await shot('09-task-delete-confirm', landmark: '删除任务？');
  await tapVisible(find.widgetWithText(FilledButton, '删除'));
  expect(find.text('写提纲（修订）'), findsNothing);
  expect(find.text('整理发布材料'), findsOneWidget);

  await tapVisible(find.text('添加任务'));
  await tester.enterText(_field('任务名称'), '补充证据');
  await pumpUi();
  await saveDialog();
  expect(find.text('1 项任务 · 进行中'), findsOneWidget);
  expect(find.text('补充证据'), findsOneWidget);
  await shot('10-task-recreated', landmark: '补充证据');

  // 7. 目标删除：先建一个一次性目标再删掉。
  await tapVisible(find.text('新建目标'));
  await tester.enterText(_field('目标名称'), '临时目标');
  await pumpUi();
  await saveDialog();
  expect(find.text('临时目标'), findsOneWidget);
  await tapVisible(
    find.descendant(of: _goalCard('临时目标'), matching: find.byTooltip('删除目标')),
  );
  expect(find.text('删除目标和任务？'), findsOneWidget);
  await shot('11-goal-delete-confirm', landmark: '删除目标和任务？');
  await tapVisible(find.widgetWithText(FilledButton, '删除'));
  expect(find.text('临时目标'), findsNothing);

  // 8. 置顶两个目标并手动排序。
  for (final title in ['季度复盘', '本周交付']) {
    await tapVisible(find.text('新建目标'));
    await tester.enterText(_field('目标名称'), title);
    await pumpUi();
    await saveDialog();
    expect(find.text(title), findsOneWidget);
  }
  for (final title in ['本周交付', '整理发布材料']) {
    await tapVisible(
      find.descendant(of: _goalCard(title), matching: find.byTooltip('置顶目标')),
    );
  }
  expect(find.text('置顶目标 · 手动顺序'), findsOneWidget);
  expect(
    _top(tester, find.text('本周交付')),
    lessThan(_top(tester, find.text('整理发布材料'))),
  );
  await shot('12-pins-order', landmark: '置顶目标 · 手动顺序');

  await tapVisible(
    find.descendant(of: _goalCard('本周交付'), matching: find.byTooltip('下移置顶目标')),
  );
  expect(
    _top(tester, find.text('整理发布材料')),
    lessThan(_top(tester, find.text('本周交付'))),
  );
  await shot('13-pins-reordered', landmark: '置顶目标 · 手动顺序');

  // 9. 看板只保留摘要：置顶目标 + 下一项，不展开任务、没有管理入口。
  await openDestination('看板');
  expect(find.byType(BoardPage), findsOneWidget);
  expectOnScreen(find.text('置顶目标'), reason: '看板置顶摘要应在视口内');
  expect(find.text('下一项：补充证据'), findsOneWidget);
  expect(find.text('补充证据'), findsNothing, reason: '看板不展开任务列表');
  expect(find.text('添加任务'), findsNothing);
  expect(find.byTooltip('开始专注'), findsNothing);
  expect(find.text('还没有置顶目标'), findsNothing);
  await shot('14-board-summary-only', landmark: '置顶目标');

  // 10. 计划日历：一条任务两条安排 + 独立事项。
  await openDestination('计划');
  await tapVisible(find.text('日历'));
  expect(find.text('新建安排'), findsOneWidget);
  expect(find.text('添加事项'), findsOneWidget);
  await shot('15-calendar', landmark: '新建安排');

  Future<void> createArrangement(
    String title, {
    String? task,
    String? reminder,
  }) async {
    await tapVisible(find.text('添加事项'));
    expectOnScreen(_field('名称'), reason: '安排名称输入框应在视口内');
    await tester.enterText(_field('名称'), title);
    if (task != null) await chooseDropdown('关联任务（可选）', task);
    if (reminder != null) await chooseDropdown('提醒（可选）', reminder);
    await saveDialog();
  }

  await createArrangement('上午整理', task: '补充证据', reminder: '提前 10 分钟');
  expect(find.text('上午整理'), findsOneWidget);
  expect(find.text('任务：补充证据'), findsOneWidget);
  expect(find.text('提前 10 分钟提醒'), findsOneWidget);
  await shot('16-arrangement-linked', landmark: '上午整理');

  await createArrangement('下午复核', task: '补充证据');
  expect(find.text('下午复核'), findsOneWidget);
  expect(find.textContaining('2 项安排'), findsOneWidget);
  await shot('17-two-arrangements', landmark: '下午复核');

  await createArrangement('取快递');
  expect(find.text('取快递'), findsOneWidget);
  expect(find.text('独立事项'), findsOneWidget);
  await shot('18-standalone-created', landmark: '取快递');

  await tapVisible(_scheduleTile('取快递'));
  expect(find.text('编辑安排'), findsOneWidget);
  await shot('19-standalone-edit-form', landmark: '编辑安排');
  await tester.enterText(_field('名称'), '取快递并寄件');
  await pumpUi();
  await saveDialog();
  expect(find.text('取快递并寄件'), findsOneWidget);

  await tapVisible(
    find.descendant(
      of: _scheduleTile('取快递并寄件'),
      matching: find.byType(Checkbox),
    ),
  );
  expect(
    tester
        .widget<Checkbox>(
          find.descendant(
            of: _scheduleTile('取快递并寄件'),
            matching: find.byType(Checkbox),
          ),
        )
        .value,
    isTrue,
  );
  await shot('20-standalone-completed', landmark: '取快递并寄件');

  await tapVisible(
    find.descendant(
      of: _scheduleTile('取快递并寄件'),
      matching: find.byTooltip('安排操作'),
    ),
  );
  await tapVisible(find.text('删除安排'));
  expect(find.text('删除这条安排？'), findsOneWidget);
  await shot('21-standalone-delete-confirm', landmark: '删除这条安排？');
  await tapVisible(find.widgetWithText(FilledButton, '删除'));
  expect(find.text('取快递并寄件'), findsNothing);
  expect(find.text('上午整理'), findsOneWidget);
  expect(find.text('下午复核'), findsOneWidget);

  // 11. 跨天 / 全天 / 已删除任务链接：编辑器要能原样读出并原样交回。
  final today = DateTime.now();
  String civil(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
  final multiDayEnd = DateTime(today.year, today.month, today.day + 2);
  final multiDay = await schedules.createSchedule(
    ScheduleDraft(
      title: '跨城评审',
      window: ScheduleWindow.timed(
        startsAt: DateTime(today.year, today.month, today.day, 9),
        endsAt: DateTime(
          multiDayEnd.year,
          multiDayEnd.month,
          multiDayEnd.day,
          17,
        ),
      ),
    ),
  );
  final allDayEnd = DateTime(today.year, today.month, today.day + 3);
  final allDayItem = await schedules.createSchedule(
    ScheduleDraft(
      title: '三天工作坊',
      window: ScheduleWindow.allDayDates(
        startDate: civil(today),
        endDateExclusive: civil(allDayEnd),
      ),
    ),
  );
  final linkGoal = await tasks.createGoal(
    const GoalDraft(title: '外部协作', classification: TaskClassification.regular),
  );
  final linkTask = await tasks.createTask(
    linkGoal.id,
    const TaskDraft(title: '对接供应商', classification: TaskClassification.regular),
  );
  final linkedItem = await schedules.createSchedule(
    ScheduleDraft(
      title: '供应商同步',
      window: ScheduleWindow.timed(
        startsAt: DateTime(today.year, today.month, today.day, 15),
        endsAt: DateTime(today.year, today.month, today.day, 16),
      ),
      taskId: linkTask.id,
    ),
  );
  await tasks.deleteTask(linkTask.id);
  await pumpUi();

  await tapVisible(find.text('跨城评审'));
  expectOnScreen(find.text('结束 ${civil(multiDayEnd)}'), reason: '跨天安排要显示结束日');
  await shot('22-multiday-edit-form', landmark: '编辑安排');
  await tapVisible(find.widgetWithText(FilledButton, '保存'));
  final multiDaySaved = (await schedules.getSchedules()).singleWhere(
    (schedule) => schedule.id == multiDay.id,
  );
  expect(multiDaySaved.startsAt, multiDay.startsAt, reason: '改期不能压缩跨天安排');
  expect(multiDaySaved.endsAt, multiDay.endsAt, reason: '改期不能压缩跨天安排');

  await tapVisible(find.text('三天工作坊'));
  expectOnScreen(
    find.text('结束（不含） ${civil(allDayEnd)}'),
    reason: '全天安排要显示不含的结束日',
  );
  await shot('23-allday-edit-form', landmark: '编辑安排');
  await tapVisible(find.widgetWithText(FilledButton, '保存'));
  final allDaySaved = (await schedules.getSchedules()).singleWhere(
    (schedule) => schedule.id == allDayItem.id,
  );
  expect(allDaySaved.allDayStartDate, allDayItem.allDayStartDate);
  expect(allDaySaved.allDayEndDateExclusive, allDayItem.allDayEndDateExclusive);
  expect(allDaySaved.startsAt, allDayItem.startsAt, reason: '全天日期不因时区被挪动');

  await tapVisible(find.text('供应商同步'));
  expectOnScreen(find.text('已删除的任务：对接供应商'), reason: '已删除任务的链接仍要可读');
  await shot('24-deleted-link-edit', landmark: '编辑安排');
  await tapVisible(find.widgetWithText(FilledButton, '保存'));
  final linkedSaved = (await schedules.getSchedules()).singleWhere(
    (schedule) => schedule.id == linkedItem.id,
  );
  expect(linkedSaved.taskId, linkTask.id, reason: '既有链接不能被保存清空');

  // 12. 回到目标视图：任务仍在、置顶顺序仍在。
  await tapVisible(find.text('目标'));
  expect(find.text('置顶目标 · 手动顺序'), findsOneWidget);
  expect(
    _top(tester, find.text('整理发布材料')),
    lessThan(_top(tester, find.text('本周交付'))),
  );
  await shot('22-plan-final', landmark: '整理发布材料');

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await schedules.dispose();
  await focus.dispose();
  await tree.dispose();
  await database.close();
  return written;
}
