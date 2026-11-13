import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/auth/user_lifecycle.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../support/fake_auth_repository.dart';
import '../support/frozen_ui79_remote.dart';

const _captureRoot = String.fromEnvironment('ISSUE79_CAPTURE');
const _baseline = bool.fromEnvironment('ISSUE79_BASELINE');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
          (_) async => null,
        );
  });
  testWidgets(
    '320 normal text keeps last successful sync readable in one status line',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      if (_captureRoot.isNotEmpty) {
        await tester.runAsync(() async {
          final font = FontLoader('Roboto')
            ..addFont(
              Future.value(
                ByteData.sublistView(
                  await File(
                    '${Platform.environment['WINDIR'] ?? 'C:/Windows'}/Fonts/msyh.ttc',
                  ).readAsBytes(),
                ),
              ),
            );
          await font.load();
          final icons = FontLoader('MaterialIcons')
            ..addFont(
              Future.value(
                ByteData.sublistView(
                  await File(
                    '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts/MaterialIcons-Regular.otf',
                  ).readAsBytes(),
                ),
              ),
            );
          await icons.load();
        });
      }
      final database = PactaDatabase(NativeDatabase.memory());
      const user = 'issue79-ui';
      final auth = FakeAuthRepository()..signedInUser = user;
      final sync = CloudSnapshotRepository(
        database: database,
        remote: FrozenUi79Remote(),
        userId: user,
        deviceId: 'issue79-desktop',
        deviceName: '家里的工作电脑',
        now: () => DateTime(2026, 11, 12, 10, 30),
      );
      final tasks = LocalTaskRepository(
        database: database,
        userId: user,
        remote: InMemoryTaskRemote(),
        now: () => DateTime(2026, 11, 12, 10),
        cloudSyncEnabled: false,
      );
      final focus = LocalFocusRepository(
        database: database,
        userId: user,
        remote: InMemoryFocusRemote(),
        cloudSyncEnabled: false,
      );
      final tree = LocalNationalFocusRepository(
        now: () => DateTime(2026, 11, 12, 10),
        database: database,
        userId: user,
        cloudSyncEnabled: false,
      );
      await tree.settleDueCheckpoints();
      final local = await sync.captureLocalState();
      await sync.uploadLocal(
        expectedRevision: 0,
        expectedFingerprint: local.fingerprint,
      );
      try {
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('issue79-capture'),
            child: PactaApp(
              authRepository: auth,
              taskRepositoryFactory: (_) => tasks,
              focusRepositoryFactory: (_) => focus,
              nationalFocusRepositoryFactory: (_) => tree,
              userLifecycleRepositoryFactory: (id) => UserLifecycleRepository(
                authRepository: auth,
                localAccess: LocalUserLifecycleAccess(
                  database: database,
                  userId: id,
                ),
              ),
              cloudSnapshotRepositoryFactory: (_) => sync,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('我的'));
        await tester.pumpAndSettle();
        await _capture(tester, 'summary-320');
        final statusHeight = tester
            .getSize(find.text('2026-11-12 10:30:00'))
            .height;
        if (_baseline) {
          expect(statusHeight, greaterThan(20));
        } else {
          expect(
            statusHeight,
            lessThanOrEqualTo(20),
            reason: 'The current status must remain one readable line at normal text size.',
          );
        }
        await tester.tap(find.byTooltip('查看云同步'));
        await tester.pumpAndSettle();
        await _capture(tester, 'choice-320');
        expect(find.text('云端与本机'), findsOneWidget);
        if (!_baseline) {
          expect(find.textContaining('丢弃'), findsNothing);
          expect(find.widgetWithText(FilledButton, '下载'), findsOneWidget);
          expect(find.widgetWithText(OutlinedButton, '上传'), findsOneWidget);
          await _capture(tester, 'directions-320');
        }
        await tester.tap(find.text('关闭'));
        await tester.pumpAndSettle();
        expect(find.text('2026-11-12 10:30:00'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await tasks.dispose();
          await focus.dispose();
          await tree.dispose();
          await database.close();
        });
      }
    },
  );
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (_captureRoot.isEmpty) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('issue79-capture')),
    );
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await Directory(_captureRoot).create(recursive: true);
    final file = File('$_captureRoot/$name.png');
    if (await file.exists()) {
      throw StateError('Refusing to overwrite capture: ${file.path}');
    }
    await file.writeAsBytes(bytes!.buffer.asUint8List());
  });
}
