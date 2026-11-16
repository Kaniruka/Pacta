import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/schedules/schedule_models.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

void main() {
  late PactaDatabase database;
  late LocalScheduleRepository repository;

  setUp(() {
    database = PactaDatabase(NativeDatabase.memory());
    repository = LocalScheduleRepository(
      database: database,
      userId: 'reminder-user',
      now: () => DateTime.utc(2026, 11, 15, 1),
    );
  });

  tearDown(() async {
    await repository.dispose();
    await database.close();
  });

  test(
    'owning, reminding and completing a schedule never creates focus work',
    () async {
      final created = await repository.createSchedule(
        ScheduleDraft(
          title: '取快递',
          window: ScheduleWindow.timed(
            startsAt: DateTime.utc(2026, 11, 16, 10),
            endsAt: DateTime.utc(2026, 11, 16, 11),
          ),
        ),
      );
      await repository.setScheduleReminder(created.id, minutesBefore: 15);
      await repository.setScheduleCompletion(created.id, isCompleted: true);

      expect(await database.select(database.focusSessions).get(), isEmpty);
      expect(await database.select(database.focusAppointments).get(), isEmpty);
      expect(await database.select(database.focusNodes).get(), isEmpty);
      expect(await database.select(database.focusChainRecords).get(), isEmpty);
      expect(
        await database.select(database.appointmentChainRecords).get(),
        isEmpty,
      );
      expect(await database.select(database.chainSignals).get(), isEmpty);
    },
  );
}
