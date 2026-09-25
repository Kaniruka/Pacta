import 'package:flutter/material.dart';

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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.calendar_month_outlined),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '今日日历',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: () => _openSources(context),
                      child: const Text('日历来源'),
                    ),
                  ],
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
                    child: Text('今天没有已导入的日历块。日历只辅助规划，不影响专注启动。'),
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

  void _openSources(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CalendarSourcesPage(
          repository: repository,
          isAndroid: Theme.of(context).platform == TargetPlatform.android,
        ),
      ),
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
      title: Text(block.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text('$time · $status${sources.isEmpty ? '' : ' · $sources'}'),
    );
  }
}

class CalendarSourcesPage extends StatefulWidget {
  const CalendarSourcesPage({
    super.key,
    required this.repository,
    required this.isAndroid,
  });

  final CalendarRepository repository;
  final bool isAndroid;

  @override
  State<CalendarSourcesPage> createState() => _CalendarSourcesPageState();
}

class _CalendarSourcesPageState extends State<CalendarSourcesPage> {
  CalendarImportState? _state;
  bool _loading = true;
  bool _working = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
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
        _message = '日历状态暂时无法读取。目标、任务和专注功能仍可使用。';
      });
    }
  }

  Future<void> _chooseSources() async {
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
      if (state!.permission != CalendarPermissionState.granted) {
        setState(() {
          _working = false;
          _message = '尚未获得读取日历权限。你仍可照常使用目标、任务和专注功能。';
        });
        return;
      }
      final importedIds = state.importedSourceIds;
      final choices = state.availableSources
          .where((source) => !importedIds.contains(source.id))
          .toList();
      if (choices.isEmpty) {
        setState(() {
          _working = false;
          _message = state!.availableSources.isEmpty
              ? '设备中没有可读取的系统日历。'
              : '当前设备上的日历来源均已导入。';
        });
        return;
      }
      final selectedIds = await _showSourcePicker(
        state.availableSources,
        importedIds,
      );
      if (selectedIds == null || selectedIds.isEmpty || !mounted) {
        if (mounted) setState(() => _working = false);
        return;
      }
      final result = await widget.repository.importCalendars(selectedIds);
      final refreshed = await widget.repository.loadImportState();
      if (!mounted) return;
      setState(() {
        _state = refreshed;
        _working = false;
        _message = result.synced
            ? '已导入 ${result.importedOccurrences} 个日历发生次并同步。'
            : '已在本机保存 ${result.importedOccurrences} 个发生次，云端同步暂未成功；恢复连接后会重试。';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _message = '日历读取未完成。现有本地数据和其他功能仍可使用。';
      });
    }
  }

  Future<Set<String>?> _showSourcePicker(
    List<CalendarSource> sources,
    Set<String> importedIds,
  ) async {
    final choices = sources
        .where((source) => !importedIds.contains(source.id))
        .toList();
    final selected = <String>{};
    return showDialog<Set<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('选择要读取的日历'),
          content: SizedBox(
            width: 420,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final source in sources)
                  if (importedIds.contains(source.id))
                    ListTile(
                      key: ValueKey('imported-${source.id}'),
                      leading: const Icon(Icons.check_circle_outline),
                      title: Text(source.displayName),
                      subtitle: const Text('已导入'),
                    )
                  else
                    CheckboxListTile(
                      key: ValueKey('calendar-${source.id}'),
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
                if (choices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('没有新的日历来源可添加。'),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(Set<String>.of(selected)),
              child: const Text('导入所选'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sync() async {
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      await widget.repository.sync();
      if (!mounted) return;
      setState(() {
        _working = false;
        _message = '日历块已同步。';
      });
      await _load();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _message = '云端暂时不可用，已同步的日历块仍保留在本机。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final imported = state?.importedSources ?? const <CalendarSource>[];
    return Scaffold(
      appBar: AppBar(title: const Text('日历块')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('日历仅作为只读规划参考。全天活动保留原始日期；空闲活动不计入占用，日历安排不会限制专注启动。'),
            ),
          ),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (widget.isAndroid)
            _androidImportStatus(state)
          else
            const Card(
              child: ListTile(
                leading: Icon(Icons.sync_outlined),
                title: Text('从 Android 同步日历块'),
                subtitle: Text('Windows 只显示已选择并同步的日历来源。'),
              ),
            ),
          if (imported.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('已导入来源', style: Theme.of(context).textTheme.titleMedium),
            for (final source in imported)
              Card(
                child: ListTile(
                  key: ValueKey('source-${source.id}'),
                  leading: const Icon(Icons.event_available_outlined),
                  title: Text(source.displayName),
                  subtitle: Text(source.timeZoneId),
                  trailing: const Icon(Icons.check_circle_outline),
                ),
              ),
          ],
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(liveRegion: true, child: Text(_message!)),
            ),
          const SizedBox(height: 12),
          if (widget.isAndroid)
            FilledButton.icon(
              onPressed: _working ? null : _chooseSources,
              icon: _working
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.calendar_month_outlined),
              label: Text(
                state?.permission == CalendarPermissionState.granted
                    ? '选择其他日历'
                    : '允许并选择日历',
              ),
            )
          else
            OutlinedButton.icon(
              onPressed: _working ? null : _sync,
              icon: const Icon(Icons.sync),
              label: const Text('立即同步'),
            ),
        ],
      ),
    );
  }

  Widget _androidImportStatus(CalendarImportState? state) {
    if (state?.permission == CalendarPermissionState.granted) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.verified_user_outlined),
          title: Text('已允许读取日历'),
          subtitle: Text('Pacta 只读取你选择的日历，不会修改源日历。'),
        ),
      );
    }
    return const Card(
      child: ListTile(
        leading: Icon(Icons.info_outline),
        title: Text('日历权限尚未开启'),
        subtitle: Text('允许后可选择要读取的日历。拒绝权限不影响目标、任务和专注功能。'),
      ),
    );
  }
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
