import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/sync/cloud_sync_card.dart';
import 'package:pacta/src/sync/cloud_sync_result.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 云同步体验的需求测试：卡片保留可识别的同步标题与图标，但常驻状态摘要只
/// 报最近一次成功同步时间；打开卡片后的首要动作是用云端数据更新本机，
/// 上传保留为次要入口。同步契约（显式覆盖确认、数据丢失告知、活动流程禁
/// 下载、预览过期检查、失败目的端保留）不在本文件放宽。
final _desktopUploadedAt = DateTime.utc(2026, 11, 12, 10);
final _localDataUpdatedAt = DateTime.utc(2026, 11, 13, 2);

String _fmt(DateTime time) {
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

List<String> _cardTexts(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(of: find.byType(Card), matching: find.byType(Text)),
    )
    .map((text) => text.data ?? '')
    .where((value) => value.isNotEmpty)
    .toList();

List<String> _surfaceTexts(WidgetTester tester) => tester
    .widgetList<RichText>(find.byType(RichText))
    .map((rich) => rich.text.toPlainText())
    .where((value) => value.isNotEmpty)
    .toList();

List<String> _cardTooltips(WidgetTester tester) => tester
    .widgetList<Tooltip>(
      find.descendant(of: find.byType(Card), matching: find.byType(Tooltip)),
    )
    .map((tooltip) => tooltip.message ?? '')
    .where((message) => message.isNotEmpty)
    .toList();

Finder _buttonLabelled(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
);

Finder? _firstLabelled(List<String> labels) {
  for (final label in labels) {
    final finder = _buttonLabelled(label);
    if (finder.evaluate().isNotEmpty) return finder;
  }
  return null;
}

/// 云 -> 本机动作的标签在需求落地后应为「从云端更新」；契约与守卫测试按新旧
/// 候选定位同一动作，避免把契约绑死在措辞上。
Finder? _downloadAction() => _firstLabelled(const ['从云端更新', '下载']);

Finder? _uploadAction() => _firstLabelled(const ['上传', '上传本机', '用本机覆盖云端']);

Future<void> _tapLabel(WidgetTester tester, Finder? target) async {
  expect(target, isNotNull);
  await tester.ensureVisible(target!);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

class _CountingRemote extends InMemoryCloudSnapshotRemote {
  int inspectCalls = 0;
  int downloadCalls = 0;
  int uploadCalls = 0;

  @override
  Future<CloudSnapshotMetadata?> inspect({required String userId}) {
    inspectCalls++;
    return super.inspect(userId: userId);
  }

  @override
  Future<CloudSnapshotMetadata> download({required String userId}) {
    downloadCalls++;
    return super.download(userId: userId);
  }

  @override
  Future<CloudSnapshotMetadata> upload({
    required String userId,
    required int expectedRevision,
    required Map<String, dynamic> payload,
    required String deviceId,
    required String deviceName,
    required DateTime dataUpdatedAt,
    required int rowCount,
    String? deviceManufacturer,
    String? deviceModel,
    String? requestId,
  }) {
    uploadCalls++;
    return super.upload(
      userId: userId,
      expectedRevision: expectedRevision,
      payload: payload,
      deviceId: deviceId,
      deviceName: deviceName,
      dataUpdatedAt: dataUpdatedAt,
      rowCount: rowCount,
      deviceManufacturer: deviceManufacturer,
      deviceModel: deviceModel,
      requestId: requestId,
    );
  }
}

/// 真实 CloudSnapshotRepository + 内存 Drift + InMemoryCloudSnapshotRemote。
/// 云端已有一份来自「家里的电脑」的快照，本机有云端没有的记录。
class _SyncHarness {
  _SyncHarness._({
    required this.phone,
    required this.desktop,
    required this.remote,
    required this.tasks,
    required this.userId,
  });

  final PactaDatabase phone;
  final PactaDatabase desktop;
  final _CountingRemote remote;
  final LocalTaskRepository tasks;
  final String userId;
  late final CloudSnapshotRepository phoneSync;

  /// 每个 harness 用独立 userId，避免同文件内 SharedPreferences 记录串味。
  static int _sequence = 0;

  /// 本机「上次成功同步时间」的注入时钟；测试可改写以区分各次成功。
  static DateTime Function() now = () => _localDataUpdatedAt;

  static Future<_SyncHarness> create({bool seedSyncResult = true}) async {
    final phone = PactaDatabase(NativeDatabase.memory());
    final desktop = PactaDatabase(NativeDatabase.memory());
    final remote = _CountingRemote();
    final userId = 'experience-user-${_sequence++}';

    final desktopTasks = LocalTaskRepository(
      database: desktop,
      userId: userId,
      remote: InMemoryTaskRemote(),
      cloudSyncEnabled: false,
      now: () => _desktopUploadedAt,
    );
    await desktopTasks.createGoal(
      const GoalDraft(title: '电脑记录', classification: TaskClassification.both),
    );
    final desktopSync = CloudSnapshotRepository(
      database: desktop,
      remote: remote,
      userId: userId,
      deviceId: 'desktop-a',
      deviceName: '家里的电脑',
      now: () => _desktopUploadedAt,
    );
    final desktopState = await desktopSync.captureLocalState();
    await desktopSync.uploadLocal(
      expectedRevision: 0,
      expectedFingerprint: desktopState.fingerprint,
    );
    await desktopTasks.dispose();

    final tasks = LocalTaskRepository(
      database: phone,
      userId: userId,
      remote: InMemoryTaskRemote(),
      cloudSyncEnabled: false,
      now: () => _localDataUpdatedAt,
    );
    await tasks.createGoal(
      const GoalDraft(title: '手机独有', classification: TaskClassification.both),
    );

    final harness = _SyncHarness._(
      phone: phone,
      desktop: desktop,
      remote: remote,
      tasks: tasks,
      userId: userId,
    );
    harness.phoneSync = CloudSnapshotRepository(
      database: phone,
      remote: remote,
      userId: userId,
      deviceId: 'phone-a',
      deviceName: '我的手机',
      now: () => now(),
    );
    if (!seedSyncResult) return harness;

    final localState = await harness.phoneSync.captureLocalState();
    await const CloudSyncResultStore().save(
      userId,
      CloudSyncResult(
        succeededAt: _localDataUpdatedAt,
        localFingerprint: localState.fingerprint,
        cloudRevision: 1,
      ),
    );
    return harness;
  }

  Future<List<String>> goalTitles() async =>
      (await tasks.getGoals()).map((goal) => goal.title).toList();

  Future<void> dispose() async {
    await tasks.dispose();
    await phone.close();
    await desktop.close();
  }
}

Future<void> _pumpCard(
  WidgetTester tester,
  _SyncHarness harness, {
  FocusRepository? focusRepository,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CloudSyncCard(
          repository: harness.phoneSync,
          focusRepository: focusRepository,
          onDownloaded: () async {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    _SyncHarness.now = () => _localDataUpdatedAt;
  });

  testWidgets('卡片状态摘要：只报最近一次成功同步时间（当前已满足）', (tester) async {
    final harness = await _SyncHarness.create();
    try {
      await _pumpCard(tester, harness);

      final texts = _cardTexts(tester);
      final syncTime = _fmt(_localDataUpdatedAt);
      // 摘要即时间：时间只出现一次，且摘要不带方向、行数或设备标识。
      expect(texts.where((text) => text == syncTime), hasLength(1));
      for (final text in texts) {
        expect(text, isNot(contains('上传')));
        expect(text, isNot(contains('下载')));
        expect(text, isNot(contains('方向')));
        expect(text, isNot(contains('条')));
        expect(text, isNot(contains('设备标识')));
      }
      // 卡片仍需可识别的标题与图标，供用户知道这是什么入口。
      expect(
        find.descendant(of: find.byType(Card), matching: find.byType(Icon)),
        findsWidgets,
      );
      expect(texts.length, greaterThanOrEqualTo(2));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await harness.dispose();
    }
  });

  testWidgets('卡片状态摘要：常驻表面不提示同步方向', (tester) async {
    final harness = await _SyncHarness.create();
    try {
      await _pumpCard(tester, harness);

      // 方向与后果只属于弹层；常驻卡片的可见文字与提示语都不该先讲方向。
      for (final message in _cardTooltips(tester)) {
        expect(message, isNot(contains('方向')));
        expect(message, isNot(contains('选择')));
      }
      expect(_cardTooltips(tester), isNot(contains('查看云端并选择方向')));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await harness.dispose();
    }
  });

  testWidgets('主操作层级：打开卡片即可用云端数据更新本机，上传保留为次要入口', (tester) async {
    final harness = await _SyncHarness.create();
    try {
      await _pumpCard(tester, harness);
      await tester.tap(find.byType(Card));
      await tester.pumpAndSettle();

      // 不再先摆一个「选择同步方式」的分叉让用户自己判断方向。
      expect(find.text('选择同步方式'), findsNothing);
      // 主操作直接是云 -> 本机，且是唯一的强调按钮。
      expect(find.widgetWithText(FilledButton, '下载'), findsOneWidget);
      final filledUpload = find.byWidgetPredicate(
        (widget) => widget is FilledButton,
      );
      for (final button in tester.widgetList<FilledButton>(filledUpload)) {
        final labels = tester
            .widgetList<Text>(
              find.descendant(
                of: find.byWidget(button),
                matching: find.byType(Text),
              ),
            )
            .map((text) => text.data ?? '');
        expect(labels.join('|'), isNot(contains('上传')));
      }
      // 面板只保留来源；覆盖后果在执行前确认内。
      expect(find.textContaining('丢弃'), findsNothing);
      expect(find.textContaining('家里的电脑'), findsWidgets);
      // 上传保留为次要入口。
      expect(_uploadAction(), isNotNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await harness.dispose();
    }
  });

  testWidgets('同步时间：成功下载并应用本机后更新为本机成功时间', (tester) async {
    final downloadTime = DateTime.utc(2026, 11, 13, 3, 15);
    final harness = await _SyncHarness.create();
    try {
      _SyncHarness.now = () => downloadTime;
      await _pumpCard(tester, harness);
      await tester.tap(find.byType(Card));
      await tester.pumpAndSettle();
      await _tapLabel(tester, _downloadAction());
      await _tapLabel(tester, _firstLabelled(const ['确认下载', '确认从云端更新']));

      expect(await harness.goalTitles(), ['电脑记录']);
      final saved = (await harness.phoneSync.loadSyncResult())!;
      expect(saved.succeededAt.toUtc(), downloadTime);

      final cloud = (await harness.remote.inspect(userId: harness.userId))!;
      // 云端上传时间是云端事件，不等于本机上次同步时间。
      expect(_fmt(cloud.uploadedAt), isNot(_fmt(downloadTime)));
      expect(_surfaceTexts(tester), contains(_fmt(downloadTime)));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await harness.dispose();
    }
  });

  testWidgets('同步时间：成功上传覆盖云端后更新为本机成功时间', (tester) async {
    final uploadTime = DateTime.utc(2026, 11, 13, 4, 30);
    final harness = await _SyncHarness.create();
    try {
      _SyncHarness.now = () => uploadTime;
      await _pumpCard(tester, harness);
      await tester.tap(find.byType(Card));
      await tester.pumpAndSettle();
      await _tapLabel(tester, _uploadAction());
      await _tapLabel(tester, _firstLabelled(const ['确认上传', '确认覆盖云端']));

      final saved = (await harness.phoneSync.loadSyncResult())!;
      expect(saved.succeededAt.toUtc(), uploadTime);
      final cloud = (await harness.remote.inspect(userId: harness.userId))!;
      expect(cloud.revision, 2);
      expect(_fmt(cloud.uploadedAt), isNot(_fmt(uploadTime)));
      expect(_surfaceTexts(tester), contains(_fmt(uploadTime)));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await harness.dispose();
    }
  });

  testWidgets('同步时间：仅检查、取消与失败都不更新时间', (tester) async {
    final harness = await _SyncHarness.create();
    try {
      final seeded = (await harness.phoneSync.loadSyncResult())!;
      await _pumpCard(tester, harness);

      await tester.tap(find.byType(Card));
      await tester.pumpAndSettle();
      expect(harness.remote.inspectCalls, greaterThan(0));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        (await harness.phoneSync.loadSyncResult())!.succeededAt.toUtc(),
        seeded.succeededAt.toUtc(),
      );

      await tester.tap(find.byType(Card));
      await tester.pumpAndSettle();
      await _tapLabel(tester, _downloadAction());
      expect(find.textContaining('覆盖本地'), findsWidgets);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(
        (await harness.phoneSync.loadSyncResult())!.succeededAt.toUtc(),
        seeded.succeededAt.toUtc(),
      );
      expect(harness.remote.downloadCalls, 0);

      harness.remote.available = false;
      await tester.tap(find.byType(Card));
      await tester.pumpAndSettle();
      expect(find.textContaining('同步未完成'), findsWidgets);
      expect(
        (await harness.phoneSync.loadSyncResult())!.succeededAt.toUtc(),
        seeded.succeededAt.toUtc(),
      );
      harness.remote.available = true;
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await harness.dispose();
    }
  });

  testWidgets('同步时间：无成功记录时卡片显示尚未同步', (tester) async {
    final harness = await _SyncHarness.create(seedSyncResult: false);
    try {
      // 桌面设备的首次上传也会写本机同步记录；无记录场景需要先清掉它。
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(
        'pacta.device.cloud_sync.result.${harness.userId}',
      );
      expect(await harness.phoneSync.loadSyncResult(), isNull);
      await _pumpCard(tester, harness);
      expect(find.text('尚未同步'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await harness.dispose();
    }
  });

  testWidgets('守卫：打开卡片只做检查，取消后本机与云端都不替换', (tester) async {
    final harness = await _SyncHarness.create();
    try {
      await _pumpCard(tester, harness);
      await tester.tap(find.byType(Card));
      await tester.pumpAndSettle();

      expect(harness.remote.inspectCalls, greaterThan(0));
      expect(await harness.goalTitles(), ['手机独有']);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(await harness.goalTitles(), ['手机独有']);
      expect(
        (await harness.remote.inspect(userId: harness.userId))!.revision,
        1,
      );
      expect(harness.remote.downloadCalls, 0);
      expect(harness.remote.uploadCalls, 1);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await harness.dispose();
    }
  });

  testWidgets('守卫：覆盖确认取消后本机与云端都不替换', (tester) async {
    final harness = await _SyncHarness.create();
    try {
      await _pumpCard(tester, harness);
      await tester.tap(find.byType(Card));
      await tester.pumpAndSettle();

      final download = _downloadAction();
      expect(download, isNotNull, reason: '打开卡片后必须能看到下载方向的动作');
      await tester.ensureVisible(download!);
      await tester.tap(download);
      await tester.pumpAndSettle();

      expect(find.textContaining('覆盖本地'), findsWidgets);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(await harness.goalTitles(), ['手机独有']);
      expect(
        (await harness.remote.inspect(userId: harness.userId))!.revision,
        1,
      );
      expect(harness.remote.downloadCalls, 0);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await harness.dispose();
    }
  });

  testWidgets('守卫：未结束流程中禁止下载，上传仍可用', (tester) async {
    final harness = await _SyncHarness.create();
    final taskSeeder = LocalTaskRepository(
      database: harness.phone,
      userId: harness.userId,
      remote: InMemoryTaskRemote(),
      cloudSyncEnabled: false,
      now: () => _localDataUpdatedAt,
    );
    final focusRepository = LocalFocusRepository(
      database: harness.phone,
      userId: harness.userId,
      remote: InMemoryFocusRemote(),
      cloudSyncEnabled: false,
      now: () => _localDataUpdatedAt,
    );
    try {
      final goal = await taskSeeder.createGoal(
        const GoalDraft(
          title: '进行中的目标',
          classification: TaskClassification.regular,
        ),
      );
      final task = await taskSeeder.createTask(
        goal.id,
        const TaskDraft(title: '预约中的任务', classification: null),
      );
      await focusRepository.startAppointment(
        taskId: task.id,
        mode: FocusChainMode.regular,
        duration: const Duration(minutes: 25),
      );

      await _pumpCard(tester, harness, focusRepository: focusRepository);
      await tester.tap(find.byType(Card));
      await tester.pumpAndSettle();

      expect(find.text('本机有未结束的专注或预约，请先处理后再下载。'), findsOneWidget);
      final download = _downloadAction();
      expect(download, isNotNull);
      expect(
        tester.widget<ButtonStyleButton>(download!).onPressed,
        isNull,
        reason: '活动流程期间下载必须保持禁用',
      );
      final upload = _uploadAction();
      expect(upload, isNotNull);
      expect(tester.widget<ButtonStyleButton>(upload!).onPressed, isNotNull);

      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await taskSeeder.dispose();
      await harness.dispose();
    }
  });
}
