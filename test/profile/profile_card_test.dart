import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/profile/account_time_zone.dart';
import 'package:pacta/src/profile/avatar_image.dart';
import 'package:pacta/src/profile/avatar_picker.dart';
import 'package:pacta/src/profile/profile_card.dart';
import 'package:pacta/src/profile/profile_edit_page.dart';
import 'package:pacta/src/profile/profile_models.dart';
import 'package:pacta/src/profile/profile_overview.dart';
import 'package:pacta/src/profile/profile_repository.dart';

class _FakeProfileRepository implements ProfileRepository {
  _FakeProfileRepository({ProfileAccount? account})
    : _account = account ?? ProfileAccount(userId: 'user-a');

  final StreamController<ProfileAccount> _updates =
      StreamController<ProfileAccount>.broadcast(sync: true);
  ProfileAccount _account;
  String? saveErrorMessage;

  /// 首次读取失败：仓储只在内存里报告错误，不写本机版本。
  String? syncErrorMessage;

  /// 同步直接抛出（错误甚至没能写入缓存行）。
  Object? syncThrownError;

  /// 让同步停在请求中，测试可在此期间触发另一入口的保存。
  Completer<void>? syncGate;

  /// 重试成功时账号存储返回的资料（例如另一台设备刚写入的时区）。
  ProfileAccount? syncResultOverride;
  int saveCalls = 0;
  int syncCalls = 0;
  ProfileAvatar? lastSavedAvatar;
  bool? lastClearAvatar;
  String? lastTimeZoneId;
  String? lastDeviceTimeZoneId;
  int ensureTimeZoneCalls = 0;

  @override
  Stream<ProfileAccount> watchProfile() async* {
    yield _account;
    yield* _updates.stream;
  }

  @override
  Future<ProfileAccount> getProfile() async => _account;

  @override
  Future<ProfileAccount> saveProfile({
    required String displayName,
    ProfileAvatar? avatar,
    bool clearAvatar = false,
    String? timeZoneId,
  }) async {
    saveCalls++;
    lastSavedAvatar = avatar;
    lastClearAvatar = clearAvatar;
    lastTimeZoneId = timeZoneId;
    final failure = saveErrorMessage;
    _account = _account.copyWith(
      displayName: displayName,
      avatar: avatar,
      clearAvatar: clearAvatar,
      // null 表示"保留账号时区"，与本仓储契约一致；只有显式选择才改写。
      displayTimeZoneId: timeZoneId ?? _account.displayTimeZoneId,
      updatedAt: DateTime.utc(2026, 11, 13),
      hasPendingSave: failure != null,
      clearSyncError: true,
    );
    _updates.add(_account);
    // 与真实仓储一致：编辑保存失败只回给本次调用（编辑页），不写进对外只读
    // 状态，退出编辑页后名片不会再看到这条报错。
    return failure == null ? _account : _account.copyWith(syncError: failure);
  }

  @override
  Future<ProfileAccount> ensureDisplayTimeZone({
    String? deviceTimeZoneId,
  }) async {
    ensureTimeZoneCalls++;
    lastDeviceTimeZoneId = deviceTimeZoneId;
    return _account;
  }

  @override
  Future<ProfileAccount> syncProfile() async {
    syncCalls++;
    final gate = syncGate;
    if (gate != null) await gate.future;
    final thrown = syncThrownError;
    if (thrown != null) throw thrown;
    final override = syncResultOverride;
    if (override != null) {
      _account = override;
      _updates.add(_account);
      return override;
    }
    if (syncErrorMessage != null) {
      // 与真实仓储一致：没有缓存行时只返回内存错误，不产生本机资料版本。
      return _account.copyWith(syncError: syncErrorMessage);
    }
    if (saveErrorMessage != null) {
      // 待上传的重试仍然失败：错误只回给本次调用，缓存行保持干净。
      return _account.copyWith(syncError: saveErrorMessage);
    }
    _account = _account.copyWith(hasPendingSave: false, clearSyncError: true);
    _updates.add(_account);
    return _account;
  }

  @override
  Future<void> dispose() async {}
}

class _FakeOverviewSource implements ProfileOverviewSource {
  final StreamController<List<NationalFocusCard>> cards =
      StreamController<List<NationalFocusCard>>.broadcast(sync: true);
  final StreamController<List<FocusSession>> sessions =
      StreamController<List<FocusSession>>.broadcast(sync: true);

  List<NationalFocusCard>? lastCards;
  List<FocusSession>? lastSessions;

  // 明细页在卡片之后才订阅，因此像 Drift 的 watch 流一样重放最近一次结果。
  @override
  Stream<List<NationalFocusCard>> watchCards() async* {
    if (lastCards != null) yield lastCards!;
    yield* cards.stream;
  }

  @override
  Stream<List<FocusSession>> watchSessions() async* {
    if (lastSessions != null) yield lastSessions!;
    yield* sessions.stream;
  }

  Future<void> emit({
    List<NationalFocusCard> cards = const [],
    List<FocusSession> sessions = const [],
  }) async {
    lastCards = cards;
    lastSessions = sessions;
    this.cards.add(cards);
    this.sessions.add(sessions);
  }
}

class _FakeAvatarPicker implements AvatarPicker {
  _FakeAvatarPicker(this.bytes);

  Uint8List? bytes;
  int calls = 0;

  @override
  Future<Uint8List?> pickSingleImage() async {
    calls++;
    return bytes;
  }
}

final Uint8List _onePixelPng = Uint8List.fromList(const [
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

NationalFocusCard _card(
  String name, {
  required bool isInTree,
  NationalFocusCardState state = NationalFocusCardState.extinguished,
  int successfulDays = 0,
}) => NationalFocusCard(
  id: name,
  name: name,
  triggerCondition: '触发',
  action: '行动',
  isInTree: isInTree,
  state: state,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
  successfulDays: successfulDays,
  currentConsecutiveDays: 4,
);

FocusSession _completedSession(int effectiveSeconds) {
  final startedAt = DateTime.utc(2026, 11, 12, 9);
  return FocusSession(
    id: 'session',
    taskId: 'task',
    mode: FocusChainMode.regular,
    durationSeconds: effectiveSeconds,
    startedAt: startedAt,
    endsAt: startedAt.add(Duration(seconds: effectiveSeconds)),
    status: FocusSessionStatus.completed,
    completedAt: startedAt.add(Duration(seconds: effectiveSeconds)),
    effectiveSeconds: effectiveSeconds,
  );
}

void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    required _FakeProfileRepository repository,
    required _FakeOverviewSource overview,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MyProfileCard(
            repository: repository,
            overview: overview,
            avatarPicker: _FakeAvatarPicker(_onePixelPng),
            accountIdentifier: 'person@example.com',
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('空资料显示占位昵称与 0 统计', (tester) async {
    final repository = _FakeProfileRepository();
    final overview = _FakeOverviewSource();
    await pumpCard(tester, repository: repository, overview: overview);
    await overview.emit();
    await tester.pump();

    expect(find.text('当前用户'), findsOneWidget);
    expect(find.text('点亮 0'), findsOneWidget);
    expect(find.text('已内化 0'), findsOneWidget);
    expect(find.text('完成 0 次'), findsOneWidget);
    expect(find.text('累计 0 分钟'), findsOneWidget);
  });

  testWidgets('名片显示未删除卡片的统计与专注累计时间', (tester) async {
    final repository = _FakeProfileRepository(
      account: ProfileAccount(userId: 'user-a', displayName: '小林'),
    );
    final overview = _FakeOverviewSource();
    await pumpCard(tester, repository: repository, overview: overview);
    await overview.emit(
      cards: [
        _card('晨光', isInTree: true, state: NationalFocusCardState.lit),
        _card('已内化一', isInTree: true, successfulDays: 180),
        _card('已内化二', isInTree: false, successfulDays: 200),
      ],
      sessions: [_completedSession(900)],
    );
    await tester.pump();

    expect(find.text('小林'), findsOneWidget);
    expect(find.text('点亮 1'), findsOneWidget);
    expect(find.text('已内化 2'), findsOneWidget);
    expect(find.text('完成 1 次'), findsOneWidget);
    expect(find.text('累计 15 分钟'), findsOneWidget);
  });

  testWidgets('首次资料读取失败在名片显示原因并可重试，且不编造本机资料', (tester) async {
    final repository = _FakeProfileRepository();
    repository.syncErrorMessage = '保存失败：云端暂不可用';
    final overview = _FakeOverviewSource();
    await pumpCard(tester, repository: repository, overview: overview);
    await overview.emit();
    await tester.pump();

    // 缓存里没有资料行，错误只存在于首次同步的返回值里；名片必须自己显示它。
    expect(find.text('保存失败：云端暂不可用'), findsOneWidget);
    expect(find.text('当前用户'), findsOneWidget);
    expect(repository.saveCalls, 0, reason: '读取失败不得写本机资料版本');

    repository.syncErrorMessage = null;
    await tester.tap(find.text('重试'));
    await tester.pump();

    expect(find.text('保存失败：云端暂不可用'), findsNothing);
    expect(repository.syncCalls, 2);
  });

  testWidgets('已有可展示资料时同步失败不把只读名片变成报错卡', (tester) async {
    final repository = _FakeProfileRepository(
      account: ProfileAccount(
        userId: 'user-a',
        displayName: '小林',
        updatedAt: DateTime.utc(2026, 11, 12),
      ),
    );
    repository.syncThrownError = StateError('资料服务暂时不可用');
    final overview = _FakeOverviewSource();
    await pumpCard(tester, repository: repository, overview: overview);
    await overview.emit();
    await tester.pump();

    // 名片有资料可展示：同步失败只在需要时由用户重试，不把整张名片变成
    // 报错（错误行只服务于"无可展示资料"的首次读取失败）。
    expect(find.text('资料服务暂时不可用'), findsNothing);
    expect(find.textContaining('资料服务暂时不可用'), findsNothing);
    expect(find.text('小林'), findsOneWidget);
    expect(repository.syncCalls, 1, reason: '重试只由用户触发');

    repository.syncThrownError = null;
    await repository.saveProfile(displayName: '小林二号');
    await tester.pump();
    expect(find.text('小林二号'), findsOneWidget);
  });

  testWidgets('同步期间并发保存成功后，这次尝试的失败不挂到新版本', (tester) async {
    final repository = _FakeProfileRepository(
      account: ProfileAccount(
        userId: 'user-a',
        displayName: '小林',
        updatedAt: DateTime.utc(2026, 11, 12),
      ),
    );
    final gate = Completer<void>();
    repository.syncGate = gate;
    repository.syncThrownError = StateError('资料服务暂时不可用');
    final overview = _FakeOverviewSource();
    await pumpCard(tester, repository: repository, overview: overview);
    await overview.emit();
    await tester.pump();

    // 请求仍在途中时另一入口保存成功：缓存行推进到新版本。
    await repository.saveProfile(displayName: '小林二号');
    await tester.pump();
    expect(find.text('小林二号'), findsOneWidget);
    expect(repository.syncThrownError, isA<StateError>());

    gate.complete();
    await tester.pumpAndSettle();

    expect(
      find.text('资料服务暂时不可用'),
      findsNothing,
      reason: '失败属于请求开始时的那一版缓存，不得挂到新版本',
    );
    expect(find.text('小林二号'), findsOneWidget);
  });

  testWidgets('统计尚未读到记录时显示加载状态而不是零', (tester) async {
    final repository = _FakeProfileRepository();
    final overview = _FakeOverviewSource();
    await pumpCard(tester, repository: repository, overview: overview);

    expect(find.text('点亮 0'), findsNothing);
    expect(find.text('已内化 0'), findsNothing);
    expect(find.text('完成 0 次'), findsNothing);
    expect(find.text('累计 0 分钟'), findsNothing);
    expect(find.text('正在读取…'), findsNWidgets(2));
  });

  testWidgets('统计读取失败显示失败与重试，不把不可读记录当成零', (tester) async {
    final repository = _FakeProfileRepository();
    final overview = _FakeOverviewSource();
    await pumpCard(tester, repository: repository, overview: overview);
    await overview.emit(
      cards: [_card('晨光', isInTree: true, state: NationalFocusCardState.lit)],
      sessions: [_completedSession(900)],
    );
    await tester.pump();

    overview.cards.addError(StateError('国策记录暂时不可读'));
    await tester.pump();

    expect(find.text('点亮 0'), findsNothing);
    expect(find.text('统计暂时无法读取'), findsOneWidget);
    expect(find.text('完成 1 次'), findsOneWidget, reason: '另一组可读时照常显示');

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text('统计暂时无法读取'), findsNothing);
    expect(find.text('点亮 1'), findsOneWidget);
  });

  testWidgets('点击国策统计组进入可读的详细记录', (tester) async {
    final repository = _FakeProfileRepository();
    final overview = _FakeOverviewSource();
    await pumpCard(tester, repository: repository, overview: overview);
    await overview.emit(
      cards: [
        _card('晨光', isInTree: true, state: NationalFocusCardState.lit),
        _card('已内化一', isInTree: true, successfulDays: 180),
      ],
    );
    await tester.pump();

    await tester.tap(find.text('点亮 1'));
    await tester.pumpAndSettle();

    expect(find.text('国策统计明细'), findsOneWidget);
    expect(find.text('晨光'), findsOneWidget);
    expect(find.text('已内化一'), findsOneWidget);
  });

  testWidgets('点击专注统计组进入已完成专注记录', (tester) async {
    final repository = _FakeProfileRepository();
    final overview = _FakeOverviewSource();
    await pumpCard(tester, repository: repository, overview: overview);
    await overview.emit(sessions: [_completedSession(900)]);
    await tester.pump();

    await tester.tap(find.text('完成 1 次'));
    await tester.pumpAndSettle();

    expect(find.text('专注统计明细'), findsOneWidget);
    expect(find.text('有效时间 15 分钟'), findsOneWidget);
  });

  testWidgets('编辑保存失败只属于编辑页，只读名片继续显示本机资料', (tester) async {
    final repository = _FakeProfileRepository();
    repository.saveErrorMessage = '保存失败：网络不可用';
    final overview = _FakeOverviewSource();
    await pumpCard(tester, repository: repository, overview: overview);
    await overview.emit();
    await tester.pump();

    await repository.saveProfile(displayName: '小林');
    await tester.pump();

    // 失败回给了编辑页的调用方，读到的缓存行仍然没有错误。
    expect(find.text('保存失败：网络不可用'), findsNothing);
    expect(find.text('小林'), findsOneWidget);
    final cached = await repository.getProfile();
    expect(cached.hasPendingSave, isTrue, reason: '待上传意图保留，重试路径不变');
    expect(cached.syncError, isNull, reason: '保存报错不得成为只读名片的永久错误');
  });

  testWidgets('名片身份整行是编辑入口，不再单列编辑按钮', (tester) async {
    final repository = _FakeProfileRepository(
      account: ProfileAccount(userId: 'user-a', displayName: '小林'),
    );
    final overview = _FakeOverviewSource();
    await pumpCard(tester, repository: repository, overview: overview);
    await overview.emit();
    await tester.pump();

    expect(find.text('数据仅供你使用'), findsNothing);
    expect(find.widgetWithText(TextButton, '编辑'), findsNothing);
    final entry = find.byTooltip('编辑资料');
    expect(entry, findsOneWidget);
    expect(
      tester.getSize(entry).height,
      greaterThanOrEqualTo(48),
      reason: '整行点击区至少 48dp',
    );

    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.byType(ProfileEditPage), findsOneWidget);
    expect(find.text('编辑资料'), findsOneWidget, reason: '编辑页标题');
  });

  testWidgets('编辑页保存失败退出后名片不继承保存报错', (tester) async {
    final repository = _FakeProfileRepository(
      account: ProfileAccount(userId: 'user-a', displayName: '小林'),
    );
    repository.saveErrorMessage = '保存失败：云端暂不可用';
    final overview = _FakeOverviewSource();
    await pumpCard(tester, repository: repository, overview: overview);
    await overview.emit();
    await tester.pump();

    await tester.tap(find.byTooltip('编辑资料'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '小林二号');
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    // 编辑页原地显示原因并提供就地重试。
    expect(find.text('保存失败：云端暂不可用'), findsOneWidget);
    expect(find.text('重试同步'), findsOneWidget);
    expect(find.byType(ProfileEditPage), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byType(MyProfileCard), findsOneWidget);
    expect(find.text('保存失败：云端暂不可用'), findsNothing);
    expect(find.text('小林二号'), findsOneWidget);
  });

  testWidgets('编辑页拒绝超限图片且不保存', (tester) async {
    final repository = _FakeProfileRepository();
    final picker = _FakeAvatarPicker(
      Uint8List.fromList(List<int>.filled(maxAvatarSourceBytes + 1, 0)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileEditPage(repository: repository, avatarPicker: picker),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('选择图片'));
    await tester.pumpAndSettle();

    expect(find.textContaining('5 MB'), findsOneWidget);
    expect(repository.saveCalls, 0);
    expect(picker.calls, 1);
  });

  testWidgets('编辑页选择图片并保存账号资料', (tester) async {
    final repository = _FakeProfileRepository();
    final picker = _FakeAvatarPicker(_onePixelPng);
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileEditPage(repository: repository, avatarPicker: picker),
      ),
    );
    await tester.pump();

    await tester.runAsync(() async {
      await tester.tap(find.text('选择图片'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(find.text('使用此头像'), findsOneWidget);
    await tester.ensureVisible(find.text('使用此头像'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('使用此头像'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '小林');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(repository.saveCalls, 1);
    expect(repository.lastSavedAvatar?.mimeType, 'image/png');
  });

  testWidgets('保存失败停留在编辑页并可重试同步', (tester) async {
    final repository = _FakeProfileRepository();
    repository.saveErrorMessage = '保存失败：云端暂不可用';
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileEditPage(
          repository: repository,
          avatarPicker: _FakeAvatarPicker(null),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), '小林');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('保存失败：云端暂不可用'), findsOneWidget);
    expect(find.text('重试同步'), findsOneWidget);

    repository.saveErrorMessage = null;
    await tester.tap(find.text('重试同步'));
    await tester.pumpAndSettle();

    expect(find.text('保存失败：云端暂不可用'), findsNothing);
  });

  testWidgets('重试保存成功但账号时区被覆盖时采用新值并提示', (tester) async {
    final repository = _FakeProfileRepository(
      account: const ProfileAccount(
        userId: 'user-a',
        displayName: '小林',
        displayTimeZoneId: 'Asia/Shanghai',
      ),
    );
    repository.saveErrorMessage = '保存失败：云端暂不可用';
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileEditPage(
          repository: repository,
          avatarPicker: _FakeAvatarPicker(null),
        ),
      ),
    );
    await tester.pump();

    // 选择东京后保存失败：停留在编辑页，等待就地重试。
    await tester.tap(find.text('东京'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '小林');
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('保存失败：云端暂不可用'), findsOneWidget);
    expect(find.text('重试同步'), findsOneWidget);

    // 重试成功，但账号存储按修订号保留了另一台设备写入的伦敦。
    repository.saveErrorMessage = null;
    repository.syncResultOverride = ProfileAccount(
      userId: 'user-a',
      displayName: '小林',
      displayTimeZoneId: 'Europe/London',
      updatedAt: DateTime.utc(2026, 11, 18),
    );
    await tester.tap(find.text('重试同步'));
    await tester.pumpAndSettle();

    expect(find.text('保存失败：云端暂不可用'), findsNothing);
    expect(find.text('重试同步'), findsNothing, reason: '重试成功不再是失败状态');
    expect(find.textContaining('账号时区已被其他设备更新'), findsOneWidget);
    expect(find.textContaining('已采用最新值：Europe/London'), findsOneWidget);
    // 页面不再停留在旧选择上：摘要与已加载值都指向账号最新值。
    expect(find.textContaining('伦敦 · Europe/London'), findsOneWidget);
  });

  testWidgets('编辑资料页提供七个城市时区并保存为账号值', (tester) async {
    final repository = _FakeProfileRepository(
      account: const ProfileAccount(
        userId: 'user-a',
        displayTimeZoneId: 'Asia/Shanghai',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileEditPage(
          repository: repository,
          avatarPicker: _FakeAvatarPicker(null),
        ),
      ),
    );
    await tester.pump();

    for (final city in AccountTimeZones.cities) {
      expect(find.text(city.label), findsOneWidget);
    }
    expect(find.textContaining('跟随设备'), findsNothing);
    expect(find.textContaining('北京 · Asia/Shanghai'), findsOneWidget);
    expect(find.textContaining('北京时间 04:00'), findsOneWidget);

    await tester.tap(find.text('东京'));
    await tester.pump();
    expect(find.textContaining('东京 · Asia/Tokyo'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '小林');
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(repository.lastTimeZoneId, 'Asia/Tokyo');
    expect((await repository.getProfile()).displayTimeZoneId, 'Asia/Tokyo');
  });

  testWidgets('城市名单外的合法账号时区不被静默改写', (tester) async {
    final repository = _FakeProfileRepository(
      account: const ProfileAccount(
        userId: 'user-a',
        displayTimeZoneId: 'Europe/Berlin',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileEditPage(
          repository: repository,
          avatarPicker: _FakeAvatarPicker(null),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('当前时区'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '小林');
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    // 没有改动时区时，保存请求会省略时区（null=保留），因此断言账号最终值
    // 保持 Berlin，而不是要求一个可选参数被重新发送。
    expect((await repository.getProfile()).displayTimeZoneId, 'Europe/Berlin');
  });
}
