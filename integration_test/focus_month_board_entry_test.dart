import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/ui/pacta_check_circle.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/profile/profile_repository.dart';
import 'package:pacta/src/schedules/schedule_models.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../test/support/fake_auth_repository.dart';
import '../test/support/test_database.dart';

/// Memory-only Windows fixture for ticket 12 phase 2: the real Board entry,
/// the standalone month page and the Plan calendar staying independent.
///
///   flutter test integration_test/focus_month_board_entry_test.dart -d windows \
///     --dart-define=FOCUS_MONTH_BOARD_VIEWPORT=360 \
///     --dart-define=FOCUS_MONTH_BOARD_THEME=light \
///     --dart-define=FOCUS_MONTH_BOARD_SCREENSHOT_DIR=C:/abs/path
///
/// Root runs the four narrow widths; this worker does not run native. The
/// fixture mounts the real AppShell with the real theme/fonts, a fixed clock and
/// fresh in-memory repositories per provider creation. Every capture is preceded
/// by a visible-state assertion; captures never overwrite and the run writes its
/// own manifest.json.
const _viewport = String.fromEnvironment(
  'FOCUS_MONTH_BOARD_VIEWPORT',
  defaultValue: '360',
);
const _theme = String.fromEnvironment(
  'FOCUS_MONTH_BOARD_THEME',
  defaultValue: 'light',
);
const _screenshotRoot = String.fromEnvironment(
  'FOCUS_MONTH_BOARD_SCREENSHOT_DIR',
);

const _user = 'focus-month-board-fixture';
const _clockIso = '2026-11-18T09:00:00Z';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('看板月历入口与计划日历独立：真实主题、固定时钟、内存数据', (tester) async {
    if (_screenshotRoot.isEmpty) {
      fail('缺少 --dart-define=FOCUS_MONTH_BOARD_SCREENSHOT_DIR=<绝对目录>');
    }
    final viewport = switch (_viewport) {
      '320' => 320.0,
      '360' => 360.0,
      '375' => 375.0,
      '412' => 412.0,
      _ => throw ArgumentError.value(_viewport, 'FOCUS_MONTH_BOARD_VIEWPORT'),
    };
    final brightness = switch (_theme) {
      'light' => Brightness.light,
      'dark' => Brightness.dark,
      _ => throw ArgumentError.value(_theme, 'FOCUS_MONTH_BOARD_THEME'),
    };
    final root = Directory(_screenshotRoot);
    if (!root.isAbsolute) {
      fail('FOCUS_MONTH_BOARD_SCREENSHOT_DIR 必须是绝对路径：${root.path}');
    }
    final runDirectory = Directory(
      '${root.path}${Platform.pathSeparator}run-${DateTime.now().microsecondsSinceEpoch}',
    );
    await runDirectory.create(recursive: true);
    final runLabel = '$_viewport-$_theme-${Platform.operatingSystem}';

    final clock = DateTime.parse(_clockIso);
    final database = openTestDatabase();
    final focusRemote = InMemoryFocusRemote();

    LocalTaskRepository tasksFor(String userId) => LocalTaskRepository(
      database: database,
      userId: userId,
      remote: InMemoryTaskRemote(),
      now: () => clock,
    );
    LocalFocusRepository focusFor(String userId) => LocalFocusRepository(
      database: database,
      userId: userId,
      remote: focusRemote,
      now: () => clock,
    );
    LocalScheduleRepository schedulesFor(String userId) =>
        LocalScheduleRepository(
          database: database,
          userId: userId,
          now: () => clock,
        );
    LocalProfileRepository profileFor(String userId) => LocalProfileRepository(
      database: database,
      userId: userId,
      now: () => clock,
    );

    final seedingTasks = tasksFor(_user);
    final seedingFocus = focusFor(_user);
    final seedingSchedules = schedulesFor(_user);
    final seedingProfile = profileFor(_user);

    final boundaryKey = GlobalKey();
    final manifest = <String, Object?>{
      'page': 'Board -> FocusMonthPage + Plan calendar',
      'viewport': viewport,
      'theme': _theme,
      'host': '${Platform.operatingSystem} ${Platform.version}',
      'clock': _clockIso,
      'account_time_zone': 'Asia/Shanghai',
      'database': 'in-memory (no user data touched)',
      'captures': <String, Object?>{},
      'note':
          'worker fixture evidence only; root runs it; not visual acceptance',
    };

    Future<void> shot(String state) async {
      final name = 'focus-month-board-$runLabel-$state';
      final logicalSize =
          tester.view.physicalSize / tester.view.devicePixelRatio;
      debugPrint(
        '[focus-month-board] state=$state logical=$logicalSize theme=$_theme',
      );
      if (!Platform.isWindows) {
        debugPrint('[focus-month-board] non-Windows host: capture skipped');
        return;
      }
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(
        pixelRatio: tester.view.devicePixelRatio,
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final width = image.width;
      final height = image.height;
      image.dispose();
      final file = File(
        '${runDirectory.path}${Platform.pathSeparator}$name.png',
      );
      if (await file.exists()) fail('拒绝覆盖已有截图：${file.path}');
      await file.writeAsBytes(data!.buffer.asUint8List());
      final captures = manifest['captures']! as Map<String, Object?>;
      captures[state] = <String, Object?>{
        'file': '$name.png',
        'bytes': await file.length(),
        'pixel_width': width,
        'pixel_height': height,
      };
      debugPrint('[focus-month-board] wrote ${file.path}');
    }

    Future<void> settle() async {
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    }

    Future<void> scrollBoardTo(String text) => tester.scrollUntilVisible(
      find.text(text),
      200,
      scrollable: find
          .descendant(
            of: find.byType(BoardPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );

    try {
      await seedingProfile.saveProfile(
        displayName: '月历夹具',
        timeZoneId: 'Asia/Shanghai',
      );
      final goal = await seedingTasks.createGoal(
        const GoalDraft(title: '季度发布', classification: TaskClassification.both),
      );
      final task = await seedingTasks.createTask(
        goal.id,
        const TaskDraft(
          title: '整理发布材料',
          classification: TaskClassification.both,
        ),
      );
      await focusRemote.upsertSessions(
        userId: _user,
        sessions: [
          FocusSession(
            id: 'board-entry-fx',
            taskId: task.id,
            mode: FocusChainMode.regular,
            durationSeconds: 13 * 60,
            startedAt: DateTime.utc(2026, 11, 12, 2),
            endsAt: DateTime.utc(2026, 11, 12, 2, 13),
            completedAt: DateTime.utc(2026, 11, 12, 2, 13),
            status: FocusSessionStatus.completed,
            effectiveSeconds: 13 * 60,
            effectiveIntervals: [
              FocusTimeInterval(
                startedAt: DateTime.utc(2026, 11, 12, 2),
                endedAt: DateTime.utc(2026, 11, 12, 2, 13),
              ),
            ],
            reviewDisposition: FocusRecordDisposition.accepted,
          ),
        ],
      );
      await seedingFocus.sync();
      final schedule = await seedingSchedules.createSchedule(
        ScheduleDraft(
          title: '取快递',
          window: ScheduleWindow.timed(
            startsAt: DateTime.utc(2026, 11, 18, 8),
            endsAt: DateTime.utc(2026, 11, 18, 9),
          ),
        ),
      );

      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(viewport, 900);
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: PactaApp(
            authRepository: FakeAuthRepository()..signedInUser = _user,
            taskRepositoryFactory: tasksFor,
            focusRepositoryFactory: focusFor,
            scheduleRepositoryFactory: schedulesFor,
            profileRepositoryFactory: profileFor,
            displayClock: () => clock,
            cloudCheckClock: () => clock,
            deviceTimeZoneIdReader: () async => null,
          ),
        ),
      );
      await settle();

      await scrollBoardTo('打开月历');
      expect(find.text('近期专注活动'), findsOneWidget);
      expect(find.text('打开月历'), findsOneWidget);
      expect(find.textContaining('累计有效专注 13分00秒'), findsOneWidget);
      await shot('board');

      await tester.tap(find.text('打开月历'));
      await settle();
      expect(find.text('专注月历'), findsOneWidget);
      expect(find.text('2026年11月'), findsOneWidget);
      expect(find.text('13分00秒'), findsOneWidget);
      final day12 = find.byKey(const ValueKey('focus-month-day-12'));
      expect(day12, findsOneWidget);
      final daySize = tester.getSize(day12);
      debugPrint('[focus-month-board] day cell at $viewport: $daySize');
      expect(daySize.width, greaterThanOrEqualTo(48));
      expect(daySize.height, greaterThanOrEqualTo(48));
      await shot('month');

      await tester.pageBack();
      await settle();
      await tester.tap(find.text('计划'));
      await settle();
      await tester.tap(find.text('日历'));
      await settle();
      final card = find.byKey(ValueKey('schedule-card-${schedule.id}'));
      expect(card, findsOneWidget);
      await tester.tap(
        find.descendant(of: card, matching: find.byType(PactaCheckCircle)),
      );
      await settle();
      expect(
        (await seedingSchedules.getSchedules()).single.isCompleted,
        isTrue,
      );
      // The fixture seeds one session for the board's number; completing a Plan
      // arrangement must not add another one.
      final sessions = await seedingFocus.getSessions();
      expect(sessions, hasLength(1));
      expect(sessions.single.id, 'board-entry-fx');
      await shot('plan-completed');

      await tester.tap(find.text('看板'));
      await settle();
      await scrollBoardTo('打开月历');
      await tester.tap(find.text('打开月历'));
      await settle();
      expect(find.text('2026年11月'), findsOneWidget);
      expect(find.text('13分00秒'), findsOneWidget);
      expect(find.text('本月暂无有效投入。'), findsNothing);
      await shot('month-after-plan');

      final manifestFile = File(
        '${runDirectory.path}${Platform.pathSeparator}manifest.json',
      );
      if (await manifestFile.exists()) {
        fail('拒绝覆盖已有 manifest：${manifestFile.path}');
      }
      await manifestFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest),
      );
      debugPrint('[focus-month-board] run directory ${runDirectory.path}');
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await seedingProfile.dispose();
      await seedingSchedules.dispose();
      await seedingFocus.dispose();
      await seedingTasks.dispose();
      await database.close();
    }
  });
}
