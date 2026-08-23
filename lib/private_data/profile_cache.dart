import 'package:drift/drift.dart';
import 'package:pacta/auth/auth_session.dart';
import 'package:pacta/private_data/app_database.dart';
import 'package:pacta/private_data/user_profile.dart';

abstract interface class ProfileCache {
  Future<UserProfile?> read(AppUserId userId);

  Future<void> write(UserProfile profile);
}

class DriftProfileCache implements ProfileCache {
  DriftProfileCache(this._database);

  final AppDatabase _database;

  @override
  Future<UserProfile?> read(AppUserId userId) async {
    final query = _database.select(_database.cachedProfiles)
      ..where((row) => row.userId.equals(userId.value));
    final row = await query.getSingleOrNull();
    if (row == null) return null;

    return UserProfile(
      userId: AppUserId(row.userId),
      displayName: row.displayName,
      updatedAt: row.updatedAt.toUtc(),
    );
  }

  @override
  Future<void> write(UserProfile profile) {
    return _database
        .into(_database.cachedProfiles)
        .insertOnConflictUpdate(
          CachedProfilesCompanion.insert(
            userId: profile.userId.value,
            displayName: Value(profile.displayName),
            updatedAt: profile.updatedAt,
          ),
        );
  }
}
