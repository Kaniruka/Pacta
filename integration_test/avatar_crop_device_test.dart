import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/main.dart' show pactaTheme;
import 'package:pacta/src/profile/avatar_image.dart';
import 'package:pacta/src/profile/avatar_picker.dart';
import 'package:pacta/src/profile/profile_edit_page.dart';
import 'package:pacta/src/profile/profile_remote.dart';
import 'package:pacta/src/profile/profile_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

const _dark = bool.fromEnvironment('AVATAR_CROP_DARK');
const _captureDir = String.fromEnvironment('AVATAR_CROP_CAPTURE_DIR');
const _captureKey = ValueKey('avatar-crop-fixture-capture');
const _viewportKey = ValueKey('avatar-crop-viewport');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('crop, cancel and save an avatar on the device', (tester) async {
    final source = await _samplePortrait();
    final database = PactaDatabase(NativeDatabase.memory());
    final remote = _MemoryProfileRemote();
    final repository = LocalProfileRepository(
      database: database,
      userId: 'avatar-crop-device-fixture',
      remote: remote,
    );
    await repository.saveProfile(displayName: '小林');
    try {
      await tester.pumpWidget(
        RepaintBoundary(
          key: _captureKey,
          child: MaterialApp(
            theme: pactaTheme(_dark ? Brightness.dark : Brightness.light),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    key: const ValueKey('avatar-fixture-open-profile'),
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => ProfileEditPage(
                          repository: repository,
                          avatarPicker: _SamplePicker(source),
                        ),
                      ),
                    ),
                    child: const Text('编辑资料'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (Platform.isAndroid) {
        await binding.convertFlutterSurfaceToImage();
        await tester.pump();
      }
      await tester.tap(find.text('编辑资料'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择图片'));
      await _waitFor(tester, find.byKey(_viewportKey));
      await _capture(tester, binding, '01-crop-initial');

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect((await repository.getProfile()).avatar, isNull);
      expect(remote.stored?.avatar, isNull);

      await tester.tap(find.text('选择图片'));
      await _waitFor(tester, find.byKey(_viewportKey));
      final slider = tester.getRect(find.byType(Slider));
      await tester.tapAt(
        Offset(slider.left + slider.width * .6, slider.center.dy),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(_viewportKey),
        const Offset(-65, 20),
        kind: Platform.isWindows
            ? ui.PointerDeviceKind.mouse
            : ui.PointerDeviceKind.touch,
      );
      await tester.pumpAndSettle();
      await _capture(tester, binding, '02-crop-adjusted');
      if (Platform.isAndroid) {
        final center = tester.getCenter(find.byKey(_viewportKey));
        final first = await tester.startGesture(
          center - const Offset(35, 0),
          pointer: 61,
        );
        final second = await tester.startGesture(
          center + const Offset(35, 0),
          pointer: 62,
        );
        await tester.pump();
        await first.moveTo(center - const Offset(55, 0));
        await second.moveTo(center + const Offset(55, 0));
        await tester.pump();
        await first.up();
        await second.up();
        await tester.pumpAndSettle();
        await _capture(tester, binding, '02b-crop-pinch');
      }
      await tester.tap(find.text('重置'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(_viewportKey),
        const Offset(-80, 0),
        kind: Platform.isWindows
            ? ui.PointerDeviceKind.mouse
            : ui.PointerDeviceKind.touch,
      );
      await tester.pumpAndSettle();
      await _capture(tester, binding, '03-crop-positioned');
      await tester.tap(find.text('使用此头像'));
      await _waitFor(tester, find.text('重新裁剪'));
      expect((await repository.getProfile()).avatar, isNull);
      expect(remote.stored?.avatar, isNull);
      await _capture(tester, binding, '04-profile-draft');
      await tester.tap(find.text('保存'));
      await _waitFor(
        tester,
        find.byKey(const ValueKey('avatar-fixture-open-profile')),
      );
      final saved = (await repository.getProfile()).avatar!;
      expect(saved.bytes.length, lessThanOrEqualTo(maxAvatarStoredBytes));
      expect(remote.stored?.avatar?.bytes, orderedEquals(saved.bytes));
      final codec = await ui.instantiateImageCodec(saved.bytes);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, frame.image.height);
      expect(frame.image.width, lessThanOrEqualTo(maxAvatarEdgePixels));
      frame.image.dispose();
      codec.dispose();

      await tester.tap(find.text('编辑资料'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重新裁剪'));
      await _waitFor(tester, find.byKey(_viewportKey));
      await _capture(tester, binding, '05-existing-avatar-crop');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(
        (await repository.getProfile()).avatar?.bytes,
        orderedEquals(saved.bytes),
      );
      await _capture(tester, binding, '06-saved-avatar');
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await repository.dispose();
      await database.close();
    }
  });
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
  }
  expect(finder, findsOneWidget);
  await tester.pumpAndSettle();
}

Future<void> _capture(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  String name,
) async {
  await tester.pumpAndSettle();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );
  await tester.pump();
  if (Platform.isAndroid) {
    await binding.takeScreenshot(name);
    return;
  }
  if (!Platform.isWindows || _captureDir.isEmpty) return;
  if (!RegExp(r'^[A-Za-z]:[\\/]').hasMatch(_captureDir)) {
    throw StateError('Capture directory must be an absolute Windows path.');
  }
  final file = File('$_captureDir/$name.png');
  await file.parent.create(recursive: true);
  if (file.existsSync()) throw StateError('Refusing to overwrite evidence.');
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  final image = await boundary.toImage(pixelRatio: 1);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await file.writeAsBytes(data!.buffer.asUint8List(), flush: true);
  } finally {
    image.dispose();
  }
}

Future<Uint8List> _samplePortrait() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 720, 480),
    Paint()..color = const Color(0xffd5ece6),
  );
  canvas.drawRect(
    const Rect.fromLTWH(450, 0, 270, 480),
    Paint()..color = const Color(0xfff8d287),
  );
  canvas.drawCircle(
    const Offset(480, 245),
    130,
    Paint()..color = const Color(0xff224e73),
  );
  canvas.drawCircle(
    const Offset(480, 225),
    90,
    Paint()..color = const Color(0xfff4bba0),
  );
  canvas.drawCircle(
    const Offset(450, 215),
    9,
    Paint()..color = const Color(0xff18374c),
  );
  canvas.drawCircle(
    const Offset(510, 215),
    9,
    Paint()..color = const Color(0xff18374c),
  );
  canvas.drawArc(
    const Rect.fromLTWH(453, 230, 54, 35),
    0,
    3.14159,
    false,
    Paint()
      ..color = const Color(0xff934e49)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7,
  );
  canvas.drawCircle(
    const Offset(130, 120),
    55,
    Paint()..color = const Color(0xff51a495),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(720, 480);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

class _SamplePicker implements AvatarPicker {
  _SamplePicker(this.bytes);
  final Uint8List bytes;
  @override
  Future<Uint8List?> pickSingleImage() async => bytes;
}

class _MemoryProfileRemote implements ProfileRemote {
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
    return stored = RemoteProfile(
      displayName: displayName,
      avatar: avatar,
      updatedAt: updatedAt,
    );
  }
}
