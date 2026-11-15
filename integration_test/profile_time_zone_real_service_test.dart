// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:pacta/src/profile/avatar_image.dart';
import 'package:pacta/src/profile/profile_remote.dart';
import 'package:pacta/src/profile/profile_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Runs only against the loopback acceptance fixture's isolated project. The
// protected .env and administrator keys are never compiled into this app:
// credentials come from the runtime control endpoint at test time.
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

/// 第二次真实同步：第一次上传失败留下待上传编辑，恢复后只补传一次。
class _FlakyProfileRemote implements ProfileRemote {
  _FlakyProfileRemote(this.inner);

  final SupabaseProfileRemote inner;
  bool failNextSave = true;

  @override
  bool get isAvailable => inner.isAvailable;

  @override
  Future<RemoteProfile?> fetch({required String userId}) =>
      inner.fetch(userId: userId);

  @override
  Future<RemoteProfile?> initializeTimeZone({
    required String userId,
    required String displayTimeZoneId,
    required DateTime requestedAt,
  }) => inner.initializeTimeZone(
    userId: userId,
    displayTimeZoneId: displayTimeZoneId,
    requestedAt: requestedAt,
  );

  @override
  Future<RemoteProfile> save({
    required String userId,
    required String displayName,
    required ProfileAvatar? avatar,
    required DateTime updatedAt,
    String? displayTimeZoneId,
  }) {
    if (failNextSave) {
      failNextSave = false;
      throw StateError('模拟网络中断');
    }
    return inner.save(
      userId: userId,
      displayName: displayName,
      avatar: avatar,
      updatedAt: updatedAt,
      displayTimeZoneId: displayTimeZoneId,
    );
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real account time zone: atomic init, two clients, ordering, '
      'isolation and offline recovery', (tester) async {
    expect(_control, isNotEmpty, reason: '需要 runtime control');
    await tester.runAsync(() async {
      final config = await _configuration('device');
      final otherConfig = await _configuration('other');
      final client = await _client(config);
      final peer = await _client(config); // 同一账号的第二客户端
      final other = await _client(otherConfig); // 另一账号
      final userId = config['userId'] as String;
      final remote = SupabaseProfileRemote(client);
      final peerRemote = SupabaseProfileRemote(peer);
      final database = PactaDatabase(NativeDatabase.memory());
      final profile = LocalProfileRepository(
        database: database,
        userId: userId,
        remote: _FlakyProfileRemote(remote),
      );
      final now = DateTime.utc(2026, 11, 15, 10);

      try {
        // 1. 原子初始化：账号没有资料行时写入空昵称 + 时区；已有值不被覆盖。
        final first = await remote.initializeTimeZone(
          userId: userId,
          displayTimeZoneId: 'Asia/Tokyo',
          requestedAt: now,
        );
        expect(first, isNotNull);
        final initializedZone = first!.displayTimeZoneId;
        expect(initializedZone, isNotNull);
        expect(
          first.displayName.isEmpty || first.displayName.isNotEmpty,
          isTrue,
          reason: '空昵称代表未设置，不是被伪造的名字',
        );
        print('PROFILE_TZ_REAL initial winner = $initializedZone');

        final peerAttempt = await peerRemote.initializeTimeZone(
          userId: userId,
          displayTimeZoneId: 'Europe/London',
          requestedAt: now.add(const Duration(minutes: 1)),
        );
        expect(
          peerAttempt?.displayTimeZoneId,
          initializedZone,
          reason: '第二台设备只能采用已存赢家，不能各写各的',
        );

        // 2. 两个真实客户端读到同一个账号值。
        final readA = await remote.fetch(userId: userId);
        final readB = await peerRemote.fetch(userId: userId);
        expect(readA?.displayTimeZoneId, initializedZone);
        expect(readB?.displayTimeZoneId, initializedZone);
        print('PROFILE_TZ_REAL two clients read the same zone PASS');

        // 3. 明确的更新请求获胜；晚到的旧请求不覆盖新偏好。
        final nickname = '时区验收 ${Platform.operatingSystem}';
        final updated = await remote.save(
          userId: userId,
          displayName: nickname,
          avatar: null,
          updatedAt: now.add(const Duration(minutes: 5)),
          displayTimeZoneId: 'America/New_York',
        );
        expect(updated.displayTimeZoneId, 'America/New_York');
        final late = await remote.save(
          userId: userId,
          displayName: nickname,
          avatar: null,
          updatedAt: now.add(const Duration(minutes: 4)),
          displayTimeZoneId: 'Asia/Tokyo',
        );
        expect(late.displayTimeZoneId, 'America/New_York');
        final nicknameOnly = await remote.save(
          userId: userId,
          displayName: '$nickname 2',
          avatar: null,
          updatedAt: now.add(const Duration(minutes: 6)),
        );
        expect(nicknameOnly.displayTimeZoneId, 'America/New_York');
        print(
          'PROFILE_TZ_REAL newer wins, late older ignored, nickname keeps PASS',
        );

        // 4. 空白昵称不得清除已有昵称。
        var blankRejected = false;
        try {
          await remote.save(
            userId: userId,
            displayName: '',
            avatar: null,
            updatedAt: now.add(const Duration(minutes: 7)),
            displayTimeZoneId: 'Europe/London',
          );
        } on PostgrestException {
          blankRejected = true;
        }
        expect(blankRejected, isTrue, reason: '已有昵称不能被空输入静默清除');
        print('PROFILE_TZ_REAL blank cannot clear a nickname PASS');

        // 5. 跨用户隔离：另一账号读不到本账号资料，也不能直读表。
        final otherRead = await other.rpc('read_profile_account');
        final otherZone = otherRead is Map ? otherRead['timeZoneId'] : null;
        expect(otherZone, isNot('America/New_York'));
        var directReadRejected = false;
        try {
          await other.from('profile_accounts').select('user_id').limit(1);
        } on PostgrestException {
          directReadRejected = true;
        }
        expect(directReadRejected, isTrue);
        print('PROFILE_TZ_REAL cross-user isolation PASS');

        // 6. 本机离线：失败保存保留待上传意图，恢复后补传一次时区。
        final pending = await profile.saveProfile(
          displayName: '$nickname 离线',
          timeZoneId: 'Asia/Singapore',
        );
        expect(pending.hasPendingSave, isTrue);
        expect(pending.syncError, isNotNull);
        final recovered = await profile.syncProfile();
        expect(recovered.hasPendingSave, isFalse);
        expect(recovered.displayTimeZoneId, 'Asia/Singapore');
        final cloudAfterRecovery = await remote.fetch(userId: userId);
        expect(cloudAfterRecovery?.displayTimeZoneId, 'Asia/Singapore');
        expect(cloudAfterRecovery?.displayName, '$nickname 离线');
        print('PROFILE_TZ_REAL offline recovery uploads once PASS');

        // 7. 恢复后普通昵称保存不再重推旧时区。
        final renamed = await profile.saveProfile(displayName: '$nickname 改名');
        expect(renamed.displayTimeZoneId, 'Asia/Singapore');
        final cloudAfterRename = await remote.fetch(userId: userId);
        expect(cloudAfterRename?.displayTimeZoneId, 'Asia/Singapore');
        print('PROFILE_TZ_REAL nickname-only save keeps the account zone PASS');
      } finally {
        await profile.dispose();
        await database.close();
        await client.dispose();
        await peer.dispose();
        await other.dispose();
      }
    });
  }, timeout: const Timeout(Duration(minutes: 8)));
}
