import 'dart:async';

import 'package:drift/drift.dart' as drift;

import '../tasks/task_database.dart';
import 'account_time_zone.dart';
import 'avatar_image.dart';
import 'profile_models.dart';
import 'profile_remote.dart';

/// Account profile reads, local caching, and account-store synchronisation.
abstract interface class ProfileRepository {
  Stream<ProfileAccount> watchProfile();

  Future<ProfileAccount> getProfile();

  /// Saves the display name, the account display time zone and, when given, a
  /// new avatar.
  ///
  /// [avatar] null keeps the current avatar; [clearAvatar] removes it.
  /// [timeZoneId] null keeps the account time zone and does not re-upload the
  /// cached one: only a zone chosen in this edit is sent, so a stale local copy
  /// never replaces an account value another device wrote later. The local
  /// cache is written first, so a failed account write leaves the edit visible
  /// and retryable through [hasPendingSave].
  Future<ProfileAccount> saveProfile({
    required String displayName,
    ProfileAvatar? avatar,
    bool clearAvatar = false,
    String? timeZoneId,
  });

  /// Makes sure the account has a display time zone, migrating the superseded
  /// device-level value once.
  ///
  /// An existing account value always wins, including one that only the account
  /// store knows about. [deviceTimeZoneId] is a one-time migration input, never
  /// a display fallback: display uses the fixed account-empty value instead.
  /// Repeated calls are idempotent.
  Future<ProfileAccount> ensureDisplayTimeZone({String? deviceTimeZoneId});

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
    String? timeZoneId,
  }) async => throw StateError('当前未登录，资料暂时不能保存。');

  @override
  Future<ProfileAccount> ensureDisplayTimeZone({String? deviceTimeZoneId}) =>
      getProfile();

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

  /// A confirmed purge keeps its mark forever, and a fresh registration gets a
  /// new auth UUID (see supabase/README.md "Explicit cloud purge"). Any profile
  /// write for a marked UUID can therefore only be a stale operation — an
  /// in-flight read answer, an upload answer, or an edit still queued behind a
  /// blocked operation — so the mark is a permanent write ban, not a counter
  /// that a later operation may read as "already current".
  Future<bool> _isPurgedAccount() async {
    final row = await (database.select(
      database.localProfileClearMarks,
    )..where((row) => row.userId.equals(userId))).getSingleOrNull();
    return row != null;
  }

  /// Runs [write] in one transaction that first proves the account was not
  /// cleared and that this repository is still live, so a late answer or a
  /// queued operation cannot write after the purge. A rejected write returns
  /// false and leaves the account data untouched.
  Future<bool> _guardedWrite({required Future<bool> Function() write}) =>
      database.transaction(() async {
        if (_disposed) return false;
        if (await _isPurgedAccount()) return false;
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
    String? timeZoneId,
  }) => _serialized(() async {
    if (timeZoneId != null && !AccountTimeZones.isKnown(timeZoneId)) {
      throw ArgumentError.value(timeZoneId, 'timeZoneId', '未知的时区标识。');
    }
    final name = validateDisplayName(displayName);
    final current = await getProfile();
    // 未设置的昵称可以保持为空（例如只改时区），但已有昵称不能被一次空输入
    // 静默清除。
    if (name.isEmpty && current.displayName.isNotEmpty) {
      throw const AvatarValidationException('昵称不能为空。');
    }
    final nextAvatar = clearAvatar ? null : (avatar ?? current.avatar);
    final nextTimeZoneId = timeZoneId ?? current.displayTimeZoneId;
    final written = await _guardedWrite(
      write: () async {
        await _writeLocal(
          displayName: name,
          avatar: nextAvatar,
          displayTimeZoneId: nextTimeZoneId,
          updatedAt: _now().toUtc(),
          pendingSave: true,
          syncError: null,
          editSequence: current.editSequence + 1,
          pendingTimeZoneUpload: timeZoneId == null
              ? current.pendingTimeZoneUpload
              : remote.isAvailable,
        );
        return true;
      },
    );
    // 账号已清除或本仓储已 dispose：这次编辑不再落到本机，也不再上传。
    if (!written) return getProfile();
    if (!remote.isAvailable) return getProfile();
    return _upload();
  });

  @override
  Future<ProfileAccount> ensureDisplayTimeZone({String? deviceTimeZoneId}) =>
      _serialized(() async {
        final local = await getProfile();
        // 已有账号值优先：本机缓存里的值不再被任何设备种子覆盖。
        if (AccountTimeZones.isKnown(local.displayTimeZoneId)) return local;

        // 旧设备级字段只在这里作为一次性迁移输入被读取，显示不读它。
        final legacy = await _legacyDisplayTimeZone();
        final seed = AccountTimeZones.isKnown(legacy)
            ? legacy
            : AccountTimeZones.isKnown(deviceTimeZoneId)
            ? deviceTimeZoneId
            : null;

        if (!remote.isAvailable) {
          // 没有配置账号存储时本机缓存就是唯一存储：迁移值直接成为账号值。
          // 一旦存在账号存储，未获接受的设备值绝不能被当成账号值缓存。
          return seed == null ? local : _cacheAccountTimeZone(local, seed);
        }

        final RemoteProfile? stored;
        try {
          stored = await remote.fetch(userId: userId);
        } catch (_) {
          // 读不到账号值：保持本机缓存。显示使用统一 fallback，不退回设备时区。
          return local;
        }
        final remoteTimeZoneId = stored?.displayTimeZoneId;
        if (AccountTimeZones.isKnown(remoteTimeZoneId)) {
          return _adoptAccountProfile(local, stored!, remoteTimeZoneId!);
        }
        if (seed == null) return local;

        // 两台设备可能同时读到"还没有值"，因此由账号存储原子决定唯一赢家，
        // 不是先读后无条件写入。
        RemoteProfile? initialized;
        try {
          initialized = await remote.initializeTimeZone(
            userId: userId,
            displayTimeZoneId: seed,
            requestedAt: _now().toUtc(),
          );
        } catch (_) {
          initialized = null;
        }
        final winner = initialized?.displayTimeZoneId;
        if (initialized != null && AccountTimeZones.isKnown(winner)) {
          return _adoptAccountProfile(local, initialized, winner!);
        }
        // 初始化没成功：账号仍然没有值，显示保持统一 fallback，稍后重试的
        // 仍是同一条原子初始化路径。设备种子既不缓存成账号值，也不会被普通
        // 保存带上云端覆盖另一台设备写入的值。
        return local;
      });

  @override
  Future<ProfileAccount> syncProfile() => _serialized(() async {
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
      // A failed read only records the failure. It must not create or advance a
      // local version, otherwise a later read could make the empty cache look
      // newer than the stored profile and upload over it.
      return _recordFailure(local, _failureText(error));
    }

    if (remoteProfile == null) {
      if (local.syncError == null) return local;
      await _clearFailureIfUnchanged(local.editSequence);
      return getProfile();
    }

    final localUpdatedAt = local.updatedAt;
    if (localUpdatedAt == null ||
        remoteProfile.updatedAt.isAfter(localUpdatedAt)) {
      // Adopting another device's profile is a local state change, so it also
      // advances the edit sequence and invalidates in-flight commits.
      await _writeLocalIfSequenceUnchanged(
        expectedSequence: local.editSequence,
        displayName: remoteProfile.displayName,
        avatar: remoteProfile.avatar,
        // 云端没有值时保留本机已迁移的账号值，不被空值抹掉。
        displayTimeZoneId:
            remoteProfile.displayTimeZoneId ?? local.displayTimeZoneId,
        updatedAt: remoteProfile.updatedAt,
        pendingSave: false,
        syncError: null,
        pendingTimeZoneUpload: false,
      );
    }
    return getProfile();
  });

  Future<ProfileAccount> _upload() async {
    final local = await getProfile();
    final sequence = local.editSequence;
    // A cached zone is not a preference this device chose: sending it again on a
    // nickname/avatar save would let a stale copy replace a newer account value
    // written elsewhere. Only an unpushed local choice travels with the save.
    final timeZoneIdToUpload = local.pendingTimeZoneUpload
        ? local.displayTimeZoneId
        : null;
    try {
      final saved = await remote.save(
        userId: userId,
        displayName: local.displayName,
        avatar: local.avatar,
        updatedAt: local.updatedAt ?? _now().toUtc(),
        displayTimeZoneId: timeZoneIdToUpload,
      );
      await _writeLocalIfSequenceUnchanged(
        expectedSequence: sequence,
        displayName: saved.displayName,
        avatar: saved.avatar,
        displayTimeZoneId: saved.displayTimeZoneId ?? local.displayTimeZoneId,
        updatedAt: saved.updatedAt,
        pendingSave: false,
        syncError: null,
        pendingTimeZoneUpload: false,
      );
    } catch (error) {
      // Keep the pending intent; only a matching sequence may carry the error.
      await _updateStateIfUnchanged(
        expectedSequence: sequence,
        syncError: _failureText(error),
        pendingSave: true,
      );
    }
    return getProfile();
  }

  /// Adopts [stored]'s account time zone. A profile this device never cached is
  /// adopted whole; otherwise only the time zone is filled, so a local nickname
  /// or avatar edit is never discarded by a migration step.
  Future<ProfileAccount> _adoptAccountProfile(
    ProfileAccount local,
    RemoteProfile stored,
    String timeZoneId,
  ) async {
    if (local.updatedAt == null) {
      await _writeLocalIfSequenceUnchanged(
        expectedSequence: local.editSequence,
        displayName: stored.displayName,
        avatar: stored.avatar,
        displayTimeZoneId: timeZoneId,
        updatedAt: stored.updatedAt,
        pendingSave: false,
        syncError: null,
        pendingTimeZoneUpload: false,
      );
      return getProfile();
    }
    await _guardedWrite(
      write: () async {
        final updated =
            await (database.update(database.localProfileAccounts)..where(
                  (row) =>
                      row.userId.equals(userId) &
                      row.editSequence.equals(local.editSequence),
                ))
                .write(
                  LocalProfileAccountsCompanion(
                    timeZoneId: drift.Value(timeZoneId),
                    editSequence: drift.Value(local.editSequence + 1),
                  ),
                );
        return updated > 0;
      },
    );
    return getProfile();
  }

  /// Caches the migrated [timeZoneId] as the account value on an installation
  /// that has no account store at all. This is the only place a seed may become
  /// a local account value, and it never starts an upload.
  Future<ProfileAccount> _cacheAccountTimeZone(
    ProfileAccount local,
    String timeZoneId,
  ) async {
    await _guardedWrite(
      write: () async {
        if (local.updatedAt == null) {
          await _writeLocal(
            displayName: local.displayName,
            avatar: local.avatar,
            displayTimeZoneId: timeZoneId,
            updatedAt: _now().toUtc(),
            pendingSave: false,
            syncError: null,
            editSequence: 1,
            pendingTimeZoneUpload: false,
          );
          return true;
        }
        final updated =
            await (database.update(database.localProfileAccounts)..where(
                  (row) =>
                      row.userId.equals(userId) &
                      row.editSequence.equals(local.editSequence),
                ))
                .write(
                  LocalProfileAccountsCompanion(
                    timeZoneId: drift.Value(timeZoneId),
                    editSequence: drift.Value(local.editSequence + 1),
                  ),
                );
        return updated > 0;
      },
    );
    return getProfile();
  }

  /// The superseded device-level field. Read only to seed the account value; a
  /// display path must never consult it.
  Future<String?> _legacyDisplayTimeZone() async {
    final row = await (database.select(
      database.focusPreferences,
    )..where((entry) => entry.userId.equals(userId))).getSingleOrNull();
    return row?.displayTimeZoneId;
  }

  Future<ProfileAccount> _recordFailure(
    ProfileAccount local,
    String message,
  ) async {
    if (local.updatedAt == null) {
      // No cached version yet: report the failure without inventing a row.
      return local.copyWith(syncError: message);
    }
    await _updateStateIfUnchanged(
      expectedSequence: local.editSequence,
      syncError: message,
      pendingSave: local.hasPendingSave,
    );
    return getProfile();
  }

  Future<void> _clearFailureIfUnchanged(int expectedSequence) =>
      _updateStateIfUnchanged(
        expectedSequence: expectedSequence,
        syncError: null,
        pendingSave: false,
      );

  Future<bool> _updateStateIfUnchanged({
    required int expectedSequence,
    required String? syncError,
    required bool pendingSave,
  }) => _guardedWrite(
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
    required String displayName,
    required ProfileAvatar? avatar,
    required String? displayTimeZoneId,
    required DateTime updatedAt,
    required bool pendingSave,
    required String? syncError,
    required bool pendingTimeZoneUpload,
  }) => _guardedWrite(
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
          displayTimeZoneId: displayTimeZoneId,
          updatedAt: updatedAt,
          pendingSave: pendingSave,
          syncError: syncError,
          editSequence: 1,
          pendingTimeZoneUpload: pendingTimeZoneUpload,
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
                  timeZoneId: drift.Value(displayTimeZoneId),
                  updatedAt: drift.Value(updatedAt),
                  pendingSave: drift.Value(pendingSave),
                  syncError: drift.Value(syncError),
                  editSequence: drift.Value(expectedSequence + 1),
                  pendingTimeZoneUpload: drift.Value(pendingTimeZoneUpload),
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
    required String? displayTimeZoneId,
    required DateTime updatedAt,
    required bool pendingSave,
    required String? syncError,
    required int editSequence,
    required bool pendingTimeZoneUpload,
  }) => database
      .into(database.localProfileAccounts)
      .insertOnConflictUpdate(
        LocalProfileAccountsCompanion.insert(
          userId: userId,
          updatedAt: updatedAt,
          displayName: drift.Value(displayName),
          avatarMimeType: drift.Value(avatar?.mimeType),
          avatarBytes: drift.Value(avatar?.bytes),
          timeZoneId: drift.Value(displayTimeZoneId),
          pendingSave: drift.Value(pendingSave),
          syncError: drift.Value(syncError),
          editSequence: drift.Value(editSequence),
          pendingTimeZoneUpload: drift.Value(pendingTimeZoneUpload),
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
      displayTimeZoneId: row.timeZoneId,
      updatedAt: row.updatedAt,
      hasPendingSave: row.pendingSave,
      syncError: row.syncError,
      editSequence: row.editSequence,
      pendingTimeZoneUpload: row.pendingTimeZoneUpload,
    );
  }

  /// 失效在途操作：dispose 之后到达的读取或上传应答不再写回本机资料。
  @override
  Future<void> dispose() async {
    _disposed = true;
  }
}
