import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_tree_page.dart';
import 'package:pacta/src/national_focus/national_focus_view_preferences.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late PactaDatabase database;
  late LocalNationalFocusRepository repository;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    database = PactaDatabase(NativeDatabase.memory());
    repository = LocalNationalFocusRepository(
      database: database,
      userId: 'user-a',
      cloudSyncEnabled: false,
    );
  });

  tearDown(() async {
    await repository.dispose();
    await database.close();
  });

  Future<void> pumpPage(
    WidgetTester tester,
    String userId, {
    Brightness brightness = Brightness.light,
    NationalFocusViewPreferences viewPreferences =
        const NationalFocusViewPreferences(),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF385A52),
            brightness: brightness,
          ),
        ),
        home: Scaffold(
          body: NationalFocusTreePage(
            repository: repository,
            userId: userId,
            viewPreferences: viewPreferences,
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('详细视图跨页面重建恢复并按本机用户隔离', (tester) async {
    await pumpPage(tester, 'user-a');
    expect(find.text('简洁视图'), findsOneWidget);

    await tester.tap(find.text('简洁视图'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('详细视图').last);
    await tester.pumpAndSettle();
    expect(find.text('详细视图'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await pumpPage(tester, 'user-a');
    expect(find.text('详细视图'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await pumpPage(tester, 'user-b');
    expect(find.text('简洁视图'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await pumpPage(tester, 'user-a');
    expect(find.text('详细视图'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('视图偏好读取失败时回退简洁并可重试', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 812);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(
      'pacta.device.national_focus.detailed.user-a',
      true,
    );
    final failingPreferences = _FailFirstReloadPreferences(preferences);
    final viewPreferences = NationalFocusViewPreferences(
      preferencesLoader: () async => failingPreferences,
    );

    await pumpPage(
      tester,
      'user-a',
      viewPreferences: viewPreferences,
      brightness: Brightness.dark,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('简洁视图'), findsOneWidget);
    expect(find.text('视图偏好读取失败，暂用简洁视图。'), findsOneWidget);
    expect(find.text('重试读取'), findsOneWidget);

    await tester.tap(find.text('重试读取'));
    await tester.pumpAndSettle();
    expect(find.text('详细视图'), findsOneWidget);
    expect(find.text('视图偏好读取失败，暂用简洁视图。'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('视图偏好写入失败不误报且可再次保存', (tester) async {
    final preferences = await SharedPreferences.getInstance();
    final failingPreferences = _FailFirstSetBoolPreferences(preferences);
    final viewPreferences = NationalFocusViewPreferences(
      preferencesLoader: () async => failingPreferences,
    );

    await pumpPage(tester, 'user-a', viewPreferences: viewPreferences);
    await tester.tap(find.text('简洁视图'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('详细视图').last);
    await tester.pumpAndSettle();
    expect(find.text('视图偏好未保存，请重试。'), findsOneWidget);
    expect(find.text('重试保存'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await pumpPage(tester, 'user-a', viewPreferences: viewPreferences);
    expect(find.text('简洁视图'), findsOneWidget);

    failingPreferences.failNextWrite();
    await tester.tap(find.text('简洁视图'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('详细视图').last);
    await tester.pumpAndSettle();
    expect(find.text('视图偏好未保存，请重试。'), findsOneWidget);
    expect(find.text('重试保存'), findsOneWidget);

    await tester.tap(find.text('重试保存'));
    await tester.pumpAndSettle();
    expect(find.text('详细视图'), findsOneWidget);
    expect(find.text('视图偏好未保存，请重试。'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await pumpPage(tester, 'user-a', viewPreferences: viewPreferences);
    expect(find.text('详细视图'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('云快照上传和下载不包含或覆盖本机视图偏好', (tester) async {
    const viewPreferences = NationalFocusViewPreferences();
    await viewPreferences.save('user-a', true);

    final remote = InMemoryCloudSnapshotRemote();
    final cloudRepository = CloudSnapshotRepository(
      database: database,
      remote: remote,
      userId: 'user-a',
      deviceId: 'device-a',
      deviceName: 'Phone A',
    );
    final beforeUpload = await cloudRepository.captureLocalState();
    final uploaded = await cloudRepository.uploadLocal(
      expectedRevision: 0,
      expectedFingerprint: beforeUpload.fingerprint,
    );

    await viewPreferences.save('user-a', false);
    final beforeDownload = await cloudRepository.captureLocalState();
    expect(beforeDownload.fingerprint, beforeUpload.fingerprint);
    expect(beforeDownload.payload, beforeUpload.payload);
    expect(
      jsonEncode(uploaded.payload),
      isNot(contains('pacta.device.national_focus.detailed.user-a')),
    );

    await cloudRepository.downloadCloud(
      expectedRevision: uploaded.revision,
      expectedFingerprint: beforeDownload.fingerprint,
    );
    final afterDownload = await cloudRepository.captureLocalState();
    expect(afterDownload.fingerprint, beforeUpload.fingerprint);
    expect(afterDownload.payload, beforeUpload.payload);

    await pumpPage(tester, 'user-a');
    expect(find.text('简洁视图'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(await viewPreferences.load('user-a'), isFalse);
  });

  testWidgets('旧用户延迟读取完成不会覆盖当前用户的视图', (tester) async {
    const store = NationalFocusViewPreferences();
    await store.save('user-a', true);
    final preferences = await SharedPreferences.getInstance();
    final delayedRead = Completer<SharedPreferences>();
    var firstRead = true;
    final delayedStore = NationalFocusViewPreferences(
      preferencesLoader: () {
        if (firstRead) {
          firstRead = false;
          return delayedRead.future;
        }
        return Future.value(preferences);
      },
    );
    await pumpPage(tester, 'user-a', viewPreferences: delayedStore);
    await pumpPage(tester, 'user-b', viewPreferences: delayedStore);
    expect(find.text('简洁视图'), findsOneWidget);
    delayedRead.complete(preferences);
    await tester.pumpAndSettle();
    expect(find.text('简洁视图'), findsOneWidget);
    expect(find.text('正在更新视图…'), findsNothing);
    await pumpPage(tester, 'user-a', viewPreferences: delayedStore);
    expect(find.text('详细视图'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('同一页面状态切换用户时分别读取各自视图偏好', (tester) async {
    const viewPreferences = NationalFocusViewPreferences();
    await viewPreferences.save('user-a', true);
    await viewPreferences.save('user-b', false);

    await pumpPage(tester, 'user-a', viewPreferences: viewPreferences);
    expect(find.text('详细视图'), findsOneWidget);

    await pumpPage(tester, 'user-b', viewPreferences: viewPreferences);
    expect(find.text('简洁视图'), findsOneWidget);

    await pumpPage(tester, 'user-a', viewPreferences: viewPreferences);
    expect(find.text('详细视图'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

class _FailFirstReloadPreferences implements SharedPreferences {
  _FailFirstReloadPreferences(this._delegate);

  final SharedPreferences _delegate;
  var _shouldFail = true;

  @override
  Future<void> reload() async {
    if (_shouldFail) {
      _shouldFail = false;
      throw StateError('Injected preference read failure');
    }
    await _delegate.reload();
  }

  @override
  bool? getBool(String key) => _delegate.getBool(key);

  @override
  Future<bool> setBool(String key, bool value) => _delegate.setBool(key, value);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailFirstSetBoolPreferences implements SharedPreferences {
  _FailFirstSetBoolPreferences(this._delegate);

  final SharedPreferences _delegate;
  var _shouldFail = true;
  final _failedCache = <String, bool>{};

  void failNextWrite() => _shouldFail = true;

  @override
  Future<void> reload() async {
    await _delegate.reload();
    _failedCache.clear();
  }

  @override
  bool? getBool(String key) => _failedCache[key] ?? _delegate.getBool(key);

  @override
  Future<bool> setBool(String key, bool value) {
    if (_shouldFail) {
      _shouldFail = false;
      // Legacy SharedPreferences updates its cache before a disk write fails.
      _failedCache[key] = value;
      return Future<bool>.value(false);
    }
    return _delegate.setBool(key, value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
