import 'package:flutter/material.dart';

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
  });

  final CloudSnapshotRepository repository;
  final Future<void> Function()? onRestored;

  /// 恢复前取消自动上传队列：恢复结果不得随后被自动上传回云端。
  final Future<void> Function()? onCancelPendingUpload;

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await Future.wait<void>([_loadCloud(), _loadPoints()]);
  }

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
          '将用 ${_time(entry.uploadedAt)} 来自 ${entry.deviceName} 的 '
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
          '将用 ${_time(point.createdAt)} 保存的 ${point.rowCount} 条记录'
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
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            error is StateError
                ? '恢复未完成：${error.message} 本机数据保持不变。'
                : '恢复未完成，本机数据保持不变，请重试。',
          ),
        ),
      );
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

  static String _time(DateTime time) {
    final local = time.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  static String _reason(CloudRecoveryReason reason) => switch (reason) {
    CloudRecoveryReason.beforeCloudRestore => '云端恢复前保存',
    CloudRecoveryReason.beforeRecoveryRestore => '找回恢复点前保存',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('历史备份')),
      body: SafeArea(child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('云端备份', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          '最近 $cloudSnapshotHistoryLimit 份成功上传，含最新一份。'
          '恢复到旧版本不会上传或覆盖云端。',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        ..._cloudSection(context),
        const SizedBox(height: 24),
        Text('本机恢复点', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          '每次恢复前自动保存在本机，与云端备份分开，可随时找回；离线也能找回。',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        ..._pointsSection(context),
      ],
    );
  }

  List<Widget> _cloudSection(BuildContext context) {
    final error = _cloudError;
    if (_loadingCloud) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: LinearProgressIndicator(),
        ),
      ];
    }
    if (error != null) {
      return [
        _SectionError(
          message: error,
          retryKey: const ValueKey('retry-cloud-history'),
          onRetry: _working ? null : _retryCloud,
        ),
      ];
    }
    if (_cloud.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('还没有可恢复的云端备份。'),
        ),
      ];
    }
    return [
      for (final entry in _cloud)
        _HistoryTile(
          title: _time(entry.uploadedAt),
          subtitle: '${entry.deviceName} · ${entry.rowCount} 条记录',
          action: '恢复',
          onPressed: _working ? null : () => _restoreCloud(entry),
          icon: Icons.cloud_outlined,
        ),
    ];
  }

  List<Widget> _pointsSection(BuildContext context) {
    final error = _pointsError;
    if (_loadingPoints) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: LinearProgressIndicator(),
        ),
      ];
    }
    if (error != null) {
      return [
        _SectionError(
          message: error,
          retryKey: const ValueKey('retry-local-points'),
          onRetry: _working ? null : _retryPoints,
        ),
      ];
    }
    if (_points.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('还没有本机恢复点；第一次恢复时会自动创建。'),
        ),
      ];
    }
    return [
      for (final point in _points)
        _HistoryTile(
          title: _time(point.createdAt),
          subtitle: '${_reason(point.reason)} · ${point.rowCount} 条记录',
          action: '找回',
          onPressed: _working ? null : () => _restorePoint(point),
          icon: Icons.restore_outlined,
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(message)),
          const SizedBox(width: 12),
          TextButton(
            key: retryKey,
            onPressed: onRetry,
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.title,
    required this.subtitle,
    required this.action,
    required this.onPressed,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final String action;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: TextButton(onPressed: onPressed, child: Text(action)),
    );
  }
}
