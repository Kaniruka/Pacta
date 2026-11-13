import 'dart:async';

import 'package:flutter/material.dart';

import '../focus/focus_repository.dart';

import 'cloud_auto_upload.dart';
import 'cloud_snapshot_history_page.dart';
import 'cloud_snapshot_repository.dart';
import 'cloud_sync_result.dart';
import 'cloud_version_check.dart';

class CloudSyncCard extends StatefulWidget {
  const CloudSyncCard({
    super.key,
    required this.repository,
    required this.onDownloaded,
    this.versionCheck,
    this.focusRepository,
    this.autoUpload,
  });

  final CloudVersionCheck? versionCheck;
  final FocusRepository? focusRepository;

  /// 今日确认后的自动上传协调器；为空表示当前未配置云端连接。
  final CloudAutoUploadCoordinator? autoUpload;
  final CloudSnapshotRepository? repository;
  final Future<void> Function() onDownloaded;

  @override
  State<CloudSyncCard> createState() => _CloudSyncCardState();
}

/// 操作层的自动上传开关：本机当前用户偏好，默认关闭。
class _AutoUploadSwitch extends StatefulWidget {
  const _AutoUploadSwitch({required this.coordinator});

  final CloudAutoUploadCoordinator coordinator;

  @override
  State<_AutoUploadSwitch> createState() => _AutoUploadSwitchState();
}

class _AutoUploadSwitchState extends State<_AutoUploadSwitch> {
  bool? _enabled;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await widget.coordinator.load();
    } catch (_) {
      // 读取失败保持未知，交给用户重开面板。
    }
    if (!mounted) return;
    setState(() => _enabled = widget.coordinator.enabled);
  }

  Future<void> _toggle(bool value) async {
    if (_working) return;
    setState(() {
      _working = true;
      _enabled = value;
    });
    try {
      await widget.coordinator.setEnabled(value);
    } catch (_) {
      if (mounted) setState(() => _enabled = widget.coordinator.enabled);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('今日确认后自动上传'),
      subtitle: const Text('今日确认成功后上传一次；关闭即停止待上传请求。'),
      value: _enabled ?? false,
      onChanged: _working ? null : _toggle,
    );
  }
}

class _CloudSyncCardState extends State<CloudSyncCard> {
  bool _working = false;
  bool _deferred = false;
  bool _evaluating = false;
  int _presentedCheck = 0;
  StreamSubscription<dynamic>? _focusSubscription;
  ModalRoute<dynamic>? _modalRoute;

  void _watchFocus() {
    _focusSubscription?.cancel();
    _focusSubscription = widget.focusRepository?.watchSessions().listen((_) {
      if (_deferred) unawaited(_checkAfterFlow());
    });
  }

  Future<void> _checkAfterFlow() async {
    final repository = widget.repository;
    if (repository == null) return;
    try {
      final local = await repository.captureLocalState();
      if (!mounted ||
          widget.repository != repository ||
          local.hasUnfinishedFlow) {
        return;
      }
      if (!_deferred) return;
      _deferred = false;
      await widget.versionCheck?.check(force: true);
    } catch (_) {
      // A failed discovery cannot interrupt a focus flow.
    }
  }

  Future<void> _maybeAutomatic() async {
    final check = widget.versionCheck;
    final repository = widget.repository;
    if (!mounted ||
        _working ||
        _evaluating ||
        repository == null ||
        widget.focusRepository == null ||
        check == null ||
        check.checking ||
        check.failed ||
        !check.hasPendingVersion ||
        check.completedChecks == _presentedCheck) {
      return;
    }
    _evaluating = true;
    try {
      final local = await repository.captureLocalState();
      if (!mounted ||
          check != widget.versionCheck ||
          !check.hasPendingVersion) {
        return;
      }
      _deferred = local.hasUnfinishedFlow;
      if (_deferred) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          const SnackBar(content: Text('云端有待处理更新，流程结束后可选择同步。')),
        );
        return;
      }
      _presentedCheck = check.completedChecks;
      await _inspect(automatic: true);
    } catch (_) {
      // Discovery must never block ordinary local use.
    } finally {
      _evaluating = false;
    }
  }

  String? _message;
  String? _resultError;
  CloudSyncResult? _result;
  int _resultRequest = 0;

  String? _reportedAutoUploadStop;

  @override
  void initState() {
    super.initState();
    widget.versionCheck?.addListener(_versionChanged);
    widget.autoUpload?.addListener(_autoUploadChanged);
    _loadResult();
    _watchFocus();
  }

  /// 自动上传被云端版本或请求冲突挡住时提示一次，避免静默不传。
  void _autoUploadChanged() {
    if (!mounted) return;
    final reason = widget.autoUpload?.blockedReason;
    if (reason == null) {
      _reportedAutoUploadStop = null;
    } else if (reason != _reportedAutoUploadStop) {
      _reportedAutoUploadStop = reason;
      _announce('自动上传已停止：$reason');
    }
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant CloudSyncCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.versionCheck != widget.versionCheck) {
      oldWidget.versionCheck?.removeListener(_versionChanged);
      widget.versionCheck?.addListener(_versionChanged);
    }
    if (oldWidget.autoUpload != widget.autoUpload) {
      oldWidget.autoUpload?.removeListener(_autoUploadChanged);
      widget.autoUpload?.addListener(_autoUploadChanged);
      _reportedAutoUploadStop = widget.autoUpload?.blockedReason;
    }
    if (oldWidget.focusRepository != widget.focusRepository) _watchFocus();
    if (oldWidget.repository != widget.repository) {
      final obsoleteRoute = _modalRoute;
      _modalRoute = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (obsoleteRoute?.isActive == true) {
          obsoleteRoute!.navigator?.removeRoute(obsoleteRoute);
        }
      });
      _presentedCheck = 0;
      _deferred = false;
      _working = false;
      _result = null;
      _resultError = null;
      _message = null;
      _loadResult();
    }
  }

  void _versionChanged() {
    if (mounted) {
      if (widget.versionCheck?.hasPendingVersion != true) _deferred = false;
      setState(() {});
      _syncFailureFeedback();
      unawaited(_loadResult());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_maybeAutomatic());
      });
    }
  }

  @override
  void dispose() {
    final obsoleteRoute = _modalRoute;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (obsoleteRoute?.isActive == true) {
        obsoleteRoute!.navigator?.removeRoute(obsoleteRoute);
      }
    });
    widget.versionCheck?.removeListener(_versionChanged);
    widget.autoUpload?.removeListener(_autoUploadChanged);
    _focusSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadResult() async {
    final request = ++_resultRequest;
    final repository = widget.repository;
    try {
      final result = await repository?.loadSyncResult();
      if (mounted &&
          widget.repository == repository &&
          request == _resultRequest) {
        setState(() {
          _result = result;
          _resultError = null;
        });
      }
    } catch (_) {
      if (mounted &&
          widget.repository == repository &&
          request == _resultRequest) {
        setState(() => _resultError = '同步记录读取失败，请重新查看云端。');
      }
    }
  }

  Future<bool?> _showModal(AlertDialog dialog) {
    if (Theme.of(context).platform == TargetPlatform.android) {
      return showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (context) {
          _modalRoute = ModalRoute.of(context);
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .85,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DefaultTextStyle(
                      style: Theme.of(context).textTheme.titleLarge!,
                      child: dialog.title!,
                    ),
                    const SizedBox(height: 16),
                    Flexible(
                      child: SingleChildScrollView(child: dialog.content!),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: dialog.actions!,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }
    return showDialog<bool>(
      context: context,
      builder: (context) {
        _modalRoute = ModalRoute.of(context);
        return dialog;
      },
    );
  }

  /// 历史备份入口：列表、指定版本恢复与本机恢复点都在这里。
  Future<void> _openHistory() async {
    final repository = widget.repository;
    if (repository == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CloudSnapshotHistoryPage(
          repository: repository,
          onRestored: widget.onDownloaded,
          onCancelPendingUpload: widget.autoUpload?.cancelPending,
        ),
      ),
    );
    if (!mounted || widget.repository != repository) return;
    await _loadResult();
  }

  Future<void> _inspect({bool automatic = false}) async {
    final repository = widget.repository;
    final versionCheck = widget.versionCheck;
    if (repository == null || _working) return;
    setState(() {
      _working = true;
      _message = null;
    });
    bool? selectedDirection;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final cloud = automatic
          ? widget.versionCheck?.metadata
          : await repository.inspectCloud();
      final local = await repository.captureLocalState();
      if (!mounted || widget.repository != repository) return;
      if (automatic &&
          (local.hasUnfinishedFlow ||
              widget.versionCheck?.hasPendingVersion != true ||
              widget.versionCheck?.metadata != cloud)) {
        _deferred = local.hasUnfinishedFlow;
        return;
      }
      final direction = await _showModal(
        _operationsSheet(
          local: local,
          cloud: cloud,
          repository: repository,
          versionCheck: versionCheck,
        ),
      );
      if (direction == null || !mounted || widget.repository != repository) {
        return;
      }
      selectedDirection = direction;
      final confirmed = await _showModal(
        _directionConfirm(upload: direction, local: local, cloud: cloud),
      );
      if (confirmed != true || !mounted || widget.repository != repository) {
        return;
      }
      if (direction) {
        await repository.uploadLocal(
          expectedRevision: cloud?.revision ?? 0,
          expectedFingerprint: local.fingerprint,
        );
        // 本次上传已覆盖排队意图；残留请求不再需要执行。
        await widget.autoUpload?.cancelPending();
      } else {
        // 下载前先取消旧请求：恢复内容不得随后被自动上传。
        await widget.autoUpload?.cancelPending();
        await repository.downloadCloud(
          expectedRevision: cloud!.revision,
          expectedFingerprint: local.fingerprint,
        );
      }
      if (!mounted || widget.repository != repository) return;
      widget.versionCheck?.handled();
      await _loadResult();
      if (!mounted || widget.repository != repository) return;
      if (messenger.mounted) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text(direction ? '上传完成，已覆盖云端数据。' : '下载完成，已覆盖本机数据。'),
          ),
        );
      }
      if (!direction && mounted && widget.repository == repository) {
        await widget.onDownloaded();
      }
    } on CloudSyncResultPersistenceException {
      if (mounted && widget.repository == repository) {
        widget.versionCheck?.handled();
      }
      final message = selectedDirection == true
          ? '数据已上传，但本机同步记录未保存。请重新查看云端核对结果，勿重复上传。'
          : '数据已下载，但本机同步记录未保存。请重新查看云端核对结果，勿重复下载。';
      if (!mounted || widget.repository != repository) return;
      await _loadResult();
      if (!mounted || widget.repository != repository) return;
      setState(() {
        _message = message;
      });
      if (messenger.mounted) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
      if (selectedDirection == false &&
          mounted &&
          widget.repository == repository) {
        await widget.onDownloaded();
      }
    } catch (error) {
      if (mounted && widget.repository == repository) {
        setState(
          () => _message =
              '同步未完成：${error is StateError ? error.message : '请检查网络与登录状态。'} 请重新查看云端数据后再选择方向。',
        );
      }
    } finally {
      if (mounted && widget.repository == repository) {
        setState(() => _working = false);
        final message = _message;
        if (message != null) _announce(message);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_maybeAutomatic());
        });
      }
    }
  }

  AlertDialog _operationsSheet({
    required CloudSnapshotLocalState local,
    required CloudSnapshotMetadata? cloud,
    required CloudSnapshotRepository repository,
    required CloudVersionCheck? versionCheck,
  }) {
    return AlertDialog(
      constraints: const BoxConstraints(maxWidth: 560),
      title: const Text('云端与本机'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(cloud == null ? '云端暂无数据，可首次上传。' : '云端来源：${cloud.deviceName}'),
            if (widget.autoUpload?.blockedReason case final reason?) ...[
              const SizedBox(height: 8),
              Text(
                '自动上传已停止：$reason',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_resultError case final error?) ...[
              const SizedBox(height: 8),
              Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (cloud != null) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: local.hasUnfinishedFlow
                      ? null
                      : () => Navigator.pop(context, false),
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('下载'),
                ),
              ),
              if (local.hasUnfinishedFlow) ...[
                const SizedBox(height: 8),
                const Text('本机有未结束的专注或预约，请先处理后再下载。'),
              ],
            ],
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('上传'),
              ),
            ),
            if (widget.autoUpload case final coordinator?) ...[
              const SizedBox(height: 4),
              _AutoUploadSwitch(coordinator: coordinator),
            ],
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history),
              title: const Text('历史备份'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(context);
                unawaited(_openHistory());
              },
            ),
          ],
        ),
      ),
      actions: [
        if (cloud != null && versionCheck != null)
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                if (!mounted ||
                    widget.repository != repository ||
                    widget.versionCheck != versionCheck) {
                  return;
                }
                await versionCheck.ignore(cloud);
                if (mounted &&
                    widget.repository == repository &&
                    context.mounted) {
                  Navigator.pop(context);
                }
              } catch (_) {
                if (messenger.mounted) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('忽略未保存，请重试。')),
                  );
                }
              }
            },
            child: const Text('忽略'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  AlertDialog _directionConfirm({
    required bool upload,
    required CloudSnapshotLocalState local,
    required CloudSnapshotMetadata? cloud,
  }) {
    return AlertDialog(
      constraints: const BoxConstraints(maxWidth: 560),
      title: Text(upload ? '上传并覆盖云端？' : '下载并覆盖本地？'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('本机数据更新：${_time(local.dataUpdatedAt)}'),
            Text('本机记录：${local.rowCount} 条'),
            const SizedBox(height: 8),
            if (cloud == null)
              const Text('云端暂无备份。')
            else ...[
              Text('云端数据更新：${_time(cloud.dataUpdatedAt)}'),
              Text('云端记录：${cloud.rowCount} 条'),
              Text('来源：${cloud.deviceName}'),
              if (cloud.isLegacy)
                const Text('发现旧版云端记录，将转换为整份数据；原设备和上传时间未记录。')
              else
                Text('上传时间：${_time(cloud.uploadedAt)}'),
              const SizedBox(height: 8),
              Text(_age(cloud.dataUpdatedAt, local.dataUpdatedAt)),
            ],
            const SizedBox(height: 12),
            Text(
              upload
                  ? (cloud == null
                        ? '本机数据将作为首份云端快照。'
                        : '将用本机整份业务数据替换云端数据。云端独有的记录将被丢弃，其他设备需手动下载才能更新。')
                  : '将用来自“${cloud!.deviceName}”的整份云端业务数据替换本机数据。本机独有的记录将被丢弃。',
            ),
            if (!upload) ...[
              const SizedBox(height: 8),
              Text(_baselineNote(local)),
            ],
            const SizedBox(height: 8),
            const Text('设备设置和登录状态不变。'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(upload ? '确认上传' : '确认下载'),
        ),
      ],
    );
  }

  String _baselineNote(CloudSnapshotLocalState local) =>
      _result?.localFingerprint?.startsWith('v2:') != true
      ? '尚无可靠的本地同步基线，无法确认本机是否有未同步修改；下载可能丢弃本机数据。'
      : _result!.localFingerprint != local.fingerprint
      ? '本机有尚未同步的修改；下载将丢弃这些修改。'
      : '本机数据与上次成功同步时一致。';

  static String _time(DateTime time) {
    final local = time.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  static String _age(DateTime cloud, DateTime local) => cloud.isAfter(local)
      ? '云端数据时间较新，请选择要保留的数据。'
      : cloud.isBefore(local)
      ? '本地数据时间较新，请选择要保留的数据。'
      : '更新时间相同，内容仍可能不同，请选择要保留的数据。';

  /// 常驻摘要只报最近一次成功同步时间；方向、检查中与失败反馈改为弹层
  /// 内容或非阻断 SnackBar，不再占用常驻摘要。
  String get _summary {
    if (widget.repository == null) return '当前未配置云端连接。';
    final result = _result;
    return result == null ? '尚未同步' : _time(result.succeededAt);
  }

  bool _reportedFailure = false;

  void _announce(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  /// 云端检查失败只在状态变化时提示一次，避免每次重建重复弹消息。
  void _syncFailureFeedback() {
    final failed = widget.versionCheck?.failed == true;
    if (!failed) {
      _reportedFailure = false;
      return;
    }
    if (_reportedFailure) return;
    _reportedFailure = true;
    _announce('云端检查失败，稍后可重试。');
  }

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Tooltip(
      message: widget.versionCheck?.failed == true ? '重试云端检查' : '查看云同步',
      child: InkWell(
        onTap: widget.repository == null || _working
            ? null
            : widget.versionCheck?.failed == true
            ? () => widget.versionCheck!.check(force: true)
            : () => _inspect(),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 400;
              final status = Text(
                _summary,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: compact ? TextAlign.start : TextAlign.end,
              );
              final heading = Row(
                children: [
                  const Icon(Icons.cloud_sync_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '数据同步',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(width: 12),
                    Flexible(fit: FlexFit.tight, child: status),
                    const SizedBox(width: 4),
                  ],
                  Icon(
                    widget.versionCheck?.failed == true
                        ? Icons.refresh
                        : Icons.chevron_right,
                  ),
                ],
              );
              if (!compact) return heading;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [heading, const SizedBox(height: 4), status],
              );
            },
          ),
        ),
      ),
    ),
  );
}
