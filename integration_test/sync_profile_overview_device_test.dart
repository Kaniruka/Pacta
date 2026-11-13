import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/auth/user_lifecycle.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/notifications/focus_notification_service.dart';
import 'package:pacta/src/profile/avatar_image.dart';
import 'package:pacta/src/profile/profile_remote.dart';
import 'package:pacta/src/profile/profile_repository.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/fake_auth_repository.dart';

const _userId = 'sync-profile-overview-device-user';
const _darkTheme = bool.fromEnvironment('SYNC_PROFILE_DARK_THEME');
const _captureDirectory = String.fromEnvironment('SYNC_PROFILE_CAPTURE_DIR');
const _captureBoundaryKey = ValueKey<String>('sync-profile-capture-boundary');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'My overview and cloud history remain usable through cancelled restore',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.platformDispatcher.platformBrightnessTestValue = _darkTheme
          ? Brightness.dark
          : Brightness.light;

      final database = PactaDatabase(NativeDatabase.memory());
      final auth = FakeAuthRepository()..signedInUser = _userId;
      final taskRepository = LocalTaskRepository(
        database: database,
        userId: _userId,
        remote: InMemoryTaskRemote(),
        cloudSyncEnabled: false,
      );
      final focusRepository = LocalFocusRepository(
        database: database,
        userId: _userId,
        remote: InMemoryFocusRemote(),
        cloudSyncEnabled: false,
      );
      final nationalFocusRepository = LocalNationalFocusRepository(
        database: database,
        userId: _userId,
        cloudSyncEnabled: false,
      );
      final profileRemote = _InMemoryProfileRemote();
      final profileRepository = LocalProfileRepository(
        database: database,
        userId: _userId,
        remote: profileRemote,
      );
      final cloudRemote = InMemoryCloudSnapshotRemote();
      final cloudSeedRepository = CloudSnapshotRepository(
        database: database,
        remote: cloudRemote,
        userId: _userId,
        deviceId: 'seed-device-2206123sc',
        deviceName: '2206123SC（Android）',
      );
      final cloudRepository = CloudSnapshotRepository(
        database: database,
        remote: cloudRemote,
        userId: _userId,
        deviceId: 'local-device-windows',
        deviceName: '本机（Windows）',
      );

      try {
        final cloudGoal = await taskRepository.createGoal(
          const GoalDraft(
            title: '云端已有的阅读计划',
            classification: TaskClassification.both,
          ),
        );
        await taskRepository.createTask(
          cloudGoal.id,
          const TaskDraft(
            title: '读完第一章并记录要点',
            classification: TaskClassification.both,
            estimatedMinutes: 30,
          ),
        );
        await profileRepository.saveProfile(displayName: '小林');

        final cloudBaseline = await cloudSeedRepository.captureLocalState();
        await cloudSeedRepository.uploadLocal(
          expectedRevision: 0,
          expectedFingerprint: cloudBaseline.fingerprint,
          captured: cloudBaseline,
        );
        // This goal is intentionally local-only, while the saved cloud revision
        // baseline prevents a startup notification before the sync card opens.
        await taskRepository.createGoal(
          const GoalDraft(
            title: '本机独有的练习计划',
            classification: TaskClassification.both,
          ),
        );

        await tester.pumpWidget(
          RepaintBoundary(
            key: _captureBoundaryKey,
            child: PactaApp(
              authRepository: auth,
              focusNotificationService: DisabledFocusNotificationService(),
              taskRepositoryFactory: (_) => taskRepository,
              focusRepositoryFactory: (_) => focusRepository,
              nationalFocusRepositoryFactory: (_) => nationalFocusRepository,
              profileRepositoryFactory: (_) => LocalProfileRepository(
                database: database,
                userId: _userId,
                remote: profileRemote,
              ),
              cloudSnapshotRepositoryFactory: (_) => cloudRepository,
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
        if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();

        await tester.tap(
          find.descendant(
            of: find.byWidgetPredicate(
              (widget) => widget is NavigationBar || widget is NavigationRail,
            ),
            matching: find.text('我的'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('小林'), findsOneWidget);
        expect(find.text('手动云同步'), findsOneWidget);
        expect(find.text('国策'), findsOneWidget);
        expect(find.text('专注'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _capture(tester, binding, 'my-overview');

        await tester.ensureVisible(find.text('手动云同步'));
        await tester.tap(find.text('手动云同步'));
        await tester.pumpAndSettle();
        expect(find.text('今日确认后自动上传'), findsOneWidget);
        await tester.ensureVisible(find.text('今日确认后自动上传'));
        expect(tester.takeException(), isNull);
        await _capture(tester, binding, 'sync-operations');

        await tester.ensureVisible(find.text('历史备份'));
        await tester.tap(find.text('历史备份'));
        await tester.pumpAndSettle();
        final cloudHistoryEntry = find.textContaining('2206123SC（Android）');
        await _pumpUntilFound(tester, cloudHistoryEntry);
        await tester.ensureVisible(cloudHistoryEntry);
        expect(find.text('历史备份'), findsOneWidget);
        expect(cloudHistoryEntry, findsOneWidget);
        expect(tester.takeException(), isNull);
        await _capture(tester, binding, 'cloud-history');

        await tester.ensureVisible(find.text('恢复'));
        await tester.tap(find.text('恢复'));
        await tester.pumpAndSettle();
        expect(find.text('恢复到该云端备份？'), findsOneWidget);
        await tester.ensureVisible(find.text('确认恢复'));
        expect(tester.takeException(), isNull);
        await _capture(tester, binding, 'restore-confirmation');

        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(find.text('恢复到该云端备份？'), findsNothing);
        expect(find.text('历史备份'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _capture(tester, binding, 'history-after-cancel');
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('手动云同步'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        tester.platformDispatcher.clearPlatformBrightnessTestValue();
        await profileRepository.dispose();
        await database.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
  }
  expect(finder, findsOneWidget);
}

Future<void> _capture(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  String name,
) async {
  if (Platform.isAndroid) {
    await binding.takeScreenshot(name);
    return;
  }
  if (!Platform.isWindows || _captureDirectory.isEmpty) return;
  if (!_isAbsoluteWindowsPath(_captureDirectory)) {
    throw ArgumentError.value(
      _captureDirectory,
      'SYNC_PROFILE_CAPTURE_DIR',
      'must be an absolute Windows path',
    );
  }

  final directory = Directory(_captureDirectory)..createSync(recursive: true);
  final file = File('${directory.path}${Platform.pathSeparator}$name.png');
  if (file.existsSync()) {
    throw StateError('Refusing to overwrite existing screenshot: ${file.path}');
  }
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureBoundaryKey),
  );
  final image = await boundary.toImage(pixelRatio: 1);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Could not encode screenshot $name.');
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
  } finally {
    image.dispose();
  }
}

bool _isAbsoluteWindowsPath(String path) =>
    RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path) || path.startsWith(r'\\');

class _InMemoryProfileRemote implements ProfileRemote {
  RemoteProfile? _profile;

  @override
  bool get isAvailable => true;

  @override
  Future<RemoteProfile?> fetch({required String userId}) async => _profile;

  @override
  Future<RemoteProfile> save({
    required String userId,
    required String displayName,
    required ProfileAvatar? avatar,
    required DateTime updatedAt,
  }) async {
    final saved = RemoteProfile(
      displayName: displayName,
      avatar: avatar,
      updatedAt: updatedAt,
    );
    _profile = saved;
    return saved;
  }
}
