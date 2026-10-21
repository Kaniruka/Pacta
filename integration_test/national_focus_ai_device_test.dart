import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/national_focus/national_focus_ai_access.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

import '../test/support/fake_auth_repository.dart';

const _userId = 'ticket-57-device-user';
const _mcpUrl = 'https://pacta.example/functions/v1/national-focus-mcp/mcp';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('国策 AI 引导可完成授权与撤销，且不触发业务快照同步', (tester) async {
    final database = PactaDatabase(NativeDatabase.memory());
    final cloudRemote = _TrackingCloudSnapshotRemote();
    final cloudRepository = CloudSnapshotRepository(
      database: database,
      remote: cloudRemote,
      userId: _userId,
      deviceId: 'android-emulator-device',
      deviceName: 'Android emulator test device',
    );
    final grantRepository = _DeviceNationalFocusAiGrantRepository();

    Future<void> closeApp() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await database.close();
    }

    try {
      await tester.pumpWidget(
        PactaApp(
          authRepository: FakeAuthRepository()..signedInUser = _userId,
          nationalFocusMcpUrl: _mcpUrl,
          nationalFocusAiGrantRepositoryFactory: (_) => grantRepository,
          cloudSnapshotRepositoryFactory: (_) => cloudRepository,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppShell), findsOneWidget);
      expect(cloudRemote.inspectCalls, 0);
      expect(cloudRemote.uploadCalls, 0);
      expect(cloudRemote.downloadCalls, 0);

      await tester.tap(find.text('我的').last);
      await tester.pumpAndSettle();
      final entry = find.byKey(const ValueKey('national-focus-ai-entry'));
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      final page = find.byKey(
        const ValueKey('national-focus-ai-analysis-page'),
      );
      expect(find.textContaining('云快照元数据'), findsOneWidget);

      final requestCodeField = find.byKey(
        const ValueKey('national-focus-ai-request-code'),
      );
      await _scrollUntilVisible(tester, page, requestCodeField);
      await tester.enterText(requestCodeField, 'b' * 64);
      await tester.pumpAndSettle();
      await _scrollUntilVisible(tester, page, find.text('核对授权码'));
      await tester.tap(find.text('核对授权码'));
      await tester.pumpAndSettle();
      expect(find.text('Codex CLI'), findsOneWidget);
      await _scrollUntilVisible(tester, page, find.text('授予 30 分钟只读授权'));
      await tester.tap(find.text('授予 30 分钟只读授权'));
      await tester.pumpAndSettle();
      await _scrollToTop(tester, page);
      expect(find.text('已授权'), findsOneWidget);

      await _scrollUntilVisible(tester, page, find.text('复制 Codex 配置'));
      await tester.tap(find.text('复制 Codex 配置'));
      await tester.pumpAndSettle();
      await _scrollToTop(tester, page);
      await tester.tap(find.text('撤销此连接'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认撤销'));
      await tester.pumpAndSettle();

      expect(grantRepository.approvedCodes, ['b' * 64]);
      expect(grantRepository.revokedIds, ['device-grant']);
      await _scrollToTop(tester, page);
      expect(find.text('已撤销'), findsOneWidget);
      expect(cloudRemote.inspectCalls, 0);
      expect(cloudRemote.uploadCalls, 0);
      expect(cloudRemote.downloadCalls, 0);
    } finally {
      await closeApp();
    }
  });
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

class _TrackingCloudSnapshotRemote extends InMemoryCloudSnapshotRemote {
  int inspectCalls = 0;
  int uploadCalls = 0;
  int downloadCalls = 0;

  @override
  Future<CloudSnapshotMetadata?> inspect({required String userId}) {
    inspectCalls++;
    return super.inspect(userId: userId);
  }

  @override
  Future<CloudSnapshotMetadata> upload({
    required String userId,
    required int expectedRevision,
    required Map<String, dynamic> payload,
    required String deviceId,
    required String deviceName,
    required DateTime dataUpdatedAt,
    required int rowCount,
  }) {
    uploadCalls++;
    return super.upload(
      userId: userId,
      expectedRevision: expectedRevision,
      payload: payload,
      deviceId: deviceId,
      deviceName: deviceName,
      dataUpdatedAt: dataUpdatedAt,
      rowCount: rowCount,
    );
  }

  @override
  Future<CloudSnapshotMetadata> download({required String userId}) {
    downloadCalls++;
    return super.download(userId: userId);
  }
}

class _DeviceNationalFocusAiGrantRepository
    implements NationalFocusAiGrantRepository {
  final approvedCodes = <String>[];
  final revokedIds = <String>[];
  final _grants = <NationalFocusAiGrant>[];

  @override
  Future<List<NationalFocusAiGrant>> listMyGrants() async => _grants;

  @override
  Future<NationalFocusAiAuthorizationRequest> inspectRequest(
    String requestCode,
  ) async => NationalFocusAiAuthorizationRequest(
    clientName: 'Codex CLI',
    redirectUri: 'https://127.0.0.1/callback',
    scope: 'national_focus:read',
    expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
  );

  @override
  Future<void> approveRequest(String requestCode) async {
    approvedCodes.add(requestCode);
    _grants.add(
      NationalFocusAiGrant(
        id: 'device-grant',
        clientName: 'Codex CLI',
        scope: 'national_focus:read',
        createdAt: DateTime.now().toUtc(),
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 30)),
      ),
    );
  }

  @override
  Future<void> revokeGrant(String grantId) async {
    revokedIds.add(grantId);
    final index = _grants.indexWhere((grant) => grant.id == grantId);
    if (index == -1) return;
    _grants[index] = _grants[index].copyWith(revokedAt: DateTime.now().toUtc());
  }
}
