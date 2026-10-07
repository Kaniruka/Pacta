import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/auth/user_lifecycle.dart';
import 'package:pacta/src/focus/chain_signals_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

void main() {
  test(
    'schema 23 upgrades with empty user signals and retains existing data',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'pacta-signals-upgrade-',
      );
      final file = File('${directory.path}/signals.sqlite');
      var database = PactaDatabase(NativeDatabase(file));
      try {
        await database.customStatement('SELECT 1 FROM chain_signals');
        await database.customStatement(
          "INSERT INTO focus_chain_records VALUES ('a', 'regular', 3, 4, 1)",
        );
        await database.customStatement('DROP TABLE chain_signals');
        await database.customStatement('PRAGMA user_version = 23');
        await database.close();
        database = PactaDatabase(NativeDatabase(file));
        expect(
          (await ChainSignalsRepository(
            database: database,
            userId: 'a',
          ).get()).regularFocusMarker,
          isEmpty,
        );
        expect(
          (await database.select(database.focusChainRecords).getSingle())
              .currentConsecutive,
          3,
        );
      } finally {
        await database.close();
        directory.deleteSync(recursive: true);
      }
    },
  );

  test('suspended users can read signals but cannot change them', () async {
    final database = PactaDatabase(NativeDatabase.memory());
    try {
      final repository = ChainSignalsRepository(
        database: database,
        userId: 'a',
        lifecycleAccess: _SuspendedAccess(),
      );
      expect((await repository.get()).eliteFocusMarker, isEmpty);
      await expectLater(
        repository.save(const ChainSignalTexts(eliteFocusMarker: '坐下')),
        throwsA(isA<UserOperationsSuspendedException>()),
      );
      expect((await repository.get()).eliteFocusMarker, isEmpty);
    } finally {
      await database.close();
    }
  });

  test(
    'persists independently for each user across reopening the database',
    () async {
      final directory = Directory.systemTemp.createTempSync('pacta-signals-');
      final file = File('${directory.path}/signals.sqlite');
      var database = PactaDatabase(NativeDatabase(file));
      try {
        final own = ChainSignalsRepository(database: database, userId: 'a');
        final other = ChainSignalsRepository(database: database, userId: 'b');
        expect((await own.get()).appointmentTriggerSignal, isEmpty);
        await own.save(
          const ChainSignalTexts(
            appointmentTriggerSignal: ' 戴耳机 ',
            eliteFocusMarker: '坐下',
            regularFocusMarker: '打开书',
          ),
        );
        expect((await other.get()).eliteFocusMarker, isEmpty);
        await other.save(const ChainSignalTexts(eliteFocusMarker: '关门'));
        await database.close();
        database = PactaDatabase(NativeDatabase(file));
        final restored = await ChainSignalsRepository(
          database: database,
          userId: 'a',
        ).get();
        expect(restored.appointmentTriggerSignal, '戴耳机');
        expect(restored.eliteFocusMarker, '坐下');
        expect(restored.regularFocusMarker, '打开书');
        expect(
          (await ChainSignalsRepository(
            database: database,
            userId: 'b',
          ).get()).eliteFocusMarker,
          '关门',
        );
      } finally {
        await database.close();
        directory.deleteSync(recursive: true);
      }
    },
  );
}

class _SuspendedAccess implements UserLifecycleAccess {
  @override
  Future<bool> isSuspended() async => true;

  @override
  Future<void> requireActive() async =>
      throw const UserOperationsSuspendedException();
}
