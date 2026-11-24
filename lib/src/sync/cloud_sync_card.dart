import 'dart:async';

import 'package:flutter/material.dart';

import '../focus/focus_repository.dart';
import '../ui/pacta_date_format.dart';
import '../ui/pacta_error_text.dart';

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
    this.accountTimeZoneIdLoader,
  });

  final CloudVersionCheck? versionCheck;
  final FocusRepository? focusRepository;

  /// 今日确认后的自动上传协调器；为空表示当前未配置云端连接。
  final CloudAutoUploadCoordinator? autoUpload;
  final CloudSnapshotRepository? repository;
  final Future<void> Function() onDownloaded;
  final Future<String?> Function()? accountTimeZoneIdLoader;

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
      // 已经读到本机与云端状态：弹层首帧就是就绪态，不再重复查库。
      await _inspect(
        automatic: true,
        initialLocal: local,
        initialCloud: check.metadata,
      );
    } catch (_) {
      // Discovery must never block ordinary local use.
    } finally {
      _evaluating = false;
    }
  }

  String? _message;
  String? _resultError;
  CloudSyncResult? _result;
  String? _displayTimeZoneId;
  int _resultRequest = 0;

  String? _reportedAutoUploadStop;

  @override
  void initState() {
    super.initState();
    widget.versionCheck?.addListener(_versionChanged);
    widget.autoUpload?.addListener(_autoUploadChanged);
    _loadResult();
    _loadTimeZone();
    _watchFocus();
  }

  Future<void> _loadTimeZone() async {
    final loader = widget.accountTimeZoneIdLoader;
    if (loader == null) return;
    try {
      final zone = await loader();
      if (!mounted) return;
      setState(() => _displayTimeZoneId = zone);
    } catch (_) {
      // 时区读取失败时保持当前值或回落本机时区。
    }
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

  /// 弹层统一入口：Android 用底部弹层，桌面用对话框。
  ///
  /// [builder] 会拿到当前是否使用底部弹层排版；弹层内容可以在自己的 [State]
  /// 里重建，加载、失败与就绪状态切换不需要外层重新 push 一次路由。
  Future<T?> _showModal<T>(
    Widget Function(BuildContext context, bool sheet) builder,
  ) {
    if (Theme.of(context).platform == TargetPlatform.android) {
      return showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (context) {
          _modalRoute = ModalRoute.of(context);
          return builder(context, true);
        },
      );
    }
    return showDialog<T>(
      context: context,
      builder: (context) {
        _modalRoute = ModalRoute.of(context);
        return builder(context, false);
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
          accountTimeZoneIdLoader: widget.accountTimeZoneIdLoader,
          displayTimeZoneId: _displayTimeZoneId,
        ),
      ),
    );
    if (!mounted || widget.repository != repository) return;
    await _loadResult();
  }

  /// 弹出同步操作面板。
  ///
  /// 手动点击不等待任何网络或数据库查询：弹层第一帧立刻出现，云端与本机状态
  /// 由 [_CloudSyncOperationsModal] 在内部并行读取。自动提示（[automatic]）
  /// 沿用调用方已经读到的 [initialLocal] / [initialCloud]，先确认本机没有未
  /// 结束的专注或预约，再让弹层首帧就是就绪态。
  Future<void> _inspect({
    bool automatic = false,
    CloudSnapshotLocalState? initialLocal,
    CloudSnapshotMetadata? initialCloud,
  }) async {
    final repository = widget.repository;
    if (repository == null || _working) return;
    setState(() {
      _working = true;
      _message = null;
    });
    bool? selectedDirection;
    final messenger = ScaffoldMessenger.of(context);
    // 面板会重新读取两端状态并自带失败提示，旧的同步反馈不叠在面板上。
    messenger.hideCurrentSnackBar();
    try {
      var readyLocal = initialLocal;
      final readyCloud = automatic
          ? (initialCloud ?? widget.versionCheck?.metadata)
          : null;
      if (automatic) {
        readyLocal ??= await repository.captureLocalState();
        if (!mounted || widget.repository != repository) return;
        if (readyLocal.hasUnfinishedFlow ||
            widget.versionCheck?.hasPendingVersion != true ||
            widget.versionCheck?.metadata != readyCloud) {
          _deferred = readyLocal.hasUnfinishedFlow;
          return;
        }
      }
      final selection = await _showModal<_CloudSyncSelection>(
        (context, sheet) => _CloudSyncOperationsModal(
          sheet: sheet,
          repository: repository,
          versionCheck: widget.versionCheck,
          autoUpload: widget.autoUpload,
          resultError: _resultError,
          onOpenHistory: _openHistory,
          initialLocal: readyLocal,
          initialCloud: readyCloud,
          initialReady: automatic,
        ),
      );
      if (selection == null || !mounted || widget.repository != repository) {
        return;
      }
      final direction = selection.upload;
      selectedDirection = direction;
      final local = selection.local;
      final cloud = selection.cloud;
      final confirmed = await _showModal<bool>((context, sheet) {
        final dialog = _directionConfirm(
          upload: direction,
          local: local,
          cloud: cloud,
        );
        return sheet ? _sheetSurface(context, dialog) : dialog;
      });
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
              '同步未完成：${_snapshotFailureText(error)} 请重新查看云端数据后再选择方向。',
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
            Text(
              '本机数据更新：${formatPactaDateTimeSeconds(local.dataUpdatedAt, timeZoneId: _displayTimeZoneId)}',
            ),
            Text('本机记录：${local.rowCount} 条'),
            const SizedBox(height: 8),
            if (cloud == null)
              const Text('云端暂无备份。')
            else ...[
              Text(
                '云端数据更新：${formatPactaDateTimeSeconds(cloud.dataUpdatedAt, timeZoneId: _displayTimeZoneId)}',
              ),
              Text('云端记录：${cloud.rowCount} 条'),
              Text('来源：${cloud.deviceName}'),
              Text(
                '上传时间：${formatPactaDateTimeSeconds(cloud.uploadedAt, timeZoneId: _displayTimeZoneId)}',
              ),
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
    return result == null
        ? '尚未同步'
        : formatPactaDateTimeSeconds(
            result.succeededAt,
            timeZoneId: _displayTimeZoneId,
          );
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
              // 窄屏（< 400dp）把时间放到标题下一行时，两者必须在同一个
              // 列里左对齐：状态行留在图标右侧的内容列内，就不能掉到图标
              // 正下方，也不会因尾部箭头压缩而错位。
              final compact = constraints.maxWidth < 400;
              // 时间戳始终是一行：窄屏下它跟标题同列左对齐，宽屏下右对齐。
              // 平板/桌面（≥400dp）下的错位来自「标题与状态各占一半 flex」：
              // 状态短的时候文本从 50% 分界处开始右对齐，看上去飘在卡片中间。
              // 这里让状态只按内容取宽、紧贴箭头，剩余宽度全给标题。
              final status = Text(
                _summary,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: compact ? TextAlign.start : TextAlign.end,
                softWrap: false,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              );
              final heading = Text(
                '数据同步',
                style: Theme.of(context).textTheme.titleMedium,
              );
              return Row(
                // 标题、状态与箭头严格同一条水平中线：任一侧换行或行高不同
                // 都不会把另一侧顶偏。
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_sync_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: compact
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              heading,
                              const SizedBox(height: 4),
                              status,
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(child: heading),
                              const SizedBox(width: 12),
                              // 非 flex 子项按内容取宽并夹紧上限：状态贴着
                              // 箭头右对齐，只有真放不下才省略。
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: constraints.maxWidth * 0.5,
                                ),
                                child: status,
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    widget.versionCheck?.failed == true
                        ? Icons.refresh
                        : Icons.chevron_right,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

/// 用户在操作面板里选中的方向，以及当时读到的两端状态。
///
/// `upload` 为 true 表示上传（用本机覆盖云端）；外层据此沿用原有的覆盖确认、
/// 防重复与冲突检测流程，反馈与执行语义都不变。
typedef _CloudSyncSelection = ({
  bool upload,
  CloudSnapshotLocalState local,
  CloudSnapshotMetadata? cloud,
});

/// 同步操作面板：先弹出、后读取。
///
/// 手动点击「数据同步」时弹层首帧就出现；[CloudSnapshotRepository.inspectCloud]
/// 与 [CloudSnapshotRepository.captureLocalState] 在面板内部并行执行。读取完成
/// 前只呈现本地即可用的自动上传开关、历史备份与关闭，绝不把上一次读到的结果
/// 当成当前状态；读取失败时整个面板保留，可原地重试。选定方向时把
/// (direction, local, cloud) 交回外层继续确认与执行。
class _CloudSyncOperationsModal extends StatefulWidget {
  const _CloudSyncOperationsModal({
    required this.sheet,
    required this.repository,
    required this.versionCheck,
    required this.autoUpload,
    required this.resultError,
    required this.onOpenHistory,
    this.initialLocal,
    this.initialCloud,
    this.initialReady = false,
  });

  /// Android 底部弹层排版；桌面直接用 [AlertDialog]。
  final bool sheet;
  final CloudSnapshotRepository repository;
  final CloudVersionCheck? versionCheck;
  final CloudAutoUploadCoordinator? autoUpload;

  /// 同步记录读取失败时的提示：属于本地状态，随面板一起展示。
  final String? resultError;
  final Future<void> Function() onOpenHistory;

  /// 自动提示路径已经读好的状态：首帧即就绪，不再重复读取。
  final CloudSnapshotLocalState? initialLocal;
  final CloudSnapshotMetadata? initialCloud;
  final bool initialReady;

  @override
  State<_CloudSyncOperationsModal> createState() =>
      _CloudSyncOperationsModalState();
}

class _CloudSyncOperationsModalState extends State<_CloudSyncOperationsModal> {
  CloudSnapshotLocalState? _local;
  CloudSnapshotMetadata? _cloud;
  Object? _failure;
  bool _loading = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    widget.autoUpload?.addListener(_autoUploadChanged);
    final readyLocal = widget.initialLocal;
    if (widget.initialReady && readyLocal != null) {
      _local = readyLocal;
      _cloud = widget.initialCloud;
    } else {
      _loading = true;
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    widget.autoUpload?.removeListener(_autoUploadChanged);
    super.dispose();
  }

  void _autoUploadChanged() {
    if (mounted) setState(() {});
  }

  bool get _ready => !_loading && _failure == null && _local != null;

  /// 并行读取云端与本机状态；任何一路失败都留在面板内，可原地重试。
  Future<void> _load() async {
    final repository = widget.repository;
    final request = ++_request;
    try {
      final states = await Future.wait<Object?>([
        repository.inspectCloud(),
        repository.captureLocalState(),
      ]);
      if (!mounted || request != _request || widget.repository != repository) {
        return;
      }
      setState(() {
        _cloud = states[0] as CloudSnapshotMetadata?;
        _local = states[1] as CloudSnapshotLocalState;
        _failure = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || request != _request || widget.repository != repository) {
        return;
      }
      setState(() {
        _failure = error;
        _loading = false;
      });
    }
  }

  void _retry() {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failure = null;
    });
    unawaited(_load());
  }

  void _select(bool upload) {
    final local = _local;
    if (local == null) return;
    Navigator.pop<_CloudSyncSelection>(context, (
      upload: upload,
      local: local,
      cloud: _cloud,
    ));
  }

  Future<void> _ignore() async {
    final versionCheck = widget.versionCheck;
    final cloud = _cloud;
    if (versionCheck == null || cloud == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await versionCheck.ignore(cloud);
      if (!mounted || !context.mounted) return;
      Navigator.pop(context);
    } catch (_) {
      if (messenger.mounted) {
        messenger.showSnackBar(const SnackBar(content: Text('忽略未保存，请重试。')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dialog = AlertDialog(
      constraints: const BoxConstraints(maxWidth: 560),
      title: const Text('云端与本机'),
      content: SingleChildScrollView(child: _content(context)),
      actions: _actions(context),
    );
    return widget.sheet ? _sheetSurface(context, dialog) : dialog;
  }

  List<Widget> _actions(BuildContext context) => [
    if (_ready && _cloud != null && widget.versionCheck != null)
      TextButton(onPressed: _ignore, child: const Text('忽略')),
    TextButton(
      onPressed: () => Navigator.pop(context),
      child: const Text('关闭'),
    ),
  ];

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);
    final local = _local;
    final cloud = _cloud;
    final errorStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.error,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_loading) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 12),
          const Text('正在读取云端与本机状态…'),
        ],
        if (_failure case final failure?) ...[
          Text('同步未完成：${_snapshotFailureText(failure)}', style: errorStyle),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: _retry, child: const Text('重试')),
          ),
        ],
        if (_ready && local != null) ...[
          Text(cloud == null ? '云端暂无数据，可首次上传。' : '云端来源：${cloud.deviceName}'),
          if (widget.autoUpload?.blockedReason case final reason?) ...[
            const SizedBox(height: 8),
            Text('自动上传已停止：$reason', style: errorStyle),
          ],
          if (widget.resultError case final error?) ...[
            const SizedBox(height: 8),
            Text(error, style: errorStyle),
          ],
          if (cloud != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: local.hasUnfinishedFlow
                    ? null
                    : () => _select(false),
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
              onPressed: () => _select(true),
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('上传'),
            ),
          ),
        ],
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
            unawaited(widget.onOpenHistory());
          },
        ),
      ],
    );
  }
}

/// 把 [AlertDialog] 的标题、内容与底栏动作排成 Android 底部弹层。
///
/// 内容自带滚动容器，这里只负责最大高度、安全间距与动作换行。
Widget _sheetSurface(BuildContext context, AlertDialog dialog) {
  return Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
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
            Flexible(child: dialog.content ?? const SizedBox.shrink()),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: dialog.actions ?? const <Widget>[],
            ),
          ],
        ),
      ),
    ),
  );
}

/// 云快照失败的用户可见文案。
///
/// [CloudSnapshotRepository] 用英文 `StateError` 表达内部校验（快照不存在、
/// 表集合不合法、某列值类型异常）。这些是实现细节，不直接摊到屏上：常见
/// 几种换成可继续操作的中文；其余仍先经 [formatUserError] 脱敏（PostgREST、
/// socket 等会换成统一中文），最后仍只剩英文时给通用提示。
String _snapshotFailureText(Object error) {
  if (error is StateError) {
    final message = error.message.trim();
    final lower = message.toLowerCase();
    if (lower.contains('cloud snapshot does not exist')) {
      return '云端快照已不存在，请重新上传本机数据。';
    }
    if (lower.contains('snapshot table set is invalid')) {
      return '云端快照的数据结构不受支持，请重新上传本机数据。';
    }
    if (lower.contains('invalid value type')) {
      return '云端快照中有字段的值类型无法识别，请重新上传本机数据。';
    }
  }
  final formatted = formatUserError(error);
  return _containsChinese(formatted) ? formatted : '请检查网络与登录状态。';
}

bool _containsChinese(String text) => RegExp(r'[\u4e00-\u9fff]').hasMatch(text);
