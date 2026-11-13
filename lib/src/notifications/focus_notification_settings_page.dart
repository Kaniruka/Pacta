import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import 'focus_device_preferences.dart';
import 'focus_notification_service.dart';

/// Picks a reminder time. Injected by tests; production uses [showTimePicker].
typedef ReminderTimePicker = Future<TimeOfDay?> Function(
  int minutesAfterMidnight,
  String helpText,
);

/// Device-local reminder settings: focus notifications, the National Focus
/// reminder, and the independent daily open-Pacta reminder.
class FocusNotificationSettingsPage extends StatefulWidget {
  const FocusNotificationSettingsPage({
    super.key,
    required this.service,
    this.timePicker,
  });

  final FocusNotificationService service;
  final ReminderTimePicker? timePicker;

  @override
  State<FocusNotificationSettingsPage> createState() =>
      _FocusNotificationSettingsPageState();
}

class _FocusNotificationSettingsPageState
    extends State<FocusNotificationSettingsPage> {
  FocusDevicePreferences? _preferences;
  bool _notificationsAllowed = false;
  bool _exactAlarmsAllowed = false;
  bool _loading = true;
  bool _updating = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final preferences = await widget.service.getPreferences();
    final notificationsAllowed = await widget.service.notificationsAllowed();
    final exactAlarmsAllowed = await widget.service.exactAlarmsAllowed();
    if (!mounted) return;
    setState(() {
      _preferences = preferences;
      _notificationsAllowed = notificationsAllowed;
      _exactAlarmsAllowed = exactAlarmsAllowed;
      _loading = false;
    });
  }

  Future<void> _applyPreferences(FocusDevicePreferences updated) async {
    await widget.service.updatePreferences(updated);
    final notificationsAllowed = await widget.service.notificationsAllowed();
    final exactAlarmsAllowed = await widget.service.exactAlarmsAllowed();
    if (!mounted) return;
    setState(() {
      _preferences = updated;
      _notificationsAllowed = notificationsAllowed;
      _exactAlarmsAllowed = exactAlarmsAllowed;
    });
  }

  Future<void> _setNotificationsEnabled(bool enabled) async {
    final current = _preferences;
    if (current == null || _updating) return;
    setState(() {
      _updating = true;
      _message = null;
    });
    try {
      if (enabled && !await widget.service.requestNotificationPermission()) {
        if (mounted) {
          setState(() {
            _notificationsAllowed = false;
            _message = '未授予通知权限，专注和预约仍可使用；可在系统设置中重新开启。';
          });
        }
        if (Platform.isAndroid) {
          await widget.service.updatePreferences(
            current.copyWith(notificationPermissionRequested: true),
          );
          if (mounted) {
            setState(
              () => _preferences = current.copyWith(
                notificationPermissionRequested: true,
              ),
            );
          }
        }
        return;
      }
      await _applyPreferences(current.copyWith(notificationsEnabled: enabled));
      if (!mounted) return;
      setState(() {
        _message = enabled && !_exactAlarmsAllowed && Platform.isAndroid
            ? '提醒已开启；未允许精确提醒时，可能延迟送达。'
            : null;
      });
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _setBackgroundEnabled(bool enabled) async {
    final current = _preferences;
    if (current == null || _updating) return;
    setState(() => _updating = true);
    try {
      await _applyPreferences(
        current.copyWith(backgroundRunningEnabled: enabled),
      );
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _setNationalFocusReminderEnabled(bool enabled) async {
    final current = _preferences;
    if (current == null || _updating) return;
    setState(() {
      _updating = true;
      _message = null;
    });
    try {
      if (enabled &&
          Platform.isAndroid &&
          !await widget.service.requestNotificationPermission()) {
        if (mounted) {
          setState(() {
            _notificationsAllowed = false;
            _message = '未授予通知权限，专注流程仍可使用；可在系统设置中重新开启。';
          });
        }
        await widget.service.updatePreferences(
          current.copyWith(notificationPermissionRequested: true),
        );
        if (mounted) {
          setState(
            () => _preferences = current.copyWith(
              notificationPermissionRequested: true,
            ),
          );
        }
        return;
      }
      await _applyPreferences(
        current.copyWith(nationalFocusReminderEnabled: enabled),
      );
      if (!mounted) return;
      setState(() {
        _message = enabled && !_exactAlarmsAllowed && Platform.isAndroid
            ? '国策提醒已开启；未允许精确提醒时，可能延迟送达。'
            : null;
      });
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _setNationalFocusReminderTime() async {
    final current = _preferences;
    if (current == null || _updating) return;
    final selected = await _pickTime(
      current.nationalFocusReminderMinutesAfterMidnight,
      helpText: '选择提醒时间（北京时间）',
    );
    if (selected == null || !mounted) return;
    await _applyPreferences(
      current.copyWith(
        nationalFocusReminderMinutesAfterMidnight:
            selected.hour * 60 + selected.minute,
      ),
    );
  }

  Future<void> _setDailyOpenReminderEnabled(bool enabled) async {
    final current = _preferences;
    if (current == null || _updating) return;
    if (!enabled) {
      setState(() {
        _updating = true;
        _message = null;
      });
      try {
        await _applyPreferences(
          current.copyWith(dailyOpenReminderEnabled: false),
        );
        if (mounted) setState(() => _message = '已关闭每日提醒，其他功能不受影响。');
      } finally {
        if (mounted) setState(() => _updating = false);
      }
      return;
    }

    // The first enable needs a time: the reminder never guesses one silently.
    var minutesAfterMidnight = current.dailyOpenReminderMinutesAfterMidnight;
    var timeChosen = current.dailyOpenReminderTimeChosen;
    if (!timeChosen) {
      final selected = await _pickTime(
        minutesAfterMidnight,
        helpText: '选择每日提醒时间（本机时间）',
      );
      if (selected == null || !mounted) return;
      minutesAfterMidnight = selected.hour * 60 + selected.minute;
      timeChosen = true;
    }

    setState(() {
      _updating = true;
      _message = null;
    });
    try {
      var updated = current.copyWith(
        dailyOpenReminderEnabled: true,
        dailyOpenReminderMinutesAfterMidnight: minutesAfterMidnight,
        dailyOpenReminderTimeChosen: timeChosen,
      );
      if (Platform.isAndroid) {
        final allowed = await widget.service.requestNotificationPermission();
        updated = updated.copyWith(notificationPermissionRequested: true);
        if (!allowed) {
          await _applyPreferences(updated);
          if (!mounted) return;
          setState(() {
            _notificationsAllowed = false;
            _message = '每日提醒已保存，但系统未授予通知权限；可在系统设置中开启。';
          });
          return;
        }
      }
      await _applyPreferences(updated);
      if (!mounted) return;
      setState(() {
        _message = null;
      });
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _setDailyOpenReminderTime() async {
    final current = _preferences;
    if (current == null || _updating) return;
    final selected = await _pickTime(
      current.dailyOpenReminderMinutesAfterMidnight,
      helpText: '选择每日提醒时间（本机时间）',
    );
    if (selected == null || !mounted) return;
    await _applyPreferences(
      current.copyWith(
        dailyOpenReminderMinutesAfterMidnight:
            selected.hour * 60 + selected.minute,
        dailyOpenReminderTimeChosen: true,
      ),
    );
  }

  Future<TimeOfDay?> _pickTime(
    int minutesAfterMidnight, {
    required String helpText,
  }) {
    final injected = widget.timePicker;
    if (injected != null) return injected(minutesAfterMidnight, helpText);
    return showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: minutesAfterMidnight ~/ 60,
        minute: minutesAfterMidnight % 60,
      ),
      helpText: helpText,
    );
  }

  Future<void> _allowExactAlarms() async {
    setState(() {
      _updating = true;
      _message = null;
    });
    try {
      final allowed = await widget.service.requestExactAlarmPermission();
      if (!mounted) return;
      setState(() {
        _exactAlarmsAllowed = allowed;
        _message = allowed ? null : '尚未允许精确提醒；专注流程不受影响。';
      });
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _openSystemNotificationSettings() async {
    await widget.service.openNotificationSettings();
    if (!mounted) return;
    final notificationsAllowed = await widget.service.notificationsAllowed();
    final exactAlarmsAllowed = await widget.service.exactAlarmsAllowed();
    if (!mounted) return;
    setState(() {
      _notificationsAllowed = notificationsAllowed;
      _exactAlarmsAllowed = exactAlarmsAllowed;
      _message = notificationsAllowed ? null : '系统仍未开放通知权限，提醒暂不可送达。';
    });
  }

  String _formatTime(int minutesAfterMidnight) =>
      '${(minutesAfterMidnight ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutesAfterMidnight % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final preferences = _preferences;
    return Scaffold(
      appBar: AppBar(title: const Text('提醒与通知')),
      body: _loading || preferences == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      _buildFocusCard(preferences),
                      const SizedBox(height: 12),
                      _buildNationalFocusCard(preferences),
                      const SizedBox(height: 12),
                      _buildDailyReminderCard(preferences),
                      const SizedBox(height: 12),
                      Card(
                        child: SwitchListTile.adaptive(
                          value: preferences.backgroundRunningEnabled,
                          onChanged: _updating ? null : _setBackgroundEnabled,
                          title: const Text('显示后台倒计时'),
                          subtitle: Text(
                            Platform.isWindows
                                ? '在系统托盘显示当前状态；关闭窗口后会话仍在后台运行。'
                                : '在通知栏显示预约或专注状态，点按可返回会话。',
                          ),
                        ),
                      ),
                      if (_message != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _message!,
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        '这些提醒仅保存在本设备，不随云备份同步。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildFocusCard(FocusDevicePreferences preferences) => Card(
    child: Column(
      children: [
        SwitchListTile.adaptive(
          value: preferences.notificationsEnabled,
          onChanged: _updating ? null : _setNotificationsEnabled,
          title: const Text('专注流程通知'),
          subtitle: const Text('预约开始专注或专注结束时提醒；不提醒任务截止时间。'),
        ),
        if (preferences.notificationsEnabled && !_notificationsAllowed)
          _PermissionHint(
            message: '系统通知权限未开放，提醒暂不可送达。',
            onOpenSettings: _updating ? null : _openSystemNotificationSettings,
          ),
        if (preferences.notificationsEnabled &&
            Platform.isAndroid &&
            _notificationsAllowed &&
            !_exactAlarmsAllowed)
          _ExactAlarmHint(onAllow: _updating ? null : _allowExactAlarms),
        if (!preferences.notificationsEnabled &&
            Platform.isAndroid &&
            preferences.notificationPermissionRequested)
          _OpenSystemSettingsHint(
            message: '通知权限已被系统关闭；重新开启后可接收提醒。',
            onOpenSettings: _updating ? null : _openSystemNotificationSettings,
          ),
      ],
    ),
  );

  Widget _buildNationalFocusCard(FocusDevicePreferences preferences) => Card(
    child: Column(
      children: [
        SwitchListTile.adaptive(
          key: const Key('national-focus-reminder-enabled'),
          value: preferences.nationalFocusReminderEnabled,
          onChanged: _updating ? null : _setNationalFocusReminderEnabled,
          title: const Text('国策待确认提醒'),
          subtitle: const Text('有国策待确认时提醒一次；预约、专注或暂停中的会话结束后再提醒。'),
        ),
        ListTile(
          title: const Text('提醒时间（北京时间）'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('仅此设备有效，不影响国策检查点。'),
              TextButton(
                key: const Key('national-focus-reminder-time'),
                onPressed: _updating ? null : _setNationalFocusReminderTime,
                child: Text(
                  _formatTime(
                    preferences.nationalFocusReminderMinutesAfterMidnight,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (preferences.nationalFocusReminderEnabled &&
            Platform.isAndroid &&
            !_notificationsAllowed)
          _PermissionHint(
            message: '未授予通知权限，国策提醒暂不可送达；专注流程仍可使用。',
            onOpenSettings: _updating ? null : _openSystemNotificationSettings,
          ),
        if (preferences.nationalFocusReminderEnabled &&
            Platform.isAndroid &&
            _notificationsAllowed &&
            !_exactAlarmsAllowed)
          _ExactAlarmHint(onAllow: _updating ? null : _allowExactAlarms),
      ],
    ),
  );

  Widget _buildDailyReminderCard(FocusDevicePreferences preferences) => Card(
    child: Column(
      children: [
        SwitchListTile.adaptive(
          key: const Key('daily-open-reminder-enabled'),
          value: preferences.dailyOpenReminderEnabled,
          onChanged: _updating ? null : _setDailyOpenReminderEnabled,
          title: const Text('每天打开 Pacta'),
          subtitle: const Text('默认关闭。按本机当地时间每天提醒一次，点按打开看板。'),
        ),
        ListTile(
          title: const Text('提醒时间（本机时间）'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                Platform.isWindows
                    ? '仅在 Pacta 正在运行（含隐藏到托盘）时送达；完全退出后不会提醒。'
                    : '仅此设备有效，不随云备份同步。',
              ),
              TextButton(
                key: const Key('daily-open-reminder-time'),
                onPressed: _updating ? null : _setDailyOpenReminderTime,
                child: Text(
                  _formatTime(
                    preferences.dailyOpenReminderMinutesAfterMidnight,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (Platform.isAndroid && !_notificationsAllowed)
          _PermissionHint(
            message: '未授予通知权限，每日提醒暂不可送达；其他功能仍可使用。',
            onOpenSettings: _updating ? null : _openSystemNotificationSettings,
          ),
        if (Platform.isAndroid && _notificationsAllowed && !_exactAlarmsAllowed)
          _ExactAlarmHint(onAllow: _updating ? null : _allowExactAlarms),
      ],
    ),
  );
}

class _PermissionHint extends StatelessWidget {
  const _PermissionHint({required this.message, required this.onOpenSettings});

  final String message;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message),
          if (onOpenSettings != null)
            TextButton.icon(
              key: const Key('open-notification-settings'),
              onPressed: onOpenSettings,
              icon: const Icon(Icons.settings_outlined),
              label: const Text('去系统设置开启通知'),
            ),
        ],
      ),
    ),
  );
}

class _OpenSystemSettingsHint extends StatelessWidget {
  const _OpenSystemSettingsHint({
    required this.message,
    required this.onOpenSettings,
  });

  final String message;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message),
          TextButton.icon(
            key: const Key('open-notification-settings'),
            onPressed: onOpenSettings,
            icon: const Icon(Icons.settings_outlined),
            label: const Text('去系统设置开启通知'),
          ),
        ],
      ),
    ),
  );
}

class _ExactAlarmHint extends StatelessWidget {
  const _ExactAlarmHint({required this.onAllow});

  final VoidCallback? onAllow;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    child: Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onAllow,
        icon: const Icon(Icons.alarm_add_outlined),
        label: const Text('允许精确提醒'),
      ),
    ),
  );
}
