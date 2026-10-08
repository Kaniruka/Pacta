import 'package:flutter/material.dart';

import 'cloud_snapshot_repository.dart';

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

  Future<void> _inspect() async {
    final repository = widget.repository;
    if (repository == null || _working) return;
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      final cloud = await repository.inspectCloud();
      final local = await repository.captureLocalState();
      if (!mounted) return;
      final direction = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
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
      if (direction == null || !mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
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
      if (confirmed != true || !mounted) return;
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
        if (mounted) await widget.onDownloaded();
      }
      if (mounted) {
        setState(
          () => _message = direction ? '上传完成，已覆盖云端数据。' : '下载完成，已覆盖本机数据。',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _message =
              '同步未完成：${error is StateError ? error.message : '请检查网络与登录状态，并重新查看云端数据。'}',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
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
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('手动云同步', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text('上传或下载整份数据，所选数据会覆盖另一份。'),
          const SizedBox(height: 12),
          if (widget.repository == null)
            const Text('当前未配置云端连接。')
          else
            FilledButton.icon(
              onPressed: _working ? null : _inspect,
              icon: const Icon(Icons.cloud_sync_outlined),
              label: Text(_working ? '处理中…' : '查看云端并选择方向'),
            ),
          if (_message != null) ...[const SizedBox(height: 8), Text(_message!)],
        ],
      ),
    ),
  );
}
