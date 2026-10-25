// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/auth/user_lifecycle.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/notifications/focus_notification_service.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/fake_auth_repository.dart';

const _phase = String.fromEnvironment('ISSUE72_PHASE');
const _runId = String.fromEnvironment('ISSUE72_RUN_ID');
const _controlToken = String.fromEnvironment('ISSUE72_CONTROL_TOKEN');
const _controlPort = int.fromEnvironment(
  'ISSUE72_CONTROL_PORT',
  defaultValue: 30351,
);
const _userId = 'issue72-native-$_runId';
const _surfaceKey = ValueKey<String>('issue72-capture-surface');
const _reminderText = '选择同步方式';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Issue 72 reminders survive process lifecycle and defer during active flows', (
    tester,
  ) async {
    expect(_phase, anyOf('exercise', 'restart-verify'));
    expect(_runId, matches(RegExp(r'^[A-Za-z0-9_-]{8,48}$')));
    expect(_controlToken, isNotEmpty);
    expect(Platform.isAndroid || Platform.isWindows, isTrue);

    final support = await getApplicationSupportDirectory();
    final separator = Platform.pathSeparator;
    final databaseFile = File(
      '${support.path}${separator}issue72-$_runId.sqlite',
    );
    final controlFile = File(
      '${support.path}${separator}issue72-$_runId-control.json',
    );
    final _ControlState control;
    if (_phase == 'exercise') {
      expect(databaseFile.existsSync(), isFalse);
      expect(controlFile.existsSync(), isFalse);
      control = await _ControlState.create(controlFile);
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove('pacta.device.cloud_sync.ignored.$_userId');
      await preferences.remove('pacta.device.cloud_sync.result.$_userId');
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
      deviceId: 'issue72-${Platform.operatingSystem}',
      deviceName: 'Issue 72 isolated native fixture',
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
            title: 'Issue 72 isolated local goal',
            classification: TaskClassification.regular,
          ),
        );
        await tasks.createTask(
          goal.id,
          const TaskDraft(title: 'Issue 72 isolated task'),
        );
        await control.save();
      }
      await _primeLocalAppState(tasks: tasks, focus: focus, national: national);
      final localBaseline = await repository.captureLocalState();
      final transferBaseline = control.businessTransfers;
      final inspectionBaseline = remote.inspectCount;
      final priorPid = control.lastPid;
      control.lastPid = pid;
      await control.save();

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
            userLifecycleRepositoryFactory: (userId) => UserLifecycleRepository(
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
      await _waitFor(() => remote.inspectCount >= inspectionBaseline + 1);

      if (_phase == 'exercise') {
        if (find.text(_reminderText).evaluate().isEmpty) {
          await _openMyPage(tester);
        }
        await _waitForReminder(tester);
        expect(find.text(_reminderText), findsOneWidget);
        expect(find.text('忽略'), findsOneWidget);
        expect(find.text('本地数据时间较新，请选择要保留的数据。'), findsOneWidget);
        // The fixture timestamp is one year old. Discovery must still prompt.
        expect(
          control.dataUpdatedAt.isBefore(
            control.now().subtract(const Duration(days: 300)),
          ),
          isTrue,
        );
        await _capture(tester, 'issue72-first-reminder-old-cloud');
        await _tap(tester, find.text('取消'));
        await tester.pumpAndSettle();

        lifecycle.armForNativeCycles();
        server.appReady = true;
        print(
          'ISSUE72_EXERCISE_READY platform=${Platform.operatingSystem} pid=$pid '
          'priorPid=$priorPid revision=${control.remoteRevision} '
          'database=${databaseFile.path} control=${controlFile.path}',
        );
        await _awaitResume(tester, lifecycle, 1);
        await _waitFor(() => remote.inspectCount >= inspectionBaseline + 2);
        await tester.pumpAndSettle();
        expect(control.remoteRevision, 1);
        expect(find.text(_reminderText), findsOneWidget);
        await _capture(tester, 'issue72-closed-then-foreground-reminder');

        await _tap(tester, find.text('忽略'));
        await tester.pumpAndSettle();
        expect(find.text(_reminderText), findsNothing);
        // Ignoring automation must leave the manual preview available.
        await _openMyPage(tester);
        await _tap(tester, find.byTooltip('查看云端并选择方向'));
        await tester.pumpAndSettle();
        expect(find.text('选择同步方式'), findsOneWidget);
        expect(find.text('上传'), findsOneWidget);
        expect(find.text('下载'), findsOneWidget);
        await _capture(tester, 'issue72-manual-preview-after-ignore');
        await _tap(tester, find.text('下载'));
        await tester.pumpAndSettle();
        expect(find.text('下载并覆盖本地？'), findsOneWidget);
        expect(find.textContaining('本机独有的记录将被丢弃'), findsOneWidget);
        await _tap(tester, find.text('取消'));
        await tester.pumpAndSettle();
        await _tap(tester, find.byTooltip('查看云端并选择方向'));
        await tester.pumpAndSettle();
        await _tap(tester, find.text('上传'));
        await tester.pumpAndSettle();
        expect(find.text('上传并覆盖云端？'), findsOneWidget);
        await _tap(tester, find.text('取消'));
        await tester.pumpAndSettle();
        await _tap(tester, find.text('取消'));
        await tester.pumpAndSettle();
        await _expectBusinessUnchanged(
          repository,
          localBaseline,
          transferBaseline,
          control,
        );
        print(
          'ISSUE72_IGNORE_SAVED platform=${Platform.operatingSystem} pid=$pid '
          'revision=${control.remoteRevision} inspections=${remote.inspectCount}',
        );
      } else {
        expect(
          priorPid,
          isNot(pid),
          reason: 'Verification must run in a new process.',
        );
        expect(
          find.text(_reminderText),
          findsNothing,
          reason: 'The ignored revision must stay quiet after process restart.',
        );
        await _waitFor(() => remote.inspectCount >= inspectionBaseline + 1);
        await tester.pumpAndSettle();
        expect(find.text(_reminderText), findsNothing);
        print(
          'ISSUE72_RESTART_SAME_VERSION_QUIET platform=${Platform.operatingSystem} '
          'pid=$pid priorPid=$priorPid inspections=${remote.inspectCount}',
        );

        var expectedInspections = remote.inspectCount;
        control.remoteRevision = 2;
        control.clockOffsetSeconds += 300;
        await control.save();
        lifecycle.armForNativeCycles();
        server.appReady = true;
        print(
          'ISSUE72_NEW_VERSION_READY pid=$pid revision=${control.remoteRevision}',
        );
        await _awaitResume(tester, lifecycle, 1);
        expectedInspections++;
        await _waitFor(() => remote.inspectCount >= expectedInspections);
        await tester.pumpAndSettle();
        expect(
          find.text(_reminderText),
          findsOneWidget,
          reason: 'A new revision must be offered even when the previous one was ignored.',
        );
        await _capture(tester, 'issue72-new-version-after-restart');
        await _tap(tester, find.text('取消'));
        await tester.pumpAndSettle();
        await _openMyPage(tester);

        final task = (await tasks.getGoals()).single.tasks.single;
        final appointment = await focus.startAppointment(
          taskId: task.id,
          mode: FocusChainMode.regular,
          duration: const Duration(minutes: 5),
        );
        control.remoteRevision = 3;
        control.clockOffsetSeconds += 300;
        await control.save();
        await _nativeCycle(tester, lifecycle, 2);
        expectedInspections++;
        await _waitFor(() => remote.inspectCount >= expectedInspections);
        await tester.pumpAndSettle();
        expect(
          find.text(_reminderText),
          findsNothing,
          reason: 'An active appointment must not be interrupted.',
        );
        expect(find.textContaining('流程结束后'), findsOneWidget);
        await _capture(tester, 'issue72-appointment-nonblocking');
        await _tap(tester, find.byTooltip('查看云端并选择方向'));
        await tester.pumpAndSettle();
        expect(find.text('本机有未结束的专注或预约，请先处理后再下载。'), findsOneWidget);
        final downloadButton = tester.widget<OutlinedButton>(
          find.ancestor(
            of: find.text('下载'),
            matching: find.byType(OutlinedButton),
          ),
        );
        final uploadButton = tester.widget<FilledButton>(
          find.ancestor(
            of: find.text('上传'),
            matching: find.byType(FilledButton),
          ),
        );
        expect(downloadButton.onPressed, isNull);
        expect(uploadButton.onPressed, isNotNull);
        await _tap(tester, find.text('取消'));
        await tester.pumpAndSettle();
        expectedInspections = remote.inspectCount;
        await focus.cancelAppointment(
          appointmentId: appointment.id,
          failureReason: 'Issue 72 native acceptance end',
        );
        await _waitForReminder(tester);
        await tester.pumpAndSettle();
        expect(
          find.text(_reminderText),
          findsOneWidget,
          reason: 'After the appointment, offer only its latest revision.',
        );
        await _capture(tester, 'issue72-appointment-ended-latest-reminder');
        await _tap(tester, find.text('忽略'));
        await tester.pumpAndSettle();

        final session = await focus.startSession(
          taskId: task.id,
          mode: FocusChainMode.regular,
          duration: const Duration(minutes: 10),
        );
        control.remoteRevision = 4;
        control.clockOffsetSeconds += 300;
        await control.save();
        await _nativeCycle(tester, lifecycle, 3);
        expectedInspections++;
        await _waitFor(() => remote.inspectCount >= expectedInspections);
        await tester.pumpAndSettle();
        expect(
          find.text(_reminderText),
          findsNothing,
          reason: 'An active focus session must not be interrupted.',
        );
        await focus.pauseSession(
          session.id,
          ruleText: 'Issue 72 native acceptance pause',
        );
        control.remoteRevision = 5;
        control.clockOffsetSeconds += 300;
        await control.save();
        await _nativeCycle(tester, lifecycle, 4);
        expectedInspections++;
        await _waitFor(() => remote.inspectCount >= expectedInspections);
        await tester.pumpAndSettle();
        expect(
          find.text(_reminderText),
          findsNothing,
          reason: 'A paused session must not be interrupted.',
        );
        expect(
          find.text('云端来源：Issue 72 controlled snapshot revision 5'),
          findsOneWidget,
          reason: 'The delayed choice must describe the latest revision, not revision 4.',
        );
        await _capture(tester, 'issue72-paused-nonblocking-latest-revision');
        await focus.resumeSession(session.id);
        await focus.completeEarlySession(
          sessionId: session.id,
          ruleText: 'Issue 72 native acceptance finish',
        );
        await _waitForReminder(tester);
        await tester.pumpAndSettle();
        expect(
          find.text(_reminderText),
          findsOneWidget,
          reason: 'After focus ends, offer only latest revision 5.',
        );
        await _capture(tester, 'issue72-focus-ended-latest-reminder');
        await _tap(tester, find.text('取消'));
        await tester.pumpAndSettle();
        expect(control.businessTransfers, transferBaseline);
        print(
          'ISSUE72_NATIVE_PASS platform=${Platform.operatingSystem} pid=$pid '
          'revision=${control.remoteRevision} inspections=${remote.inspectCount} '
          'businessTransfers=${control.businessTransfers} database=${databaseFile.path}',
        );
      }
      expect(tester.takeException(), isNull);
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
  }, timeout: const Timeout(Duration(minutes: 12)));
}

Future<void> _tap(WidgetTester tester, Finder target) => tester.tap(
  target,
  kind: Platform.isWindows
      ? ui.PointerDeviceKind.mouse
      : ui.PointerDeviceKind.touch,
);

Future<void> _openMyPage(WidgetTester tester) async {
  final navigation = find.byWidgetPredicate(
    (widget) => widget is NavigationBar || widget is NavigationRail,
  );
  await _tap(
    tester,
    find.descendant(of: navigation, matching: find.text('我的')).last,
  );
  await tester.pumpAndSettle();
}

Future<void> _waitForReminder(WidgetTester tester) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.text(_reminderText).evaluate().isNotEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  throw StateError('Issue 72 automatic reminder did not arrive.');
}

Future<void> _primeLocalAppState({
  required LocalTaskRepository tasks,
  required LocalFocusRepository focus,
  required LocalNationalFocusRepository national,
}) async {
  await focus.settleDueSessions();
  await national.getTreeCards();
  await focus.getActiveSession();
  await focus.getActiveAppointment();
  await tasks.getGoals();
}

Future<void> _nativeCycle(
  WidgetTester tester,
  _NativeLifecycleProbe lifecycle,
  int count,
) async {
  print('ISSUE72_WAITING_FOR_RESUME count=$count');
  await tester.runAsync(() => lifecycle.waitForResumeCount(count));
  await tester.pumpAndSettle();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 500)),
  );
  await tester.pumpAndSettle();
}

Future<void> _awaitResume(
  WidgetTester tester,
  _NativeLifecycleProbe lifecycle,
  int count,
) => _nativeCycle(tester, lifecycle, count);

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
    'Issue 72 native reminder did not reach expected state.',
  );
}

Future<void> _expectBusinessUnchanged(
  CloudSnapshotRepository repository,
  CloudSnapshotLocalState baseline,
  int transferBaseline,
  _ControlState control,
) async {
  final after = await repository.captureLocalState();
  expect(
    after.fingerprint,
    baseline.fingerprint,
    reason: 'Reminder, dismissal, and ignore must not mutate business data.',
  );
  expect(
    control.businessTransfers,
    transferBaseline,
    reason:
        'Read-only reminder scenarios must not transfer business snapshots.',
  );
}

Future<void> _capture(WidgetTester tester, String stage) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_surfaceKey),
  );
  final image = await boundary.toImage(pixelRatio: 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final support = await getApplicationSupportDirectory();
  final output = File('${support.path}${Platform.pathSeparator}$stage.png');
  await output.writeAsBytes(bytes!.buffer.asUint8List());
  print('ISSUE72_SCREENSHOT stage=$stage path=${output.path}');
}

class _ControlState {
  _ControlState._(this.file, this.clockBaseUtc);
  final File file;
  final DateTime clockBaseUtc;
  int clockOffsetSeconds = 0;
  int remoteRevision = 1;
  int inspectCount = 0;
  int businessTransfers = 0;
  int? lastPid;
  DateTime dataUpdatedAt = DateTime.utc(2025, 1, 1);

  DateTime now() => clockBaseUtc.add(Duration(seconds: clockOffsetSeconds));

  static Future<_ControlState> create(File file) async {
    final state = _ControlState._(file, DateTime.now().toUtc());
    await state.save();
    return state;
  }

  static Future<_ControlState> read(File file) async {
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return _ControlState._(
        file,
        DateTime.parse(json['clockBaseUtc'] as String).toUtc(),
      )
      ..clockOffsetSeconds = json['clockOffsetSeconds'] as int
      ..remoteRevision = json['remoteRevision'] as int
      ..inspectCount = json['inspectCount'] as int
      ..businessTransfers = json['businessTransfers'] as int
      ..lastPid = json['lastPid'] as int?
      ..dataUpdatedAt = DateTime.parse(json['dataUpdatedAt'] as String).toUtc();
  }

  Future<void> save() async {
    await file.writeAsString(
      jsonEncode({
        'clockBaseUtc': clockBaseUtc.toIso8601String(),
        'clockOffsetSeconds': clockOffsetSeconds,
        'remoteRevision': remoteRevision,
        'inspectCount': inspectCount,
        'businessTransfers': businessTransfers,
        'lastPid': lastPid,
        'dataUpdatedAt': dataUpdatedAt.toIso8601String(),
      }),
      flush: true,
    );
  }
}

class _FileControlledCloudRemote implements CloudSnapshotRemote {
  _FileControlledCloudRemote(this.control);
  final _ControlState control;
  int get inspectCount => control.inspectCount;

  CloudSnapshotMetadata _metadata(int revision) => CloudSnapshotMetadata(
    revision: revision,
    deviceId: 'issue72-remote',
    deviceName: 'Issue 72 controlled snapshot revision $revision',
    dataUpdatedAt: control.dataUpdatedAt,
    uploadedAt: control.dataUpdatedAt,
    rowCount: 2,
  );

  @override
  Future<CloudSnapshotMetadata?> inspect({required String userId}) async {
    control.inspectCount++;
    await control.save();
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
    throw StateError('Issue 72 read-only reminder fixture must not download.');
  }
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
    await waiter.future.timeout(const Duration(minutes: 3));
  }
}

class _RuntimeControlServer {
  _RuntimeControlServer(this.server, this.token, this.control, this.lifecycle);
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
    final runtime = _RuntimeControlServer(server, token, control, lifecycle);
    server.listen(runtime._handle);
    return runtime;
  }

  Future<void> _handle(HttpRequest request) async {
    if (request.headers.value('X-Issue72-Control') != token) {
      request.response
        ..statusCode = HttpStatus.forbidden
        ..close();
      return;
    }
    if (request.method == 'GET' && request.uri.path == '/status') {
      request.response
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'phase': _phase,
            'pid': pid,
            'ready': appReady,
            'resumeCount': lifecycle.resumeCount,
            'lifecycleStates': lifecycle.states
                .map((state) => state.name)
                .toList(),
            'clockUtc': control.now().toIso8601String(),
            'remoteRevision': control.remoteRevision,
            'inspectCount': control.inspectCount,
            'businessTransfers': control.businessTransfers,
          }),
        );
      await request.response.close();
      return;
    }
    if (request.method == 'POST' && request.uri.path == '/control') {
      final body = jsonDecode(
        await utf8.decoder.bind(request).join(),
      ) as Map<String, dynamic>;
      final advance = body['advanceSeconds'];
      if (advance is int && advance >= 0 && advance <= 86400) {
        control.clockOffsetSeconds += advance;
      }
      final revision = body['remoteRevision'];
      if (revision is int && revision > 0) control.remoteRevision = revision;
      await control.save();
      request.response
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
      final body = jsonDecode(
        await utf8.decoder.bind(request).join(),
      ) as Map<String, dynamic>;
      switch (body['action']) {
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
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'ok': true, 'action': body['action']}));
      await request.response.close();
      return;
    }
    request.response
      ..statusCode = HttpStatus.notFound
      ..close();
  }

  Future<void> close() => server.close(force: true);
}

class _WindowsWindowLifecycle {
  static final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');
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
  static final DynamicLibrary _ole32 = DynamicLibrary.open('ole32.dll');
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
      final ownerPid = _allocate(sizeOf<Uint32>()).cast<Uint32>();
      if (ownerPid == nullptr) {
        throw StateError('Could not allocate window process id.');
      }
      try {
        ownerPid.value = 0;
        if (_getWindowThreadProcessId(handle, ownerPid) == 0 ||
            ownerPid.value != pid) {
          throw StateError('Refusing to control another process window.');
        }
      } finally {
        _free(ownerPid.cast<Void>());
      }
      return handle;
    } finally {
      _free(className.cast<Void>());
    }
  }

  static Future<void> minimize() async {
    final handle = _windowHandle();
    _showWindow(handle, 6);
    await _waitFor(() => _isIconic(handle) != 0);
  }

  static Future<void> restore() async {
    final handle = _windowHandle();
    _showWindow(handle, 9);
    _setForegroundWindow(handle);
    await _waitFor(
      () => _isIconic(handle) == 0 && _getForegroundWindow() == handle,
    );
  }

  static Future<void> _waitFor(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      if (condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    throw TimeoutException(
      'The native Pacta window did not change foreground state.',
    );
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
