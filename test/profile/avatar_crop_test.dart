import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/profile/avatar_picker.dart';
import 'package:pacta/src/profile/avatar_image.dart';
import 'package:pacta/src/profile/profile_edit_page.dart';
import 'package:pacta/src/profile/profile_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

class _Picker implements AvatarPicker {
  _Picker(this.bytes);
  final Uint8List bytes;
  @override
  Future<Uint8List?> pickSingleImage() async => bytes;
}

void main() {
  for (final mode in [0, 1, 2]) {
    final portrait = mode == 1;
    final zoomOnly = mode == 2;
    testWidgets(
      '裁剪确认只更新草稿，取消不写资料，保存才保留所选位置 portrait=$portrait zoom=$zoomOnly',
      (tester) async {
        final db = PactaDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final repo = LocalProfileRepository(database: db, userId: 'crop-user');
        await tester.runAsync(repo.getProfile);
        final bytes = await tester.runAsync(() async {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          canvas.drawRect(
            Rect.fromLTWH(0, 0, portrait ? 200 : 600, portrait ? 600 : 200),
            Paint()..color = Colors.red,
          );
          canvas.drawRect(
            Rect.fromLTWH(
              zoomOnly ? 275 : (portrait ? 0 : 400),
              zoomOnly ? 75 : (portrait ? 400 : 0),
              zoomOnly ? 50 : 200,
              zoomOnly ? 50 : 200,
            ),
            Paint()..color = Colors.blue,
          );
          final picture = recorder.endRecording();
          final image = await picture.toImage(
            portrait ? 200 : 600,
            portrait ? 600 : 200,
          );
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          picture.dispose();
          return data!.buffer.asUint8List();
        });
        await tester.runAsync(
          () => repo.saveProfile(
            displayName: '旧昵称',
            avatar: ProfileAvatar(bytes: bytes!, mimeType: 'image/png'),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: ProfileEditPage(
              repository: repo,
              avatarPicker: _Picker(bytes!),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await tester.tap(find.text('选择图片'));
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        await tester.pumpAndSettle();
        expect(find.text('裁剪头像'), findsOneWidget);
        await tester.tapAt(
          tester.getTopRight(find.byType(Slider)) - const Offset(24, -24),
        );
        await tester.pump();
        if (!zoomOnly) {
          await tester.tap(find.text('重置'));
          await tester.pump();
          await tester.timedDrag(
            find.byKey(const ValueKey('avatar-crop-viewport')),
            portrait ? const Offset(0, -400) : const Offset(-400, 0),
            const Duration(milliseconds: 500),
          );
        }
        await tester.pump();
        await tester.ensureVisible(find.text('使用此头像'));
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await tester.tap(find.text('使用此头像'));
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        await tester.pumpAndSettle();
        expect(
          (await tester.runAsync(repo.getProfile))!.avatar!.bytes,
          orderedEquals(bytes),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await tester.tap(find.text('重新裁剪'));
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        await tester.pumpAndSettle();
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(
          (await tester.runAsync(repo.getProfile))!.avatar!.bytes,
          orderedEquals(bytes),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pump();
        expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, '保存'))
              .onPressed,
          isNotNull,
        );
        await tester.runAsync(() async {
          await tester.tap(find.text('保存'));
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
        }
        final saved = (await tester.runAsync(repo.getProfile))!.avatar!;
        expect(saved.bytes.length, lessThanOrEqualTo(maxAvatarStoredBytes));
        final pixels = await tester.runAsync(() async {
          final codec = await ui.instantiateImageCodec(saved.bytes);
          final image = (await codec.getNextFrame()).image;
          expect(image.width, lessThanOrEqualTo(384));
          expect(image.width, image.height);
          final pixels = await image.toByteData();
          image.dispose();
          codec.dispose();
          return pixels!;
        });
        for (var offset = 3; offset < pixels!.lengthInBytes; offset += 4) {
          expect(pixels.getUint8(offset), 255, reason: '移动到边缘后不得出现透明空白');
        }
        expect(
          pixels.getUint8(
            zoomOnly
                ? (192 * 384 + 160) * 4 + 2
                : pixels.lengthInBytes ~/ 2 + 384 * 2 + 2,
          ),
          greaterThan(240),
          reason: '移动到右侧后输出蓝色，而非固定中央的红色',
        );
      },
    );
  }
}
