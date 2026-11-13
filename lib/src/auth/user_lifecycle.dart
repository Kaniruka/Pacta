import 'package:drift/drift.dart';

import '../sync/cloud_auto_upload_preference.dart';
import '../sync/cloud_auto_upload_queue.dart';
import '../tasks/task_database.dart';
import 'auth_repository.dart';
import 'user_lifecycle_models.dart';

abstract interface class UserLifecycleAccess {
  Future<bool> isSuspended();
  Future<void> requireActive();
}

class UserOperationsSuspendedException implements Exception {
  const UserOperationsSuspendedException();

  @override
  String toString() => '用户已停用，恢复前不能创建或修改业务数据。';
}

class AlwaysActiveUserLifecycleAccess implements UserLifecycleAccess {
  const AlwaysActiveUserLifecycleAccess();

  @override
  Future<bool> isSuspended() async => false;

  @override
  Future<void> requireActive() async {}
}

class LocalUserLifecycleAccess implements UserLifecycleAccess {
  LocalUserLifecycleAccess({required this.database, required this.userId});

  final PactaDatabase database;
  final String userId;

  Future<UserLifecycleStatus?> readStatus() async {
    final row = await (database.select(
      database.localUserLifecycleStates,
    )..where((state) => state.userId.equals(userId))).getSingleOrNull();
    return row == null ? null : _statusFromRow(row);
  }

  Stream<UserLifecycleStatus?> watchStatus() async* {
    final query = database.select(database.localUserLifecycleStates)
      ..where((state) => state.userId.equals(userId));
    await for (final rows in query.watch()) {
      final row = rows.isEmpty ? null : rows.single;
      yield row == null ? null : _statusFromRow(row);
    }
  }

  UserLifecycleStatus _statusFromRow(LocalUserLifecycleState row) =>
      UserLifecycleStatus(
        isSuspended: row.isSuspended,
        suspendedAt: row.suspendedAt,
        purgeEligibleAt: row.purgeEligibleAt,
        isEligibleForPurge: row.isEligibleForPurge,
        checkedAt: row.checkedAt,
      );

  Future<void> saveStatus(UserLifecycleStatus status) async {
    await database
        .into(database.localUserLifecycleStates)
        .insertOnConflictUpdate(
          LocalUserLifecycleStatesCompanion.insert(
            userId: userId,
            isSuspended: Value(status.isSuspended),
            suspendedAt: Value(status.suspendedAt),
            purgeEligibleAt: Value(status.purgeEligibleAt),
            isEligibleForPurge: Value(status.isEligibleForPurge),
            checkedAt: status.checkedAt,
          ),
        );
  }

  @override
  Future<bool> isSuspended() async =>
      (await readStatus())?.isSuspended ?? false;

  @override
  Future<void> requireActive() async {
    if (await isSuspended()) throw const UserOperationsSuspendedException();
  }
}

abstract interface class UserLifecycleStatusRepository {
  Future<UserLifecycleStatus?> readCachedStatus();
  Stream<UserLifecycleStatus?> watchStatus();
  Future<UserLifecycleStatus> refresh();
}

class UserLifecycleRepository implements UserLifecycleStatusRepository {
  const UserLifecycleRepository({
    required this.authRepository,
    required this.localAccess,
  });

  final AuthRepository authRepository;
  final LocalUserLifecycleAccess localAccess;

  @override
  Future<UserLifecycleStatus?> readCachedStatus() => localAccess.readStatus();

  @override
  Stream<UserLifecycleStatus?> watchStatus() => localAccess.watchStatus();

  @override
  Future<UserLifecycleStatus> refresh() async {
    final status = await authRepository.getCurrentUserLifecycle();
    await localAccess.saveStatus(status);
    return status;
  }

  Future<List<ManagedUserLifecycle>> listUsers() =>
      authRepository.listUserLifecycles();

  Future<void> suspendUser(String userId) async {
    await authRepository.suspendUser(userId);
  }

  Future<void> restoreUser(String userId) async {
    await authRepository.restoreUser(userId);
  }

  Future<bool> purgeLocalDataIfConfirmed(String oldUserId) async {
    return UserPurgeCleanupRepository(
      authRepository: authRepository,
      database: localAccess.database,
    ).purgeUserIfConfirmed(oldUserId);
  }
}

/// Checks receipts for every UUID still present in local business tables.
/// This deliberately does not depend on the currently authenticated user so
/// offline data remains discoverable after Auth removes the old session.
class UserPurgeCleanupRepository {
  UserPurgeCleanupRepository({
    required this.authRepository,
    required this.database,
    this.queueStore = const SharedPreferencesCloudAutoUploadQueueStore(),
    this.autoUploadPreference = const CloudAutoUploadPreference(),
  });

  final AuthRepository authRepository;
  final PactaDatabase database;

  /// 自动上传队列里暂存着整份业务快照；账号清除必须一起删掉，
  /// 否则已清除用户的业务数据还会留在本机偏好里。
  final CloudAutoUploadQueueStore queueStore;
  final CloudAutoUploadPreference autoUploadPreference;
  Future<int>? _inFlight;

  Future<int> purgeLocallyConfirmedUsers() async {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;

    final operation = _purgeLocallyConfirmedUsers();
    _inFlight = operation;
    try {
      return await operation;
    } finally {
      if (identical(_inFlight, operation)) _inFlight = null;
    }
  }

  /// 只有 receipt 确认已清除时才动手；先删本机自动上传状态（含冻结载荷），
  /// 再删业务表。任一步失败都会抛出，receipt 仍在，下次运行继续重试；
  /// 全程只处理 [oldUserId]，不跨用户清理。
  Future<bool> purgeUserIfConfirmed(String oldUserId) async {
    if (oldUserId.isEmpty) return false;
    final receipt = await authRepository.lookupPurgeReceipt(oldUserId);
    if (receipt == null || !receipt.confirmsPurgedUser(oldUserId)) return false;
    final queueBefore = await queueStore.load(oldUserId);
    await queueStore.clear(oldUserId);
    await autoUploadPreference.clear(oldUserId);
    final purgedRows = await database.purgeUserDataForReceipt(
      userId: oldUserId,
      receipt: receipt,
    );
    return purgedRows ||
        queueBefore.hasWork ||
        queueBefore.blockedReason != null;
  }

  Future<int> _purgeLocallyConfirmedUsers() async {
    // 业务表可能已被清除，但队列里还留着该用户的冻结载荷；
    // 只按数据库枚举会漏掉这种只剩队列的旧 UUID。
    final userIds = {
      ...await database.localUserIdsWithData(),
      ...await queueStore.userIds(),
    };
    var purgedCount = 0;
    for (final userId in userIds) {
      if (await purgeUserIfConfirmed(userId)) purgedCount++;
    }
    return purgedCount;
  }
}

class UnavailableUserLifecycleStatusRepository
    implements UserLifecycleStatusRepository {
  const UnavailableUserLifecycleStatusRepository();

  @override
  Future<UserLifecycleStatus?> readCachedStatus() async => null;

  @override
  Stream<UserLifecycleStatus?> watchStatus() => Stream.value(null);

  @override
  Future<UserLifecycleStatus> refresh() async =>
      throw StateError('尚未配置 Supabase。请使用 --dart-define-from-file=.env 启动。');
}
