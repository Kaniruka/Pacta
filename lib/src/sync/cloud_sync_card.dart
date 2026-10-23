import 'package:flutter/material.dart';

import 'cloud_snapshot_repository.dart';
import 'cloud_sync_result.dart';

class CloudSyncCard extends StatefulWidget {
  const CloudSyncCard({
    super.key,
    required this.repository,
    required this.onDownloaded,
  });

  final CloudSnapshotRepository? repository;
  final Future<void> Function() onDownloaded;

  @override
  State<CloudSyncCard> createState() => _CloudSyncCardState();
}

class _CloudSyncCardState extends State<CloudSyncCard> {
  bool _working = false;
  String? _message;
  CloudSyncResult? _result;
  CloudSnapshotMetadata? _inspectedCloud;

  @override
  void initState() {
    super.initState();
    _loadResult();
  }

  @override
  void didUpdateWidget(covariant CloudSyncCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _working = false;
      _result = null;
      _inspectedCloud = null;
      _message = null;
      _loadResult();
    }
  }

  Future<void> _loadResult() async {
    final repository = widget.repository;
    try {
      final result = await repository?.loadSyncResult();
      if (mounted && widget.repository == repository) {
        setState(() => _result = result);
      }
    } catch (_) {
      if (mounted && widget.repository == repository) {
        setState(() => _message = '同步记录读取失败，请重新查看云端。');
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
        builder: (context) => Padding(
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
        ),
      );
    }
    return showDialog<bool>(context: context, builder: (_) => dialog);
  }

  Future<void> _inspect() async {
    final repository = widget.repository;
    if (repository == null || _working) return;
    setState(() {
      _working = true;
      _message = null;
    });
    bool? selectedDirection;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final cloud = await repository.inspectCloud();
      final local = await repository.captureLocalState();
      if (!mounted || widget.repository != repository) return;
      setState(() => _inspectedCloud = cloud);
      final direction = await _showModal(
        AlertDialog(
          constraints: const BoxConstraints(maxWidth: 560),
          title: const Text('选择同步方式'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('本地数据更新：${_time(local.dataUpdatedAt)}'),
                Text('本地记录：${local.rowCount} 条'),
                const SizedBox(height: 12),
                if (cloud == null)
                  const Text('云端暂无数据，可首次上传。')
                else ...[
                  Text('云端来源：${cloud.deviceName}'),
                  if (cloud.isLegacy)
                    const Text('发现旧版云端记录，将转换为整份数据；原设备和上传时间未记录。')
                  else ...[
                    Text('设备标识：${cloud.deviceId}'),
                    Text('上传时间：${_time(cloud.uploadedAt)}'),
                  ],
                  Text('云端数据更新：${_time(cloud.dataUpdatedAt)}'),
                  Text('云端记录：${cloud.rowCount} 条'),
                  const SizedBox(height: 8),
                  Text(_age(cloud.dataUpdatedAt, local.dataUpdatedAt)),
                ],
                const SizedBox(height: 12),
                const Text('整份覆盖会丢弃另一份独有的记录；设备设置和登录状态不变。'),
                const SizedBox(height: 8),
                Text(
                  _result?.localFingerprint == null
                      ? '尚无可靠的本地同步基线，无法确认本机是否有未同步修改；下载可能丢弃本机数据。'
                      : _result!.localFingerprint != local.fingerprint
                      ? '本机有尚未同步的修改；下载将丢弃这些修改。'
                      : '本机数据与上次成功同步时一致。',
                ),
                if (local.hasUnfinishedFlow) ...[
                  const SizedBox(height: 8),
                  const Text('本机有未结束的专注或预约，请先处理后再下载。'),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            OutlinedButton(
              onPressed: cloud == null || local.hasUnfinishedFlow
                  ? null
                  : () => Navigator.pop(context, false),
              child: const Text('下载'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('上传'),
            ),
          ],
        ),
      );
      if (direction == null || !mounted || widget.repository != repository) {
        return;
      }
      selectedDirection = direction;
      final confirmed = await _showModal(
        AlertDialog(
          constraints: const BoxConstraints(maxWidth: 560),
          title: Text(direction ? '上传并覆盖云端？' : '下载并覆盖本地？'),
          content: Text(
            direction
                ? '将用本机整份业务数据替换云端数据。云端独有的记录将被丢弃，其他设备需手动下载才能更新。'
                : '将用来自“${cloud!.deviceName}”的整份云端业务数据替换本机数据。本机独有的记录将被丢弃。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(direction ? '确认上传' : '确认下载'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted || widget.repository != repository) {
        return;
      }
      if (direction) {
        await repository.uploadLocal(
          expectedRevision: cloud?.revision ?? 0,
          expectedFingerprint: local.fingerprint,
        );
      } else {
        await repository.downloadCloud(
          expectedRevision: cloud!.revision,
          expectedFingerprint: local.fingerprint,
        );
      }
      if (!mounted || widget.repository != repository) return;
      await _loadResult();
      if (!mounted || widget.repository != repository) return;
      setState(() => _inspectedCloud = null);
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
      final message = selectedDirection == true
          ? '数据已上传，但本机同步记录未保存。请重新查看云端核对结果，勿重复上传。'
          : '数据已下载，但本机同步记录未保存。请重新查看云端核对结果，勿重复下载。';
      if (!mounted || widget.repository != repository) return;
      await _loadResult();
      if (!mounted || widget.repository != repository) return;
      setState(() {
        _inspectedCloud = null;
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
      }
    }
  }

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

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Tooltip(
      message: '查看云端并选择方向',
      child: InkWell(
        onTap: widget.repository == null || _working ? null : _inspect,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.cloud_sync_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '手动云同步',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                fit: FlexFit.tight,
                child: Text(
                  widget.repository == null
                      ? '当前未配置云端连接。'
                      : _working
                      ? '处理中…'
                      : _message != null
                      ? _message!
                      : ((_inspectedCloud != null &&
                            (_result?.cloudRevision !=
                                    _inspectedCloud!.revision ||
                                _result?.legacyToken !=
                                    _inspectedCloud!.legacyToken)))
                      ? '云端有待处理更新'
                      : _result == null
                      ? '尚未同步'
                      : _time(_result!.succeededAt),
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    ),
  );
}
