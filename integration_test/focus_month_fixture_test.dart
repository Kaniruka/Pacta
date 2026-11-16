import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_month_page.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart' show PactaDatabase;
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

/// Memory-only Windows fixture for the read-only focus month page (ticket 12,
/// stage 1).
///
///   flutter test integration_test/focus_month_fixture_test.dart -d windows \
///     --dart-define=FOCUS_MONTH_VIEWPORT=360 \
///     --dart-define=FOCUS_MONTH_THEME=light \
///     --dart-define=FOCUS_MONTH_SCREENSHOT_DIR=C:/abs/path
///
/// The fixture mounts [FocusMonthPage] directly - the final Board entry belongs
/// to the later combination step - with the real [pactaTheme] and MiSans assets,
/// a fixed clock, and an in-memory database. Every capture is preceded by a
/// visible-state assertion; a capture that would overwrite an existing file
/// fails instead. A worker run here is fixture evidence, never final visual
/// acceptance.
const _viewport = String.fromEnvironment(
  'FOCUS_MONTH_VIEWPORT',
  defaultValue: '360',
);
const _theme = String.fromEnvironment(
  'FOCUS_MONTH_THEME',
  defaultValue: 'light',
);
const _screenshotRoot = String.fromEnvironment('FOCUS_MONTH_SCREENSHOT_DIR');

const _user = 'focus-month-offline-fixture';
const _noon = '2026-11-18T09:00:00Z';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('专注月历只有效投入：窄/宽、亮/暗与切换月份', (tester) async {
    if (_screenshotRoot.isEmpty) {
      fail('缺少 --dart-define=FOCUS_MONTH_SCREENSHOT_DIR=<绝对目录>');
    }
    final root = Directory(_screenshotRoot);
    if (!root.isAbsolute) {
      fail('FOCUS_MONTH_SCREENSHOT_DIR 必须是绝对路径：${root.path}');
    }
    final width = switch (_viewport) {
      '360' => 360.0,
      '1440' => 1440.0,
      _ => throw ArgumentError.value(_viewport, 'FOCUS_MONTH_VIEWPORT'),
    };
    final brightness = switch (_theme) {
      'light' => Brightness.light,
      'dark' => Brightness.dark,
      _ => throw ArgumentError.value(_theme, 'FOCUS_MONTH_THEME'),
    };
    final runDirectory = Directory(
      '${root.path}${Platform.pathSeparator}'
      'run-${DateTime.now().microsecondsSinceEpoch}',
    );
    await runDirectory.create(recursive: true);
    final runLabel = '$_viewport-$_theme-${Platform.operatingSystem}';

    final clock = DateTime.parse(_noon);
    final database = PactaDatabase(NativeDatabase.memory());
    final tasks = LocalTaskRepository(
      database: database,
      userId: _user,
      remote: InMemoryTaskRemote(),
      now: () => clock,
    );
    final remote = InMemoryFocusRemote();
    // Cloud sync stays enabled: the fixture seeds through the same in-memory
    // remote boundary the app uses, and `sync()` is a no-op when disabled.
    final focus = LocalFocusRepository(
      database: database,
      userId: _user,
      remote: remote,
      now: () => clock,
    );
    final boundaryKey = GlobalKey();
    var ready = false;

    Future<void> shot(String state) async {
      final name = 'focus-month-$runLabel-$state';
      final size = tester.view.physicalSize / tester.view.devicePixelRatio;
      debugPrint(
        '[focus-month-fixture] state=$state logical=$size '
        'theme=$_theme dpr=${tester.view.devicePixelRatio}',
      );
      if (!Platform.isWindows) {
        // The fixture target is Windows; elsewhere keep the state evidence only.
        debugPrint('[focus-month-fixture] non-Windows host: capture skipped');
        return;
      }
      if (Platform.isAndroid) {
        if (!ready) {
          await binding.convertFlutterSurfaceToImage();
          ready = true;
        }
        await binding.takeScreenshot(name);
        return;
      }
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(
        pixelRatio: tester.view.devicePixelRatio,
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final file = File(
        '${runDirectory.path}${Platform.pathSeparator}$name.png',
      );
      if (await file.exists()) fail('拒绝覆盖已有截图：${file.path}');
      await file.writeAsBytes(data!.buffer.asUint8List());
      debugPrint('[focus-month-fixture] wrote ${file.path}');
    }

    Future<void> settle() async {
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    }

    try {
      final goal = await tasks.createGoal(
        const GoalDraft(title: '季度发布', classification: TaskClassification.both),
      );
      final task = await tasks.createTask(
        goal.id,
        const TaskDraft(
          title: '整理发布材料',
          classification: TaskClassification.both,
        ),
      );
      // 2026 年 11 月：3 日 45 分、12 日 90 分、18 日 60 分 => 3 小时 15 分钟。
      // 2026 年 10 月：9 日 30 分，用来证明切月后读到的是另一份投影。
      await remote.upsertSessions(
        userId: _user,
        sessions: [
          _session(task.id, DateTime.utc(2026, 10, 9, 2), 30 * 60),
          _session(task.id, DateTime.utc(2026, 11, 3, 2), 45 * 60),
          _session(task.id, DateTime.utc(2026, 11, 12, 2), 90 * 60),
          _session(task.id, DateTime.utc(2026, 11, 18, 2), 60 * 60),
        ],
      );
      await focus.sync();

      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: pactaTheme(brightness),
            home: FocusMonthPage(
              repository: focus,
              accountTimeZoneIds: () => Stream<String?>.value('Asia/Shanghai'),
              initialMonth: DateTime(2026, 11),
              now: () => clock,
            ),
          ),
        ),
      );
      await settle();

      // State check before the first capture: real visible projection, not a
      // widget-existence check.
      expect(find.text('专注月历'), findsOneWidget);
      expect(find.text('2026年11月'), findsOneWidget);
      expect(find.text('本月有效投入'), findsOneWidget);
      expect(find.text('3 小时 15 分钟'), findsOneWidget);
      expect(find.text('有投入的天数 3 天'), findsOneWidget);
      await shot('month');

      await tester.tap(find.byKey(const ValueKey('focus-month-day-12')));
      await settle();
      expect(find.text('11月12日'), findsOneWidget);
      expect(find.text('有效投入 1 小时 30 分钟'), findsOneWidget);
      await shot('day-detail');

      await tester.tap(find.byTooltip('上个月'));
      await settle();
      expect(find.text('2026年10月'), findsOneWidget);
      expect(find.text('30 分钟'), findsOneWidget);
      await shot('previous-month');

      final manifest = File(
        '${runDirectory.path}${Platform.pathSeparator}manifest.txt',
      );
      await manifest.writeAsString(
        [
          'page: FocusMonthPage (stage 1 standalone mount)',
          'viewport: $_viewport',
          'theme: $_theme',
          'host: ${Platform.operatingSystem} ${Platform.version}',
          'clock: $_noon',
          'account_time_zone: Asia/Shanghai',
          'database: in-memory (no user data touched)',
          'states: month, day-detail, previous-month',
          'note: worker fixture evidence only; not final visual acceptance',
        ].join('\n'),
      );
      debugPrint('[focus-month-fixture] run directory ${runDirectory.path}');
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await focus.dispose();
      await tasks.dispose();
      await database.close();
    }
  });
}

FocusSession _session(String taskId, DateTime startedAt, int seconds) {
  final endsAt = startedAt.add(Duration(seconds: seconds));
  return FocusSession(
    id: 'fx-${startedAt.toIso8601String()}',
    taskId: taskId,
    mode: FocusChainMode.regular,
    durationSeconds: seconds,
    startedAt: startedAt,
    endsAt: endsAt,
    status: FocusSessionStatus.completed,
    completedAt: endsAt,
    effectiveSeconds: seconds,
    effectiveIntervals: [
      FocusTimeInterval(startedAt: startedAt, endedAt: endsAt),
    ],
    reviewDisposition: FocusRecordDisposition.accepted,
  );
}
