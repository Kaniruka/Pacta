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

  testWidgets('创建只读与读写连接、切换多端配置格式并撤销单个与全部连接', (tester) async {
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
    expect(
      find.descendant(of: page, matching: find.text('外部工具接入')),
      findsOneWidget,
    );
    expect(find.text('尚未创建连接'), findsOneWidget);

    // 1. 创建默认 Antigravity 只读连接
    await tester.tap(find.byKey(const ValueKey('national-focus-ai-create')));
    await tester.pumpAndSettle();
    final submitButton = find.byKey(
      const ValueKey('national-focus-ai-submit-create'),
    );
    await tester.ensureVisible(submitButton);
    await tester.pumpAndSettle();
    await tester.tap(submitButton);
    await tester.pumpAndSettle();

    expect(find.text('连接已创建'), findsOneWidget);
    expect(grants.createdCalls.length, 1);
    expect(grants.createdCalls.first.scope, NationalFocusAiScope.read);

    // 切换到 Claude Code 并复制配置
    await tester.tap(find.widgetWithText(ChoiceChip, 'Claude Code').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('national-focus-ai-copy-config')),
    );
    await tester.pumpAndSettle();
    expect(
      copiedText,
      contains('claude mcp add --transport http pacta-national-focus'),
    );
    expect(copiedText, contains('$mcpUrl/readonly'));
    expect(copiedText, contains('Bearer pacta_mcp_'));

    // 复制令牌
    await tester.tap(
      find.byKey(const ValueKey('national-focus-ai-copy-token')),
    );
    await tester.pumpAndSettle();
    expect(copiedText, startsWith('pacta_mcp_'));

    final doneButton = find.byKey(
      const ValueKey('national-focus-ai-sheet-done'),
    );
    await tester.ensureVisible(doneButton);
    await tester.pumpAndSettle();
    await tester.tap(doneButton);
    await tester.pumpAndSettle();
    expect(find.text('Antigravity'), findsNWidgets(2));
    expect(find.text('只读'), findsOneWidget);
    expect(find.text('生效中'), findsOneWidget);
    expect(find.textContaining('后到期'), findsOneWidget);

    // 2. 创建第二个连接：Codex 读写 + 永不过期
    await tester.tap(find.byKey(const ValueKey('national-focus-ai-create')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Codex').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('读写'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '永不过期'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(submitButton);
    await tester.pumpAndSettle();
    await tester.tap(submitButton);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('national-focus-ai-copy-config')),
    );
    await tester.pumpAndSettle();
    expect(copiedText, contains('[mcp_servers.pacta_national_focus]'));
    expect(copiedText, contains('$mcpUrl/readwrite'));

    await tester.ensureVisible(doneButton);
    await tester.pumpAndSettle();
    await tester.tap(doneButton);
    await tester.pumpAndSettle();
    expect(find.text('永不过期'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('national-focus-ai-revoke-all')),
      findsOneWidget,
    );

    // 3. 撤销单个连接，随后可删除该条失效记录
    await tester.tap(
      find.byKey(const ValueKey('national-focus-ai-revoke-grant-1')),
    );
    await tester.pumpAndSettle();
    expect(find.text('撤销「Antigravity」？'), findsOneWidget);
    await tester.tap(find.text('确认撤销'));
    await tester.pumpAndSettle();
    expect(grants.revokeCalls, ['grant-1']);
    expect(find.text('已撤销'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('national-focus-ai-delete-grant-1')),
    );
    await tester.pumpAndSettle();
    expect(find.text('删除「Antigravity」？'), findsOneWidget);
    await tester.tap(find.text('确认删除'));
    await tester.pumpAndSettle();
    expect(grants.deleteCalls, ['grant-1']);
    expect(find.text('Antigravity'), findsNothing);

    // 4. 再创建一个带自定义有效期（12 小时）的连接并测试全部撤销
    await tester.tap(find.byKey(const ValueKey('national-focus-ai-create')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'DSH').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('national-focus-ai-ttl-custom')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('national-focus-ai-ttl-custom-value')),
      '12',
    );
    await tester.tap(find.text('小时'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(submitButton);
    await tester.pumpAndSettle();
    await tester.tap(submitButton);
    await tester.pumpAndSettle();
    expect(grants.createdCalls.last.ttl, const Duration(hours: 12));
    await tester.ensureVisible(doneButton);
    await tester.pumpAndSettle();
    await tester.tap(doneButton);
    await tester.pumpAndSettle();

    final revokeAllButton = find.byKey(
      const ValueKey('national-focus-ai-revoke-all'),
    );
    await tester.ensureVisible(revokeAllButton);
    await tester.pumpAndSettle();
    await tester.tap(revokeAllButton);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '全部撤销'));
    await tester.pumpAndSettle();
    expect(grants.revokeAllCalls, 1);
    expect(find.text('已撤销'), findsNWidgets(2));
  });

  testWidgets('展示最近调用与写入记录并支持进入手动同步', (tester) async {
    final now = DateTime.utc(2026, 11, 25, 12, 0);
    final grants = _FakeNationalFocusAiGrantRepository()
      ..auditLogs.addAll([
        NationalFocusAiAuditLog(
          id: 'log-write',
          grantId: 'grant-1',
          grantLabel: 'Codex',
          toolName: 'create_national_focus_card',
          actionKind: 'write',
          summary: '创建国策卡「先发制人」',
          snapshotRevision: 9,
          createdAt: now,
        ),
        NationalFocusAiAuditLog(
          id: 'log-read',
          grantId: 'grant-1',
          grantLabel: 'Codex',
          toolName: 'get_national_focus_tree',
          actionKind: 'read',
          summary: '读取国策树',
          snapshotRevision: 8,
          createdAt: now.subtract(const Duration(minutes: 5)),
        ),
      ]);

    await tester.pumpWidget(
      PactaApp(
        authRepository: FakeAuthRepository()..signedInUser = 'user@example.com',
        nationalFocusMcpUrl: mcpUrl,
        nationalFocusAiGrantRepositoryFactory: (_) => grants,
      ),
    );
    await tester.pumpAndSettle();
    final page = await _openMyAiPage(tester);

    await _scrollUntilVisible(tester, page, find.text('创建国策卡「先发制人」'));
    expect(find.text('写入'), findsOneWidget);
    expect(find.text('读取'), findsOneWidget);
    expect(find.text('r9'), findsOneWidget);

    await _scrollToTop(tester, page);
    await tester.tap(find.byKey(const ValueKey('national-focus-ai-open-sync')));
    await tester.pumpAndSettle();
    expect(find.text('手动同步'), findsOneWidget);
    expect(find.textContaining('仅进入本页不会上传或下载'), findsOneWidget);
  });

  testWidgets('国策树更多菜单进入同一个开放能力页', (tester) async {
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
    await tester.tap(find.text('开放能力').last);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('national-focus-ai-analysis-page')),
      findsOneWidget,
    );
  });

  testWidgets('320 窄屏、20:9 全面屏与深色主题下顶对齐且无溢出', (tester) async {
    tester.view.physicalSize = const Size(393, 873);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
    final heroRect = tester.getRect(find.text('外部工具接入'));
    expect(heroRect.top, lessThan(180));
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(320, 800);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('未配置服务时禁用创建并展示提示', (tester) async {
    await tester.pumpWidget(
      PactaApp(
        authRepository: FakeAuthRepository()..signedInUser = 'user@example.com',
      ),
    );
    await tester.pumpAndSettle();
    await _openMyAiPage(tester);
    expect(find.text('服务地址或登录会话尚未配置，请联系应用维护者。'), findsOneWidget);
    final createButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('national-focus-ai-create')),
    );
    expect(createButton.onPressed, isNull);
  });

  testWidgets('加载失败可重试，恢复后展示连接列表', (tester) async {
    final grants = _FakeNationalFocusAiGrantRepository()
      ..listError = StateError('temporary outage');
    await tester.pumpWidget(
      PactaApp(
        authRepository: FakeAuthRepository()..signedInUser = 'user@example.com',
        nationalFocusMcpUrl: mcpUrl,
        nationalFocusAiGrantRepositoryFactory: (_) => grants,
      ),
    );
    await tester.pumpAndSettle();
    await _openMyAiPage(tester);
    expect(find.text('重试'), findsOneWidget);
    grants.listError = null;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(grants.listCalls, 2);
    expect(find.text('尚未创建连接'), findsOneWidget);
  });
}

class _CreatedArgs {
  const _CreatedArgs(this.label, this.scope, this.ttl, this.agentPreset);
  final String label;
  final NationalFocusAiScope scope;
  final Duration? ttl;
  final String? agentPreset;
}

class _FakeNationalFocusAiGrantRepository
    implements NationalFocusAiGrantRepository {
  final grants = <NationalFocusAiGrant>[];
  final auditLogs = <NationalFocusAiAuditLog>[];
  final createdCalls = <_CreatedArgs>[];
  final revokeCalls = <String>[];
  final deleteCalls = <String>[];
  int revokeAllCalls = 0;
  Object? listError;
  int listCalls = 0;

  @override
  Future<List<NationalFocusAiGrant>> listMyGrants() async {
    listCalls++;
    final error = listError;
    if (error != null) throw error;
    return List.unmodifiable(grants);
  }

  @override
  Future<CreatedNationalFocusAiGrant> createGrant({
    required String label,
    required NationalFocusAiScope scope,
    Duration? ttl,
    String? agentPreset,
  }) async {
    createdCalls.add(_CreatedArgs(label, scope, ttl, agentPreset));
    final now = DateTime.now().toUtc();
    final id = 'grant-${grants.length + 1}';
    final token = 'pacta_mcp_${id.padRight(64, 'a').substring(0, 64)}';
    final grant = NationalFocusAiGrant(
      id: id,
      label: label,
      agentPreset: agentPreset,
      scope: scope,
      tokenPrefix: '${token.substring(0, 14)}...',
      createdAt: now,
      expiresAt: ttl == null ? null : now.add(ttl),
    );
    grants.insert(0, grant);
    return CreatedNationalFocusAiGrant(grant: grant, token: token);
  }

  @override
  Future<void> revokeGrant(String grantId) async {
    revokeCalls.add(grantId);
    final index = grants.indexWhere((g) => g.id == grantId);
    if (index != -1) {
      grants[index] = grants[index].copyWith(revokedAt: DateTime.now().toUtc());
    }
  }

  @override
  Future<void> deleteGrant(String grantId) async {
    deleteCalls.add(grantId);
    grants.removeWhere((g) => g.id == grantId);
  }

  @override
  Future<int> revokeAllGrants() async {
    revokeAllCalls++;
    var count = 0;
    final now = DateTime.now().toUtc();
    for (var i = 0; i < grants.length; i++) {
      if (grants[i].revokedAt == null) {
        grants[i] = grants[i].copyWith(revokedAt: now);
        count++;
      }
    }
    return count;
  }

  @override
  Future<List<NationalFocusAiAuditLog>> listRecentAuditLogs({
    int limit = 20,
  }) async => List.unmodifiable(auditLogs.take(limit));
}

class _EmptyNationalFocusRepository implements NationalFocusRepository {
  @override
  Stream<List<NationalFocusCard>> watchTreeCards() => Stream.value(const []);

  @override
  Stream<List<NationalFocusCard>> watchLibraryCards() => Stream.value(const []);

  @override
  Stream<List<NationalFocusFailure>> watchFailures() => Stream.value(const []);

  @override
  Future<void> settleDueCheckpoints() async {}

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Finder _scrollableFor(Finder container) {
  if (container.evaluate().any((e) => e.widget is ListView)) {
    return container;
  }
  return find.descendant(of: container, matching: find.byType(ListView));
}

Future<void> _scrollUntilVisible(
  WidgetTester tester,
  Finder page,
  Finder target,
) async {
  final listView = _scrollableFor(page);
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
}

Future<void> _scrollToTop(WidgetTester tester, Finder page) async {
  final listView = _scrollableFor(page);
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
