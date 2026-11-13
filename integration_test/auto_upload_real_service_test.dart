// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:pacta/src/sync/cloud_auto_upload.dart';
import 'package:pacta/src/sync/cloud_auto_upload_preference.dart';
import 'package:pacta/src/sync/cloud_auto_upload_queue.dart';
import 'package:pacta/src/sync/cloud_snapshot_history.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// 共享的 loopback 验收控制端口：只发放临时会话，绝不编译 .env 或管理员密钥。
// 端口沿用 ISSUE90_RUNTIME_PORT（默认 30390），与历史备份真实服务用例同一启动器。
const _control = String.fromEnvironment('ISSUE71_RUNTIME_CONTROL');
const _port = String.fromEnvironment(
  'ISSUE90_RUNTIME_PORT',
  defaultValue: '30390',
);

Future<Map<String, dynamic>> _configuration(String user) async {
  final response = await http.get(
    Uri.parse('http://127.0.0.1:$_port/session?user=$user'),
    headers: {'X-Pacta-Acceptance': _control},
  );
  if (response.statusCode != 200) {
    throw StateError('Isolated acceptance session unavailable.');
  }
  return jsonDecode(response.body) as Map<String, dynamic>;
}

Future<SupabaseClient> _client(Map<String, dynamic> config) async {
  final client = SupabaseClient(
    config['url'] as String,
    config['publishableKey'] as String,
  );
  await client.auth.setSession(config['refreshToken'] as String);
  expect(client.auth.currentUser?.id, config['userId']);
  return client;
}

/// 只制造“客户端丢应答/离线”的包装；上传本身仍然到达隔离云。
class _GuardedRemote implements CloudSnapshotRemote {
  _GuardedRemote(this.inner);

  final CloudSnapshotRemote inner;

  /// 服务端完成写入后丢弃这次应答，模拟响应丢失。
  bool dropNextResponse = false;
  int uploadCalls = 0;

  @override
  Future<CloudSnapshotMetadata?> inspect({required String userId}) =>
      inner.inspect(userId: userId);

  @override
  Future<CloudSnapshotMetadata> download({required String userId}) =>
      inner.download(userId: userId);

  @override
  Future<List<CloudSnapshotHistoryEntry>> history({required String userId}) =>
      inner.history(userId: userId);

  @override
  Future<CloudSnapshotMetadata> downloadRevision({
    required String userId,
    required int revision,
  }) => inner.downloadRevision(userId: userId, revision: revision);

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
  }) async {
    uploadCalls++;
    final saved = await inner.upload(
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
    if (dropNextResponse) {
      dropNextResponse = false;
      throw StateError('模拟客户端丢失上传应答（服务端已写入）');
    }
    return saved;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real cloud automatic upload: lost response, merged intent, foreign version stop',
    (tester) async {
      expect(_control, isNotEmpty);
      await tester.runAsync(() async {
        final config = await _configuration('device');
        final client = await _client(config);
        final userId = config['userId'] as String;
        final preferences = await SharedPreferences.getInstance();
        final queueKey = 'pacta.device.cloud_auto_upload.queue.$userId';
        final enabledKey = 'pacta.device.cloud_auto_upload.enabled.$userId';
        final resultKey = 'pacta.device.cloud_sync.result.$userId';
        final previousQueue = preferences.getString(queueKey);
        final previousEnabled = preferences.getBool(enabledKey);
        final previousResult = preferences.getString(resultKey);

        final database = PactaDatabase(NativeDatabase.memory());
        final tasks = LocalTaskRepository(
          database: database,
          userId: userId,
          remote: const UnavailableTaskRemoteDataSource(),
          cloudSyncEnabled: false,
        );
        final guarded = _GuardedRemote(SupabaseCloudSnapshotRemote(client));
        final sync = CloudSnapshotRepository(
          database: database,
          remote: guarded,
          userId: userId,
          deviceId: 'issue93-${Platform.operatingSystem}',
          deviceName: Platform.isAndroid ? '验收手机（Android）' : '验收电脑（Windows）',
        );
        const queueStore = SharedPreferencesCloudAutoUploadQueueStore();
        final coordinator = CloudAutoUploadCoordinator(
          userId: userId,
          repository: sync,
          preference: const CloudAutoUploadPreference(),
          queueStore: queueStore,
          canAccess: () async => true,
          isAccessible: () async => true,
        );
        try {
          // 1) 手动上传一份有效快照，建立“已处理版本”基线。
          final initial = await sync.inspectCloud();
          final manual = await sync.uploadLocal(
            expectedRevision: initial?.revision ?? 0,
            expectedFingerprint: (await sync.captureLocalState()).fingerprint,
          );
          final baselineRevision = manual.revision;
          expect(
            (await sync.loadSyncResult())!.cloudRevision,
            baselineRevision,
          );
          print('AUTO_UPLOAD_REAL baseline upload rev=$baselineRevision PASS');

          // 2) 自动上传：服务端已写入，客户端丢应答；期间又发生一次今日确认。
          await coordinator.setEnabled(true);
          await tasks.createGoal(
            const GoalDraft(
              title: '自动上传 A',
              classification: TaskClassification.regular,
            ),
          );
          guarded.dropNextResponse = true;
          await coordinator.enqueue();
          final dropped = await sync.inspectCloud();
          expect(
            dropped!.revision,
            baselineRevision + 1,
            reason: '隔离云确实写入了这份快照',
          );
          expect(
            (await sync.loadSyncResult())!.cloudRevision,
            baselineRevision,
            reason: '丢应答不得推进本机已处理基线',
          );
          var queue = await queueStore.load(userId);
          expect(queue.request, isNotNull, reason: '原请求身份必须保留以便重试');
          final requestId = queue.request!.requestId;
          print(
            'AUTO_UPLOAD_REAL lost response keeps requestId and old baseline PASS',
          );

          // 3) 恢复后：旧 request 按台账去重（不新增版本），最新意图另生成请求。
          await tasks.createGoal(
            const GoalDraft(
              title: '自动上传 B',
              classification: TaskClassification.regular,
            ),
          );
          await coordinator.enqueue();
          final afterRecovery = await sync.inspectCloud();
          expect(
            afterRecovery!.revision,
            baselineRevision + 2,
            reason: '旧请求去重不增版本，只为最新快照写入一次',
          );
          final history = await sync.listCloudHistory();
          expect(history.first.revision, baselineRevision + 2);
          expect(history[1].revision, baselineRevision + 1);
          final snapshot = await remotePayload(client, userId);
          final goalTitles = [
            for (final row
                in (snapshot['tables'] as Map)['local_goals'] as List)
              (row as Map)['title'],
          ];
          expect(goalTitles, containsAll(['自动上传 A', '自动上传 B']));
          expect(
            (await sync.loadSyncResult())!.cloudRevision,
            baselineRevision + 2,
          );
          queue = await queueStore.load(userId);
          expect(queue.hasWork, isFalse, reason: '两轮请求都已确认');
          print(
            'AUTO_UPLOAD_REAL idempotent retry requestId=$requestId + new intent PASS',
          );

          // 4) 另一台设备推进云端版本：自动上传必须停止覆盖，等待用户处理。
          final current = (await sync.inspectCloud())!;
          final otherRemote = SupabaseCloudSnapshotRemote(client);
          final otherPayload = Map<String, dynamic>.from(
            (await otherRemote.download(userId: userId)).payload!,
          );
          final tables = Map<String, dynamic>.from(
            otherPayload['tables'] as Map,
          );
          final otherGoals = [
            for (final row in (tables['local_goals'] as List))
              Map<String, dynamic>.from(row as Map),
          ];
          otherGoals.add({
            ...otherGoals.first,
            'id': 'issue93-other-${DateTime.now().microsecondsSinceEpoch}',
            'title': '另一台设备的记录',
            'created_at': DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
            'updated_at': DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
          });
          tables['local_goals'] = otherGoals;
          otherPayload['tables'] = tables;
          final otherSaved = await otherRemote.upload(
            userId: userId,
            expectedRevision: current.revision,
            payload: otherPayload,
            deviceId: 'issue93-other',
            deviceName: '另一台设备（Windows）',
            dataUpdatedAt: DateTime.now().toUtc(),
            rowCount: current.rowCount + 1,
          );
          expect(otherSaved.revision, current.revision + 1);

          await tasks.createGoal(
            const GoalDraft(
              title: '自动上传 C',
              classification: TaskClassification.regular,
            ),
          );
          await coordinator.enqueue();
          final stopped = await sync.inspectCloud();
          expect(
            stopped!.revision,
            otherSaved.revision,
            reason: '未处理的云版本不得被自动覆盖',
          );
          expect(
            coordinator.blockedReason,
            cloudAutoUploadUnhandledCloudReason,
          );
          expect((await queueStore.load(userId)).pending, isTrue);
          expect(
            (await sync.loadSyncResult())!.cloudRevision,
            otherSaved.revision - 1,
          );
          print('AUTO_UPLOAD_REAL foreign version stops overwrite PASS');
        } finally {
          await coordinator.cancelPending();
          coordinator.dispose();
          if (previousQueue == null) {
            await preferences.remove(queueKey);
          } else {
            await preferences.setString(queueKey, previousQueue);
          }
          if (previousEnabled == null) {
            await preferences.remove(enabledKey);
          } else {
            await preferences.setBool(enabledKey, previousEnabled);
          }
          if (previousResult == null) {
            await preferences.remove(resultKey);
          } else {
            await preferences.setString(resultKey, previousResult);
          }
          await database.close();
          await client.dispose();
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

/// 读回云端当前整份载荷（用于核对内容，不依赖本机快照）。
Future<Map<String, dynamic>> remotePayload(
  SupabaseClient client,
  String userId,
) async {
  final row = await client
      .from('cloud_business_snapshots')
      .select('payload')
      .eq('user_id', userId)
      .maybeSingle();
  return Map<String, dynamic>.from(row!['payload'] as Map);
}
