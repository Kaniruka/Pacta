import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/app/app_providers.dart';
import 'package:pacta/src/focus/effective_duration_text.dart';
import 'package:pacta/src/focus/focus_chain_page.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';
import 'package:pacta/src/theme/pacta_theme.dart';

/// 工单 06：《选择任务》副标题简写 + 三档筛选左右滑动。
void main() {
  group('紧凑时长文案', () {
    test('专注进度整分时省掉末尾的 00秒 噪音', () {
      expect(formatCompactFocusDuration(1500), '25分');
      expect(formatCompactFocusDuration(900), '15分');
      expect(formatCompactFocusDuration(3600), '1小时');
    });

    test('满 10 分钟省掉秒，不足 10 分钟保留非零秒，小时位只在非零时出现', () {
      expect(formatCompactFocusDuration(185), '3分5秒');
      expect(formatCompactFocusDuration(4498), '1小时14分');
      expect(formatCompactFocusDuration(3605), '1小时');
      expect(formatCompactFocusDuration(3661), '1小时1分');
    });

    test('不足一分钟按秒读，零值写 0分', () {
      expect(formatCompactFocusDuration(45), '45秒');
      expect(formatCompactFocusDuration(1), '1秒');
      expect(formatCompactFocusDuration(0), '0分');
      expect(formatCompactFocusDuration(-10), '0分');
    });

    test('预计时长满 60 分钟自动换算为小时与分', () {
      expect(formatCompactEstimateMinutes(2880), '48小时');
      expect(formatCompactEstimateMinutes(60), '1小时');
      expect(formatCompactEstimateMinutes(90), '1小时30分');
      expect(formatCompactEstimateMinutes(25), '25分钟');
      expect(formatCompactEstimateMinutes(0), '0分钟');
    });
  });

  group('《选择任务》副标题', () {
    testWidgets('只保留目标名、已专注进度与预计时长', (tester) async {
      await _pumpPicker(tester, goals: _goals());

      expect(_subtitleOf(tester, '精读一章'), '每日精进，已专注 0分 / 48小时');
      expect(_subtitleOf(tester, '整理笔记'), '每日精进，已专注 25分 / 1小时30分');
      expect(_subtitleOf(tester, '写摘要'), '每日精进，已专注 0分 / 25分钟');
      expect(_subtitleOf(tester, '复盘'), '每日精进，尚未专注');
      expect(_subtitleOf(tester, '晨间冥想'), '每日精进，已专注 45秒');
      expect(_subtitleOf(tester, '双模式任务'), '每日精进，已专注 1小时 / 1小时');

      // 不再回显左侧图标已经表达的分类，也不再写无意义的未设置占位。
      expect(find.textContaining('目标：'), findsNothing);
      expect(find.textContaining('预计时长'), findsNothing);
      for (final subtitle in _subtitles(tester)) {
        expect(subtitle, isNot(contains(' · 精锐')), reason: subtitle);
        expect(subtitle, isNot(contains(' · 普通')), reason: subtitle);
        expect(subtitle, isNot(contains(' · 两者')), reason: subtitle);
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('三档筛选左右滑动', () {
    testWidgets('触控横滑与胶囊双向联动', (tester) async {
      await _pumpPicker(tester, goals: _goals());
      final pager = find.byKey(const ValueKey('focus-task-picker-pager'));
      expect(pager, findsOneWidget);
      expect(_selectedFilter(tester), <TaskClassification?>{null});
      expect(find.text('精读一章'), findsOneWidget);
      expect(find.text('整理笔记'), findsOneWidget);

      // 左滑到「精锐」：只剩精锐与双模式任务。
      await tester.drag(pager, const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(_selectedFilter(tester), <TaskClassification?>{
        TaskClassification.elite,
      });
      expect(find.text('精读一章'), findsOneWidget);
      expect(find.text('写摘要'), findsOneWidget);
      expect(find.text('双模式任务'), findsOneWidget);
      expect(find.text('整理笔记'), findsNothing);
      expect(find.text('晨间冥想'), findsNothing);

      // 继续左滑到「普通」：普通与双模式任务。
      await tester.drag(pager, const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(_selectedFilter(tester), <TaskClassification?>{
        TaskClassification.regular,
      });
      expect(find.text('整理笔记'), findsOneWidget);
      expect(find.text('复盘'), findsOneWidget);
      expect(find.text('晨间冥想'), findsOneWidget);
      expect(find.text('双模式任务'), findsOneWidget);
      expect(find.text('精读一章'), findsNothing);

      // 点选胶囊回到「全部」：页面与高亮同步。
      await tester.tap(find.text('全部'));
      await tester.pumpAndSettle();
      expect(_selectedFilter(tester), <TaskClassification?>{null});
      expect(find.text('精读一章'), findsOneWidget);
      expect(find.text('整理笔记'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('鼠标按住横拖同样能翻页', (tester) async {
      await _pumpPicker(tester, goals: _goals());
      final pager = find.byKey(const ValueKey('focus-task-picker-pager'));

      await tester.drag(
        pager,
        const Offset(-400, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(_selectedFilter(tester), <TaskClassification?>{
        TaskClassification.elite,
      });
      expect(find.text('写摘要'), findsOneWidget);

      await tester.drag(
        pager,
        const Offset(400, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(_selectedFilter(tester), <TaskClassification?>{null});
      expect(find.text('整理笔记'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('三页各自的 PageStorageKey 保留独立滚动位置', (tester) async {
      await _pumpPicker(tester, goals: _goals());
      final pager = find.byKey(const ValueKey('focus-task-picker-pager'));

      expect(
        _visibleList(tester).key,
        const PageStorageKey<String>('focus-task-picker-list-0'),
      );
      await tester.drag(find.byType(ListView), const Offset(0, -260));
      await tester.pumpAndSettle();
      final savedOffset = _listPosition(tester).pixels;
      expect(savedOffset, greaterThan(0));

      await tester.drag(pager, const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(
        _visibleList(tester).key,
        const PageStorageKey<String>('focus-task-picker-list-1'),
      );
      expect(_listPosition(tester).pixels, 0, reason: '精锐页有独立滚动位置');

      await tester.drag(pager, const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(
        _visibleList(tester).key,
        const PageStorageKey<String>('focus-task-picker-list-2'),
      );

      await tester.drag(pager, const Offset(400, 0));
      await tester.pumpAndSettle();
      await tester.drag(pager, const Offset(400, 0));
      await tester.pumpAndSettle();
      expect(
        _visibleList(tester).key,
        const PageStorageKey<String>('focus-task-picker-list-0'),
      );
      expect(
        _listPosition(tester).pixels,
        moreOrLessEquals(savedOffset, epsilon: 1),
        reason: '滑回全部页仍停在原来的滚动位置',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('桌面分页交互', () {
    testWidgets('1280x800 宽屏左留白鼠标横拖切换筛选', (tester) async {
      await _pumpPicker(tester, goals: _goals(), size: const Size(1280, 800));
      expect(_selectedFilter(tester), <TaskClassification?>{null});

      // 页头与列表都收在 960dp 阅读线内：x=60 落在左侧留白，仍然能起手。
      await tester.dragFrom(
        const Offset(60, 400),
        const Offset(-300, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(_selectedFilter(tester), <TaskClassification?>{
        TaskClassification.elite,
      });

      await tester.dragFrom(
        const Offset(60, 400),
        const Offset(300, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(_selectedFilter(tester), <TaskClassification?>{null});
      expect(tester.takeException(), isNull);
    });

    testWidgets('Windows 精确触控板双指横滑翻页，斜滑不翻页', (tester) async {
      await _pumpPicker(tester, goals: _goals(), size: const Size(1280, 800));

      var gesture = await tester.createGesture(
        kind: PointerDeviceKind.trackpad,
      );
      await gesture.panZoomStart(const Offset(640, 400));
      for (var step = 1; step <= 4; step++) {
        await gesture.panZoomUpdate(
          const Offset(640, 400),
          pan: Offset(-50.0 * step, -50.0 * step),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.panZoomEnd();
      await tester.pumpAndSettle();
      expect(_selectedFilter(tester), <TaskClassification?>{
        null,
      }, reason: '斜滑不翻页');

      gesture = await tester.createGesture(kind: PointerDeviceKind.trackpad);
      await gesture.panZoomStart(const Offset(640, 400));
      for (var step = 1; step <= 4; step++) {
        await gesture.panZoomUpdate(
          const Offset(640, 400),
          pan: Offset(-50.0 * step, 0),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.panZoomEnd();
      await tester.pumpAndSettle();
      expect(_selectedFilter(tester), <TaskClassification?>{
        TaskClassification.elite,
      });
      expect(tester.takeException(), isNull);
    });

    testWidgets('Shift+滚轮、横向滚轮与快捷键切换筛选', (tester) async {
      await _pumpPicker(tester, goals: _goals(), size: const Size(1280, 800));
      final pager = find.byKey(const ValueKey('focus-task-picker-pager'));
      final center = tester.getCenter(pager);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: center,
          scrollDelta: const Offset(0, 100),
          kind: PointerDeviceKind.mouse,
        ),
      );
      await tester.pumpAndSettle();
      expect(_selectedFilter(tester), <TaskClassification?>{
        TaskClassification.elite,
      });
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

      await tester.pump(const Duration(milliseconds: 400));
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: center,
          scrollDelta: const Offset(-100, 0),
          kind: PointerDeviceKind.mouse,
        ),
      );
      await tester.pumpAndSettle();
      expect(_selectedFilter(tester), <TaskClassification?>{null});

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(_selectedFilter(tester), <TaskClassification?>{
        TaskClassification.elite,
      });
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(_selectedFilter(tester), <TaskClassification?>{
        TaskClassification.regular,
      });
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(_selectedFilter(tester), <TaskClassification?>{
        TaskClassification.regular,
      }, reason: '末端 Ctrl+Tab 不循环');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(_selectedFilter(tester), <TaskClassification?>{
        TaskClassification.elite,
      });
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(tester.takeException(), isNull);
    });
  });
}

Future<void> _pumpPicker(
  WidgetTester tester, {
  required List<Goal> goals,
  Size size = const Size(480, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        taskRepositoryProvider.overrideWithValue(_FakeTaskRepository(goals)),
        focusRepositoryProvider.overrideWithValue(
          const UnavailableFocusRepository(),
        ),
      ],
      child: MaterialApp(
        theme: pactaTheme(Brightness.light),
        home: const FocusTaskPickerPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Set<TaskClassification?> _selectedFilter(WidgetTester tester) => tester
    .widget<SegmentedButton<TaskClassification?>>(
      find.byType(SegmentedButton<TaskClassification?>),
    )
    .selected;

ListView _visibleList(WidgetTester tester) =>
    tester.widget<ListView>(find.byType(ListView));

ScrollPosition _listPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

List<String> _subtitles(WidgetTester tester) => [
  for (final tile in tester.widgetList<ListTile>(find.byType(ListTile)))
    if (tile.subtitle case final Text text) text.data ?? '',
];

String _subtitleOf(WidgetTester tester, String taskTitle) {
  final tile = tester.widget<ListTile>(
    find.ancestor(
      of: find.descendant(
        of: find.byType(ListTile),
        matching: find.text(taskTitle),
      ),
      matching: find.byType(ListTile),
    ),
  );
  return (tile.subtitle! as Text).data!;
}

List<Goal> _goals() {
  final createdAt = DateTime.utc(2026, 11, 1);
  Task task({
    required String id,
    required String title,
    required TaskClassification classification,
    required int? estimatedMinutes,
    required int focusProgressSeconds,
  }) => Task(
    id: id,
    goalId: 'goal-1',
    title: title,
    classification: classification,
    estimatedMinutes: estimatedMinutes,
    deadline: null,
    isComplete: false,
    focusProgressSeconds: focusProgressSeconds,
    createdAt: createdAt,
    updatedAt: createdAt,
  );
  return [
    Goal(
      id: 'goal-1',
      title: '每日精进',
      classification: TaskClassification.both,
      createdAt: createdAt,
      updatedAt: createdAt,
      tasks: [
        task(
          id: 'task-elite-long',
          title: '精读一章',
          classification: TaskClassification.elite,
          estimatedMinutes: 2880,
          focusProgressSeconds: 0,
        ),
        task(
          id: 'task-regular-90',
          title: '整理笔记',
          classification: TaskClassification.regular,
          estimatedMinutes: 90,
          focusProgressSeconds: 1500,
        ),
        task(
          id: 'task-elite-25',
          title: '写摘要',
          classification: TaskClassification.elite,
          estimatedMinutes: 25,
          focusProgressSeconds: 0,
        ),
        task(
          id: 'task-regular-none',
          title: '复盘',
          classification: TaskClassification.regular,
          estimatedMinutes: null,
          focusProgressSeconds: 0,
        ),
        task(
          id: 'task-regular-progress',
          title: '晨间冥想',
          classification: TaskClassification.regular,
          estimatedMinutes: null,
          focusProgressSeconds: 45,
        ),
        task(
          id: 'task-both',
          title: '双模式任务',
          classification: TaskClassification.both,
          estimatedMinutes: 60,
          focusProgressSeconds: 3600,
        ),
        // 足够多的普通任务让「全部」与「普通」两页真实可滚动。
        for (var index = 1; index <= 8; index++)
          task(
            id: 'task-extra-$index',
            title: '补充任务$index',
            classification: TaskClassification.regular,
            estimatedMinutes: 25,
            focusProgressSeconds: 0,
          ),
      ],
    ),
  ];
}

class _FakeTaskRepository extends UnavailableTaskRepository {
  _FakeTaskRepository(this.goals);

  final List<Goal> goals;

  @override
  Stream<List<Goal>> watchGoals({bool includeDeleted = false}) =>
      Stream.value(goals);
}
