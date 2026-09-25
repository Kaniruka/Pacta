import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/src/calendar/calendar_models.dart';
import 'package:pacta/src/calendar/calendar_provider.dart';
import 'package:pacta/src/calendar/calendar_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets(
    'T20 Android Calendar Provider grants read-only access and imports selected sources',
    (tester) async {
      final database = PactaDatabase(NativeDatabase.memory());
      final repository = LocalCalendarRepository(
        database: database,
        userId: 't20-android-device-check',
        provider: const AndroidCalendarProvider(),
        remote: InMemoryCalendarRemote(),
      );
      try {
        final state = await tester.runAsync(repository.requestAccess);
        expect(state, isNotNull);
        expect(state!.permission, CalendarPermissionState.granted);
        expect(state.availableSources, isNotEmpty);

        final result = await tester.runAsync(
          () => repository.importCalendars(
            state.availableSources.map((source) => source.id).toSet(),
          ),
        );
        expect(result, isNotNull);
        expect(result!.synced, isTrue);

        final afterImport = await tester.runAsync(repository.loadImportState);
        expect(afterImport, isNotNull);
        expect(
          afterImport!.importedSources.map((source) => source.id).toSet(),
          state.availableSources.map((source) => source.id).toSet(),
        );
        final today = DateTime.now();
        final agenda = await tester.runAsync(
          () => repository.getAgenda(
            from: DateTime(
              today.year,
              today.month,
              today.day,
            ).subtract(const Duration(days: 30)),
            to: DateTime(
              today.year,
              today.month,
              today.day,
            ).add(const Duration(days: 91)),
          ),
        );
        expect(agenda, isNotNull);
        expect(agenda!.blocks.length, result.importedOccurrences);
      } finally {
        await repository.dispose();
        await database.close();
      }
    },
  );
}
