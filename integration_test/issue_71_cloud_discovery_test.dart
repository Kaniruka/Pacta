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
import 'package:pacta/src/sync/cloud_sync_result.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _phase = String.fromEnvironment('ISSUE71_PHASE');
const _surfaceKey = ValueKey<String>('issue71-capture-surface');
const _control = String.fromEnvironment('ISSUE71_RUNTIME_CONTROL');
const _port = String.fromEnvironment(
  'ISSUE71_RUNTIME_PORT',
  defaultValue: '30347',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('cold AppShell cloud discovery is read-only and version-aware', (
    tester,
  ) async {
    expect(_phase, anyOf('snapshot', 'legacy'));
    expect(_control, isNotEmpty);
    final fixture = await _startFixture(
      tester,
      _phase == 'legacy' ? 'legacy' : 'device',
    );
    SupabaseClient? secondClient;
    try {
      // AppShell performs this normal local checkpoint maintenance at startup.
      // Include it in the baseline so the assertion isolates cloud discovery.
      await fixture.initializeLocalMaintenance();
      final before = await fixture.sync.captureLocalState();
      expect(before.rowCount, greaterThanOrEqualTo(1));
      final initialCloud = await tester.runAsync(fixture.sync.inspectCloud);
      expect(initialCloud, isNotNull);
      final baseline = initialCloud!;
      await fixture.sync.syncResultStore.save(
        fixture.userId,
        CloudSyncResult(
          succeededAt: fixture.clock,
          localFingerprint: before.fingerprint,
          cloudRevision: baseline.revision,
          legacyToken: baseline.legacyToken,
        ),
      );
      fixture.client.httpObserver.clear();

      await fixture.mount(tester);
      await _waitForCloudState(
        tester,
        fixture,
        1,
        expectedPending: false,
        minimumLegacyReads: _phase == 'legacy' ? 1 : 0,
      );

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('云端有待处理更新'), findsNothing);
      await tester.ensureVisible(find.byTooltip('查看云端并选择方向'));
      await fixture.capture(tester, 'issue71-$_phase-handled-version');
      final initialReads = fixture.client.httpObserver.discoveryReads;
      expect(initialReads, greaterThanOrEqualTo(1));
      await tester.runAsync(
        () => _runtimePost('/control/record', {
          'kind': _phase == 'legacy' ? 'legacy-inspect' : 'snapshot-inspect',
        }),
      );
      if (_phase == 'legacy') {
        expect(
          fixture.client.httpObserver.legacyReads,
          greaterThanOrEqualTo(1),
        );
        expect(
          fixture.client.httpObserver.requests.any(
            (request) =>
                request.path.endsWith('/rpc/save_cloud_business_snapshot'),
          ),
          isFalse,
        );
      }

      // A second authenticated user can read their own snapshot but never the
      // first user's snapshot or legacy rows.
      final otherConfig = await tester.runAsync(
        () => _runtimeGet('/session?user=other'),
      );
      expect(otherConfig, isNotNull);
      final otherSession = otherConfig!;
      secondClient = SupabaseClient(
        otherSession['url'] as String,
        otherSession['publishableKey'] as String,
      );
      await tester.runAsync(
        () => secondClient!.auth.setSession(
          otherSession['refreshToken'] as String,
        ),
      );
      final foreignSnapshot = await tester.runAsync(
        () => secondClient!
            .from('cloud_business_snapshots')
            .select('revision')
            .eq('user_id', fixture.userId)
            .maybeSingle(),
      );
      expect(foreignSnapshot, isNull);
      final ownSnapshot = await tester.runAsync(
        () => secondClient!
            .from('cloud_business_snapshots')
            .select('revision')
            .eq('user_id', otherSession['userId'] as String)
            .maybeSingle(),
      );
      expect(ownSnapshot?['revision'], 1);
      final foreignLegacy = await tester.runAsync(
        () => secondClient!.rpc('read_legacy_business_records'),
      );
      expect(foreignLegacy, isNull);
      await secondClient.dispose();
      secondClient = null;

      if (_phase == 'snapshot') {
        expect(baseline.revision, 1);
        expect(baseline.isLegacy, isFalse);
        await tester.runAsync(
          () => _runtimePost('/control/change-snapshot', {'user': 'device'}),
        );
      } else {
        expect(baseline.isLegacy, isTrue);
        expect(baseline.legacyToken, isNotEmpty);
        await tester.runAsync(
          () => _runtimePost('/control/change-legacy', const {}),
        );
      }

      // This is a test-runner lifecycle callback, not proof of a process
      // restart. The native lifecycle exercise records real OS transitions.
      final readsBeforeForeground = fixture.client.httpObserver.discoveryReads;
      final legacyReadsBeforeForeground =
          fixture.client.httpObserver.legacyReads;
      fixture.clock = fixture.clock.add(const Duration(minutes: 6));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _waitForCloudState(
        tester,
        fixture,
        readsBeforeForeground + 1,
        expectedPending: true,
        minimumLegacyReads: _phase == 'legacy'
            ? legacyReadsBeforeForeground + 1
            : legacyReadsBeforeForeground,
      );
      await tester.runAsync(
        () => _runtimePost('/control/record', {'kind': 'foreground-check'}),
      );
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('云端有待处理更新'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('查看云端并选择方向'));
      await fixture.capture(tester, 'issue71-$_phase-pending');

      if (_phase == 'legacy') {
        await tester.tap(find.byTooltip('查看云端并选择方向'));
        await tester.pumpAndSettle();
        await _waitForText(tester, '选择同步方式');
        await fixture.capture(tester, 'issue71-legacy-preview');
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
      }

      final updated = await tester.runAsync(fixture.sync.inspectCloud);
      expect(updated, isNotNull);
      final updatedCloud = updated!;
      if (_phase == 'snapshot') {
        expect(updatedCloud.revision, 2);
        expect(updatedCloud.dataUpdatedAt, baseline.dataUpdatedAt);
      } else {
        expect(updatedCloud.legacyToken, isNot(baseline.legacyToken));
        expect(updatedCloud.dataUpdatedAt, baseline.dataUpdatedAt);
      }
      final after = await fixture.sync.captureLocalState();
      expect(after.fingerprint, before.fingerprint);
      expect(after.rowCount, before.rowCount);
      expect(
        fixture.client.httpObserver.requests.any(
          (request) =>
              request.method != 'GET' &&
              (request.path.endsWith('/cloud_business_snapshots') ||
                  request.path.endsWith('/rpc/save_cloud_business_snapshot')),
        ),
        isFalse,
      );
      final snapshotMetadataReads = fixture.client.httpObserver.requests
          .where(
            (request) =>
                request.method == 'GET' &&
                request.path.endsWith('/cloud_business_snapshots'),
          )
          .toList();
      expect(snapshotMetadataReads, isNotEmpty);
      expect(
        snapshotMetadataReads.every(
          (request) =>
              request.select != null &&
              request.select != '*' &&
              !request.select!.contains('payload'),
        ),
        isTrue,
      );
      final observations = await tester.runAsync(
        () => _runtimeGet('/observations'),
      );
      expect(observations, isNotNull);
      final eventCounts = observations!['counts'] as Map<String, dynamic>;
      expect(eventCounts['foreground-check'], greaterThanOrEqualTo(1));
      expect(
        eventCounts[_phase == 'legacy' ? 'legacy-inspect' : 'snapshot-inspect'],
        greaterThanOrEqualTo(1),
      );
      // ignore: avoid_print
      print(
        'ISSUE71_DISCOVERY_PASSED phase=$_phase '
        'reads=${fixture.client.httpObserver.discoveryReads} '
        'legacyReads=${fixture.client.httpObserver.legacyReads} '
        'localRows=${after.rowCount} localFingerprintUnchanged=true',
      );
    } finally {
      await secondClient?.dispose();
      await fixture.close(tester);
    }
  });
}

Future<void> _waitForCloudState(
  WidgetTester tester,
  _Fixture fixture,
  int minimumReads, {
  required bool expectedPending,
  int minimumLegacyReads = 0,
}) async {
  await tester.tap(find.text('我的').last);
  for (var attempt = 0; attempt < 150; attempt++) {
    await tester.pump(const Duration(milliseconds: 200));
    final pending = find.text('云端有待处理更新').evaluate().isNotEmpty;
    final checking = find.text('正在检查云端…').evaluate().isNotEmpty;
    final failed = find.text('云端检查失败，点击重试').evaluate().isNotEmpty;
    if (fixture.client.httpObserver.discoveryReads >= minimumReads &&
        fixture.client.httpObserver.legacyReads >= minimumLegacyReads &&
        pending == expectedPending &&
        !checking &&
        !failed) {
      await tester.pumpAndSettle();
      return;
    }
  }
  throw StateError('Issue 71 cloud discovery did not finish for $_phase.');
}

Future<void> _waitForText(WidgetTester tester, String text) async {
  for (var attempt = 0; attempt < 150; attempt++) {
    await tester.pump(const Duration(milliseconds: 200));
    if (find.text(text).evaluate().isNotEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  throw StateError('Issue 71 expected UI state did not arrive: $text');
}

Future<Map<String, dynamic>> _runtimeGet(String path) async {
  final response = await http.get(
    Uri.parse('http://127.0.0.1:$_port$path'),
    headers: {'X-Pacta-Acceptance': _control},
  );
  if (response.statusCode != 200) {
    throw StateError('Issue 71 runtime session request failed.');
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
    throw StateError('Issue 71 fixture version change failed.');
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
  final directory = await Directory.systemTemp.createTemp('pacta-issue71-');
  final database = PactaDatabase(
    NativeDatabase(File('${directory.path}/business.sqlite')),
  );
  var clock = DateTime.now().toUtc();
  final sync = CloudSnapshotRepository(
    database: database,
    remote: SupabaseCloudSnapshotRemote(client),
    userId: userId,
    deviceId: 'issue71-${Platform.operatingSystem}',
    deviceName: 'Issue 71 ${Platform.operatingSystem} acceptance client',
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
      title: 'Issue 71 local-only business row',
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
    if (Platform.isAndroid) {
      await IntegrationTestWidgetsFlutterBinding.ensureInitialized()
          .convertFlutterSurfaceToImage();
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
