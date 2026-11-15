// Isolated Windows acceptance fixture for ordinary schedule reminders (ticket 06).
//
// It never touches user data: memory database, fake account, its own AUMID and
// a unique output file chosen by the runner. The product registration is never
// reused, so a fixture reminder cannot appear as a real Pacta reminder.
//
// Build: flutter build windows -t tool/schedule_reminder_fixture/main.dart
// Run:   tool/schedule_reminder_fixture/run.py --mode exit|logout|reschedule
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:pacta/src/notifications/focus_device_preferences.dart';
import 'package:pacta/src/notifications/focus_notification_service.dart';
import 'package:pacta/src/notifications/schedule_reminder_sync.dart';
import 'package:pacta/src/notifications/windows_notification_adapter.dart';
import 'package:pacta/src/schedules/schedule_models.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

const fixtureAppName = 'Pacta Reminder Fixture';
const fixtureAppUserModelId = 'Pacta.Validation.Schedule06';
const fixtureGuid = '0b6f1c55-9b1a-4f21-9c9d-3c76a1e7b210';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final options = _FixtureOptions.parse(args);
  final startedAtUtc = DateTime.now().toUtc();
  final identity = WindowsNotificationIdentity(
    appName: options.appName,
    appUserModelId: options.aumid,
    guid: fixtureGuid,
  );
  final report = <String, Object?>{
    'pid': pid,
    'mode': options.mode,
    'exe': Platform.resolvedExecutable,
    'appUserModelId': identity.appUserModelId,
    'startedAtUtc': startedAtUtc.toIso8601String(),
  };
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final output = File(options.output);
  if (await output.exists()) {
    stderr.writeln('refusing to overwrite ${options.output}');
    exit(2);
  }
  final database = PactaDatabase(NativeDatabase.memory());
  final repository = LocalScheduleRepository(
    database: database,
    userId: 'fixture-user',
  );
  final adapter = LocalNotificationsWindowsAdapter(identity: identity);
  final service = FocusNotificationService(
    preferencesStore: FocusDevicePreferencesStore(
      await SharedPreferences.getInstance(),
    ),
    windowsNotifications: adapter,
  );
  final sync = ScheduleReminderSync(
    notificationService: service,
    accountTimeZoneId: () async => 'Etc/UTC',
  );
  var exitCode = 0;
  try {
    report['initialized'] = await adapter.initialize();
    await service.updatePreferences(
      const FocusDevicePreferences(
        notificationsEnabled: true,
        backgroundRunningEnabled: false,
      ),
    );
    // The fixture owns a fake account: binding it is what makes logout and
    // account isolation observable, exactly like the shell's owner binding.
    await service.setUserId('fixture-user');
    final clock = DateTime.now().toUtc();
    final created = await repository.createSchedule(
      ScheduleDraft(
        title: '隔离日程提醒 ${options.marker}',
        window: ScheduleWindow.timed(
          startsAt: clock.add(
            Duration(
              seconds: options.dueInSeconds + options.offsetMinutes * 60,
            ),
          ),
          endsAt: clock.add(
            Duration(
              seconds: options.dueInSeconds + options.offsetMinutes * 60 + 600,
            ),
          ),
        ),
      ),
    );
    await repository.setScheduleReminder(
      created.id,
      minutesBefore: options.offsetMinutes,
    );
    await sync.attach(repository);
    await _settle(sync);

    report['dueAtUtc'] = clock
        .add(Duration(seconds: options.dueInSeconds))
        .toIso8601String();
    report['pending'] = await adapter.pendingIds();
    report['scheduledIds'] = (await adapter.pendingIds()).length;

    switch (options.mode) {
      case 'logout':
        await service.releaseUser('fixture-user');
        report['pendingAfterLogout'] = await adapter.pendingIds();
        await _settle(sync);
      case 'reschedule':
        final moved = created.copyWith(
          startsAt: clock.add(const Duration(minutes: 40)),
          endsAt: clock.add(const Duration(minutes: 50)),
        );
        await repository.rescheduleSchedule(moved.id, moved.window);
        await _settle(sync);
        report['rescheduledAtUtc'] = moved.startsAt.toIso8601String();
        report['pendingAfterReschedule'] = await adapter.pendingIds();
      default:
        // Ordinary exit: stop this process's listeners, keep the OS queue.
        await service.detachForProcessExit();
        report['pendingAtExit'] = await adapter.pendingIds();
    }
  } catch (error) {
    exitCode = 1;
    report['error'] = error.toString();
  } finally {
    report['finishedAtUtc'] = DateTime.now().toUtc().toIso8601String();
    await output.parent.create(recursive: true);
    await output.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
    );
    stdout.writeln(
      jsonEncode({'output': options.output, 'mode': options.mode}),
    );
    await sync.detach();
    await service.dispose();
    await repository.dispose();
    await database.close();
  }
  exit(exitCode);
}

Future<void> _settle(ScheduleReminderSync sync) async {
  for (var attempt = 0; attempt < 40; attempt += 1) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sync.settled;
  }
}

class _FixtureOptions {
  const _FixtureOptions({
    required this.mode,
    required this.output,
    required this.dueInSeconds,
    required this.offsetMinutes,
    required this.marker,
    required this.aumid,
    required this.appName,
  });

  final String mode;
  final String output;
  final int dueInSeconds;
  final int offsetMinutes;
  final String marker;
  final String aumid;
  final String appName;

  static _FixtureOptions parse(List<String> args) {
    final values = <String, String>{};
    for (final arg in args) {
      if (!arg.startsWith('--')) continue;
      final separator = arg.indexOf('=');
      if (separator <= 2) continue;
      values[arg.substring(2, separator)] = arg.substring(separator + 1);
    }
    return _FixtureOptions(
      mode: values['mode'] ?? 'exit',
      output: values['output'] ?? '',
      dueInSeconds: int.tryParse(values['due'] ?? '') ?? 90,
      offsetMinutes: int.tryParse(values['offset'] ?? '') ?? 30,
      marker: values['marker'] ?? 'default',
      aumid: values['aumid'] ?? fixtureAppUserModelId,
      appName: values['app-name'] ?? fixtureAppName,
    );
  }
}
