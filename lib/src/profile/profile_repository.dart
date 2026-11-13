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
  /// device. Never uploads without a pending local edit and never touches the
  /// business snapshot.
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

  /// Serialises local edits and account-store calls for this repository, so a
  /// background read cannot interleave with an upload or a user edit.
  Future<void> _operationQueue = Future<void>.value();

  bool _disposed = false;

  /// The account-clear generation this repository last observed. Every write
  /// re-reads it inside the write transaction, so an account purge that lands
  /// while a read or upload is in flight cannot be undone by the late result.
  Future<int> _readClearGeneration() async {
    final row = await (database.select(
      database.localProfileClearMarks,
    )..where((row) => row.userId.equals(userId))).getSingleOrNull();
    return row?.generation ?? 0;
  }

  /// Runs [write] in one transaction that first proves the account was not
  /// cleared and that this repository is still live. A rejected write returns
  /// false and leaves the account data untouched.
  Future<bool> _guardedWrite({
    required int clearGeneration,
    required Future<bool> Function() write,
  }) => database.transaction(() async {
    if (_disposed) return false;
    if (await _readClearGeneration() != clearGeneration) return false;
    return write();
  });

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _operationQueue.then((_) => action());
    _operationQueue = result.then((_) {}, onError: (Object _) {});
    return result;
  }

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
  }) => _serialized(() async {
    final clearGeneration = await _readClearGeneration();
    final name = validateDisplayName(displayName);
    final current = await getProfile();
    final nextAvatar = clearAvatar ? null : (avatar ?? current.avatar);
    final written = await _guardedWrite(
      clearGeneration: clearGeneration,
      write: () async {
        await _writeLocal(
          displayName: name,
          avatar: nextAvatar,
          updatedAt: _now().toUtc(),
          pendingSave: true,
          syncError: null,
          editSequence: current.editSequence + 1,
        );
        return true;
      },
    );
    // 账号已清除或本仓储已 dispose：这次编辑不再落到本机，也不再上传。
    if (!written) return getProfile();
    if (!remote.isAvailable) return getProfile();
    return _upload(clearGeneration);
  });

  @override
  Future<ProfileAccount> syncProfile() => _serialized(() async {
    final clearGeneration = await _readClearGeneration();
    final local = await getProfile();
    if (local.hasPendingSave) {
      if (!remote.isAvailable) return local;
      return _upload(clearGeneration);
    }
    if (!remote.isAvailable) return local;

    final RemoteProfile? remoteProfile;
    try {
      remoteProfile = await remote.fetch(userId: userId);
    } catch (error) {
      // A failed read only records the failure. It must not create or advance a
      // local version, otherwise a later read could make the empty cache look
      // newer than the stored profile and upload over it.
      return _recordFailure(local, _failureText(error), clearGeneration);
    }

    if (remoteProfile == null) {
      if (local.syncError == null) return local;
      await _clearFailureIfUnchanged(local.editSequence, clearGeneration);
      return getProfile();
    }

    final localUpdatedAt = local.updatedAt;
    if (localUpdatedAt == null ||
        remoteProfile.updatedAt.isAfter(localUpdatedAt)) {
      // Adopting another device's profile is a local state change, so it also
      // advances the edit sequence and invalidates in-flight commits.
      await _writeLocalIfSequenceUnchanged(
        expectedSequence: local.editSequence,
        clearGeneration: clearGeneration,
        displayName: remoteProfile.displayName,
        avatar: remoteProfile.avatar,
        updatedAt: remoteProfile.updatedAt,
        pendingSave: false,
        syncError: null,
      );
    }
    return getProfile();
  });

  Future<ProfileAccount> _upload(int clearGeneration) async {
    final local = await getProfile();
    final sequence = local.editSequence;
    try {
      final saved = await remote.save(
        userId: userId,
        displayName: local.displayName,
        avatar: local.avatar,
        updatedAt: local.updatedAt ?? _now().toUtc(),
      );
      await _writeLocalIfSequenceUnchanged(
        expectedSequence: sequence,
        clearGeneration: clearGeneration,
        displayName: saved.displayName,
        avatar: saved.avatar,
        updatedAt: saved.updatedAt,
        pendingSave: false,
        syncError: null,
      );
    } catch (error) {
      // Keep the pending intent; only a matching sequence may carry the error.
      await _updateStateIfUnchanged(
        expectedSequence: sequence,
        clearGeneration: clearGeneration,
        syncError: _failureText(error),
        pendingSave: true,
      );
    }
    return getProfile();
  }

  Future<ProfileAccount> _recordFailure(
    ProfileAccount local,
    String message,
    int clearGeneration,
  ) async {
    if (local.updatedAt == null) {
      // No cached version yet: report the failure without inventing a row.
      return local.copyWith(syncError: message);
    }
    await _updateStateIfUnchanged(
      expectedSequence: local.editSequence,
      clearGeneration: clearGeneration,
      syncError: message,
      pendingSave: local.hasPendingSave,
    );
    return getProfile();
  }

  Future<void> _clearFailureIfUnchanged(
    int expectedSequence,
    int clearGeneration,
  ) => _updateStateIfUnchanged(
    expectedSequence: expectedSequence,
    clearGeneration: clearGeneration,
    syncError: null,
    pendingSave: false,
  );

  Future<bool> _updateStateIfUnchanged({
    required int expectedSequence,
    required int clearGeneration,
    required String? syncError,
    required bool pendingSave,
  }) => _guardedWrite(
    clearGeneration: clearGeneration,
    write: () async {
      final updated =
          await (database.update(database.localProfileAccounts)..where(
                (row) =>
                    row.userId.equals(userId) &
                    row.editSequence.equals(expectedSequence),
              ))
              .write(
                LocalProfileAccountsCompanion(
                  syncError: drift.Value(syncError),
                  pendingSave: drift.Value(pendingSave),
                ),
              );
      return updated > 0;
    },
  );

  Future<bool> _writeLocalIfSequenceUnchanged({
    required int expectedSequence,
    required int clearGeneration,
    required String displayName,
    required ProfileAvatar? avatar,
    required DateTime updatedAt,
    required bool pendingSave,
    required String? syncError,
  }) => _guardedWrite(
    clearGeneration: clearGeneration,
    write: () async {
      final existing = await (database.select(
        database.localProfileAccounts,
      )..where((row) => row.userId.equals(userId))).getSingleOrNull();
      if (existing == null) {
        // Adopting the first profile for this account: nothing local can be
        // newer than the sequence this call started from.
        if (expectedSequence != 0) return false;
        await _writeLocal(
          displayName: displayName,
          avatar: avatar,
          updatedAt: updatedAt,
          pendingSave: pendingSave,
          syncError: syncError,
          editSequence: 1,
        );
        return true;
      }
      final updated =
          await (database.update(database.localProfileAccounts)..where(
                (row) =>
                    row.userId.equals(userId) &
                    row.editSequence.equals(expectedSequence),
              ))
              .write(
                LocalProfileAccountsCompanion(
                  displayName: drift.Value(displayName),
                  avatarMimeType: drift.Value(avatar?.mimeType),
                  avatarBytes: drift.Value(avatar?.bytes),
                  updatedAt: drift.Value(updatedAt),
                  pendingSave: drift.Value(pendingSave),
                  syncError: drift.Value(syncError),
                  editSequence: drift.Value(expectedSequence + 1),
                ),
              );
      return updated > 0;
    },
  );

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
    required int editSequence,
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
          editSequence: drift.Value(editSequence),
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
      editSequence: row.editSequence,
    );
  }

  /// 失效在途操作：dispose 之后到达的读取或上传应答不再写回本机资料。
  @override
  Future<void> dispose() async {
    _disposed = true;
  }
}
