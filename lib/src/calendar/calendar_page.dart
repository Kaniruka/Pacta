import 'package:flutter/material.dart';

import '../notifications/device_permission_gateway.dart';
import '../schedules/calendar_import_models.dart';
import '../schedules/schedule_repository.dart';
import 'calendar_models.dart';
import 'calendar_repository.dart';

class CalendarAgendaCard extends StatelessWidget {
  const CalendarAgendaCard({super.key, required this.repository});

  final CalendarRepository repository;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day);
    final to = from.add(const Duration(days: 1));
    return StreamBuilder<CalendarAgenda>(
      stream: repository.watchAgenda(from: from, to: to),
      builder: (context, snapshot) {
        final agenda = snapshot.data;
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('今日日历', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                if (agenda?.isStale == true)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Semantics(
                      liveRegion: true,
                      label: '日历块尚未更新，已保留本地缓存。',
                      child: const Text('日历块尚未更新，已保留本地缓存。'),
                    ),
                  ),
                if (snapshot.connectionState == ConnectionState.waiting &&
                    agenda == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: LinearProgressIndicator(),
                  )
                else if (snapshot.hasError)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('日历块暂时无法读取；任务和专注仍可使用。'),
                  )
                else if ((agenda?.blocks ?? const []).isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(2, 4, 2, 12),
                    child: Text('今天没有导入的安排。'),
                  )
                else ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '今日占用 ${_durationLabel(agenda!.occupiedDuration)}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  for (final block in agenda.blocks.take(5))
                    _CalendarBlockTile(block: block),
                  if (agenda.blocks.length > 5)
                    Padding(
                      padding: const EdgeInsets.only(left: 16, bottom: 8),
                      child: Text('还有 ${agenda.blocks.length - 5} 项'),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CalendarBlockTile extends StatelessWidget {
  const _CalendarBlockTile({required this.block});

  final CalendarBlock block;

  @override
  Widget build(BuildContext context) {
    final time = block.allDay
        ? _allDayLabel(block)
        : '${_formatTime(context, block.startsAt)}–${_formatTime(context, block.endsAt)}';
    final status = block.allDay
        ? '全天提醒'
        : block.availability == CalendarAvailability.free
        ? '空闲'
        : '占用';
    final sources = block.sourceNames.toSet().join('、');
    return ListTile(
      key: ValueKey(block.eventIdentity),
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        block.allDay
            ? Icons.event_note_outlined
            : block.occupiesTime
            ? Icons.event_busy_outlined
            : Icons.event_available_outlined,
      ),
      title: Text(
        block.title,
        style: Theme.of(context).textTheme.bodyMedium,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '$time · $status${sources.isEmpty ? '' : ' · $sources'}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class CalendarSourcesPage extends StatefulWidget {
  const CalendarSourcesPage({
    super.key,
    required this.repository,
    required this.isAndroid,
    this.scheduleRepository,
    this.permissionGateway,
  });

  final CalendarRepository repository;
  final bool isAndroid;

  /// Owns the imported copies. When absent the page explains that the import
  /// destination is not wired instead of writing anything.
  final ScheduleRepository? scheduleRepository;

  /// Optional so tests can observe the system settings entry.
  final DevicePermissionGateway? permissionGateway;

  @override
  State<CalendarSourcesPage> createState() => _CalendarSourcesPageState();
}

class _CalendarSourcesPageState extends State<CalendarSourcesPage> {
  CalendarImportState? _state;
  bool _loading = true;
  bool _working = false;
  String? _message;

  DevicePermissionGateway get _permissions =>
      widget.permissionGateway ?? createDevicePermissionGateway();

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Android stops presenting the dialog after repeated denials, so the app
  /// settings screen stays available as the way back to calendar access.
  Future<void> _openSystemSettings() async {
    await _permissions.openAppSettings();
    if (!mounted) return;
    await _load();
  }

  Future<void> _load() async {
    try {
      final state = await widget.repository.loadImportState();
      if (!mounted) return;
      setState(() {
        _state = state;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = '日历状态暂时无法读取，其他功能仍可使用。';
      });
    }
  }

  void _finish(String? message) {
    if (!mounted) return;
    setState(() {
      _working = false;
      _message = message;
    });
  }

  /// Preview first, write only after confirmation. Cancelling either step
  /// leaves the account untouched.
  Future<void> _startImport() async {
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      var state = _state;
      if (state?.permission != CalendarPermissionState.granted) {
        state = await widget.repository.requestAccess();
        if (!mounted) return;
        setState(() => _state = state);
      }
      if (state == null) {
        _finish('日历状态暂时无法读取，其他功能仍可使用。');
        return;
      }
      if (state.permission == CalendarPermissionState.unknown) {
        _finish('无法确认日历权限状态，请稍后重试。');
        return;
      }
      if (state.permission != CalendarPermissionState.granted) {
        _finish('未获得日历读取权限，其他功能仍可使用。');
        return;
      }
      final sources = state.availableSources;
      if (sources.isEmpty) {
        _finish('设备中没有可读取的系统日历。');
        return;
      }
      final scheduleRepository = widget.scheduleRepository;
      if (scheduleRepository == null) {
        _finish('导入目标尚未就绪，日程管理仍可使用。');
        return;
      }

      // Stop the busy indicator before opening a dialog: an indeterminate
      // spinner never settles while the user reads the preview.
      setState(() => _working = false);
      final selection = await _showImportDialog(sources);
      if (selection == null || !mounted) {
        if (mounted) _finish(null);
        return;
      }
      setState(() => _working = true);

      final occurrences = await widget.repository.readOccurrences(
        sourceIds: selection.sourceIds,
        from: selection.from,
        to: selection.to,
      );
      final preview = await scheduleRepository.previewCalendarImport(
        CalendarImportRequest(
          sources: [
            for (final source in sources)
              if (selection.sourceIds.contains(source.id))
                CalendarImportSource(
                  id: source.id,
                  displayName: source.displayName,
                  localCalendarId: source.localCalendarId,
                ),
          ],
          occurrences: occurrences,
          from: selection.from,
          to: selection.to,
        ),
      );
      if (!mounted) return;
      setState(() => _working = false);
      final confirmed = await _showPreviewDialog(preview);
      if (confirmed != true || !mounted) return;
      if (!preview.hasPending) {
        _finish(
          preview.duplicateCount > 0
              ? '所选范围内都是已存在的日程，跳过 ${preview.duplicateCount} 个。'
              : '所选范围内没有可导入的日程。',
        );
        return;
      }
      setState(() {
        _working = true;
        _message = null;
      });
      final outcome = await scheduleRepository.confirmCalendarImport(preview);
      _finish(
        '已导入 ${outcome.createdCount} 个日程；跳过 '
        '${outcome.skippedDuplicates} 个已存在日程。',
      );
    } catch (_) {
      _finish('日历读取未完成，其他功能仍可使用。');
    }
  }

  Future<_CalendarImportSelection?> _showImportDialog(
    List<CalendarSource> sources,
  ) {
    final selected = <String>{};
    final today = DateTime.now();
    var from = DateTime(today.year, today.month, today.day);
    var to = from.add(const Duration(days: 7));
    return showDialog<_CalendarImportSelection>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('导入系统日历'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('选择来源日历，并指定要导入的日期范围。'),
                  const SizedBox(height: 8),
                  for (final source in sources)
                    CheckboxListTile(
                      key: ValueKey('import-source-${source.id}'),
                      value: selected.contains(source.id),
                      title: Text(source.displayName),
                      subtitle: Text(source.timeZoneId),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (value) => setDialogState(() {
                        if (value == true) {
                          selected.add(source.id);
                        } else {
                          selected.remove(source.id);
                        }
                      }),
                    ),
                  ListTile(
                    key: const Key('import-range'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.date_range_outlined),
                    title: const Text('日期范围'),
                    subtitle: Text('${_dateLabel(from)} 至 ${_dateLabel(to)}'),
                    trailing: const Icon(Icons.edit_calendar_outlined),
                    onTap: () async {
                      final picked = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(today.year - 2),
                        lastDate: DateTime(today.year + 3),
                        initialDateRange: DateTimeRange(
                          start: from,
                          end: to.subtract(const Duration(days: 1)),
                        ),
                      );
                      if (picked == null) return;
                      setDialogState(() {
                        from = picked.start;
                        to = picked.end.add(const Duration(days: 1));
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const Key('import-preview'),
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(
                      _CalendarImportSelection(
                        sourceIds: Set<String>.of(selected),
                        from: from,
                        to: to,
                      ),
                    ),
              child: const Text('预览'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _showPreviewDialog(CalendarImportPreview preview) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认导入'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('将导入 ${preview.pending.length} 个日程'),
            const SizedBox(height: 6),
            Text('已存在将跳过 ${preview.duplicateCount} 个'),
            if (preview.ignoredCount > 0) ...[
              const SizedBox(height: 6),
              Text('${preview.ignoredCount} 个活动无法作为日程导入'),
            ],
            const SizedBox(height: 12),
            const Text('导入后这些日程归 Pacta 管理；源日历不会被修改。'),
          ],
        ),
        actions: [
          TextButton(
            key: const Key('import-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('import-confirm'),
            onPressed: preview.hasPending
                ? () => Navigator.of(context).pop(true)
                : null,
            child: const Text('确认导入'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    return Scaffold(
      appBar: AppBar(title: const Text('系统日历导入')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      '系统日历只读：Pacta 只复制你确认导入的日程，不会修改或删除源日历；'
                      '源事件之后的变化不会回写到已导入的副本。',
                    ),
                  ),
                ),
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else if (widget.isAndroid)
                  _androidStatus(state)
                else
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.desktop_access_disabled_outlined),
                      title: Text('Windows 暂不支持读取系统日历'),
                      subtitle: Text('自有日程与已导入的副本仍可正常管理；导入入口只在 Android 提供。'),
                    ),
                  ),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Semantics(liveRegion: true, child: Text(_message!)),
                  ),
                const SizedBox(height: 12),
                if (widget.isAndroid)
                  FilledButton.icon(
                    key: const Key('calendar-import-start'),
                    onPressed: _working ? null : _startImport,
                    icon: _working
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.calendar_month_outlined),
                    label: const Text('导入系统日历'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _androidStatus(CalendarImportState? state) {
    if (state?.permission == CalendarPermissionState.granted) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.verified_user_outlined),
          title: Text('已允许读取日历'),
          subtitle: Text('Pacta 只读取你选择的日历，不会修改源日历。'),
        ),
      );
    }
    if (state?.permission == CalendarPermissionState.unknown) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.cloud_off_outlined),
          title: Text('日历权限状态暂不可用'),
          subtitle: Text('其他功能仍可使用；稍后可重试读取权限状态。'),
        ),
      );
    }
    if (state?.permission == CalendarPermissionState.denied) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('设备日历权限已关闭'),
              subtitle: Text(
                '可能尚未授权或被系统关闭。已导入的副本仍会保留，其他功能仍可使用；重新导入前请开启日历读取权限。',
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            key: const Key('calendar-open-system-settings'),
            onPressed: _working ? null : _openSystemSettings,
            icon: const Icon(Icons.settings_outlined),
            label: const Text('去系统设置开启日历权限'),
          ),
        ],
      );
    }
    return Card(
      child: Column(
        children: [
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('日历权限尚未开启'),
            subtitle: Text('允许后可选择只读导入的系统日历。拒绝权限不影响其他功能。'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('calendar-open-system-settings'),
                onPressed: _working ? null : _openSystemSettings,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('去系统设置开启日历权限'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarImportSelection {
  const _CalendarImportSelection({
    required this.sourceIds,
    required this.from,
    required this.to,
  });

  final Set<String> sourceIds;
  final DateTime from;
  final DateTime to;
}

String _formatTime(BuildContext context, DateTime value) =>
    TimeOfDay.fromDateTime(value.toLocal()).format(context);

String _allDayLabel(CalendarBlock block) {
  final start = block.allDayStartDate!;
  final endExclusive = DateTime.parse(
    '${block.allDayEndDateExclusive}T00:00:00Z',
  );
  final lastDate = endExclusive.subtract(const Duration(days: 1));
  final last = _dateLabel(lastDate);
  return start == last ? '$start · 全天' : '$start 至 $last · 全天';
}

String _dateLabel(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String _durationLabel(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours == 0) return '$minutes 分钟';
  if (minutes == 0) return '$hours 小时';
  return '$hours 小时 $minutes 分钟';
}
