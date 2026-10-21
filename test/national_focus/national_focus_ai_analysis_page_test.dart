import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/national_focus/national_focus_ai_access.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';

import '../support/fake_auth_repository.dart';

void main() {
  const mcpUrl = 'https://pacta.example/functions/v1/national-focus-mcp/mcp';
  String? copiedText;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedText = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
  });

  tearDown(() {
    copiedText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('我的中的国策 AI 入口可复制无密钥配置并撤销连接', (tester) async {
    final grants = _FakeNationalFocusAiGrantRepository();

    await tester.pumpWidget(
      PactaApp(
        authRepository: FakeAuthRepository()..signedInUser = 'user@example.com',
        nationalFocusMcpUrl: mcpUrl,
        nationalFocusAiGrantRepositoryFactory: (_) => grants,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();
    final entry = find.byKey(const ValueKey('national-focus-ai-entry'));
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();

    final page = find.byKey(const ValueKey('national-focus-ai-analysis-page'));
    expect(
      find.descendant(of: page, matching: find.text('国策 AI 分析')),
      findsOneWidget,
    );
    expect(find.textContaining('最近一次手动上传'), findsOneWidget);
    expect(find.textContaining('失败时冻结的完整树快照'), findsOneWidget);
    expect(find.textContaining('强化等级、要求版本、连续记录和内化进度'), findsOneWidget);
    expect(find.textContaining('快照版本、来源设备和上传时间'), findsOneWidget);
    expect(find.textContaining('原始原因与事后说明分开'), findsOneWidget);
    expect(find.textContaining('不是完整的逐日审计日志'), findsOneWidget);
    expect(find.textContaining('不能新增、修改或删除失败记录与说明'), findsOneWidget);
    expect(find.text('尚未授权'), findsOneWidget);

    final requestCodeField = find.byKey(
      const ValueKey('national-focus-ai-request-code'),
    );
    await _scrollUntilVisible(tester, page, requestCodeField);
    await tester.enterText(requestCodeField, 'a' * 64);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(requestCodeField).controller!.text,
      'a' * 64,
    );
    await _scrollUntilVisible(tester, page, find.text('核对授权码'));
    final inspectButton = find.ancestor(
      of: find.text('核对授权码'),
      matching: find.byType(OutlinedButton),
    );
    expect(tester.widget<OutlinedButton>(inspectButton).onPressed, isNotNull);
    await tester.ensureVisible(find.text('核对授权码'));
    await tester.tap(find.text('核对授权码'));
    await tester.pumpAndSettle();
    expect(grants.inspectedCodes, ['a' * 64]);
    expect(find.text('Codex CLI'), findsOneWidget);
    expect(find.text('https://127.0.0.1/callback'), findsOneWidget);
    expect(find.textContaining('失败历史（含冻结快照'), findsOneWidget);
    expect(find.textContaining('Codex 不能修改失败记录'), findsOneWidget);

    await _scrollUntilVisible(tester, page, find.text('授予 30 分钟只读授权'));
    await tester.tap(find.text('授予 30 分钟只读授权'));
    await tester.pumpAndSettle();
    expect(grants.approvedCodes, ['a' * 64]);
    await _scrollToTop(tester, page);
    expect(find.text('已授权'), findsOneWidget);
    expect(find.text('Codex CLI'), findsOneWidget);
    expect(find.textContaining('30 分钟'), findsOneWidget);

    await _scrollUntilVisible(tester, page, find.text('复制 Codex 配置'));
    await tester.tap(find.text('复制 Codex 配置'));
    await tester.pumpAndSettle();
    expect(copiedText, contains('codex mcp add pacta-national-focus'));
    expect(copiedText, contains(mcpUrl));
    expect(copiedText, isNot(contains('SUPABASE_PUBLISHABLE_KEY')));
    expect(copiedText, isNot(contains('Bearer ')));

    await _scrollToTop(tester, page);
    await tester.tap(find.text('撤销此连接'));
    await tester.pumpAndSettle();
    expect(find.text('撤销 Codex 连接？'), findsOneWidget);
    await tester.tap(find.text('确认撤销'));
    await tester.pumpAndSettle();

    expect(grants.revokeCalls, ['grant-1']);
    await _scrollToTop(tester, page);
    expect(find.text('已撤销'), findsOneWidget);
    expect(find.text('撤销此连接'), findsNothing);
  });

  testWidgets('国策树更多菜单进入同一个国策 AI 分析页', (tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
    final grants = _FakeNationalFocusAiGrantRepository();

    await tester.pumpWidget(
      PactaApp(
        authRepository: FakeAuthRepository()..signedInUser = 'user@example.com',
        nationalFocusMcpUrl: mcpUrl,
        nationalFocusAiGrantRepositoryFactory: (_) => grants,
        nationalFocusRepositoryFactory: (_) => _EmptyNationalFocusRepository(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('国策树').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('国策 AI 分析').last);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('national-focus-ai-analysis-page')),
      findsOneWidget,
    );
    expect(find.textContaining('最近一次手动上传'), findsOneWidget);
    expect(find.textContaining('失败时冻结的完整树快照'), findsOneWidget);
  });

  testWidgets('320 窄屏、大字号与深色主题下引导页可滚动且无溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final grants = _FakeNationalFocusAiGrantRepository();

    await tester.pumpWidget(
      PactaApp(
        authRepository: FakeAuthRepository()..signedInUser = 'user@example.com',
        nationalFocusMcpUrl: mcpUrl,
        nationalFocusAiGrantRepositoryFactory: (_) => grants,
      ),
    );
    await tester.pumpAndSettle();
    final page = await _openMyAiPage(tester);

    expect(Theme.of(tester.element(page)).brightness, Brightness.dark);
    expect(tester.takeException(), isNull);
    await _scrollUntilVisible(tester, page, find.text('复制 Codex 配置'));
    expect(tester.takeException(), isNull);
    await _scrollUntilVisible(
      tester,
      page,
      find.byKey(const ValueKey('national-focus-ai-request-code')),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Windows 宽屏通过侧边导航打开引导页且无溢出', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final grants = _FakeNationalFocusAiGrantRepository();

    await tester.pumpWidget(
      PactaApp(
        authRepository: FakeAuthRepository()..signedInUser = 'user@example.com',
        nationalFocusMcpUrl: mcpUrl,
        nationalFocusAiGrantRepositoryFactory: (_) => grants,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('我的'),
      ),
    );
    await tester.pumpAndSettle();
    final page = await _openMyAiPage(tester, selectMyTab: false);

    expect(page, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('未配置服务时说明原因并禁用授权操作', (tester) async {
    await tester.pumpWidget(
      PactaApp(
        authRepository: FakeAuthRepository()..signedInUser = 'user@example.com',
      ),
    );
    await tester.pumpAndSettle();
    final page = await _openMyAiPage(tester);

    await _scrollUntilVisible(tester, page, find.text('服务地址尚未配置，请联系应用维护者。'));
    expect(find.text('服务地址尚未配置，请联系应用维护者。'), findsOneWidget);
    await _scrollToTop(tester, page);
    expect(find.text('连接状态不可用'), findsOneWidget);
    expect(find.text('复制 Codex 配置'), findsNothing);
    await _scrollUntilVisible(
      tester,
      page,
      find.byKey(const ValueKey('national-focus-ai-request-code')),
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('national-focus-ai-request-code')),
          )
          .enabled,
      isFalse,
    );
    expect(tester.takeException(), isNull);
    expect(page, findsOneWidget);
  });

  testWidgets('授权状态加载失败可重试，恢复后显示连接状态', (tester) async {
    final grants = _FakeNationalFocusAiGrantRepository()
      ..listError = StateError('temporary outage')
      ..grants.add(
        NationalFocusAiGrant(
          id: 'grant-retry',
          clientName: 'Codex CLI',
          scope: 'national_focus:read',
          createdAt: DateTime.now().toUtc(),
          expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 30)),
        ),
      );
    await tester.pumpWidget(
      PactaApp(
        authRepository: FakeAuthRepository()..signedInUser = 'user@example.com',
        nationalFocusMcpUrl: mcpUrl,
        nationalFocusAiGrantRepositoryFactory: (_) => grants,
      ),
    );
    await tester.pumpAndSettle();
    final page = await _openMyAiPage(tester);
    await _scrollUntilVisible(tester, page, find.text('无法读取授权状态'));

    expect(find.text('无法读取授权状态'), findsOneWidget);
    grants.listError = null;
    await _scrollUntilVisible(tester, page, find.text('重试'));
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(grants.listCalls, 2);
    await _scrollUntilVisible(tester, page, find.text('已授权'));
    expect(find.text('已授权'), findsOneWidget);
    expect(find.text('撤销此连接'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeNationalFocusAiGrantRepository
    implements NationalFocusAiGrantRepository {
  _FakeNationalFocusAiGrantRepository();

  final grants = <NationalFocusAiGrant>[];
  final inspectedCodes = <String>[];
  final approvedCodes = <String>[];
  final revokeCalls = <String>[];
  Object? listError;
  int listCalls = 0;

  @override
  Future<List<NationalFocusAiGrant>> listMyGrants() async {
    listCalls++;
    final error = listError;
    if (error != null) throw error;
    return grants;
  }

  @override
  Future<NationalFocusAiAuthorizationRequest> inspectRequest(
    String requestCode,
  ) async {
    inspectedCodes.add(requestCode);
    return NationalFocusAiAuthorizationRequest(
      clientName: 'Codex CLI',
      redirectUri: 'https://127.0.0.1/callback',
      scope: 'national_focus:read',
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
    );
  }

  @override
  Future<void> approveRequest(String requestCode) async {
    approvedCodes.add(requestCode);
    grants.add(
      NationalFocusAiGrant(
        id: 'grant-1',
        clientName: 'Codex CLI',
        scope: 'national_focus:read',
        createdAt: DateTime.now().toUtc(),
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 30)),
      ),
    );
  }

  @override
  Future<void> revokeGrant(String grantId) async {
    revokeCalls.add(grantId);
    final index = grants.indexWhere((grant) => grant.id == grantId);
    if (index == -1) return;
    grants[index] = grants[index].copyWith(revokedAt: DateTime.now().toUtc());
  }
}

class _EmptyNationalFocusRepository implements NationalFocusRepository {
  @override
  Stream<List<NationalFocusCard>> watchTreeCards() => Stream.value(const []);

  @override
  Stream<NationalFocusReviewState> watchNationalFocusReviewState() =>
      Stream.value(const NationalFocusReviewState());

  @override
  Future<void> settleDueCheckpoints() async {}

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _scrollUntilVisible(
  WidgetTester tester,
  Finder page,
  Finder target,
) async {
  final listView = find.descendant(of: page, matching: find.byType(ListView));
  for (var attempt = 0; attempt < 24; attempt++) {
    if (target.evaluate().isNotEmpty) {
      final targetRect = tester.getRect(target.first);
      final listRect = tester.getRect(listView.first);
      if (targetRect.top >= listRect.top &&
          targetRect.bottom <= listRect.bottom) {
        return;
      }
      await tester.drag(
        listView.first,
        Offset(0, targetRect.bottom > listRect.bottom ? -280 : 280),
      );
    } else {
      await tester.drag(listView.first, const Offset(0, -280));
    }
    await tester.pumpAndSettle();
  }
  expect(target, findsOneWidget);
  final targetRect = tester.getRect(target.first);
  final listRect = tester.getRect(listView.first);
  expect(targetRect.top, greaterThanOrEqualTo(listRect.top));
  expect(targetRect.bottom, lessThanOrEqualTo(listRect.bottom));
}

Future<void> _scrollToTop(WidgetTester tester, Finder page) async {
  final listView = find.descendant(of: page, matching: find.byType(ListView));
  await tester.drag(listView.first, const Offset(0, 6000));
  await tester.pumpAndSettle();
}

Future<Finder> _openMyAiPage(
  WidgetTester tester, {
  bool selectMyTab = true,
}) async {
  if (selectMyTab) {
    final navigation = find.byType(NavigationBar);
    final rail = find.byType(NavigationRail);
    if (navigation.evaluate().isNotEmpty) {
      await tester.tap(
        find.descendant(of: navigation, matching: find.text('我的')),
      );
    } else if (rail.evaluate().isNotEmpty) {
      await tester.tap(find.descendant(of: rail, matching: find.text('我的')));
    }
    await tester.pumpAndSettle();
  }
  final entry = find.byKey(const ValueKey('national-focus-ai-entry'));
  await _scrollUntilVisible(tester, find.byType(MyPage), entry);
  await tester.tap(entry);
  await tester.pumpAndSettle();
  return find.byKey(const ValueKey('national-focus-ai-analysis-page'));
}
