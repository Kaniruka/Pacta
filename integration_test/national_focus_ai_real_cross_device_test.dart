// Real-service acceptance companion for scripts/issue62_cross_device_demo.py.
// Supabase sessions/keys arrive through a loopback bridge at runtime. Dart
// defines contain only its short-lived local test capability and port.
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/auth/supabase_auth_repository.dart';
import 'package:pacta/src/auth/user_lifecycle.dart';
import 'package:pacta/src/calendar/calendar_provider.dart';
import 'package:pacta/src/calendar/calendar_repository.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_ai_access.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _control = String.fromEnvironment('PACTA_DEMO_CONTROL');
const _port = String.fromEnvironment('PACTA_DEMO_PORT', defaultValue: '30348');
const _networkTest = bool.fromEnvironment('PACTA_DEMO_ANDROID_NETWORK_TEST');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real native upload, desktop Codex, App consent and revocation', (
    tester,
  ) async {
    Future<Map<String, dynamic>> bridge(String stage) async {
      final result = await tester.runAsync(() async {
        final response = await http
            .get(
              Uri.parse('http://127.0.0.1:$_port/$stage'),
              headers: {'X-Pacta-Acceptance': _control},
            )
            .timeout(const Duration(minutes: 8));
        if (response.statusCode != 200) {
          throw StateError('Demo bridge: $stage');
        }
        return jsonDecode(response.body) as Map<String, dynamic>;
      });
      return result!;
    }

    final config = await bridge('session');
    final client = SupabaseClient(
      config['url'] as String,
      config['publishableKey'] as String,
    );
    await tester.runAsync(
      () => client.auth.setSession(config['refreshToken'] as String),
    );
    final userId = client.auth.currentUser!.id;
    final directory = await Directory.systemTemp.createTemp('pacta-ai-demo-');
    final database = PactaDatabase(
      NativeDatabase(File('${directory.path}/db')),
    );
    var clock = DateTime.now().toUtc().subtract(const Duration(days: 1));
    final national = LocalNationalFocusRepository(
      now: () => clock,
      database: database,
      userId: userId,
      cloudSyncEnabled: false,
    );
    final sync = CloudSnapshotRepository(
      database: database,
      remote: SupabaseCloudSnapshotRemote(client),
      userId: userId,
      deviceId: 'issue62-${Platform.operatingSystem}',
      deviceName: Platform.isAndroid
          ? 'Issue62 Android real-service demo'
          : 'Issue62 Windows real-service demo',
    );
    try {
      // Use production local behavior on Android, including a frozen failure.
      final card = await national.createCard(
        const NationalFocusCardDraft(
          name: 'Issue62 bedtime reading',
          triggerCondition: 'Before bed',
          action: 'Read 5 pages',
        ),
      );
      await national.placeCard(cardId: card.id, parentId: null);
      await national.lightCard(card.id);
      await national.extinguishCard(
        cardId: card.id,
        failureReason: 'Demo: the book was left in another room',
      );
      clock = DateTime.now().toUtc();
      await national.settleDueCheckpoints();
      expect(
        await database.select(database.localNationalFocusFailures).get(),
        hasLength(1),
      );
      await tester.pumpWidget(
        PactaApp(
          authRepository: SupabaseAuthRepository(client),
          nationalFocusMcpUrl:
              '${config['url']}/functions/v1/national-focus-mcp/mcp',
          nationalFocusAiGrantRepositoryFactory: (_) =>
              SupabaseNationalFocusAiGrantRepository(
                client: client,
                userId: userId,
              ),
          nationalFocusRepositoryFactory: (_) => national,
          taskRepositoryFactory: (_) => LocalTaskRepository(
            remote: const UnavailableTaskRemoteDataSource(),
            database: database,
            userId: userId,
            cloudSyncEnabled: false,
          ),
          focusRepositoryFactory: (_) => LocalFocusRepository(
            remote: const UnavailableFocusRemoteDataSource(),
            database: database,
            userId: userId,
            cloudSyncEnabled: false,
          ),
          calendarRepositoryFactory: (_) => LocalCalendarRepository(
            remote: const UnavailableCalendarRemoteDataSource(),
            database: database,
            userId: userId,
            provider: const UnsupportedCalendarProvider(),
            cloudSyncEnabled: false,
          ),
          userLifecycleRepositoryFactory: (_) => UserLifecycleRepository(
            authRepository: SupabaseAuthRepository(client),
            localAccess: LocalUserLifecycleAccess(
              database: database,
              userId: userId,
            ),
          ),
          cloudSnapshotRepositoryFactory: (_) => sync,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('我的').last);
      await tester.pumpAndSettle();
      await _upload(tester);
      final authorization = await bridge('uploaded');
      final entry = find.byKey(const ValueKey('national-focus-ai-entry'));
      await _myControl(tester, entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      final request = find.byKey(
        const ValueKey('national-focus-ai-request-code'),
      );
      await _visible(tester, request);
      await tester.enterText(request, authorization['requestCode'] as String);
      await _visible(tester, find.text('核对授权码'));
      await tester.tap(find.text('核对授权码'));
      await _wait(tester, 'Issue62 desktop Codex');
      await _visible(tester, find.text('授予 30 分钟只读授权'));
      await tester.tap(find.text('授予 30 分钟只读授权'));
      await _top(tester);
      await _wait(tester, '已授权');
      await bridge('approved');
      await national.updateCard(
        cardId: card.id,
        draft: const NationalFocusCardDraft(
          name: 'Issue62 local-only revised reading',
          triggerCondition: 'Before bed',
          action: 'Read 2 pages',
        ),
      );
      await bridge('local-edit');
      if (Platform.isAndroid && _networkTest) {
        await bridge('offline');
        await _top(tester);
        await tester.tap(find.byTooltip('刷新授权状态'));
        await _wait(tester, '无法读取授权状态');
        await bridge('online');
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 5)),
        );
        await tester.tap(find.byTooltip('刷新授权状态'));
        await _wait(tester, '已授权');
        await bridge('recovered');
      }
      await tester.pageBack();
      await tester.pumpAndSettle();
      await _upload(tester);
      await bridge('reuploaded');
      await _myControl(tester, entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      await _visible(tester, find.text('撤销此连接'));
      await tester.tap(find.text('撤销此连接'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认撤销'));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 2)),
      );
      await tester.pumpAndSettle();
      await _top(tester);
      await _wait(tester, '已撤销');
      await bridge('revoked');
      expect(tester.takeException(), isNull);
      debugPrint('ISSUE62_REAL_CROSS_DEVICE_PASSED');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await national.dispose();
      await database.close();
      await client.dispose();
      await directory.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}

Future<void> _upload(WidgetTester tester) async {
  final entry = find.text('查看云端并选择方向');
  await _myControl(tester, entry);
  await tester.tap(entry);
  await _wait(tester, '选择同步方式');
  await tester.tap(find.text('上传'));
  await tester.pumpAndSettle();
  expect(find.text('上传并覆盖云端？'), findsOneWidget);
  await tester.tap(find.text('确认上传'));
  await _wait(tester, '上传完成，已覆盖云端数据。');
}

Future<void> _myControl(WidgetTester tester, Finder target) async {
  final list = find.descendant(
    of: find.byType(MyPage),
    matching: find.byType(ListView),
  );
  await tester.drag(list.first, const Offset(0, 6000));
  await tester.pumpAndSettle();
  for (var i = 0; i < 30; i++) {
    if (target.evaluate().isNotEmpty) {
      await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
      await tester.pumpAndSettle();
      if (target.hitTestable().evaluate().isNotEmpty) return;
    }
    await tester.drag(list.first, const Offset(0, -250));
    await tester.pumpAndSettle();
  }
  expect(target.hitTestable(), findsOneWidget);
}

Future<void> _wait(WidgetTester tester, String text) async {
  for (var i = 0; i < 100; i++) {
    await tester.pump();
    if (find.text(text).evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
  }
  expect(find.text(text), findsOneWidget);
}

Future<void> _visible(WidgetTester tester, Finder target) async {
  final list = find.descendant(
    of: find.byKey(const ValueKey('national-focus-ai-analysis-page')),
    matching: find.byType(ListView),
  );
  for (var i = 0; i < 30; i++) {
    if (target.evaluate().isNotEmpty) {
      await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
      await tester.pumpAndSettle();
      if (target.hitTestable().evaluate().isNotEmpty) return;
    }
    await tester.drag(list.first, const Offset(0, -250));
    await tester.pumpAndSettle();
  }
  expect(target.hitTestable(), findsOneWidget);
}

Future<void> _top(WidgetTester tester) async {
  final list = find.descendant(
    of: find.byKey(const ValueKey('national-focus-ai-analysis-page')),
    matching: find.byType(ListView),
  );
  await tester.drag(list.first, const Offset(0, 6000));
  await tester.pumpAndSettle();
}
