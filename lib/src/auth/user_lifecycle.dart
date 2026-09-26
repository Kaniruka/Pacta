import 'package:drift/drift.dart';

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
  });

  final AuthRepository authRepository;
  final PactaDatabase database;
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

  Future<bool> purgeUserIfConfirmed(String oldUserId) async {
    if (oldUserId.isEmpty) return false;
    final receipt = await authRepository.lookupPurgeReceipt(oldUserId);
    if (receipt == null || !receipt.confirmsPurgedUser(oldUserId)) return false;
    return database.purgeUserDataForReceipt(
      userId: oldUserId,
      receipt: receipt,
    );
  }

  Future<int> _purgeLocallyConfirmedUsers() async {
    final userIds = await database.localUserIdsWithData();
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
