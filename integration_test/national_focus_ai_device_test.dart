import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/auth/user_lifecycle.dart';
import 'package:pacta/src/national_focus/national_focus_ai_access.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

import '../test/support/fake_auth_repository.dart';

const _userId = 'ticket-60-device-user';
const _mcpUrl = 'https://pacta.example/functions/v1/national-focus-mcp/mcp';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('国策 AI 连接创建与撤销不隐式同步，手动上传必须确认覆盖', (tester) async {
    final database = PactaDatabase(NativeDatabase.memory());
    final auth = FakeAuthRepository()..signedInUser = _userId;
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
          authRepository: auth,
          userLifecycleRepositoryFactory: (userId) => UserLifecycleRepository(
            authRepository: auth,
            localAccess: LocalUserLifecycleAccess(
              database: database,
              userId: userId,
            ),
          ),
          nationalFocusMcpUrl: _mcpUrl,
          nationalFocusAiGrantRepositoryFactory: (_) => grantRepository,
          cloudSnapshotRepositoryFactory: (_) => cloudRepository,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppShell), findsOneWidget);
      final initialChecks = cloudRemote.inspectCalls;
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
      expect(page, findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('national-focus-ai-create')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('national-focus-ai-submit-create')),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('national-focus-ai-copy-config')),
      );
      await tester.pumpAndSettle();
      final copied = await Clipboard.getData(Clipboard.kTextPlain);
      expect(copied?.text, contains('$_mcpUrl/readonly'));
      expect(copied?.text, contains('Bearer pacta_mcp_'));

      await tester.tap(
        find.byKey(const ValueKey('national-focus-ai-sheet-done')),
      );
      await tester.pumpAndSettle();

      final revokeBtn = find.byKey(
        const ValueKey('national-focus-ai-revoke-device-grant'),
      );
      await tester.ensureVisible(revokeBtn);
      await tester.tap(revokeBtn);
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认撤销'));
      await tester.pumpAndSettle();

      expect(grantRepository.revokedIds, ['device-grant']);
      expect(cloudRemote.inspectCalls, initialChecks);
      expect(cloudRemote.uploadCalls, 0);
      expect(cloudRemote.downloadCalls, 0);

      final openSyncBtn = find.byKey(
        const ValueKey('national-focus-ai-open-sync'),
      );
      await tester.ensureVisible(openSyncBtn);
      await tester.tap(openSyncBtn);
      await tester.pumpAndSettle();
      expect(find.text('手动同步'), findsOneWidget);
      final uploadEntry = find.byTooltip('查看云同步');
      await tester.ensureVisible(uploadEntry);
      await tester.tap(uploadEntry);
      await tester.pumpAndSettle();
      await tester.tap(find.text('上传'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认上传'));
      await tester.pumpAndSettle();
      expect(cloudRemote.uploadCalls, 1);
      expect(cloudRemote.downloadCalls, 0);
    } finally {
      await closeApp();
    }
  });
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
    String? deviceManufacturer,
    String? deviceModel,
    String? requestId,
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
      deviceManufacturer: deviceManufacturer,
      deviceModel: deviceModel,
      requestId: requestId,
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
  final revokedIds = <String>[];
  final _grants = <NationalFocusAiGrant>[];

  @override
  Future<List<NationalFocusAiGrant>> listMyGrants() async => _grants;

  @override
  Future<CreatedNationalFocusAiGrant> createGrant({
    required String label,
    required NationalFocusAiScope scope,
    Duration? ttl,
    String? agentPreset,
  }) async {
    final now = DateTime.now().toUtc();
    final token = 'pacta_mcp_${'d'.padRight(64, 'd')}';
    final grant = NationalFocusAiGrant(
      id: 'device-grant',
      label: label,
      agentPreset: agentPreset,
      scope: scope,
      tokenPrefix: '${token.substring(0, 14)}...',
      createdAt: now,
      expiresAt: ttl == null ? null : now.add(ttl),
    );
    _grants.add(grant);
    return CreatedNationalFocusAiGrant(grant: grant, token: token);
  }

  @override
  Future<void> revokeGrant(String grantId) async {
    revokedIds.add(grantId);
    _grants.removeWhere((grant) => grant.id == grantId);
  }

  @override
  Future<void> deleteGrant(String grantId) async {
    _grants.removeWhere((grant) => grant.id == grantId);
  }

  @override
  Future<int> revokeAllGrants() async {
    final now = DateTime.now().toUtc();
    final activeIds = _grants
        .where((grant) => grant.isActiveAt(now))
        .map((grant) => grant.id)
        .toSet();
    _grants.removeWhere((grant) => activeIds.contains(grant.id));
    return activeIds.length;
  }

  @override
  Future<int> clearExpiredGrants() async {
    final now = DateTime.now().toUtc();
    final before = _grants.length;
    _grants.removeWhere((grant) => !grant.isActiveAt(now));
    return before - _grants.length;
  }

  @override
  Future<List<NationalFocusAiAuditLog>> listRecentAuditLogs({
    int limit = 20,
  }) async => const [];
}
