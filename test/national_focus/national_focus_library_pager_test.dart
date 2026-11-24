import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/national_focus/national_focus_library_page.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/theme/pacta_theme.dart';

/// 国策卡片库的分页交互：页签、横拖、触控板、Shift+滚轮与快捷键共用一套页序。
///
/// 仓储用内存 Fake（不触网）：只提供卡片库/已删除两条流，页面其余动作不参与。

const _pagerKey = ValueKey('national-focus-library-pager');
const _shiftWheelDelta = Offset(0, 100);
const _horizontalWheelDelta = Offset(100, 0);
const _shiftWheelUpDelta = Offset(0, -100);

class _FakeNationalFocusRepository extends UnavailableNationalFocusRepository {
  _FakeNationalFocusRepository({
    this.libraryCards = const [],
    this.deletedCards = const [],
  });

  final List<NationalFocusCard> libraryCards;
  final List<NationalFocusCard> deletedCards;

  @override
  Stream<List<NationalFocusCard>> watchLibraryCards() =>
      Stream.value(libraryCards);

  @override
  Stream<List<NationalFocusCard>> watchDeletedCards() =>
      Stream.value(deletedCards);
}

NationalFocusCard _card(String id, String name) => NationalFocusCard(
  id: id,
  name: name,
  triggerCondition: '开始前',
  action: '写下今天的第一步',
  isInTree: false,
  state: NationalFocusCardState.extinguished,
  createdAt: DateTime.utc(2026, 11, 1),
  updatedAt: DateTime.utc(2026, 11, 1),
);

Future<void> _pumpLibrary(
  WidgetTester tester, {
  Size size = const Size(1280, 800),
  List<NationalFocusCard> libraryCards = const [],
  List<NationalFocusCard> deletedCards = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: pactaTheme(Brightness.light),
      home: NationalFocusCardLibraryPage(
        repository: _FakeNationalFocusRepository(
          libraryCards: libraryCards,
          deletedCards: deletedCards,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

PageController _pageController(WidgetTester tester) =>
    tester.widget<PageView>(find.byKey(_pagerKey)).controller!;

TabController _tabController(WidgetTester tester) =>
    tester.widget<TabBar>(find.byType(TabBar)).controller!;

Future<void> _scroll(
  WidgetTester tester,
  Offset delta, {
  Offset? position,
}) async {
  await tester.sendEventToBinding(
    PointerScrollEvent(
      position: position ?? tester.getCenter(find.byKey(_pagerKey)),
      scrollDelta: delta,
      kind: PointerDeviceKind.mouse,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('点按页签双向联动，指示条与页码始终同一页', (tester) async {
    await _pumpLibrary(tester, libraryCards: [_card('a', '库卡')]);
    expect(_pageController(tester).page, 0.0);

    await tester.tap(find.text('已删除'));
    await tester.pumpAndSettle();
    expect(_pageController(tester).page, 1.0);
    expect(_tabController(tester).index, 1);
    expect(find.text('没有可恢复的卡片'), findsOneWidget);

    await tester.tap(find.text('卡片库'));
    await tester.pumpAndSettle();
    expect(_pageController(tester).page, 0.0);
    expect(_tabController(tester).index, 0);
    expect(find.text('库卡'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('1280x800 鼠标横拖切页，拖动中指示条跟手', (tester) async {
    await _pumpLibrary(
      tester,
      libraryCards: [_card('a', '库卡')],
      deletedCards: [_card('b', '旧卡')],
    );
    final pagerRect = tester.getRect(find.byKey(_pagerKey));
    final blankPoint = Offset(pagerRect.left + 4, pagerRect.center.dy);

    final gesture = await tester.startGesture(
      blankPoint,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 16));
    for (var step = 0; step < 6; step++) {
      await gesture.moveBy(const Offset(-40, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      _tabController(tester).offset,
      greaterThan(0.05),
      reason: '拖动中 Tab 指示条 1:1 跟手',
    );
    expect(_pageController(tester).page, lessThan(1.0));

    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_pageController(tester).page, 1.0);
    expect(_tabController(tester).index, 1);
    expect(find.text('旧卡'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('精确触控板双指横滑切页，反向滑回卡片库', (tester) async {
    await _pumpLibrary(
      tester,
      libraryCards: [_card('a', '库卡')],
      deletedCards: [_card('b', '旧卡')],
    );
    final center = tester.getCenter(find.byKey(_pagerKey));

    var gesture = await tester.createGesture(kind: PointerDeviceKind.trackpad);
    await gesture.panZoomStart(center);
    for (var step = 1; step <= 4; step++) {
      await gesture.panZoomUpdate(center, pan: Offset(-60.0 * step, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.panZoomEnd();
    await tester.pumpAndSettle();
    expect(_tabController(tester).index, 1);
    expect(find.text('旧卡'), findsOneWidget);

    gesture = await tester.createGesture(kind: PointerDeviceKind.trackpad);
    await gesture.panZoomStart(center);
    for (var step = 1; step <= 4; step++) {
      await gesture.panZoomUpdate(center, pan: Offset(60.0 * step, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.panZoomEnd();
    await tester.pumpAndSettle();
    expect(_tabController(tester).index, 0);
    expect(find.text('库卡'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Shift+滚轮与横向滚轮切换页签，两端不循环', (tester) async {
    await _pumpLibrary(
      tester,
      libraryCards: [_card('a', '库卡')],
      deletedCards: [_card('b', '旧卡')],
    );

    // 首端向上滚不越界。
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await _scroll(tester, _shiftWheelUpDelta);
    expect(_tabController(tester).index, 0);

    await tester.pump(const Duration(milliseconds: 400));
    await _scroll(tester, _shiftWheelDelta);
    expect(_tabController(tester).index, 1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    await tester.pump(const Duration(milliseconds: 400));
    await _scroll(tester, -_horizontalWheelDelta);
    expect(_tabController(tester).index, 0);

    await tester.pump(const Duration(milliseconds: 400));
    await _scroll(tester, -_horizontalWheelDelta);
    expect(_tabController(tester).index, 0, reason: '首端不回绕');
    expect(tester.takeException(), isNull);
  });

  testWidgets('方向键与 Ctrl+Tab 切换页签，两端钳位', (tester) async {
    await _pumpLibrary(
      tester,
      libraryCards: [_card('a', '库卡')],
      deletedCards: [_card('b', '旧卡')],
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_tabController(tester).index, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(_tabController(tester).index, 0);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(_tabController(tester).index, 1);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(_tabController(tester).index, 0);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(tester.takeException(), isNull);
  });

  testWidgets('上方弹窗盖住卡片库时不切页', (tester) async {
    await _pumpLibrary(
      tester,
      libraryCards: [_card('a', '库卡')],
      deletedCards: [_card('b', '旧卡')],
    );
    await tester.tap(find.byTooltip('卡片操作'));
    await tester.pumpAndSettle();
    expect(find.text('查看详情'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_tabController(tester).index, 0, reason: '菜单覆盖时不切页');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('查看详情'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_tabController(tester).index, 1);
    expect(tester.takeException(), isNull);
  });
}
