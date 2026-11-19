import 'package:flutter/material.dart';

import '../notifications/device_permission_gateway.dart';
import '../schedules/schedule_repository.dart';
import 'calendar_models.dart';
import 'calendar_repository.dart';
import 'manual_calendar_import.dart';

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
    required this.displayTimeZoneIdLoader,
    this.scheduleRepository,
    this.permissionGateway,
  });

  final CalendarRepository repository;
  final bool isAndroid;

  /// 手动导入使用的账号显示时区；页面不读取设备时区。
  final Future<String> Function() displayTimeZoneIdLoader;

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

  /// 与计划页共用同一个手动导入流程：账号时区、预览/确认、跳过与取消
  /// 语义都只有一套实现。
  Future<void> _startImport() async {
    final scheduleRepository = widget.scheduleRepository;
    if (scheduleRepository == null) {
      _finish('导入目标尚未就绪，日程管理仍可使用。');
      return;
    }
    // 共享流程本身是模态的；不在这里放常驻进度圈，否则对话框打开时
    // 页面仍有一层无限动画，测试与用户都会看到多余的忙碌状态。
    setState(() {
      _working = false;
      _message = null;
    });
    final displayTimeZoneId = await widget.displayTimeZoneIdLoader();
    if (!mounted) return;
    final message = await runManualCalendarImport(
      context,
      calendar: widget.repository,
      schedules: scheduleRepository,
      displayTimeZoneId: displayTimeZoneId,
      now: DateTime.now(),
    );
    if (!mounted) return;
    _finish(message);
    await _load();
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
