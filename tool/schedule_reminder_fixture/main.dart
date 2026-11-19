// Isolated Windows acceptance fixture for ordinary schedule reminders (ticket 06).
//
// Isolation: memory database, fake account, a per-run test AUMID/GUID and a
// unique output file chosen by the runner. It never reads user data and never
// registers under the product AUMID.
//
// Build: flutter build windows --release -t tool/schedule_reminder_fixture/main.dart
// Run:   PACTA_TEST_NOTIFICATION_AUMID=<Pacta.Test.*> tool/schedule_reminder_fixture/run.py
//
// The identity is chosen by the runner before Dart starts, so it travels in
// PACTA_TEST_NOTIFICATION_AUMID. Only Pacta.Test.* is accepted there; the
// product identity can never be replaced from outside the process.
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/auth/auth_repository.dart';
import 'package:pacta/src/auth/user_lifecycle_models.dart';
import 'package:pacta/src/notifications/focus_device_preferences.dart';
import 'package:pacta/src/notifications/focus_notification_service.dart';
import 'package:pacta/src/notifications/schedule_reminder_plan.dart';
import 'package:pacta/src/notifications/schedule_reminder_sync.dart';
import 'package:pacta/src/notifications/windows_notification_adapter.dart';
import 'package:pacta/src/plan/plan_calendar_view.dart';
import 'package:pacta/src/schedules/schedule_models.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

const fixtureBuildMarker = 'schedule06-fixture-v3';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // The shell launches the executable with its own activation switch after a
  // notification click; there is no fixture argument in that launch.
  final activationLaunch = args.any(
    (argument) => argument.contains('AppNotificationActivated'),
  );
  final options = _FixtureOptions.parse(args);
  final startedAtUtc = DateTime.now().toUtc();
  final report = <String, Object?>{
    'pid': pid,
    'mode': options.mode,
    'exe': Platform.resolvedExecutable,
    'appUserModelId': options.aumid,
    'aumid': options.aumid,
    'marker': options.marker,
    'fixtureBuildMarker': fixtureBuildMarker,
    'startedAtUtc': startedAtUtc.toIso8601String(),
  };
  final output = File(
    options.output.isEmpty
        ? '${Directory.systemTemp.path}${Platform.pathSeparator}'
              'pacta-notification-activation${Platform.pathSeparator}'
              '${options.aumid}-$pid.json'
        : options.output,
  );
  if (await output.exists()) {
    if (!activationLaunch) {
      stderr.writeln('refusing an existing output path');
      exit(2);
    }
    await output.delete();
  }
  if (!options.aumid.startsWith('Pacta.Test.')) {
    report['error'] = 'refusing a non-test AUMID';
    await _write(output, report);
    exit(3);
  }
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});

  // A cold activation opens a second process with no arguments; it can only
  // see the arrangement the scheduling run wrote if that run used the same
  // file database.
  final persistentDatabase = activationLaunch || options.mode != 'cleanup';
  final database = persistentDatabase
      ? PactaDatabase(
          NativeDatabase(
            File(
              '${Directory.systemTemp.path}${Platform.pathSeparator}'
              'pacta-fixture-db${Platform.pathSeparator}${options.aumid}.sqlite',
            )..parent.createSync(recursive: true),
          ),
        )
      : PactaDatabase(NativeDatabase.memory());
  final repository = LocalScheduleRepository(
    database: database,
    userId: 'fixture-user',
  );
  final adapter = RunnerWindowsNotificationAdapter(
    identity: WindowsNotificationIdentity(
      appName: 'Pacta Reminder Fixture',
      appUserModelId: options.aumid,
    ),
  );
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
  if (activationLaunch) {
    var exitCode = 0;
    final clicks = <ScheduleReminderRequest>[];
    final subscription = service.openScheduleRequests.listen(clicks.add);
    try {
      report['activationLaunch'] = true;
      report['initialized'] = await adapter.initialize();
      report['registeredAumid'] = adapter.registeredAumid;
      report['identitySource'] = adapter.identitySource;
      await service.updatePreferences(
        const FocusDevicePreferences(
          notificationsEnabled: true,
          backgroundRunningEnabled: false,
        ),
      );
      await service.setUserId('fixture-user');
      runApp(
        PactaApp(
          authRepository: _FixtureAuthRepository(),
          focusNotificationService: service,
          scheduleRepositoryFactory: (_) => repository,
        ),
      );
      final shell = await _waitForElement((widget) => widget is AppShell);
      report['shellMounted'] = shell != null;
      final payloadArrived = await _waitForCondition(
        () => clicks.isNotEmpty,
        attempts: 400,
      );
      report['clickPayload'] = clicks.isEmpty ? null : clicks.first.toPayload();
      final planOpened = await _waitForCondition(
        () => _findElement((widget) => widget is PlanCalendarView) != null,
        attempts: 100,
      );
      report['planOpened'] = planOpened;
      if (!payloadArrived) exitCode = 3;
    } catch (error) {
      exitCode = 1;
      report['error'] = error.toString();
    } finally {
      await subscription.cancel();
      report['finishedAtUtc'] = DateTime.now().toUtc().toIso8601String();
      await _write(output, report);
      stdout.writeln(
        jsonEncode({
          'output': output.path,
          'mode': 'activation',
          'payload': report['clickPayload'],
          'planOpened': report['planOpened'],
        }),
      );
    }
    exit(exitCode);
  }
  var exitCode = 0;
  try {
    report['initialized'] = await adapter.initialize();
    // The bridge, not this fixture, decides which identity the process
    // registered; record what it actually says.
    report['registeredAumid'] = adapter.registeredAumid;
    report['identitySource'] = adapter.identitySource;
    if (report['initialized'] != true) {
      throw StateError('notification initialization failed');
    }
    await service.updatePreferences(
      const FocusDevicePreferences(
        notificationsEnabled: true,
        backgroundRunningEnabled: false,
      ),
    );
    await service.setUserId('fixture-user');

    // Drift stores DateTimes at whole-second precision, so the fixture clock is
    // aligned before it becomes an event start. A sub-second clock would make
    // the read-back plan differ from the fixture's arithmetic for storage
    // reasons only.
    final clock = _secondAligned(DateTime.now().toUtc());
    final startsAt = clock.add(
      Duration(seconds: options.dueInSeconds + options.offsetMinutes * 60),
    );
    final created = await repository.createSchedule(
      ScheduleDraft(
        title: '隔离日程提醒 ${options.marker}',
        window: ScheduleWindow.timed(
          startsAt: startsAt,
          endsAt: startsAt.add(const Duration(minutes: 10)),
        ),
      ),
    );
    await repository.setScheduleReminder(
      created.id,
      minutesBefore: options.offsetMinutes,
    );
    await sync.attach(repository);
    // The production planner is the authority for id, instant and payload: the
    // runner must not infer them from the fixture's own arithmetic.
    final expectedDue = clock.add(Duration(seconds: options.dueInSeconds));
    final planned = await _plannedReminder(repository, scheduleId: created.id);
    if (!planned.deliverAt.isAtSameMomentAs(expectedDue)) {
      throw StateError(
        'planner due ${planned.deliverAt} != expected $expectedDue',
      );
    }
    report['scheduleId'] = created.id;
    report['startUtc'] = startsAt.toIso8601String();
    report['dueAtUtc'] = expectedDue.toIso8601String();
    report['plannedDueAtUtc'] = planned.deliverAt.toIso8601String();
    report['plannedNotificationId'] = planned.notificationId;
    report['plannedPayload'] = planned.payload;
    report['plannedDateKey'] = planned.dateKey;
    report['plannedIdentity'] = planned.identity;
    await _waitForNotification(adapter, planned.notificationId);
    final pending = await adapter.pendingIds();
    report['pending'] = pending;
    if (!pending.contains(planned.notificationId)) {
      throw StateError(
        'planned notification ${planned.notificationId} is not queued',
      );
    }

    // Dart 3 switch cases never fall through: every branch below is exclusive
    // and ends explicitly so the control flow is not misread.
    switch (options.mode) {
      case 'logout':
        final beforeLogout = await adapter.pendingIds();
        report['pendingBeforeLogout'] = beforeLogout;
        if (!beforeLogout.contains(planned.notificationId)) {
          throw StateError('logout started without a queued reminder');
        }
        await service.releaseUser('fixture-user');
        report['pendingAfterLogout'] = await _waitForQueue(
          adapter,
          (ids) => ids.isEmpty,
        );
        // Bounded quiescence window: a late registration must not resurrect
        // the signed-out queue after the cancellation reported success.
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        report['pendingAfterLogoutSettled'] = await adapter.pendingIds();
        break;
      case 'reschedule':
        // Keep the same reminder offset: the new delivery instant is the new
        // event start minus that offset, not the event start itself.
        final movedDue = clock.add(
          Duration(
            seconds: options.dueInSeconds + options.rescheduleDelaySeconds,
          ),
        );
        final movedStart = movedDue.add(
          Duration(minutes: options.offsetMinutes),
        );
        report['oldDueAtUtc'] = planned.deliverAt.toIso8601String();
        report['rescheduledStartUtc'] = movedStart.toIso8601String();
        await repository.rescheduleSchedule(
          created.id,
          ScheduleWindow.timed(
            startsAt: movedStart,
            endsAt: movedStart.add(const Duration(minutes: 10)),
          ),
        );
        // A one-shot read is the completion condition: waiting on the
        // subscription's first event would return before any replan.
        await sync.reconcileOnce();
        final moved = await _plannedReminder(
          repository,
          scheduleId: created.id,
        );
        if (!moved.deliverAt.isAtSameMomentAs(movedDue)) {
          throw StateError(
            'rescheduled due ${moved.deliverAt} != expected $movedDue',
          );
        }
        report['newDueAtUtc'] = moved.deliverAt.toIso8601String();
        report['newPlannedNotificationId'] = moved.notificationId;
        report['newPlannedPayload'] = moved.payload;
        report['pendingAfterReschedule'] = await _waitForQueue(
          adapter,
          (ids) => ids.length == 1 && ids.contains(moved.notificationId),
        );
        // Quiescence re-read: a late registration must not add a second item.
        await Future<void>.delayed(const Duration(milliseconds: 800));
        report['pendingAfterRescheduleSettled'] = await adapter.pendingIds();
        break;
      case 'shell':
        final auth = _FixtureAuthRepository();
        runApp(
          PactaApp(
            authRepository: auth,
            focusNotificationService: service,
            scheduleRepositoryFactory: (_) => repository,
          ),
        );
        // The shell must really mount and bind the same owner before any queue
        // claim is meaningful.
        final shell = await _waitForElement((widget) => widget is AppShell);
        report['shellMounted'] = shell != null;
        if (shell == null) throw StateError('AppShell did not mount');
        final ownerBound = await _waitForCondition(
          () => service.ownerUserId == 'fixture-user',
        );
        report['authUserId'] = auth.currentUserId;
        report['serviceOwnerUserId'] = service.ownerUserId;
        if (!ownerBound) {
          throw StateError(
            'reminder owner did not bind to the fixture account',
          );
        }
        report['shellDependencies'] = _dependencyEvidence(shell);
        await _waitForNotification(adapter, planned.notificationId);
        report['pendingBeforeUnmount'] = await adapter.pendingIds();
        // Replacing the tree disposes AppShell exactly like the product shell.
        runApp(const SizedBox());
        report['pendingAfterShellUnmount'] = await _waitForQueue(
          adapter,
          (ids) => ids.contains(planned.notificationId),
        );
        // Dispose is asynchronous; re-read after it settles so a late cancel
        // cannot be mistaken for preservation.
        await Future<void>.delayed(const Duration(milliseconds: 800));
        report['pendingAfterShellUnmountSettled'] = await adapter.pendingIds();
        break;
      case 'click':
        final clicks = <ScheduleReminderRequest>[];
        final subscription = service.openScheduleRequests.listen(clicks.add);
        runApp(
          PactaApp(
            authRepository: _FixtureAuthRepository(),
            focusNotificationService: service,
            scheduleRepositoryFactory: (_) => repository,
          ),
        );
        final shell = await _waitForElement((widget) => widget is AppShell);
        report['shellMounted'] = shell != null;
        final arrived = await _waitForCondition(
          () => clicks.isNotEmpty,
          attempts: 1200,
        );
        report['clickPayload'] = clicks.isEmpty
            ? null
            : clicks.first.toPayload();
        final planOpened = await _waitForCondition(
          () => _findElement((widget) => widget is PlanCalendarView) != null,
          attempts: 100,
        );
        report['planOpened'] = planOpened;
        await subscription.cancel();
        if (!arrived) throw StateError('no notification click arrived');
        break;
      case 'cleanup':
        // Permanent deregistration is the only teardown that leaves no SDK
        // registration behind. The bridge requires a Pacta.Test.* identity and
        // the explicit runtime opt-in, so the product identity is unreachable.
        await adapter.unregisterAllForTestIdentity();
        report['unregisteredAll'] = true;
        report['pendingAfterCleanup'] = await _waitForQueue(
          adapter,
          (ids) => ids.isEmpty,
        );
        break;
      default:
        await service.detachForProcessExit();
        report['pendingAtDetach'] = await _waitForQueue(
          adapter,
          (ids) => ids.contains(planned.notificationId),
        );
        await Future<void>.delayed(const Duration(milliseconds: 800));
        report['pendingAfterDetachSettled'] = await adapter.pendingIds();
        break;
    }
  } catch (error) {
    exitCode = 1;
    report['error'] = error.toString();
  } finally {
    report['finishedAtUtc'] = DateTime.now().toUtc().toIso8601String();
    await _write(output, report);
    stdout.writeln(
      jsonEncode({'output': options.output, 'mode': options.mode}),
    );
  }
  exit(exitCode);
}

Future<void> _write(File output, Map<String, Object?> report) async {
  await output.parent.create(recursive: true);
  await output.writeAsString(
    const JsonEncoder.withIndent('  ').convert(report),
  );
}

/// Whole-second clock, matching the precision Drift persists.
DateTime _secondAligned(DateTime value) => DateTime.fromMillisecondsSinceEpoch(
  (value.millisecondsSinceEpoch ~/ 1000) * 1000,
  isUtc: true,
);

/// Waits until [done] accepts the OS queue, and returns the accepted list.
Future<List<int>> _waitForQueue(
  WindowsNotificationAdapter adapter,
  bool Function(List<int> ids) done,
) async {
  var last = const <int>[];
  for (var attempt = 0; attempt < 160; attempt += 1) {
    last = await adapter.pendingIds();
    if (done(last)) return last;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError('OS queue never reached the expected state: $last');
}

/// Waits until this run's planned id — not merely any id — is queued.
Future<void> _waitForNotification(WindowsNotificationAdapter adapter, int id) =>
    _waitForQueue(adapter, (ids) => ids.contains(id));

/// Polls [predicate] while the real app loop runs.
Future<bool> _waitForCondition(
  bool Function() predicate, {
  int attempts = 160,
}) async {
  for (var attempt = 0; attempt < attempts; attempt += 1) {
    if (predicate()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  return predicate();
}

/// Polls for a mounted element, returning it once the tree has built it.
Future<Element?> _waitForElement(
  bool Function(Widget widget) test, {
  int attempts = 160,
}) async {
  for (var attempt = 0; attempt < attempts; attempt += 1) {
    final found = _findElement(test);
    if (found != null) return found;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  return _findElement(test);
}

/// Finds the first mounted widget matching [test].
Element? _findElement(bool Function(Widget widget) test) {
  Element? found;
  void visit(Element element) {
    if (found != null) return;
    if (test(element.widget)) {
      found = element;
      return;
    }
    element.visitChildren(visit);
  }

  final root = WidgetsBinding.instance.rootElement;
  if (root != null) visit(root);
  return found;
}

/// Runtime types the shell resolved for dependencies the fixture did not wire.
///
/// Every omitted factory falls back to an Unavailable repository or null, so
/// this records the actual boundary instead of assuming it.
Map<String, String> _dependencyEvidence(Element context) {
  // The context must sit below the inherited scope ProviderScope installs, so
  // the mounted shell element is used rather than the scope element itself.
  final container = ProviderScope.containerOf(context, listen: false);
  String name(Object? value) => value?.runtimeType.toString() ?? 'null';
  String read(Object? Function() value) {
    try {
      return name(value());
    } catch (error) {
      return 'error:${error.runtimeType}';
    }
  }

  return {
    'taskRepository': read(() => container.read(taskRepositoryProvider)),
    'focusRepository': read(() => container.read(focusRepositoryProvider)),
    'nationalFocusRepository': read(
      () => container.read(nationalFocusRepositoryProvider),
    ),
    'calendarRepository': read(
      () => container.read(calendarRepositoryProvider),
    ),
    'profileRepository': read(() => container.read(profileRepositoryProvider)),
    'cloudSnapshotRepository': read(
      () => container.read(cloudSnapshotRepositoryProvider),
    ),
    'scheduleRepository': read(
      () => container.read(scheduleRepositoryProvider),
    ),
  };
}

/// The exact registration the production planner derives for [scheduleId].
///
/// This is the same planner the service uses, so a mismatch with the fixture's
/// own arithmetic is a real defect rather than a duplicated guess.
Future<ScheduleReminderPlan> _plannedReminder(
  LocalScheduleRepository repository, {
  required String scheduleId,
}) async {
  final now = DateTime.now().toUtc();
  final rows = await repository.getSchedules(
    from: now.subtract(const Duration(days: 2)),
    to: now.add(const Duration(days: 2)),
  );
  final plans = ScheduleReminderPlanner.plan(
    schedules: rows,
    now: now,
    timeZoneId: 'Etc/UTC',
    ownerId: _FixtureAuthRepository._userId,
  );
  return plans.singleWhere(
    (plan) => plan.scheduleId == scheduleId,
    orElse: () => throw StateError('no reminder plan for $scheduleId'),
  );
}

class _FixtureOptions {
  const _FixtureOptions({
    required this.mode,
    required this.output,
    required this.dueInSeconds,
    required this.offsetMinutes,
    required this.marker,
    required this.aumid,
    required this.rescheduleDelaySeconds,
  });

  final String mode;
  final String output;
  final int dueInSeconds;
  final int offsetMinutes;
  final String marker;
  final String aumid;
  final int rescheduleDelaySeconds;

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
      aumid:
          Platform.environment['PACTA_TEST_NOTIFICATION_AUMID'] ??
          _identityFileAumid() ??
          values['aumid'] ??
          'Pacta.Test.Schedule06.default',
      rescheduleDelaySeconds:
          int.tryParse(values['reschedule-delay'] ?? '') ?? 180,
    );
  }
}

/// The identity the runner used for this executable.
///
/// The runner resolves the notification identity before Dart starts, so a cold
/// activation (no fixture arguments, no inherited environment) learns it from
/// the same file the native side read.
String? _identityFileAumid() {
  try {
    final directory = File(Platform.resolvedExecutable).parent.path;
    final file = File(
      '$directory${Platform.pathSeparator}pacta_fixture_identity.json',
    );
    final text = file.readAsStringSync();
    final marker = RegExp(r'"aumid"\s*:\s*"([^"]+)"').firstMatch(text);
    final value = marker?.group(1);
    if (value != null && value.startsWith('Pacta.Test.')) return value;
  } catch (_) {
    // No identity file: fall back to the arguments.
  }
  return null;
}

/// Fixture-only account so the shell can mount without a cloud session.
class _FixtureAuthRepository implements AuthRepository {
  static const _userId = 'fixture-user';

  @override
  Stream<String?> get authState => const Stream<String?>.empty();

  @override
  String? get currentUserIdentifier => _userId;

  @override
  String? get currentUserId => _userId;

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signUp({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<bool> isAdministrator() async => false;

  @override
  Future<void> grantEligibility({required String email}) async {}

  @override
  Future<bool> revokeEligibility({required String email}) async => false;

  @override
  Future<void> adminResetUserPassword({
    required String targetEmail,
    required String newPassword,
    required bool manualVerificationConfirmed,
  }) async {}

  @override
  Future<UserLifecycleStatus> getCurrentUserLifecycle() async =>
      UserLifecycleStatus(
        isSuspended: false,
        checkedAt: DateTime.utc(2026, 11, 15),
      );

  @override
  Future<List<ManagedUserLifecycle>> listUserLifecycles() async => const [];

  @override
  Future<void> suspendUser(String userId) async {}

  @override
  Future<void> restoreUser(String userId) async {}

  @override
  Future<UserPurgeReceipt> purgeUser(String userId) async => UserPurgeReceipt(
    userId: userId,
    status: UserPurgeStatus.completed,
    purgedAt: DateTime.utc(2026, 11, 15),
  );

  @override
  Future<UserPurgeReceipt?> lookupPurgeReceipt(String oldUserId) async => null;
}
