import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/auth/supabase_auth_repository.dart';
import 'package:pacta/src/auth/user_lifecycle.dart';
import 'package:pacta/src/calendar/calendar_provider.dart';
import 'package:pacta/src/calendar/calendar_repository.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _surfaceKey = ValueKey<String>('issue72-capture-surface');
bool _surfaceConverted = false;
ui.PointerDeviceKind get _pointerKind => Platform.isWindows
    ? ui.PointerDeviceKind.mouse
    : ui.PointerDeviceKind.touch;
// The Issue 71 runtime protocol is intentionally reused by the guarded Python
// fixture. These defines contain only its random, local control capability.
const _control = String.fromEnvironment('ISSUE71_RUNTIME_CONTROL');
const _port = String.fromEnvironment(
  'ISSUE71_RUNTIME_PORT',
  defaultValue: '30348',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets(
    'real AppShell cloud choices preserve local data and ignored versions',
    (tester) async {
      expect(_control, isNotEmpty);
      final otherConfig = (await tester.runAsync(
        () => _runtimeGet('/session?user=other'),
      ))!;
      final otherClient = SupabaseClient(
        otherConfig['url'] as String,
        otherConfig['publishableKey'] as String,
      );
      addTearDown(otherClient.dispose);
      await tester.runAsync(
        () =>
            otherClient.auth.setSession(otherConfig['refreshToken'] as String),
      );
      for (final user in ['device', 'legacy']) {
        final fixture = await _startFixture(tester, user);
        try {
          final preferences = await SharedPreferences.getInstance();
          await preferences.remove(
            'pacta.device.cloud_sync.result.${fixture.userId}',
          );
          await preferences.remove(
            'pacta.device.cloud_sync.ignored.${fixture.userId}',
          );
          await fixture.initializeLocalMaintenance();
          final before = await fixture.sync.captureLocalState();
          final baseline = (await tester.runAsync(fixture.sync.inspectCloud))!;
          if (user == 'device') {
            expect(baseline.revision, 1);
            expect(baseline.dataUpdatedAt.year, 2001);
          } else {
            expect(baseline.isLegacy, isTrue);
            expect(baseline.legacyToken, isNotEmpty);
          }
          fixture.client.httpObserver.clear();
          await fixture.mount(tester);
          await _waitForDialog(tester);
          expect(find.text('忽略'), findsOneWidget);
          expect(find.text('上传'), findsOneWidget);
          expect(find.text('下载'), findsOneWidget);
          await fixture.capture(tester, 'issue72-$user-first-choice');

          // Dismissal remains eligible on the next throttled foreground check.
          await tester.tap(find.text('取消'), kind: _pointerKind);
          await tester.pumpAndSettle();
          await _foreground(tester, fixture);
          await _waitForDialog(tester);
          await tester.tap(find.text('忽略'), kind: _pointerKind);
          await tester.pumpAndSettle();
          final ignoredKey =
              'pacta.device.cloud_sync.ignored.${fixture.userId}';
          final ignored = preferences.getString(ignoredKey);
          expect(ignored, isNotEmpty);
          final sameCloud = (await tester.runAsync(fixture.sync.inspectCloud))!;
          expect(sameCloud.revision, baseline.revision);
          expect(sameCloud.legacyToken, baseline.legacyToken);

          await _foreground(tester, fixture);
          expect(find.text('选择同步方式'), findsNothing);
          // Native restart persistence is exercised independently by the
          // Issue 72 device lifecycle fixture; this test retains a live service.
          await tester.tap(find.text('我的').last, kind: _pointerKind);
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.byTooltip('查看云端并选择方向'));
          await tester.tap(find.byTooltip('查看云端并选择方向'), kind: _pointerKind);
          await _waitForDialog(tester);
          expect(find.text('上传'), findsOneWidget);
          await tester.tap(find.text('取消'), kind: _pointerKind);
          await tester.pumpAndSettle();
          await fixture.capture(
            tester,
            'issue72-$user-ignored-manual-available',
          );

          // A separately authenticated client cannot read this user's snapshot.
          final foreign = await tester.runAsync(
            () => otherClient
                .from('cloud_business_snapshots')
                .select('revision')
                .eq('user_id', fixture.userId),
          );
          expect(foreign, isEmpty);
          expect(
            await tester.runAsync(
              () => otherClient.rpc('read_legacy_business_records'),
            ),
            isNull,
          );
          if (user == 'device') {
            // A second authenticated device writes through the public RPC;
            // the AppShell client remains strictly read-only throughout.
            final peer = SupabaseClient(
              otherConfig['url'] as String,
              otherConfig['publishableKey'] as String,
            );
            try {
              await tester.runAsync(
                () => peer.auth.setSession(
                  fixture.client.auth.currentSession!.refreshToken!,
                ),
              );
              final peerRemote = SupabaseCloudSnapshotRemote(peer);
              final uploaded = await tester.runAsync(
                () => peerRemote.upload(
                  userId: fixture.userId,
                  expectedRevision: 1,
                  payload: before.payload,
                  deviceId: 'issue72-peer-${Platform.operatingSystem}',
                  deviceName: 'Issue 72 second authenticated device',
                  dataUpdatedAt: baseline.dataUpdatedAt,
                  rowCount: before.rowCount,
                ),
              );
              expect(uploaded!.revision, 2);
            } finally {
              await peer.dispose();
            }
          } else {
            await tester.runAsync(
              () => _runtimePost('/control/change-legacy', {}),
            );
          }
          await _foreground(tester, fixture);
          await _waitForDialog(tester);
          final updated = (await tester.runAsync(fixture.sync.inspectCloud))!;
          if (user == 'device') {
            expect(updated.revision, 2);
            expect(updated.deviceName, 'Issue 72 second authenticated device');
          } else {
            expect(updated.legacyToken, isNot(baseline.legacyToken));
          }
          expect(updated.dataUpdatedAt, baseline.dataUpdatedAt);
          expect(preferences.getString(ignoredKey), ignored);
          await fixture.capture(tester, 'issue72-$user-new-version-choice');
          await tester.tap(find.text('忽略'), kind: _pointerKind);
          await tester.pumpAndSettle();
          expect(preferences.getString(ignoredKey), isNot(ignored));
          final after = await fixture.sync.captureLocalState();
          expect(after.fingerprint, before.fingerprint);
          expect(after.rowCount, before.rowCount);
          expect(await fixture.sync.loadSyncResult(), isNull);
          expect(
            fixture.client.httpObserver.requests.any(
              (request) =>
                  request.path.endsWith('/rpc/save_cloud_business_snapshot'),
            ),
            isFalse,
          );
          expect(
            fixture.client.httpObserver.requests.any(
              (request) =>
                  request.method != 'GET' &&
                  request.path.endsWith('/cloud_business_snapshots'),
            ),
            isFalse,
          );
          expect(tester.takeException(), isNull);
          // ignore: avoid_print
          print(
            'ISSUE72_REAL_CLOUD_PASS platform=${Platform.operatingSystem} user=$user firstSeen=true dismissalReprompts=true ignoredPersisted=true manualAvailable=true sameVersionStable=true newVersionReprompts=true localFingerprintUnchanged=true crossUserDenied=true',
          );
        } finally {
          await fixture.close(tester);
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

Future<void> _waitForDialog(WidgetTester tester) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.text('选择同步方式').evaluate().isNotEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  throw StateError('Issue 72 real cloud choice did not arrive.');
}

Future<void> _foreground(WidgetTester tester, _Fixture fixture) async {
  final reads = fixture.client.httpObserver.discoveryReads;
  fixture.clock = fixture.clock.add(const Duration(minutes: 6));
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  for (var attempt = 0; attempt < 200; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (fixture.client.httpObserver.discoveryReads > reads) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 700)),
      );
      await tester.pumpAndSettle();
      return;
    }
  }
  throw StateError('Issue 72 real cloud foreground check did not run.');
}

Future<Map<String, dynamic>> _runtimeGet(String path) async {
  final response = await http.get(
    Uri.parse('http://127.0.0.1:$_port$path'),
    headers: {'X-Pacta-Acceptance': _control},
  );
  if (response.statusCode != 200) {
    throw StateError('Issue 72 runtime session request failed.');
  }
  return jsonDecode(response.body) as Map<String, dynamic>;
}

Future<void> _runtimePost(String path, Map<String, dynamic> body) async {
  final response = await http.post(
    Uri.parse('http://127.0.0.1:$_port$path'),
    headers: {
      'X-Pacta-Acceptance': _control,
      'Content-Type': 'application/json',
    },
    body: jsonEncode(body),
  );
  if (response.statusCode != 200) {
    throw StateError('Issue 72 fixture version change failed.');
  }
}

Future<_Fixture> _startFixture(WidgetTester tester, String user) async {
  final config = await tester.runAsync(
    () => _runtimeGet('/session?user=$user'),
  );
  expect(config, isNotNull);
  final settings = config!;
  final observer = _DiscoveryHttpObserver();
  final client = _ObservedSupabaseClient(
    settings['url'] as String,
    settings['publishableKey'] as String,
    httpClient: observer,
  );
  await tester.runAsync(
    () => client.auth.setSession(settings['refreshToken'] as String),
  );
  final userId = settings['userId'] as String;
  expect(client.auth.currentUser?.id, userId);
  final directory = await Directory.systemTemp.createTemp('pacta-issue72-');
  final database = PactaDatabase(
    NativeDatabase(File('${directory.path}/business.sqlite')),
  );
  var clock = DateTime.now().toUtc();
  final sync = CloudSnapshotRepository(
    database: database,
    remote: SupabaseCloudSnapshotRemote(client),
    userId: userId,
    deviceId: 'issue72-${Platform.operatingSystem}',
    deviceName: 'Issue 72 ${Platform.operatingSystem} acceptance client',
    now: () => clock,
  );
  final tasks = LocalTaskRepository(
    database: database,
    userId: userId,
    remote: const UnavailableTaskRemoteDataSource(),
    cloudSyncEnabled: false,
    now: () => clock,
  );
  await tasks.createGoal(
    const GoalDraft(
      title: 'Issue 72 local-only business row',
      classification: TaskClassification.regular,
    ),
  );
  await tasks.dispose();
  return _Fixture(
    userId: userId,
    client: client,
    directory: directory,
    database: database,
    sync: sync,
    clock: clock,
    onClockChanged: (value) => clock = value,
  );
}

class _Fixture {
  _Fixture({
    required this.userId,
    required this.client,
    required this.directory,
    required this.database,
    required this.sync,
    required this._clock,
    required this.onClockChanged,
  });

  final String userId;
  final _ObservedSupabaseClient client;
  final Directory directory;
  final PactaDatabase database;
  final CloudSnapshotRepository sync;
  final void Function(DateTime) onClockChanged;
  DateTime _clock;
  DateTime get clock => _clock;
  set clock(DateTime value) {
    _clock = value;
    onClockChanged(value);
  }

  late final _auth = SupabaseAuthRepository(client);
  late final _focus = LocalFocusRepository(
    database: database,
    userId: userId,
    remote: const UnavailableFocusRemoteDataSource(),
    cloudSyncEnabled: false,
    now: () => clock,
  );
  late final _national = LocalNationalFocusRepository(
    database: database,
    userId: userId,
    remote: const UnavailableNationalFocusRemoteDataSource(),
    cloudSyncEnabled: false,
    now: () => clock,
  );

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      RepaintBoundary(
        key: _surfaceKey,
        child: PactaApp(
          authRepository: _auth,
          cloudCheckClock: () => clock,
          taskRepositoryFactory: (_) => LocalTaskRepository(
            database: database,
            userId: userId,
            remote: const UnavailableTaskRemoteDataSource(),
            cloudSyncEnabled: false,
            now: () => clock,
          ),
          focusRepositoryFactory: (_) => _focus,
          nationalFocusRepositoryFactory: (_) => _national,
          calendarRepositoryFactory: (_) => LocalCalendarRepository(
            database: database,
            userId: userId,
            provider: const UnsupportedCalendarProvider(),
            remote: const UnavailableCalendarRemoteDataSource(),
            cloudSyncEnabled: false,
          ),
          userLifecycleRepositoryFactory: (_) => UserLifecycleRepository(
            authRepository: _auth,
            localAccess: LocalUserLifecycleAccess(
              database: database,
              userId: userId,
            ),
          ),
          cloudSnapshotRepositoryFactory: (_) => sync,
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (Platform.isAndroid && !_surfaceConverted) {
      await IntegrationTestWidgetsFlutterBinding.ensureInitialized()
          .convertFlutterSurfaceToImage();
      _surfaceConverted = true;
      await tester.pump();
    }
  }

  Future<void> initializeLocalMaintenance() => _national.settleDueCheckpoints();

  Future<void> capture(WidgetTester tester, String name) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_surfaceKey),
    );
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final support = await getApplicationSupportDirectory();
    await File('${support.path}/$name.png')
        .writeAsBytes(data!.buffer.asUint8List());
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await _focus.dispose();
    await _national.dispose();
    await database.close();
    await client.dispose();
    await directory.delete(recursive: true);
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove('pacta.device.cloud_sync.result.$userId');
    await preferences.remove('pacta.device.cloud_sync.ignored.$userId');
  }
}

class _ObservedSupabaseClient extends SupabaseClient {
  _ObservedSupabaseClient(
    super.supabaseUrl,
    super.supabaseKey, {
    required _DiscoveryHttpObserver httpClient,
  }) : httpObserver = httpClient,
       super(httpClient: httpClient);

  final _DiscoveryHttpObserver httpObserver;
}

class _ObservedRequest {
  const _ObservedRequest(this.method, this.path, this.select);
  final String method;
  final String path;
  final String? select;
}

class _DiscoveryHttpObserver extends http.BaseClient {
  final http.Client _delegate = http.Client();
  final List<_ObservedRequest> requests = [];

  int get discoveryReads => requests
      .where(
        (request) =>
            request.method == 'GET' &&
            request.path.endsWith('/cloud_business_snapshots'),
      )
      .length;

  int get legacyReads => requests
      .where(
        (request) =>
            request.method == 'POST' &&
            request.path.endsWith('/rpc/read_legacy_business_records'),
      )
      .length;

  void clear() => requests.clear();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(
      _ObservedRequest(
        request.method,
        request.url.path,
        request.url.queryParameters['select'],
      ),
    );
    return _delegate.send(request);
  }

  @override
  void close() {
    _delegate.close();
    super.close();
  }
}
