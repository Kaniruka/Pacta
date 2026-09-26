import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/auth/user_lifecycle_models.dart';

void main() {
  test('only a completed receipt for the old identity authorizes cleanup', () {
    final completed = UserPurgeReceipt.fromJson({
      'user_id': 'old-user-id',
      'status': 'completed',
      'purged_at': '2026-09-26T05:00:00Z',
    });
    final pending = UserPurgeReceipt.fromJson({
      'user_id': 'old-user-id',
      'status': 'pending',
      'purged_at': null,
    });

    expect(completed.confirmsPurgedUser('old-user-id'), isTrue);
    expect(completed.confirmsPurgedUser('new-user-id'), isFalse);
    expect(pending.confirmsPurgedUser('old-user-id'), isFalse);
  });

  test('a completed response without a purge time is not authorization', () {
    final incomplete = UserPurgeReceipt.fromJson({
      'user_id': 'old-user-id',
      'status': 'completed',
      'purged_at': null,
    });

    expect(incomplete.confirmsPurgedUser('old-user-id'), isFalse);
  });
}
