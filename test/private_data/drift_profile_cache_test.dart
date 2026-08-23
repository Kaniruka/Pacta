import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/auth/auth_session.dart';
import 'package:pacta/private_data/app_database.dart';
import 'package:pacta/private_data/profile_cache.dart';
import 'package:pacta/private_data/user_profile.dart';

void main() {
  test('Drift profile cache isolates records by User', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final cache = DriftProfileCache(database);
    final timestamp = DateTime.utc(2026, 8, 24, 9);

    await cache.write(
      UserProfile(
        userId: const AppUserId('user-a'),
        displayName: 'Alpha',
        updatedAt: timestamp,
      ),
    );
    await cache.write(
      UserProfile(
        userId: const AppUserId('user-b'),
        displayName: 'Beta',
        updatedAt: timestamp,
      ),
    );

    expect(
      await cache.read(const AppUserId('user-a')),
      UserProfile(
        userId: const AppUserId('user-a'),
        displayName: 'Alpha',
        updatedAt: timestamp,
      ),
    );
    expect(
      await cache.read(const AppUserId('user-b')),
      UserProfile(
        userId: const AppUserId('user-b'),
        displayName: 'Beta',
        updatedAt: timestamp,
      ),
    );
    expect(await cache.read(const AppUserId('user-c')), isNull);
  });
}
