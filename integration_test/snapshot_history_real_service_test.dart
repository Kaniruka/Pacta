// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

// The existing loopback fixture exposes only temporary acceptance sessions.
// Never compile the protected .env or an administrator key into this test app.
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real cloud backup retention, restore and cross-device transfer',
    (tester) async {
      expect(_control, isNotEmpty);
      await tester.runAsync(() async {
        final config = await _configuration('device');
        final otherConfig = await _configuration('other');
        final client = await _client(config);
        final other = await _client(otherConfig);
        final userId = config['userId'] as String;
        final preferences = await SharedPreferences.getInstance();
        final resultKey = 'pacta.device.cloud_sync.result.$userId';
        final previousResult = preferences.getString(resultKey);
        final database = PactaDatabase(NativeDatabase.memory());
        final tasks = LocalTaskRepository(
          database: database,
          userId: userId,
          remote: const UnavailableTaskRemoteDataSource(),
          cloudSyncEnabled: false,
        );
        final sync = CloudSnapshotRepository(
          database: database,
          remote: SupabaseCloudSnapshotRemote(client),
          userId: userId,
          deviceId: 'issue90-${Platform.operatingSystem}',
          deviceName: Platform.isAndroid ? '验收手机（Android）' : '验收电脑（Windows）',
        );
        try {
          final initial = (await sync.inspectCloud())!;
          if (Platform.isWindows) {
            expect(initial.deviceName, '验收手机（Android）');
            await sync.downloadCloud(
              expectedRevision: initial.revision,
              expectedFingerprint: (await sync.captureLocalState()).fingerprint,
            );
            expect((await tasks.getGoals()).length, 17);
            print('HISTORY_REAL cross-device Android-to-Windows download PASS');
          }
          final startingGoals = (await tasks.getGoals()).length;
          var revision = initial.revision;
          String? lastRequestId;
          for (var index = 0; index < 17; index++) {
            await tasks.createGoal(
              GoalDraft(
                title: '隔离验收 ${Platform.operatingSystem} ${index + 1}',
                classification: TaskClassification.both,
              ),
            );
            final requestId = const Uuid().v4();
            final uploaded = await sync.uploadLocal(
              expectedRevision: revision,
              expectedFingerprint: (await sync.captureLocalState()).fingerprint,
              requestId: requestId,
            );
            expect(uploaded.revision, revision + 1);
            revision = uploaded.revision;
            lastRequestId = requestId;
          }
          var history = await sync.listCloudHistory();
          expect(history.length, 15);
          expect(history.first.revision, revision);
          expect(history.last.revision, revision - 14);
          final retried = await sync.uploadLocal(
            expectedRevision: revision - 1,
            expectedFingerprint: (await sync.captureLocalState()).fingerprint,
            requestId: lastRequestId,
          );
          expect(retried.revision, revision);
          expect((await sync.listCloudHistory()).length, 15);
          print('HISTORY_REAL retention=15 and idempotent retry PASS');

          await sync.restoreCloudVersion(
            revision: history.last.revision,
            expectedFingerprint: (await sync.captureLocalState()).fingerprint,
          );
          expect((await tasks.getGoals()).length, startingGoals + 3);
          final recovery = (await sync.listLocalRecoveryPoints()).first;
          expect(recovery.rowCount, startingGoals + 17);
          expect((await sync.inspectCloud())!.revision, revision);
          await sync.restoreLocalRecoveryPoint(
            pointId: recovery.id,
            expectedFingerprint: (await sync.captureLocalState()).fingerprint,
          );
          expect((await tasks.getGoals()).length, startingGoals + 17);
          expect((await sync.inspectCloud())!.revision, revision);
          history = await sync.listCloudHistory();
          expect(history.length, 15);
          print(
            'HISTORY_REAL cloud restore/local recovery preserve cloud PASS',
          );

          final foreignRows = await other
              .from('cloud_business_snapshot_history')
              .select('revision')
              .eq('user_id', userId);
          expect(foreignRows, isEmpty);
          print('HISTORY_REAL cross-user HTTP RLS PASS');
        } finally {
          if (previousResult == null) {
            await preferences.remove(resultKey);
          } else {
            await preferences.setString(resultKey, previousResult);
          }
          await database.close();
          await client.dispose();
          await other.dispose();
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
