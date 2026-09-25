import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/src/calendar/calendar_models.dart';
import 'package:pacta/src/calendar/calendar_provider.dart';
import 'package:pacta/src/calendar/calendar_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:path_provider/path_provider.dart';

const _userId = 'ticket-21-permission-check';
const _sourceId = 'ticket-21-synthetic-source';
const _phase = String.fromEnvironment('T21_PERMISSION_PHASE');

// Run both phases with flutter drive --keep-app-running. Grant READ_CALENDAR
// after the seed marker, revoke it after seed completes, then run verify.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Android permission changes retain cached Calendar Blocks across restart',
    (tester) async {
      expect(_phase, anyOf('seed', 'verify'));
      final supportDirectory = await getApplicationSupportDirectory();
      final databaseFile = File(
        '${supportDirectory.path}${Platform.pathSeparator}'
        'pacta_ticket21_permission.sqlite',
      );
      if (_phase == 'seed' && databaseFile.existsSync()) {
        await databaseFile.delete();
      }
      if (_phase == 'verify') expect(databaseFile.existsSync(), isTrue);

      final now = DateTime.now().toUtc();
      final database = PactaDatabase(NativeDatabase(databaseFile));
      final provider = const AndroidCalendarProvider();
      final repository = LocalCalendarRepository(
        database: database,
        userId: _userId,
        provider: provider,
        remote: InMemoryCalendarRemote(),
        now: () => now,
      );
      addTearDown(() async {
        await repository.dispose();
        await database.close();
        if (_phase == 'verify' && databaseFile.existsSync()) {
          await databaseFile.delete();
        }
      });

      if (_phase == 'seed') {
        debugPrint('T21_PERMISSION_GRANT_NOW');
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 60)),
        );
        await database
            .into(database.localCalendarSources)
            .insert(
              LocalCalendarSourcesCompanion.insert(
                userId: _userId,
                sourceId: _sourceId,
                displayName: 'T21 合成权限验收来源',
                timeZoneId: 'Etc/UTC',
                isSelected: const Value(true),
                updatedAt: now,
              ),
            );
        await database
            .into(database.localCalendarBlocks)
            .insert(
              LocalCalendarBlocksCompanion.insert(
                userId: _userId,
                sourceId: _sourceId,
                sourceEventId: 'synthetic-event',
                occurrenceId: 'synthetic-occurrence',
                eventIdentity: 'synthetic-identity',
                title: 'T21 合成缓存活动',
                startsAt: now.add(const Duration(hours: 1)),
                endsAt: now.add(const Duration(hours: 2)),
                availability: CalendarAvailability.busy.name,
                timeZoneId: 'Etc/UTC',
                updatedAt: now,
              ),
            );

        final state = await repository.loadImportState();
        expect(databaseFile.existsSync(), isTrue);
        expect(state.permission, CalendarPermissionState.granted);
        expect(state.importedSources.single.id, _sourceId);
        expect(state.importedSources.single.isStale, isFalse);
        debugPrint('T21_PERMISSION_SEED_COMPLETE');
        return;
      }

      final state = await repository.loadImportState();
      final agenda = await repository.getAgenda(
        from: now.subtract(const Duration(days: 1)),
        to: now.add(const Duration(days: 1)),
      );
      expect(state.permission, CalendarPermissionState.denied);
      expect(state.importedSources.single.id, _sourceId);
      expect(state.importedSources.single.isStale, isTrue);
      expect(agenda.isStale, isTrue);
      expect(agenda.blocks.single.title, 'T21 合成缓存活动');
    },
    timeout: const Timeout(Duration(minutes: 3)),
    skip: _phase != 'seed' && _phase != 'verify',
  );
}
