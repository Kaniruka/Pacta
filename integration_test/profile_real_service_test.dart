// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:pacta/src/profile/avatar_image.dart';
import 'package:pacta/src/profile/profile_remote.dart';
import 'package:pacta/src/profile/profile_repository.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

// Runs only against the loopback acceptance fixture's isolated project. The
// protected .env and administrator keys are never compiled into this app:
// credentials come from the runtime control endpoint at test time.
const _control = String.fromEnvironment('ISSUE71_RUNTIME_CONTROL');
const _port = String.fromEnvironment(
  'ISSUE90_RUNTIME_PORT',
  defaultValue: '30390',
);

const String _androidDisplayName = 'Android 验收昵称';
const String _windowsDisplayName = 'Windows 验收昵称';

/// Synthetic 1x1 PNG; the point is a real binary round trip, not the picture.
final Uint8List _syntheticAvatar = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

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

ProfileAvatar _avatar() => ProfileAvatar(
  bytes: _syntheticAvatar,
  mimeType: AvatarImageFormat.png.mimeType,
);

/// Uploads and restores a real business snapshot and proves the account
/// profile cache and cloud profile are untouched by that transfer.
Future<void> _verifyBusinessSnapshotRestoreKeepsProfile({
  required SupabaseClient client,
  required String userId,
  required PactaDatabase database,
  required LocalProfileRepository profile,
}) async {
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
    deviceId: 'issue94-profile-${Platform.operatingSystem}',
    deviceName: Platform.isAndroid ? '验收手机（Android）' : '验收电脑（Windows）',
  );
  final before = await profile.getProfile();

  await tasks.createGoal(
    GoalDraft(
      title: '资料隔离验收 ${Platform.operatingSystem}',
      classification: TaskClassification.both,
    ),
  );
  final baseline = await sync.captureLocalState();
  final current = await sync.inspectCloud();
  final uploaded = await sync.uploadLocal(
    expectedRevision: current?.revision ?? 0,
    expectedFingerprint: baseline.fingerprint,
    requestId: const Uuid().v4(),
  );
  await tasks.createGoal(
    GoalDraft(
      title: '恢复前本机临时 ${Platform.operatingSystem}',
      classification: TaskClassification.both,
    ),
  );
  final beforeRestore = await sync.captureLocalState();
  await sync.downloadCloud(
    expectedRevision: uploaded.revision,
    expectedFingerprint: beforeRestore.fingerprint,
  );

  final after = await profile.getProfile();
  expect(after.displayName, before.displayName);
  expect(after.avatar?.bytes, before.avatar?.bytes);
  final cloudProfile = await SupabaseProfileRemote(client)
      .fetch(userId: userId);
  expect(cloudProfile?.displayName, before.displayName);
  expect(cloudProfile?.avatar?.bytes, before.avatar?.bytes);
  print('PROFILE_REAL business snapshot upload/restore keeps profile PASS');
}

/// Another signed-in user must not read this account's profile, by RPC or by a
/// direct table read.
Future<void> _verifyOtherUserCannotReadProfile({
  required SupabaseClient other,
  required String ownerDisplayName,
}) async {
  final otherProfile = await other.rpc('read_profile_account');
  final otherName = otherProfile is Map ? otherProfile['displayName'] : null;
  expect(otherName, isNot(ownerDisplayName));

  var rejected = false;
  try {
    await other.from('profile_accounts').select('user_id').limit(1);
  } on PostgrestException {
    rejected = true;
  }
  expect(rejected, isTrue);
  print('PROFILE_REAL cross-user RPC and table isolation PASS');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real account profile save, cross-device adopt, avatar clear and '
      'snapshot isolation', (tester) async {
    expect(_control, isNotEmpty, reason: '需要 runtime control');
    await tester.runAsync(() async {
      final config = await _configuration('device');
      final otherConfig = await _configuration('other');
      final client = await _client(config);
      final other = await _client(otherConfig);
      final userId = config['userId'] as String;
      final preferences = await SharedPreferences.getInstance();
      final resultKey = 'pacta.device.cloud_sync.result.$userId';
      final previousResult = preferences.getString(resultKey);
      // 临时内存数据库；本机资料缓存与业务表在同一库，便于验证快照隔离。
      final database = PactaDatabase(NativeDatabase.memory());
      final profile = LocalProfileRepository(
        database: database,
        userId: userId,
        remote: SupabaseProfileRemote(client),
      );
      try {
        if (Platform.isAndroid) {
          final saved = await profile.saveProfile(
            displayName: _androidDisplayName,
            avatar: _avatar(),
          );
          expect(saved.syncError, isNull);
          expect(saved.hasPendingSave, isFalse);

          final remoteProfile = await SupabaseProfileRemote(client)
              .fetch(userId: userId);
          expect(remoteProfile?.displayName, _androidDisplayName);
          expect(remoteProfile?.avatar?.mimeType, 'image/png');
          expect(remoteProfile?.avatar?.bytes, _syntheticAvatar);
          print('PROFILE_REAL android save and cloud read-back PASS');
        } else if (Platform.isWindows) {
          // 独立缓存：本机没有任何资料，必须从云端采用 Android 保存的结果。
          final adopted = await profile.syncProfile();
          final adoptedAndroidProfile =
              adopted.displayName == _androidDisplayName;
          expect(
            adoptedAndroidProfile || adopted.displayName == _windowsDisplayName,
            isTrue,
            reason: '首次运行应读到 Android 资料；重复运行可读到上一次 Windows 结果',
          );
          if (adoptedAndroidProfile) {
            expect(adopted.avatar?.bytes, _syntheticAvatar);
            expect(adopted.avatar?.mimeType, 'image/png');
          }
          print('PROFILE_REAL windows adopts android profile PASS');

          final renamed = await profile.saveProfile(
            displayName: _windowsDisplayName,
            clearAvatar: true,
          );
          expect(renamed.syncError, isNull);
          expect(renamed.hasPendingSave, isFalse);
          expect(renamed.avatar, isNull);

          final remoteProfile = await SupabaseProfileRemote(client)
              .fetch(userId: userId);
          expect(remoteProfile?.displayName, _windowsDisplayName);
          expect(remoteProfile?.avatar, isNull);
          print('PROFILE_REAL windows rename and avatar clear PASS');
        }

        await _verifyOtherUserCannotReadProfile(
          other: other,
          ownerDisplayName: (await profile.getProfile()).displayName,
        );
        await _verifyBusinessSnapshotRestoreKeepsProfile(
          client: client,
          userId: userId,
          database: database,
          profile: profile,
        );
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
  }, timeout: const Timeout(Duration(minutes: 8)));
}
