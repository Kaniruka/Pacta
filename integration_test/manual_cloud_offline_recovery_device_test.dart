import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/calendar/calendar_models.dart';
import 'package:pacta/src/calendar/calendar_provider.dart';
import 'package:pacta/src/calendar/calendar_repository.dart';
import 'package:pacta/src/focus/focus_models.dart' as focus;
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/notifications/focus_notification_service.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../test/support/fake_auth_repository.dart';

const _phase = String.fromEnvironment('MANUAL_OFFLINE_PHASE');
const _runId = String.fromEnvironment('MANUAL_OFFLINE_RUN_ID');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets(
    'startup, offline edits, reconnect, resume, and process restart stay local',
    (tester) async {
      expect(_phase, anyOf('seed', 'verify'));
      expect(_runId, matches(RegExp(r'^[A-Za-z0-9_-]{8,48}$')));
      final supportDirectory = await getApplicationSupportDirectory();
      final databaseFile = File(
        '${supportDirectory.path}${Platform.pathSeparator}'
        'pacta-offline-recovery-$_runId.sqlite',
      );
      if (_phase == 'seed') {
        expect(
          databaseFile.existsSync(),
          isFalse,
          reason: 'The host supplies a unique test run id; existing data is never cleared.',
        );
      } else {
        expect(databaseFile.existsSync(), isTrue);
      }

      final database = PactaDatabase(NativeDatabase(databaseFile));
      final calls = _BusinessRemoteCalls();
      final taskRepository = LocalTaskRepository(
        database: database,
        userId: 'offline-test-$_runId',
        remote: _CountingTaskRemote(calls),
        cloudSyncEnabled: false,
      );
      final focusRepository = LocalFocusRepository(
        database: database,
        userId: 'offline-test-$_runId',
        remote: _CountingFocusRemote(calls),
        cloudSyncEnabled: false,
      );
      final nationalFocusRepository = LocalNationalFocusRepository(
        database: database,
        userId: 'offline-test-$_runId',
        remote: _CountingNationalFocusRemote(calls),
        cloudSyncEnabled: false,
      );
      final calendarRepository = LocalCalendarRepository(
        database: database,
        userId: 'offline-test-$_runId',
        provider: const UnsupportedCalendarProvider(),
        remote: _CountingCalendarRemote(calls),
        cloudSyncEnabled: false,
      );
      final snapshotRemote = _CountingCloudSnapshotRemote(calls);
      final snapshotRepository = CloudSnapshotRepository(
        database: database,
        remote: snapshotRemote,
        userId: 'offline-test-$_runId',
        deviceName: 'Android offline test double',
      );
      final lifecycleProbe = _LifecycleProbe();
      var lifecycleProbeAttached = false;

      try {
        if (_phase == 'seed') {
          final goal = await taskRepository.createGoal(
            const GoalDraft(
              title: 'Before offline transition',
              classification: TaskClassification.regular,
            ),
          );
          await taskRepository.createTask(
            goal.id,
            const TaskDraft(title: 'Baseline local task', classification: null),
          );
          final card = await nationalFocusRepository.createCard(
            const NationalFocusCardDraft(
              name: 'Before offline transition',
              triggerCondition: 'Before offline transition',
              action: 'Keep the existing rule',
            ),
          );
          await nationalFocusRepository.placeCard(
            cardId: card.id,
            parentId: null,
          );
        }

        await tester.pumpWidget(
          PactaApp(
            authRepository: FakeAuthRepository()
              ..signedInUser = 'offline-test-$_runId',
            focusNotificationService: DisabledFocusNotificationService(),
            taskRepositoryFactory: (_) => taskRepository,
            focusRepositoryFactory: (_) => focusRepository,
            nationalFocusRepositoryFactory: (_) => nationalFocusRepository,
            calendarRepositoryFactory: (_) => calendarRepository,
            cloudSnapshotRepositoryFactory: (_) => snapshotRepository,
          ),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 1)),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AppShell), findsOneWidget);
        expect(
          calls.total,
          0,
          reason: 'App startup must not contact a remote.',
        );

        if (_phase == 'seed') {
          debugPrint('MANUAL_OFFLINE_READY:$_runId');
          final offline = await tester.runAsync(
            () => _waitForConnectivity(offline: true),
          );
          expect(offline, contains(ConnectivityResult.none));
          snapshotRemote.available = false;
          debugPrint('MANUAL_OFFLINE_NETWORK_CONFIRMED:$_runId');

          final offlineGoal = await taskRepository.createGoal(
            const GoalDraft(
              title: 'Created while Android is offline',
              classification: TaskClassification.both,
            ),
          );
          await taskRepository.createTask(
            offlineGoal.id,
            const TaskDraft(
              title: 'Offline local task remains editable',
              classification: null,
            ),
          );
          final offlineCard = await nationalFocusRepository.createCard(
            const NationalFocusCardDraft(
              name: 'While Android is offline',
              triggerCondition: 'While Android is offline',
              action: 'Save the National Focus rule locally',
            ),
          );
          await nationalFocusRepository.placeCard(
            cardId: offlineCard.id,
            parentId: null,
          );
          await nationalFocusRepository.lightCard(offlineCard.id);
          expect(calls.total, 0);
          expect(
            (await taskRepository.getGoals()).any(
              (goal) => goal.title == 'Created while Android is offline',
            ),
            isTrue,
          );
          expect(
            (await nationalFocusRepository.getTreeCards()).any(
              (card) => card.triggerCondition == 'While Android is offline',
            ),
            isTrue,
          );
          debugPrint('MANUAL_OFFLINE_LOCAL_EDITS_SAVED:$_runId');

          final online = await tester.runAsync(
            () => _waitForConnectivity(offline: false),
          );
          expect(online, isNotEmpty);
          expect(online, isNot(contains(ConnectivityResult.none)));
          snapshotRemote.available = true;
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(seconds: 1)),
          );
          expect(calls.total, 0);
          debugPrint('MANUAL_OFFLINE_ONLINE_CONFIRMED:$_runId');
          WidgetsBinding.instance.addObserver(lifecycleProbe);
          lifecycleProbeAttached = true;
          debugPrint('MANUAL_OFFLINE_WAITING_FOR_RESUME:$_runId');
          await tester.runAsync(lifecycleProbe.waitForResume);
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(seconds: 1)),
          );
          expect(calls.total, 0);
          expect(
            (await taskRepository.getGoals()).any(
              (goal) => goal.title == 'Created while Android is offline',
            ),
            isTrue,
          );
          expect(
            (await nationalFocusRepository.getTreeCards()).any(
              (card) => card.triggerCondition == 'While Android is offline',
            ),
            isTrue,
          );
          debugPrint('MANUAL_OFFLINE_RECOVERY_VERIFIED:$_runId');
          debugPrint('MANUAL_OFFLINE_SEED_PHASE_COMPLETE:$_runId');
        } else {
          expect(calls.total, 0);
          final goals = await taskRepository.getGoals();
          expect(
            goals.any(
              (goal) => goal.title == 'Created while Android is offline',
            ),
            isTrue,
          );
          expect(
            (await nationalFocusRepository.getTreeCards()).any(
              (card) => card.triggerCondition == 'While Android is offline',
            ),
            isTrue,
          );
          expect(calls.total, 0);
          debugPrint('MANUAL_OFFLINE_RESTART_VERIFIED:$_runId');
        }
        expect(tester.takeException(), isNull);
      } finally {
        if (lifecycleProbeAttached) {
          WidgetsBinding.instance.removeObserver(lifecycleProbe);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await database.close();
        if (_phase == 'verify' && await databaseFile.exists()) {
          await databaseFile.delete();
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<List<ConnectivityResult>> _waitForConnectivity({
  required bool offline,
}) async {
  final connectivity = Connectivity();
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  while (DateTime.now().isBefore(deadline)) {
    final current = await connectivity.checkConnectivity();
    final isOffline =
        current.isEmpty || current.contains(ConnectivityResult.none);
    if (offline ? isOffline : !isOffline) return current;
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  throw TimeoutException(
    offline
        ? 'Android connectivity did not report offline.'
        : 'Android connectivity did not recover online.',
  );
}

class _LifecycleProbe extends WidgetsBindingObserver {
  final _resumed = Completer<void>();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_resumed.isCompleted) {
      _resumed.complete();
    }
  }

  Future<void> waitForResume() => _resumed.future.timeout(
    const Duration(seconds: 30),
    onTimeout: () => throw TimeoutException('Android app did not resume.'),
  );
}

class _BusinessRemoteCalls {
  int total = 0;
}

class _CountingTaskRemote implements TaskRemoteDataSource {
  _CountingTaskRemote(this.calls);

  final _BusinessRemoteCalls calls;

  @override
  Future<TaskRemoteSnapshot> pull({required String userId}) async {
    calls.total++;
    return const TaskRemoteSnapshot();
  }

  @override
  Future<void> upsertGoals({
    required String userId,
    required List<Goal> goals,
  }) async {
    calls.total++;
  }

  @override
  Future<void> upsertTasks({
    required String userId,
    required List<Task> tasks,
  }) async {
    calls.total++;
  }
}

class _CountingFocusRemote extends InMemoryFocusRemote {
  _CountingFocusRemote(this.calls);

  final _BusinessRemoteCalls calls;

  @override
  Future<FocusRemoteSnapshot> pull({required String userId}) {
    calls.total++;
    return super.pull(userId: userId);
  }

  @override
  Future<void> upsertSessions({
    required String userId,
    required List<focus.FocusSession> sessions,
  }) {
    calls.total++;
    return super.upsertSessions(userId: userId, sessions: sessions);
  }

  @override
  Future<void> upsertAppointments({
    required String userId,
    required List<focus.AppointmentPreparation> appointments,
  }) {
    calls.total++;
    return super.upsertAppointments(userId: userId, appointments: appointments);
  }

  @override
  Future<void> upsertNodes({
    required String userId,
    required List<focus.FocusNode> nodes,
  }) {
    calls.total++;
    return super.upsertNodes(userId: userId, nodes: nodes);
  }

  @override
  Future<void> deleteNodes({
    required String userId,
    required List<String> sessionIds,
  }) {
    calls.total++;
    return super.deleteNodes(userId: userId, sessionIds: sessionIds);
  }

  @override
  Future<void> upsertRecords({
    required String userId,
    required List<focus.FocusChainRecord> records,
  }) {
    calls.total++;
    return super.upsertRecords(userId: userId, records: records);
  }

  @override
  Future<void> upsertAppointmentRecords({
    required String userId,
    required List<focus.AppointmentChainRecord> records,
  }) {
    calls.total++;
    return super.upsertAppointmentRecords(userId: userId, records: records);
  }

  @override
  Future<void> upsertPrecedentRules({
    required String userId,
    required List<focus.PrecedentRule> rules,
  }) {
    calls.total++;
    return super.upsertPrecedentRules(userId: userId, rules: rules);
  }

  @override
  Future<void> upsertSources({
    required String userId,
    required List<focus.FocusSyncSource> sources,
  }) {
    calls.total++;
    return super.upsertSources(userId: userId, sources: sources);
  }
}

class _CountingNationalFocusRemote
    extends InMemoryNationalFocusRemoteDataSource {
  _CountingNationalFocusRemote(this.calls);

  final _BusinessRemoteCalls calls;

  @override
  Future<List<NationalFocusSyncSource>> pull({required String userId}) {
    calls.total++;
    return super.pull(userId: userId);
  }

  @override
  Future<void> upsertSources({
    required String userId,
    required List<NationalFocusSyncSource> sources,
  }) {
    calls.total++;
    return super.upsertSources(userId: userId, sources: sources);
  }
}

class _CountingCalendarRemote extends InMemoryCalendarRemote {
  _CountingCalendarRemote(this.calls);

  final _BusinessRemoteCalls calls;

  @override
  Future<CalendarRemoteSnapshot> pull({required String userId}) {
    calls.total++;
    return super.pull(userId: userId);
  }

  @override
  Future<void> upsertSources({
    required String userId,
    required List<CalendarSource> sources,
  }) {
    calls.total++;
    return super.upsertSources(userId: userId, sources: sources);
  }

  @override
  Future<void> upsertEvents({
    required String userId,
    required List<CalendarEventOccurrence> events,
  }) {
    calls.total++;
    return super.upsertEvents(userId: userId, events: events);
  }

  @override
  Future<void> deleteSources({
    required String userId,
    required Set<String> sourceIds,
  }) {
    calls.total++;
    return super.deleteSources(userId: userId, sourceIds: sourceIds);
  }

  @override
  Future<void> deleteEvents({
    required String userId,
    required String sourceId,
    required Set<String> occurrenceIds,
  }) {
    calls.total++;
    return super.deleteEvents(
      userId: userId,
      sourceId: sourceId,
      occurrenceIds: occurrenceIds,
    );
  }
}

class _CountingCloudSnapshotRemote extends InMemoryCloudSnapshotRemote {
  _CountingCloudSnapshotRemote(this.calls);

  final _BusinessRemoteCalls calls;

  @override
  Future<CloudSnapshotMetadata?> inspect({required String userId}) {
    calls.total++;
    return super.inspect(userId: userId);
  }

  @override
  Future<CloudSnapshotMetadata> upload({
    required String userId,
    required int expectedRevision,
    required Map<String, dynamic> payload,
    required String deviceId,
    required String deviceName,
    required DateTime dataUpdatedAt,
    required int rowCount,
  }) {
    calls.total++;
    return super.upload(
      userId: userId,
      expectedRevision: expectedRevision,
      payload: payload,
      deviceId: deviceId,
      deviceName: deviceName,
      dataUpdatedAt: dataUpdatedAt,
      rowCount: rowCount,
    );
  }

  @override
  Future<CloudSnapshotMetadata> download({required String userId}) {
    calls.total++;
    return super.download(userId: userId);
  }
}
