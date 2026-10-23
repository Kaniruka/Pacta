import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/national_focus/national_focus_ai_access.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

import '../test/support/fake_auth_repository.dart';

const _userId = 'ticket-60-device-user';
const _mcpUrl = 'https://pacta.example/functions/v1/national-focus-mcp/mcp';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('国策 AI 引导授权撤销不隐式同步，手动上传必须确认覆盖', (tester) async {
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
      expect(find.textContaining('失败时冻结的完整树快照'), findsOneWidget);
      expect(find.textContaining('强化等级、要求版本、连续记录和内化进度'), findsOneWidget);
      expect(find.textContaining('快照版本、来源设备和上传时间'), findsOneWidget);
      expect(find.textContaining('不是完整的逐日审计日志'), findsOneWidget);
      expect(find.textContaining('不能新增、修改或删除失败记录与说明'), findsOneWidget);

      if (const bool.fromEnvironment('PACTA_CAPTURE_GUIDE')) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 20)),
        );
      }
      for (final label in ['复制 skill 安装说明', '复制首次问题', '复制失败复盘示例']) {
        await _scrollUntilVisible(tester, page, find.text(label));
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        if (label == '复制失败复盘示例') {
          final copied = await Clipboard.getData(Clipboard.kTextPlain);
          expect(copied?.text, contains(r'$pacta-national-focus-analysis'));
          expect(copied?.text, contains('近 30 个国策日'));
          expect(copied?.text, contains('按工具游标读完分页'));
          expect(copied?.text, contains('失败事件 ID 和历史要求版本 ID'));
        }
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      }
      // Let copy feedback dismiss before testing controls at the desktop edge.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await _scrollToTop(tester, page);

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
      expect(find.textContaining('失败历史（含冻结快照'), findsOneWidget);
      expect(find.textContaining('Codex 不能修改失败记录'), findsOneWidget);
      await _scrollUntilVisible(tester, page, find.text('授予 30 分钟只读授权'));
      await tester.tap(find.text('授予 30 分钟只读授权'));
      await tester.pumpAndSettle();
      await _scrollToTop(tester, page);
      expect(find.text('已授权'), findsOneWidget);

      await _scrollUntilVisible(tester, page, find.text('复制 Codex 配置'));
      await tester.tap(find.text('复制 Codex 配置'));
      await tester.pumpAndSettle();
      await _scrollToTop(tester, page);
      await _scrollUntilVisible(tester, page, find.text('撤销此连接'));
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

      // Follow the guide into the existing whole-snapshot preview/confirmation.
      await _scrollUntilVisible(
        tester,
        page,
        find.byKey(const ValueKey('national-focus-ai-open-sync')),
      );
      await tester.tap(
        find.byKey(const ValueKey('national-focus-ai-open-sync')),
      );
      await tester.pumpAndSettle();
      expect(find.text('手动同步'), findsOneWidget);
      expect(cloudRemote.inspectCalls, 0);
      expect(cloudRemote.uploadCalls, 0);
      expect(cloudRemote.downloadCalls, 0);
      final uploadEntry = find.text('查看云端并选择方向');
      await tester.tap(uploadEntry);
      await tester.pumpAndSettle();
      expect(find.text('云端暂无数据，可首次上传。'), findsOneWidget);
      await tester.tap(find.text('上传'));
      await tester.pumpAndSettle();
      expect(find.text('上传并覆盖云端？'), findsOneWidget);
      expect(cloudRemote.uploadCalls, 0);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(cloudRemote.uploadCalls, 0);
      await tester.tap(uploadEntry);
      await tester.pumpAndSettle();
      await tester.tap(find.text('上传'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认上传'));
      await tester.pumpAndSettle();
      expect(cloudRemote.uploadCalls, 1);
      expect(cloudRemote.downloadCalls, 0);
      expect(find.text('上传完成，已覆盖云端数据。'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('国策树').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('国策 AI 分析').last);
      await tester.pumpAndSettle();
      expect(page, findsOneWidget);
      expect(cloudRemote.uploadCalls, 1);
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
        await Scrollable.ensureVisible(
          tester.element(target.first),
          alignment: 0.5,
        );
        await tester.pumpAndSettle();
        if (target.hitTestable().evaluate().isNotEmpty) return;
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
  expect(target.hitTestable(), findsOneWidget);
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
    String? deviceManufacturer,
    String? deviceModel,
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
