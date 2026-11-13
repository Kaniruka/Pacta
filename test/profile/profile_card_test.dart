import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
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
  int saveCalls = 0;
  int syncCalls = 0;
  ProfileAvatar? lastSavedAvatar;
  bool? lastClearAvatar;

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
  }) async {
    saveCalls++;
    lastSavedAvatar = avatar;
    lastClearAvatar = clearAvatar;
    _account = _account.copyWith(
      displayName: displayName,
      avatar: avatar,
      clearAvatar: clearAvatar,
      updatedAt: DateTime.utc(2026, 11, 13),
      hasPendingSave: saveErrorMessage != null,
      syncError: saveErrorMessage,
      clearSyncError: saveErrorMessage == null,
    );
    _updates.add(_account);
    return _account;
  }

  @override
  Future<ProfileAccount> syncProfile() async {
    syncCalls++;
    final thrown = syncThrownError;
    if (thrown != null) throw thrown;
    if (syncErrorMessage != null) {
      // 与真实仓储一致：没有缓存行时只返回内存错误，不产生本机资料版本。
      return _account.copyWith(syncError: syncErrorMessage);
    }
    if (saveErrorMessage == null) {
      _account = _account.copyWith(hasPendingSave: false, clearSyncError: true);
      _updates.add(_account);
    }
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

  testWidgets('已有缓存时同步抛异常仍显示这次尝试的错误，缓存更新后清掉', (tester) async {
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

    // 缓存行没有记录这次错误（错误没能写库），瞬态原因不能被缓存掩盖。
    expect(find.text('资料服务暂时不可用'), findsOneWidget);
    expect(find.text('小林'), findsOneWidget);

    // 另一入口更新了缓存：旧的瞬态错误作废，不再提示。
    repository.syncThrownError = null;
    await repository.saveProfile(displayName: '小林二号');
    await tester.pump();

    expect(find.text('资料服务暂时不可用'), findsNothing);
    expect(find.text('小林二号'), findsOneWidget);
    expect(repository.syncCalls, 1, reason: '重试只由用户触发');
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

  testWidgets('云端写入失败显示原因并可重试', (tester) async {
    final repository = _FakeProfileRepository();
    repository.saveErrorMessage = '保存失败：网络不可用';
    repository.saveCalls = 0;
    final overview = _FakeOverviewSource();
    await pumpCard(tester, repository: repository, overview: overview);
    await overview.emit();
    await repository.saveProfile(displayName: '小林');
    await tester.pump();

    expect(find.text('保存失败：网络不可用'), findsOneWidget);

    repository.saveErrorMessage = null;
    await tester.tap(find.text('重试'));
    await tester.pump();

    expect(find.text('保存失败：网络不可用'), findsNothing);
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
}
