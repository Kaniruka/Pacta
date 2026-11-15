import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/profile/avatar_image.dart';
import 'package:pacta/src/profile/avatar_picker.dart';
import 'package:pacta/src/profile/profile_edit_page.dart';
import 'package:pacta/src/profile/profile_remote.dart';
import 'package:pacta/src/profile/profile_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

/// 另一台设备在本次编辑期间先写入了纽约，账号存储按修订号保留它；本机的
/// 伦敦请求基于旧修订号，因此只能采用赢家。
class _ConflictRemote implements ProfileRemote {
  RemoteProfile stored = RemoteProfile(
    displayName: '小林',
    avatar: null,
    updatedAt: DateTime.utc(2026, 11, 15, 10),
    displayTimeZoneId: 'Asia/Tokyo',
    timeZoneRevision: 1,
  );

  String? lastRequestedZone;
  int? lastRequestedRevision;

  @override
  bool get isAvailable => true;

  @override
  Future<RemoteProfile?> fetch({required String userId}) async => stored;

  @override
  Future<RemoteProfile?> initializeTimeZone({
    required String userId,
    required String displayTimeZoneId,
  }) async => stored;

  @override
  Future<RemoteProfile> save({
    required String userId,
    required String displayName,
    required ProfileAvatar? avatar,
    required DateTime updatedAt,
    String? displayTimeZoneId,
    int? timeZoneRevision,
  }) async {
    lastRequestedZone = displayTimeZoneId;
    lastRequestedRevision = timeZoneRevision;
    final acceptedZone = displayTimeZoneId == null
        ? stored.displayTimeZoneId
        : 'America/New_York';
    final acceptedRevision = displayTimeZoneId == null
        ? stored.timeZoneRevision
        : stored.timeZoneRevision + 1;
    stored = RemoteProfile(
      displayName: displayName,
      avatar: avatar,
      updatedAt: updatedAt,
      displayTimeZoneId: acceptedZone,
      timeZoneRevision: acceptedRevision,
      timeZoneConflict: displayTimeZoneId != null,
    );
    return stored;
  }
}

class _NoPicker implements AvatarPicker {
  const _NoPicker();

  @override
  Future<Uint8List?> pickSingleImage() async => null;
}

void main() {
  testWidgets('时区被其他设备更新时如实说明采用最新值，而不是保存成功', (tester) async {
    final database = PactaDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final remote = _ConflictRemote();
    final repository = LocalProfileRepository(
      database: database,
      userId: 'user-a',
      remote: remote,
      now: () => DateTime.utc(2026, 11, 15, 10, 5),
    );
    await repository.syncProfile();

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileEditPage(
          repository: repository,
          avatarPicker: const _NoPicker(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, '伦敦'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(remote.lastRequestedZone, 'Europe/London');
    expect(remote.lastRequestedRevision, 1, reason: '请求基于本机已知修订号');
    expect(find.text('编辑资料'), findsOneWidget, reason: '时区未被采用时不得关闭页面假装成功');
    expect(find.textContaining('已被其他设备更新'), findsOneWidget);
    expect(find.textContaining('America/New_York'), findsWidgets);

    final cached = await repository.getProfile();
    expect(cached.displayTimeZoneId, 'America/New_York');
    expect(cached.timeZoneRevision, 2);
    expect(cached.syncError, isNull, reason: '采用账号值是收敛而不是失败');
  });
}
