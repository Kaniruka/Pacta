import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/auth/user_lifecycle.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/notifications/focus_notification_service.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/sync/cloud_sync_result.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../test/support/fake_auth_repository.dart';

const _phase = String.fromEnvironment('ISSUE71_PHASE');
const _runId = String.fromEnvironment('ISSUE71_RUN_ID');
const _controlToken = String.fromEnvironment('ISSUE71_CONTROL_TOKEN');
const _controlPort = int.fromEnvironment(
  'ISSUE71_CONTROL_PORT',
  defaultValue: 30349,
);
const _userId = 'issue71-native-$_runId';
const _surfaceKey = ValueKey<String>('issue71-capture-surface');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Issue 71 native cold start, foreground, reconnect, and process restart',
    (tester) async {
      expect(_phase, anyOf('exercise', 'cold-verify', 'network-verify'));
      expect(_runId, matches(RegExp(r'^[A-Za-z0-9_-]{8,48}$')));
      expect(_controlToken, isNotEmpty);
      expect(Platform.isAndroid || Platform.isWindows, isTrue);

      final support = await getApplicationSupportDirectory();
      final separator = Platform.pathSeparator;
      final databaseFile = File(
        '${support.path}${separator}issue71-$_runId.sqlite',
      );
      final controlFile = File(
        '${support.path}${separator}issue71-$_runId-control.json',
      );

      final _ControlState control;
      if (_phase == 'exercise') {
        expect(databaseFile.existsSync(), isFalse);
        expect(controlFile.existsSync(), isFalse);
        control = await _ControlState.create(controlFile);
      } else {
        expect(databaseFile.existsSync(), isTrue);
        expect(controlFile.existsSync(), isTrue);
        control = await _ControlState.read(controlFile);
      }

      final database = PactaDatabase(NativeDatabase(databaseFile));
      final remote = _FileControlledCloudRemote(control);
      final repository = CloudSnapshotRepository(
        database: database,
        remote: remote,
        userId: _userId,
        deviceId: 'issue71-${Platform.operatingSystem}',
        deviceName: 'Issue 71 isolated native fixture',
        now: control.now,
      );
      final tasks = LocalTaskRepository(
        database: database,
        userId: _userId,
        remote: InMemoryTaskRemote(),
        cloudSyncEnabled: false,
        now: control.now,
      );
      final focus = LocalFocusRepository(
        database: database,
        userId: _userId,
        remote: InMemoryFocusRemote(),
        cloudSyncEnabled: false,
        now: control.now,
      );
      final national = LocalNationalFocusRepository(
        database: database,
        userId: _userId,
        cloudSyncEnabled: false,
        now: control.now,
      );
      final auth = FakeAuthRepository()..signedInUser = _userId;
      final lifecycle = _NativeLifecycleProbe();
      WidgetsBinding.instance.addObserver(lifecycle);
      _RuntimeControlServer? server;

      try {
        if (_phase == 'exercise') {
          final goal = await tasks.createGoal(
            const GoalDraft(
              title: 'Issue 71 preserved local goal',
              classification: TaskClassification.regular,
            ),
          );
          await tasks.createTask(
            goal.id,
            const TaskDraft(
              title: 'Issue 71 preserved local task',
              classification: null,
            ),
          );

          await _primeLocalAppState(
            tasks: tasks,
            focus: focus,
            national: national,
          );

          final seeded = await repository.captureLocalState();
          await repository.uploadLocal(
            expectedRevision: 0,
            expectedFingerprint: seeded.fingerprint,
          );
          final syncResult = await repository.loadSyncResult();
          expect(syncResult, isNotNull);
          final savedSyncResult = syncResult!;
          expect(savedSyncResult.cloudRevision, 1);
          expect(control.businessTransfers, 1);
          control
            ..baselineFingerprint = seeded.fingerprint
            ..baselineSucceededAt = savedSyncResult.succeededAt
                .toIso8601String()
            ..remoteRevision = 2;
          await control.save();
        } else {
          final savedGoal = (await tasks.getGoals()).single;
          expect(savedGoal.title, 'Issue 71 preserved local goal');
          expect(savedGoal.tasks.single.title, 'Issue 71 preserved local task');
          await _primeLocalAppState(
            tasks: tasks,
            focus: focus,
            national: national,
          );
        }

        final baseline = await repository.captureLocalState();
        final loadedBaselineResult = await repository.loadSyncResult();
        expect(loadedBaselineResult, isNotNull);
        final baselineResult = loadedBaselineResult!;
        expect(baseline.fingerprint, control.baselineFingerprint);
        expect(
          baselineResult.succeededAt.toIso8601String(),
          control.baselineSucceededAt,
        );
        final baselineTransfers = control.businessTransfers;
        final initialInspectionCount = remote.inspectCount;

        server = await _RuntimeControlServer.start(
          port: _controlPort,
          token: _controlToken,
          control: control,
          lifecycle: lifecycle,
        );

        await tester.pumpWidget(
          RepaintBoundary(
            key: _surfaceKey,
            child: PactaApp(
              authRepository: auth,
              cloudCheckClock: control.now,
              taskRepositoryFactory: (_) => tasks,
              focusRepositoryFactory: (_) => focus,
              nationalFocusRepositoryFactory: (_) => national,
              cloudSnapshotRepositoryFactory: (_) => repository,
              focusNotificationService: DisabledFocusNotificationService(),
              userLifecycleRepositoryFactory: (userId) =>
                  UserLifecycleRepository(
                    authRepository: auth,
                    localAccess: LocalUserLifecycleAccess(
                      database: database,
                      userId: userId,
                    ),
                  ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AppShell), findsOneWidget);
        await _waitFor(() => remote.inspectCount >= initialInspectionCount + 1);
        await tester.pumpAndSettle();

        final navigation = find.byWidgetPredicate(
          (widget) => widget is NavigationBar || widget is NavigationRail,
        );
        await tester.tap(
          find.descendant(of: navigation, matching: find.text('我的')).last,
        );
        await tester.pumpAndSettle();
        expect(find.text('云端有待处理更新'), findsOneWidget);

        if (_phase == 'exercise') {
          lifecycle.armForNativeCycles();
          server.appReady = true;
          // ignore: avoid_print
          print(
            'ISSUE71_RUNTIME_READY platform=${Platform.operatingSystem} '
            'pid=$pid phase=$_phase port=$_controlPort '
            'database=${databaseFile.path} inspections=${remote.inspectCount} '
            'businessTransfers=${control.businessTransfers} '
            'resumeCount=${lifecycle.resumeCount}',
          );

          await _awaitResume(tester, lifecycle, 1);
          expect(remote.inspectCount, 1, reason: '4:59 must remain throttled.');
          expect(find.text('云端有待处理更新'), findsOneWidget);
          await _expectReadOnlyState(
            repository: repository,
            control: control,
            baseline: baseline,
            baselineResult: baselineResult,
            baselineTransfers: baselineTransfers,
            remote: remote,
          );
          await _capture(tester, 'issue71-throttled');
          // ignore: avoid_print
          print('ISSUE71_CYCLE_PASSED cycle=1 check=throttled');

          await _awaitResume(tester, lifecycle, 2);
          await _waitFor(() => remote.inspectCount >= 2);
          await tester.pumpAndSettle();
          expect(find.text('云端检查失败，点击重试'), findsOneWidget);
          await _expectReadOnlyState(
            repository: repository,
            control: control,
            baseline: baseline,
            baselineResult: baselineResult,
            baselineTransfers: baselineTransfers,
            remote: remote,
          );
          await _capture(tester, 'issue71-failed');
          // ignore: avoid_print
          print(
            'ISSUE71_CYCLE_PASSED cycle=2 check=controlled-failure-retryable',
          );

          await _awaitResume(tester, lifecycle, 3);
          await _waitFor(() => remote.inspectCount >= 3);
          await tester.pumpAndSettle();
          expect(find.text('云端有待处理更新'), findsOneWidget);
          await _expectReadOnlyState(
            repository: repository,
            control: control,
            baseline: baseline,
            baselineResult: baselineResult,
            baselineTransfers: baselineTransfers,
            remote: remote,
          );
          await _capture(tester, 'issue71-recovered');
          // ignore: avoid_print
          print('ISSUE71_CYCLE_PASSED cycle=3 check=recovered');

          // The host performs a real OS network disconnect/reconnect while the
          // app remains foregrounded, then sends this synchronization marker.
          // Connectivity recovery itself must not issue another cloud inspect.
          // ignore: avoid_print
          print('ISSUE71_WAITING_FOR_NETWORK_RECONNECT');
          await tester.runAsync(
            () => _waitFor(
              () => control.networkReconnectConfirmed,
              timeout: const Duration(minutes: 3),
            ),
          );
          await tester.pumpAndSettle();
          expect(remote.inspectCount, 3);
          await _expectReadOnlyState(
            repository: repository,
            control: control,
            baseline: baseline,
            baselineResult: baselineResult,
            baselineTransfers: baselineTransfers,
            remote: remote,
          );
          // ignore: avoid_print
          print(
            'ISSUE71_NETWORK_RECONNECT_PASS inspections=${remote.inspectCount}',
          );
        } else {
          server.appReady = true;
          expect(remote.inspectCount, initialInspectionCount + 1);
          expect(find.text('云端有待处理更新'), findsOneWidget);
          await _expectReadOnlyState(
            repository: repository,
            control: control,
            baseline: baseline,
            baselineResult: baselineResult,
            baselineTransfers: baselineTransfers,
            remote: remote,
          );
          // ignore: avoid_print
          print(
            'ISSUE71_COLD_VERIFY_PASS platform=${Platform.operatingSystem} '
            'pid=$pid inspections=${remote.inspectCount} '
            'businessTransfers=${control.businessTransfers} '
            'fingerprint=${baseline.fingerprint} '
            'succeededAt=${baselineResult.succeededAt.toIso8601String()}',
          );
          if (_phase == 'network-verify') {
            expect(control.networkReconnectConfirmed, isFalse);
            lifecycle.armForNativeCycles();
            // ignore: avoid_print
            print(
              'ISSUE71_NETWORK_RUNTIME_READY '
              'platform=${Platform.operatingSystem} pid=$pid '
              'resumeCount=${lifecycle.resumeCount} '
              'inspections=${remote.inspectCount} '
              'businessTransfers=${control.businessTransfers}',
            );
            await _awaitResume(tester, lifecycle, 1);
            await tester.pumpAndSettle();
            expect(remote.inspectCount, initialInspectionCount + 1);
            await _expectReadOnlyState(
              repository: repository,
              control: control,
              baseline: baseline,
              baselineResult: baselineResult,
              baselineTransfers: baselineTransfers,
              remote: remote,
            );
            // ignore: avoid_print
            print(
              'ISSUE71_COLD_VERIFY_LIFECYCLE_PASS '
              'resumeCount=${lifecycle.resumeCount} '
              'inspections=${remote.inspectCount}',
            );
            // ignore: avoid_print
            print('ISSUE71_WAITING_FOR_NETWORK_RECONNECT');
            await tester.runAsync(
              () => _waitFor(
                () => control.networkReconnectConfirmed,
                timeout: const Duration(minutes: 3),
              ),
            );
            await tester.pumpAndSettle();
            expect(remote.inspectCount, initialInspectionCount + 1);
            await _expectReadOnlyState(
              repository: repository,
              control: control,
              baseline: baseline,
              baselineResult: baselineResult,
              baselineTransfers: baselineTransfers,
              remote: remote,
            );
            // ignore: avoid_print
            print(
              'ISSUE71_NETWORK_RECONNECT_PASS '
              'inspections=${remote.inspectCount} '
              'businessTransfers=${control.businessTransfers}',
            );
          }
        }

        expect(tester.takeException(), isNull);
        await _capture(tester, _phase);
        // ignore: avoid_print
        print(
          'ISSUE71_NATIVE_PASS platform=${Platform.operatingSystem} '
          'pid=$pid phase=$_phase inspections=${remote.inspectCount} '
          'businessTransfers=${control.businessTransfers} '
          'database=${databaseFile.path}',
        );
      } finally {
        WidgetsBinding.instance.removeObserver(lifecycle);
        await server?.close();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await national.dispose();
        await focus.dispose();
        await tasks.dispose();
        await database.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}

Future<void> _primeLocalAppState({
  required LocalTaskRepository tasks,
  required LocalFocusRepository focus,
  required LocalNationalFocusRepository national,
}) async {
  // AppShell settles these local repositories during its first frame/resume.
  // Run the same idempotent initialization before taking the read-only
  // comparison point so setup maintenance is not attributed to cloud inspect.
  await focus.settleDueSessions();
  await national.getTreeCards();
  await focus.getActiveSession();
  await focus.getActiveAppointment();
  await tasks.getGoals();
}

Future<void> _awaitResume(
  WidgetTester tester,
  _NativeLifecycleProbe lifecycle,
  int count,
) async {
  // ignore: avoid_print
  print('ISSUE71_WAITING_FOR_RESUME count=$count');
  await tester.runAsync(() => lifecycle.waitForResumeCount(count));
  await tester.pumpAndSettle();
  // The AppShell observer refreshes lifecycle status before requesting a cloud
  // inspection. Let that asynchronous local refresh complete after resume.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 500)),
  );
  await tester.pumpAndSettle();
}

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw TimeoutException(
    'Issue 71 native check did not reach its expected state.',
  );
}

Future<void> _expectReadOnlyState({
  required CloudSnapshotRepository repository,
  required _ControlState control,
  required CloudSnapshotLocalState baseline,
  required CloudSyncResult baselineResult,
  required int baselineTransfers,
  required _FileControlledCloudRemote remote,
}) async {
  final after = await repository.captureLocalState();
  final syncResult = await repository.loadSyncResult();
  if (after.fingerprint != baseline.fingerprint) {
    // The fixture contains only synthetic records. Emit the exact snapshot
    // difference so startup maintenance cannot be mistaken for cloud reads.
    // ignore: avoid_print
    print(
      'ISSUE71_BUSINESS_DIFF before=${jsonEncode(baseline.payload)} '
      'after=${jsonEncode(after.payload)}',
    );
  }
  expect(after.fingerprint, baseline.fingerprint);
  expect(syncResult, isNotNull);
  expect(syncResult!.succeededAt, baselineResult.succeededAt);
  expect(syncResult.localFingerprint, baselineResult.localFingerprint);
  expect(syncResult.cloudRevision, baselineResult.cloudRevision);
  expect(control.businessTransfers, baselineTransfers);
  expect(remote.transferCount, baselineTransfers);
}

Future<void> _capture(WidgetTester tester, String stage) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_surfaceKey),
  );
  final image = await boundary.toImage(pixelRatio: 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final support = await getApplicationSupportDirectory();
  final output = File(
    '${support.path}${Platform.pathSeparator}issue71-$stage.png',
  );
  await output.writeAsBytes(bytes!.buffer.asUint8List());
}

class _ControlState {
  _ControlState._(this.file, this.clockBaseUtc);

  final File file;
  final DateTime clockBaseUtc;
  int clockOffsetSeconds = 0;
  int remoteRevision = 0;
  bool failInspect = false;
  int inspectCount = 0;
  int businessTransfers = 0;
  bool networkReconnectConfirmed = false;
  String? baselineFingerprint;
  String? baselineSucceededAt;

  DateTime now() => clockBaseUtc.add(Duration(seconds: clockOffsetSeconds));

  static Future<_ControlState> create(File file) async {
    final state = _ControlState._(file, DateTime.now().toUtc());
    await state.save();
    return state;
  }

  static Future<_ControlState> read(File file) async {
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final state =
        _ControlState._(
            file,
            DateTime.parse(json['clockBaseUtc'] as String).toUtc(),
          )
          ..clockOffsetSeconds = json['clockOffsetSeconds'] as int
          ..remoteRevision = json['remoteRevision'] as int
          ..failInspect = json['failInspect'] as bool
          ..inspectCount = json['inspectCount'] as int
          ..businessTransfers = json['businessTransfers'] as int
          ..networkReconnectConfirmed =
              json['networkReconnectConfirmed'] as bool? ?? false
          ..baselineFingerprint = json['baselineFingerprint'] as String?
          ..baselineSucceededAt = json['baselineSucceededAt'] as String?;
    return state;
  }

  Future<void> save() async {
    await file.writeAsString(
      jsonEncode({
        'clockBaseUtc': clockBaseUtc.toIso8601String(),
        'clockOffsetSeconds': clockOffsetSeconds,
        'remoteRevision': remoteRevision,
        'failInspect': failInspect,
        'inspectCount': inspectCount,
        'businessTransfers': businessTransfers,
        'networkReconnectConfirmed': networkReconnectConfirmed,
        'baselineFingerprint': baselineFingerprint,
        'baselineSucceededAt': baselineSucceededAt,
      }),
      flush: true,
    );
  }
}

class _FileControlledCloudRemote implements CloudSnapshotRemote {
  _FileControlledCloudRemote(this.control);

  final _ControlState control;

  int get inspectCount => control.inspectCount;
  int get transferCount => control.businessTransfers;

  @override
  Future<CloudSnapshotMetadata?> inspect({required String userId}) async {
    control.inspectCount++;
    await control.save();
    if (control.failInspect) {
      throw StateError('Issue 71 controlled remote failure.');
    }
    if (control.remoteRevision == 0) return null;
    return _metadata(control.remoteRevision);
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
    String? deviceManufacturer,
    String? deviceModel,
  }) async {
    control.businessTransfers++;
    control.remoteRevision = expectedRevision + 1;
    await control.save();
    return _metadata(control.remoteRevision);
  }

  @override
  Future<CloudSnapshotMetadata> download({required String userId}) async {
    control.businessTransfers++;
    await control.save();
    throw StateError('Issue 71 discovery must never download business data.');
  }

  CloudSnapshotMetadata _metadata(int revision) => CloudSnapshotMetadata(
    revision: revision,
    deviceId: 'issue71-remote',
    deviceName: 'Issue 71 controlled remote',
    dataUpdatedAt: control.now().subtract(const Duration(minutes: 1)),
    uploadedAt: control.now().subtract(const Duration(minutes: 1)),
    rowCount: 2,
  );
}

class _NativeLifecycleProbe extends WidgetsBindingObserver {
  final List<AppLifecycleState> states = [];
  final List<Completer<void>> _resumeWaiters = [];
  int resumeCount = 0;
  bool _armed = false;
  bool _backgrounded = false;

  void armForNativeCycles() {
    resumeCount = 0;
    _backgrounded = false;
    _armed = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    states.add(state);
    if (!_armed) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgrounded = true;
      return;
    }
    if (state != AppLifecycleState.resumed || !_backgrounded) return;
    resumeCount++;
    _backgrounded = false;
    for (final waiter in _resumeWaiters.toList()) {
      waiter.complete();
      _resumeWaiters.remove(waiter);
    }
  }

  Future<void> waitForResumeCount(int target) async {
    if (resumeCount >= target) return;
    final waiter = Completer<void>();
    _resumeWaiters.add(waiter);
    await waiter.future.timeout(
      const Duration(minutes: 3),
      onTimeout: () => throw TimeoutException(
        'The native app did not resume for lifecycle cycle $target.',
      ),
    );
  }
}

class _RuntimeControlServer {
  _RuntimeControlServer({
    required this.server,
    required this.token,
    required this.control,
    required this.lifecycle,
  });

  final HttpServer server;
  final String token;
  final _ControlState control;
  final _NativeLifecycleProbe lifecycle;
  bool appReady = false;

  static Future<_RuntimeControlServer> start({
    required int port,
    required String token,
    required _ControlState control,
    required _NativeLifecycleProbe lifecycle,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    final runtime = _RuntimeControlServer(
      server: server,
      token: token,
      control: control,
      lifecycle: lifecycle,
    );
    server.listen(runtime._handle);
    return runtime;
  }

  Future<void> _handle(HttpRequest request) async {
    if (request.headers.value('X-Issue71-Control') != token) {
      request.response
        ..statusCode = HttpStatus.forbidden
        ..close();
      return;
    }

    if (request.method == 'GET' && request.uri.path == '/status') {
      final connectivity = await Connectivity().checkConnectivity();
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'phase': _phase,
          'pid': pid,
          'platform': Platform.operatingSystem,
          'ready': appReady,
          'currentLifecycle': lifecycle.states.isEmpty
              ? WidgetsBinding.instance.lifecycleState?.name
              : lifecycle.states.last.name,
          'resumeCount': lifecycle.resumeCount,
          'lifecycleStates': lifecycle.states
              .map((state) => state.name)
              .toList(),
          'clockUtc': control.now().toIso8601String(),
          'remoteRevision': control.remoteRevision,
          'failInspect': control.failInspect,
          'inspectCount': control.inspectCount,
          'businessTransfers': control.businessTransfers,
          'networkReconnectConfirmed': control.networkReconnectConfirmed,
          'connectivity': connectivity.map((state) => state.name).toList(),
        }),
      );
      await request.response.close();
      return;
    }

    if (request.method == 'POST' && request.uri.path == '/control') {
      final body = await utf8.decoder.bind(request).join();
      final payload = jsonDecode(body) as Map<String, dynamic>;
      final advanceSeconds = payload['advanceSeconds'];
      if (advanceSeconds != null) {
        if (advanceSeconds is! int ||
            advanceSeconds < 0 ||
            advanceSeconds > 86400) {
          request.response
            ..statusCode = HttpStatus.badRequest
            ..close();
          return;
        }
        control.clockOffsetSeconds += advanceSeconds;
      }
      final failInspect = payload['failInspect'];
      if (failInspect != null) {
        if (failInspect is! bool) {
          request.response
            ..statusCode = HttpStatus.badRequest
            ..close();
          return;
        }
        control.failInspect = failInspect;
      }
      final revision = payload['remoteRevision'];
      if (revision != null) {
        if (revision is! int || revision < 0) {
          request.response
            ..statusCode = HttpStatus.badRequest
            ..close();
          return;
        }
        control.remoteRevision = revision;
      }
      final networkReconnectConfirmed = payload['networkReconnectConfirmed'];
      if (networkReconnectConfirmed != null) {
        if (networkReconnectConfirmed is! bool) {
          request.response
            ..statusCode = HttpStatus.badRequest
            ..close();
          return;
        }
        control.networkReconnectConfirmed = networkReconnectConfirmed;
      }
      await control.save();
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({'ok': true, 'clockUtc': control.now().toIso8601String()}),
        );
      await request.response.close();
      return;
    }

    if (request.method == 'POST' && request.uri.path == '/lifecycle') {
      if (!Platform.isWindows) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..write('Use ADB to background and foreground Android.');
        await request.response.close();
        return;
      }
      final body = await utf8.decoder.bind(request).join();
      final payload = jsonDecode(body) as Map<String, dynamic>;
      switch (payload['action']) {
        case 'minimize':
          await _WindowsWindowLifecycle.minimize();
          break;
        case 'restore':
          await _WindowsWindowLifecycle.restore();
          break;
        default:
          request.response
            ..statusCode = HttpStatus.badRequest
            ..write('action must be minimize or restore');
          await request.response.close();
          return;
      }
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'ok': true, 'action': payload['action']}));
      await request.response.close();
      return;
    }

    request.response
      ..statusCode = HttpStatus.notFound
      ..close();
  }

  Future<void> close() async {
    await server.close(force: true);
  }
}

class _WindowsWindowLifecycle {
  static final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');
  static final DynamicLibrary _ole32 = DynamicLibrary.open('ole32.dll');
  static final _FindWindowDart _findWindow = _user32
      .lookupFunction<_FindWindowNative, _FindWindowDart>('FindWindowA');
  static final _ShowWindowDart _showWindow = _user32
      .lookupFunction<_ShowWindowNative, _ShowWindowDart>('ShowWindow');
  static final _IsIconicDart _isIconic = _user32
      .lookupFunction<_IsIconicNative, _IsIconicDart>('IsIconic');
  static final _GetWindowThreadProcessIdDart _getWindowThreadProcessId = _user32
      .lookupFunction<
        _GetWindowThreadProcessIdNative,
        _GetWindowThreadProcessIdDart
      >('GetWindowThreadProcessId');
  static final _GetForegroundWindowDart _getForegroundWindow = _user32
      .lookupFunction<_GetForegroundWindowNative, _GetForegroundWindowDart>(
        'GetForegroundWindow',
      );
  static final _SetForegroundWindowDart _setForegroundWindow = _user32
      .lookupFunction<_SetForegroundWindowNative, _SetForegroundWindowDart>(
        'SetForegroundWindow',
      );
  static final _CoTaskMemAllocDart _allocate = _ole32
      .lookupFunction<_CoTaskMemAllocNative, _CoTaskMemAllocDart>(
        'CoTaskMemAlloc',
      );
  static final _CoTaskMemFreeDart _free = _ole32
      .lookupFunction<_CoTaskMemFreeNative, _CoTaskMemFreeDart>(
        'CoTaskMemFree',
      );

  static int _windowHandle() {
    final bytes = utf8.encode('FLUTTER_RUNNER_WIN32_WINDOW');
    final className = _allocate(bytes.length + 1).cast<Int8>();
    if (className == nullptr) {
      throw StateError('Could not allocate window class name.');
    }
    final view = className.asTypedList(bytes.length + 1);
    view.setRange(0, bytes.length, bytes);
    view[bytes.length] = 0;
    try {
      final handle = _findWindow(className, nullptr);
      if (handle == 0) {
        throw StateError('Could not find the Pacta Flutter runner window.');
      }
      final ownerProcessId = _allocate(sizeOf<Uint32>()).cast<Uint32>();
      if (ownerProcessId == nullptr) {
        throw StateError('Could not allocate window process id.');
      }
      try {
        ownerProcessId.value = 0;
        if (_getWindowThreadProcessId(handle, ownerProcessId) == 0) {
          throw StateError('Could not read the Pacta window process id.');
        }
        if (ownerProcessId.value != pid) {
          throw StateError('Refusing to control another Flutter window.');
        }
      } finally {
        _free(ownerProcessId.cast<Void>());
      }
      return handle;
    } finally {
      _free(className.cast<Void>());
    }
  }

  static Future<void> minimize() async {
    final handle = _windowHandle();
    _showWindow(handle, 6); // SW_MINIMIZE
    await _waitFor(
      () => _isIconic(handle) != 0,
      'Pacta window did not minimize.',
    );
  }

  static Future<void> restore() async {
    final handle = _windowHandle();
    _showWindow(handle, 9); // SW_RESTORE
    _setForegroundWindow(handle);
    await _waitFor(
      () => _isIconic(handle) == 0 && _getForegroundWindow() == handle,
      'Pacta window did not return to the foreground.',
    );
  }

  static Future<void> _waitFor(
    bool Function() condition,
    String message,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      if (condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    throw TimeoutException(message);
  }
}

typedef _FindWindowNative = IntPtr Function(Pointer<Int8>, Pointer<Int8>);
typedef _FindWindowDart = int Function(Pointer<Int8>, Pointer<Int8>);
typedef _ShowWindowNative = Int32 Function(IntPtr, Int32);
typedef _ShowWindowDart = int Function(int, int);
typedef _IsIconicNative = Int32 Function(IntPtr);
typedef _IsIconicDart = int Function(int);
typedef _GetWindowThreadProcessIdNative = Uint32 Function(
  IntPtr,
  Pointer<Uint32>,
);
typedef _GetWindowThreadProcessIdDart = int Function(int, Pointer<Uint32>);
typedef _GetForegroundWindowNative = IntPtr Function();
typedef _GetForegroundWindowDart = int Function();
typedef _SetForegroundWindowNative = Int32 Function(IntPtr);
typedef _SetForegroundWindowDart = int Function(int);
typedef _CoTaskMemAllocNative = Pointer<Void> Function(IntPtr);
typedef _CoTaskMemAllocDart = Pointer<Void> Function(int);
typedef _CoTaskMemFreeNative = Void Function(Pointer<Void>);
typedef _CoTaskMemFreeDart = void Function(Pointer<Void>);
