// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/main.dart' show pactaTheme;
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/profile/avatar_image.dart';
import 'package:pacta/src/profile/avatar_picker.dart';
import 'package:pacta/src/profile/profile_card.dart';
import 'package:pacta/src/profile/profile_overview.dart';
import 'package:pacta/src/profile/profile_remote.dart';
import 'package:pacta/src/profile/profile_repository.dart';
import 'package:pacta/src/tasks/task_database.dart' hide FocusSession;

/// Offline, rerunnable layout fixture for Issue #94's profile card.
///
/// Android captures through the integration-test binding and its host driver;
/// desktop captures through a RepaintBoundary. No credentials, persistent
/// database, cloud write, or real account is involved.
const String _evidenceDir = String.fromEnvironment(
  'PROFILE_PILOT_DIR',
  defaultValue: 'profile-card/current',
);
const bool _lightMode = bool.fromEnvironment('PROFILE_PILOT_LIGHT');

final Uint8List _avatarPng = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

class _FixtureProfileRemote implements ProfileRemote {
  RemoteProfile? stored;

  @override
  bool get isAvailable => true;

  @override
  Future<RemoteProfile?> fetch({required String userId}) async => stored;

  @override
  Future<RemoteProfile> save({
    required String userId,
    required String displayName,
    required ProfileAvatar? avatar,
    required DateTime updatedAt,
  }) async {
    stored = RemoteProfile(
      displayName: displayName,
      avatar: avatar,
      updatedAt: updatedAt,
    );
    return stored!;
  }
}

class _FixtureAvatarPicker implements AvatarPicker {
  @override
  Future<Uint8List?> pickSingleImage() async => _avatarPng;
}

class _FixtureOverview implements ProfileOverviewSource {
  _FixtureOverview({required this.cards, required this.sessions});

  final List<NationalFocusCard> cards;
  final List<FocusSession> sessions;

  @override
  Stream<List<NationalFocusCard>> watchCards() => Stream.value(cards);

  @override
  Stream<List<FocusSession>> watchSessions() => Stream.value(sessions);
}

NationalFocusCard _card(
  String name, {
  required bool isInTree,
  NationalFocusCardState state = NationalFocusCardState.extinguished,
  int successfulDays = 0,
  int currentConsecutiveDays = 0,
}) => NationalFocusCard(
  id: name,
  name: name,
  triggerCondition: '每天起床后',
  action: '读十页书',
  isInTree: isInTree,
  state: state,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 11, 13),
  successfulDays: successfulDays,
  currentConsecutiveDays: currentConsecutiveDays,
);

FocusSession _session(
  String id,
  int effectiveSeconds, {
  FocusSessionStatus status = FocusSessionStatus.completed,
}) {
  final startedAt = DateTime.utc(2026, 11, 12, 9);
  return FocusSession(
    id: id,
    taskId: 'fixture-task',
    mode: FocusChainMode.regular,
    durationSeconds: effectiveSeconds,
    startedAt: startedAt,
    endsAt: startedAt.add(Duration(seconds: effectiveSeconds)),
    status: status,
    completedAt: startedAt.add(Duration(seconds: effectiveSeconds)),
    effectiveSeconds: effectiveSeconds,
  );
}

Future<void> _savePng(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
) async {
  final object = boundaryKey.currentContext?.findRenderObject();
  if (object is! RenderRepaintBoundary)
    fail('screenshot "$name": boundary missing');
  final image = await object.toImage(pixelRatio: tester.view.devicePixelRatio);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) fail('screenshot "$name": PNG encoding failed');
  final directory = Directory('build/ui-layout-evidence/$_evidenceDir');
  await directory.create(recursive: true);
  final file = File('${directory.path}/$name.png');
  if (await file.exists()) fail('screenshot "$name": refusing to overwrite');
  await file.writeAsBytes(data.buffer.asUint8List());
  print('[profile-fixture] ${file.absolute.path}');
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('我的名片统计与资料页离线布局', (tester) async {
    final boundaryKey = GlobalKey();
    final database = PactaDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final profile = LocalProfileRepository(
      database: database,
      userId: 'profile-pilot',
      remote: _FixtureProfileRemote(),
      now: () => DateTime.utc(2026, 11, 13, 9),
    );
    await profile.saveProfile(
      displayName: '小林',
      avatar: ProfileAvatar(
        bytes: _avatarPng,
        mimeType: AvatarImageFormat.png.mimeType,
      ),
    );
    final overview = _FixtureOverview(
      cards: [
        _card(
          '晨光校准',
          isInTree: true,
          state: NationalFocusCardState.lit,
          successfulDays: 42,
          currentConsecutiveDays: 9,
        ),
        _card('夜间复盘', isInTree: true, successfulDays: 180),
        _card('周末长读', isInTree: false, successfulDays: 210),
        _card(
          '待确认节点',
          isInTree: true,
          state: NationalFocusCardState.pendingTodayConfirmation,
        ),
      ],
      sessions: [
        _session('session-a', 1500),
        _session('session-b', 2700),
        _session('session-failed', 600, status: FocusSessionStatus.failed),
      ],
    );

    final brightness = _lightMode ? Brightness.light : Brightness.dark;
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          theme: pactaTheme(brightness),
          home: Scaffold(
            appBar: AppBar(title: const Text('我的')),
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  MyProfileCard(
                    repository: profile,
                    overview: overview,
                    avatarPicker: _FixtureAvatarPicker(),
                    accountIdentifier: 'fixture@example.com',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final suffix = _lightMode ? 'light' : 'dark';
    await _capture(tester, binding, boundaryKey, 'profile-card-$suffix');

    await tester.tap(find.text('点亮 1'));
    await tester.pumpAndSettle();
    await _capture(
      tester,
      binding,
      boundaryKey,
      'profile-national-detail-$suffix',
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成 2 次'));
    await tester.pumpAndSettle();
    await _capture(
      tester,
      binding,
      boundaryKey,
      'profile-focus-detail-$suffix',
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    await _capture(tester, binding, boundaryKey, 'profile-edit-$suffix');
  });
}

Future<void> _capture(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  GlobalKey boundaryKey,
  String name,
) async {
  if (Platform.isAndroid) {
    await binding.takeScreenshot(name);
    return;
  }
  await _savePng(tester, boundaryKey, name);
}
