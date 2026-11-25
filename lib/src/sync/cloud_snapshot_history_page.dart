import 'package:flutter/material.dart';

import '../theme/pacta_icon_sizes.dart';
import '../theme/pacta_spacing.dart';
import '../theme/pacta_surfaces.dart';
import '../ui/pacta_date_format.dart';
import '../ui/pacta_error_text.dart';
import '../ui/pacta_grouped_list.dart';
import 'cloud_recovery_point.dart';
import 'cloud_snapshot_history.dart';
import 'cloud_snapshot_repository.dart';

/// 云端备份与本机恢复点的统一入口。
///
/// 云端列表只显示时间、来源和记录数；恢复选定版本不会上传或覆盖云端。
/// 每次恢复前都会持久保存本机恢复点，恢复失败不会留下半份数据。
///
/// 云端备份与本机恢复点各自加载、各自呈现错误：离线时仍可查看并找回已有
/// 本机恢复点，不必先联网。
class CloudSnapshotHistoryPage extends StatefulWidget {
  const CloudSnapshotHistoryPage({
    super.key,
    required this.repository,
    this.onRestored,
    this.onCancelPendingUpload,
    this.accountTimeZoneIdLoader,
    this.displayTimeZoneId,
  });

  final CloudSnapshotRepository repository;
  final Future<void> Function()? onRestored;

  /// 恢复前取消自动上传队列：恢复结果不得随后被自动上传回云端。
  final Future<void> Function()? onCancelPendingUpload;
  final Future<String?> Function()? accountTimeZoneIdLoader;
  final String? displayTimeZoneId;

  @override
  State<CloudSnapshotHistoryPage> createState() =>
      _CloudSnapshotHistoryPageState();
}

class _CloudSnapshotHistoryPageState extends State<CloudSnapshotHistoryPage> {
  bool _loadingCloud = true;
  bool _loadingPoints = true;
  bool _working = false;
  String? _cloudError;
  String? _pointsError;
  List<CloudSnapshotHistoryEntry> _cloud = const [];
  List<CloudRecoveryPointSummary> _points = const [];
  String? _displayTimeZoneId;
  final _infoTooltipKey = GlobalKey<TooltipState>();

  @override
  void initState() {
    super.initState();
    _displayTimeZoneId = widget.displayTimeZoneId;
    _load();
  }

  Future<void> _load() async {
    await Future.wait<void>([_loadCloud(), _loadPoints(), _loadTimeZone()]);
  }

  Future<void> _loadTimeZone() async {
    final loader = widget.accountTimeZoneIdLoader;
    if (loader == null) return;
    try {
      final zone = await loader();
      if (!mounted) return;
      setState(() => _displayTimeZoneId = zone);
    } catch (_) {
      // 时区读取失败时回退到现有值或本机时区。
    }
  }

  String _formatDateTime(DateTime value) =>
      formatPactaDateTimeInZone(value, timeZoneId: _displayTimeZoneId);

  Future<void> _loadCloud() async {
    try {
      final cloud = await widget.repository.listCloudHistory();
      if (!mounted) return;
      setState(() {
        _cloud = cloud;
        _loadingCloud = false;
        _cloudError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingCloud = false;
        _cloudError = '云端备份读取失败，请检查网络与登录状态。';
      });
    }
  }

  Future<void> _loadPoints() async {
    try {
      final points = await widget.repository.listLocalRecoveryPoints();
      if (!mounted) return;
      setState(() {
        _points = points;
        _loadingPoints = false;
        _pointsError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingPoints = false;
        _pointsError = '本机恢复点读取失败，请重试。';
      });
    }
  }

  void _retryCloud() {
    setState(() {
      _loadingCloud = true;
      _cloudError = null;
    });
    _loadCloud();
  }

  void _retryPoints() {
    setState(() {
      _loadingPoints = true;
      _pointsError = null;
    });
    _loadPoints();
  }

  Future<void> _restoreCloud(CloudSnapshotHistoryEntry entry) async {
    final confirmed = await _confirm(
      title: '恢复到该云端备份？',
      body:
          '将用 ${_formatDateTime(entry.uploadedAt)} 来自 '
          '${entry.deviceName} 的 '
          '${entry.rowCount} 条记录替换本机数据。'
          '本机独有记录会被替换，恢复前会自动保存一份本机恢复点。'
          '本次恢复不会上传或覆盖云端。',
      action: '确认恢复',
    );
    if (!confirmed) return;
    await _runRestore(() async {
      final local = await widget.repository.captureLocalState();
      await widget.repository.restoreCloudVersion(
        revision: entry.revision,
        expectedFingerprint: local.fingerprint,
      );
    }, success: '已恢复到该云端备份；恢复前的本机数据已保存在本机恢复点。');
  }

  Future<void> _restorePoint(CloudRecoveryPointSummary point) async {
    final confirmed = await _confirm(
      title: '找回本机恢复点？',
      body:
          '将用 ${_formatDateTime(point.createdAt)} 保存的 '
          '${point.rowCount} 条记录'
          '替换本机数据。当前的记录会先另存为新的本机恢复点。'
          '本次操作不会上传或覆盖云端。',
      action: '确认找回',
    );
    if (!confirmed) return;
    await _runRestore(() async {
      final local = await widget.repository.captureLocalState();
      await widget.repository.restoreLocalRecoveryPoint(
        pointId: point.id,
        expectedFingerprint: local.fingerprint,
      );
    }, success: '已找回该本机恢复点。');
  }

  Future<void> _runRestore(
    Future<void> Function() action, {
    required String success,
  }) async {
    if (_working) return;
    setState(() => _working = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // 两个恢复入口都先取消旧请求：恢复内容不会被自动上传回云端。
      await widget.onCancelPendingUpload?.call();
      await action();
      await widget.onRestored?.call();
      await _load();
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(success)));
    } catch (error) {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      // 异常先过共享脱敏：业务原因保留，技术异常一律换成可继续操作的话。
      final detail = formatUserError(error, fallback: '');
      final message = detail.isEmpty
          ? '恢复未完成，本机数据保持不变，请重试。'
          : '恢复未完成：$detail 本机数据保持不变。';
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 560),
        title: Text(title),
        content: SingleChildScrollView(child: Text(body)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result == true;
  }

  static String _reason(CloudRecoveryReason reason) => switch (reason) {
    CloudRecoveryReason.beforeCloudRestore => '云端恢复前保存',
    CloudRecoveryReason.beforeRecoveryRestore => '找回恢复点前保存',
    CloudRecoveryReason.beforeRecordReset => '重置记录前备份',
  };

  @override
  Widget build(BuildContext context) {
    return PactaSurfaces.wrapIfMissing(
      context,
      Scaffold(
        appBar: AppBar(
          title: const Text('历史备份'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: PactaSpacing.sm),
              // 说明只有一层 Tooltip：IconButton 不再挂第二个命名气泡，
              // 读屏仍通过 Semantics 得到「历史备份说明」。
              child: Semantics(
                label: '历史备份说明',
                button: true,
                child: Tooltip(
                  key: _infoTooltipKey,
                  triggerMode: TooltipTriggerMode.tap,
                  message:
                      '云端保留最近 $cloudSnapshotHistoryLimit 份成功上传，'
                      '恢复不会上传或覆盖云端；每次恢复前自动保存可离线找回的本机恢复点。',
                  child: IconButton(
                    key: const ValueKey('cloud-history-info'),
                    onPressed: () =>
                        _infoTooltipKey.currentState?.ensureTooltipVisible(),
                    icon: const Icon(
                      Icons.info_outline,
                      size: PactaIconSizes.md,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          // 与其余二级页同一版心：宽屏居中收到 800dp，长屏顶部对齐。
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: ListView(
                padding: PactaSpacing.pageInsets(context),
                children: [
                  _section(
                    context,
                    title: '云端备份',
                    trailing: '${_cloud.length} / $cloudSnapshotHistoryLimit',
                    children: _cloudSection(context),
                  ),
                  const SizedBox(height: PactaSpacing.lg),
                  _section(
                    context,
                    title: '本机恢复点',
                    trailing: '${_points.length} 份',
                    children: _pointsSection(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(
    BuildContext context, {
    required String title,
    required String trailing,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PactaSectionHeader(
          title: title,
          trailing: Text(
            trailing,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        ...children,
      ],
    );
  }

  /// 加载／错误／空态都是一张 20dp 纯白卡片：页面底部不再裸铺文字或进度条。
  Widget _stateCard(Widget child) => Card(
    child: Padding(padding: PactaSpacing.cardInsets, child: child),
  );

  List<Widget> _cloudSection(BuildContext context) {
    final error = _cloudError;
    if (_loadingCloud) {
      return [_stateCard(const LinearProgressIndicator(minHeight: 4))];
    }
    if (error != null) {
      return [
        _stateCard(
          _SectionError(
            message: error,
            retryKey: const ValueKey('retry-cloud-history'),
            onRetry: _working ? null : _retryCloud,
          ),
        ),
      ];
    }
    if (_cloud.isEmpty) {
      return [_stateCard(const Text('还没有可恢复的云端备份。'))];
    }
    final primary = Theme.of(context).colorScheme.primary;
    return [
      PactaGroupedList(
        key: const ValueKey('cloud-history-list'),
        children: [
          for (final entry in _cloud)
            _HistoryTile(
              title: _formatDateTime(entry.uploadedAt),
              sourceLabel: entry.deviceName,
              rowCount: entry.rowCount,
              action: '恢复',
              onPressed: _working ? null : () => _restoreCloud(entry),
              icon: Icons.cloud_outlined,
              iconColor: primary,
            ),
        ],
      ),
    ];
  }

  List<Widget> _pointsSection(BuildContext context) {
    final error = _pointsError;
    if (_loadingPoints) {
      return [_stateCard(const LinearProgressIndicator(minHeight: 4))];
    }
    if (error != null) {
      return [
        _stateCard(
          _SectionError(
            message: error,
            retryKey: const ValueKey('retry-local-points'),
            onRetry: _working ? null : _retryPoints,
          ),
        ),
      ];
    }
    if (_points.isEmpty) {
      return [_stateCard(const Text('还没有本机恢复点；第一次恢复时会自动创建。'))];
    }
    final tertiary = Theme.of(context).colorScheme.tertiary;
    return [
      PactaGroupedList(
        key: const ValueKey('local-recovery-points-list'),
        children: [
          for (final point in _points)
            _HistoryTile(
              title: _formatDateTime(point.createdAt),
              sourceLabel: _reason(point.reason),
              rowCount: point.rowCount,
              action: '找回',
              onPressed: _working ? null : () => _restorePoint(point),
              icon: Icons.restore_outlined,
              iconColor: tertiary,
            ),
        ],
      ),
    ];
  }
}

class _SectionError extends StatelessWidget {
  const _SectionError({
    required this.message,
    required this.retryKey,
    required this.onRetry,
  });

  final String message;
  final Key retryKey;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: Text(message)),
        const SizedBox(width: PactaSpacing.md),
        TextButton(
          key: retryKey,
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: onRetry,
          child: const Text('重试'),
        ),
      ],
    );
  }
}

/// 一行历史记录：图标 + 时间与来源/记录数 + 单一文字按钮。
///
/// 来源与「N 条记录」放在同一行 `Wrap`：记录数是一枚不可拆分的
/// [PactaStatusBadge]，360dp 窄屏宁可整枚换行，也不会把「201 条记录」
/// 折成单字孤行。
class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.title,
    required this.sourceLabel,
    required this.rowCount,
    required this.action,
    required this.onPressed,
    required this.icon,
    required this.iconColor,
  });

  final String title;
  final String sourceLabel;
  final int rowCount;
  final String action;
  final VoidCallback? onPressed;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: PactaIconSizes.md, color: iconColor),
          const SizedBox(width: PactaSpacing.md),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      sourceLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    PactaStatusBadge(label: '$rowCount 条记录'),
                  ],
                ),
              ],
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: onPressed,
            child: Text(action),
          ),
        ],
      ),
    );
  }
}
