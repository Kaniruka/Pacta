import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/main.dart' show pactaTheme;
import 'package:pacta/src/profile/avatar_image.dart';
import 'package:pacta/src/profile/avatar_picker.dart';

const _expectCancel = bool.fromEnvironment('PICKER_EXPECT_CANCEL');
const _evidenceFile = String.fromEnvironment('PICKER_EVIDENCE_FILE');
const _pickerTimeout = Duration(minutes: 5);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('opens the native single-image picker and validates its result', (
    tester,
  ) async {
    final picker = const SystemAvatarPicker();
    final result = Completer<Uint8List?>();
    await tester.pumpWidget(
      MaterialApp(
        theme: pactaTheme(Brightness.light),
        home: Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                _record('PICKER_OPENED');
                try {
                  result.complete(await picker.pickSingleImage());
                } catch (error, stackTrace) {
                  result.completeError(error, stackTrace);
                }
              },
              child: const Text('选择头像图片'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('选择头像图片'));
    await tester.pump();
    final selected = await result.future.timeout(_pickerTimeout);

    if (_expectCancel) {
      expect(selected, isNull, reason: 'Expected the native picker to cancel.');
      _record('PICKER_CANCELLED');
    } else {
      expect(
        selected,
        isNotNull,
        reason: 'Select one PNG or JPEG in the native picker.',
      );
      final source = selected!;
      final format = validateAvatarSelection(source);
      final prepared = await prepareAvatarForUpload(source);
      expect(prepared.bytes, isNotEmpty);
      expect(prepared.mimeType, AvatarImageFormat.png.mimeType);
      _record(
        'PICKER_SELECTED bytes=${prepared.bytes.length} mime=${format.mimeType}',
      );
    }
    _record('PASS');
  }, timeout: const Timeout(_pickerTimeout));
}

void _record(String message) {
  // Keep evidence content limited to status and byte/MIME metadata.
  // No image bytes, selected-file paths, or credentials are recorded.
  // ignore: avoid_print
  print(message);
  if (_evidenceFile.isEmpty) return;
  File(_evidenceFile).writeAsStringSync(
    '${DateTime.now().toIso8601String()} $message\n',
    mode: FileMode.append,
    flush: true,
  );
}
