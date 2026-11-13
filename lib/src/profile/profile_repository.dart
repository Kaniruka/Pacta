import 'dart:async';

import 'package:drift/drift.dart' as drift;

import '../tasks/task_database.dart';
import 'avatar_image.dart';
import 'profile_models.dart';
import 'profile_remote.dart';

/// Account profile reads, local caching, and account-store synchronisation.
abstract interface class ProfileRepository {
  Stream<ProfileAccount> watchProfile();

  Future<ProfileAccount> getProfile();

  /// Saves the display name and, when given, a new avatar.
  ///
  /// [avatar] null keeps the current avatar; [clearAvatar] removes it. The
  /// local cache is written first, so a failed account write leaves the edit
  /// visible and retryable through [hasPendingSave].
  Future<ProfileAccount> saveProfile({
    required String displayName,
    ProfileAvatar? avatar,
    bool clearAvatar = false,
  });

  /// Uploads a pending local edit, or adopts a newer profile from another
  /// device. Never touches the business snapshot.
  Future<ProfileAccount> syncProfile();

  Future<void> dispose();
}

/// Used before a signed-in account store exists; editing stays disabled.
class UnavailableProfileRepository implements ProfileRepository {
  const UnavailableProfileRepository();

  @override
  Stream<ProfileAccount> watchProfile() =>
      Stream.value(const ProfileAccount(userId: ''));

  @override
  Future<ProfileAccount> getProfile() async => const ProfileAccount(userId: '');

  @override
  Future<ProfileAccount> saveProfile({
    required String displayName,
    ProfileAvatar? avatar,
    bool clearAvatar = false,
  }) async => throw StateError('当前未登录，资料暂时不能保存。');

  @override
  Future<ProfileAccount> syncProfile() => getProfile();

  @override
  Future<void> dispose() async {}
}

class LocalProfileRepository implements ProfileRepository {
  LocalProfileRepository({
    required this.database,
    required this.userId,
    this.remote = const UnavailableProfileRemote(),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final PactaDatabase database;
  final String userId;
  final ProfileRemote remote;
  final DateTime Function() _now;

  @override
  Stream<ProfileAccount> watchProfile() {
    final query = database.select(database.localProfileAccounts)
      ..where((row) => row.userId.equals(userId));
    return query.watchSingleOrNull().map(_accountFromRow);
  }

  @override
  Future<ProfileAccount> getProfile() async {
    final row = await (database.select(
      database.localProfileAccounts,
    )..where((row) => row.userId.equals(userId))).getSingleOrNull();
    return _accountFromRow(row);
  }

  @override
  Future<ProfileAccount> saveProfile({
    required String displayName,
    ProfileAvatar? avatar,
    bool clearAvatar = false,
  }) async {
    final name = validateDisplayName(displayName);
    final current = await getProfile();
    final nextAvatar = clearAvatar ? null : (avatar ?? current.avatar);
    await _writeLocal(
      displayName: name,
      avatar: nextAvatar,
      updatedAt: _now().toUtc(),
      pendingSave: remote.isAvailable,
      syncError: null,
    );
    if (!remote.isAvailable) return getProfile();
    return _upload();
  }

  @override
  Future<ProfileAccount> syncProfile() async {
    final local = await getProfile();
    if (local.hasPendingSave) {
      if (!remote.isAvailable) return local;
      return _upload();
    }
    if (!remote.isAvailable) return local;

    final RemoteProfile? remoteProfile;
    try {
      remoteProfile = await remote.fetch(userId: userId);
    } catch (error) {
      await _recordError(
        local,
        _failureText(error),
        pending: local.hasPendingSave,
      );
      return getProfile();
    }

    if (remoteProfile == null) {
      if (!local.hasDisplayName && local.avatar == null) return local;
      return _upload();
    }
    final localUpdatedAt = local.updatedAt;
    if (localUpdatedAt == null ||
        remoteProfile.updatedAt.isAfter(localUpdatedAt)) {
      await _writeLocal(
        displayName: remoteProfile.displayName,
        avatar: remoteProfile.avatar,
        updatedAt: remoteProfile.updatedAt,
        pendingSave: false,
        syncError: null,
      );
      return getProfile();
    }
    if (localUpdatedAt.isAfter(remoteProfile.updatedAt)) {
      return _upload();
    }
    return local;
  }

  Future<ProfileAccount> _upload() async {
    final local = await getProfile();
    try {
      final saved = await remote.save(
        userId: userId,
        displayName: local.displayName,
        avatar: local.avatar,
        updatedAt: local.updatedAt ?? _now().toUtc(),
      );
      await _writeLocal(
        displayName: saved.displayName,
        avatar: saved.avatar,
        updatedAt: saved.updatedAt,
        pendingSave: false,
        syncError: null,
      );
    } catch (error) {
      // A failed upload stays pending so the retry uploads the local edit
      // instead of silently losing it.
      await _recordError(local, _failureText(error), pending: true);
    }
    return getProfile();
  }

  Future<void> _recordError(
    ProfileAccount local,
    String message, {
    required bool pending,
  }) async {
    await _writeLocal(
      displayName: local.displayName,
      avatar: local.avatar,
      updatedAt: local.updatedAt ?? _now().toUtc(),
      pendingSave: pending,
      syncError: message,
    );
  }

  String _failureText(Object error) {
    final message = error is StateError ? error.message : error.toString();
    if (message.startsWith('保存失败')) return message;
    return '保存失败：$message';
  }

  Future<void> _writeLocal({
    required String displayName,
    required ProfileAvatar? avatar,
    required DateTime updatedAt,
    required bool pendingSave,
    required String? syncError,
  }) => database
      .into(database.localProfileAccounts)
      .insertOnConflictUpdate(
        LocalProfileAccountsCompanion.insert(
          userId: userId,
          updatedAt: updatedAt,
          displayName: drift.Value(displayName),
          avatarMimeType: drift.Value(avatar?.mimeType),
          avatarBytes: drift.Value(avatar?.bytes),
          pendingSave: drift.Value(pendingSave),
          syncError: drift.Value(syncError),
        ),
      );

  ProfileAccount _accountFromRow(LocalProfileAccount? row) {
    if (row == null) return ProfileAccount(userId: userId);
    final bytes = row.avatarBytes;
    return ProfileAccount(
      userId: row.userId,
      displayName: row.displayName,
      avatar: bytes == null || bytes.isEmpty
          ? null
          : ProfileAvatar(
              bytes: bytes,
              mimeType: row.avatarMimeType ?? AvatarImageFormat.png.mimeType,
            ),
      updatedAt: row.updatedAt,
      hasPendingSave: row.pendingSave,
      syncError: row.syncError,
    );
  }

  @override
  Future<void> dispose() async {}
}
