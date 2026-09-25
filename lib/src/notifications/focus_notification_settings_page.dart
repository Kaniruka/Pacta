import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import 'focus_device_preferences.dart';
import 'focus_notification_service.dart';

class FocusNotificationSettingsPage extends StatefulWidget {
  const FocusNotificationSettingsPage({
    super.key,
    required this.service,
  });

  final FocusNotificationService service;

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
            _message = '系统通知权限未开放；专注和预约仍可照常使用。';
          });
        }
        return;
      }
      final updated = current.copyWith(notificationsEnabled: enabled);
      await widget.service.updatePreferences(updated);
      final notificationsAllowed = await widget.service.notificationsAllowed();
      final exactAlarmsAllowed = await widget.service.exactAlarmsAllowed();
      if (mounted) {
        setState(() {
          _preferences = updated;
          _notificationsAllowed = notificationsAllowed;
          _exactAlarmsAllowed = exactAlarmsAllowed;
          _message = enabled && !exactAlarmsAllowed && Platform.isAndroid
              ? '已启用提醒；未允许精确提醒时，系统可能延后送达。'
              : null;
        });
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _setBackgroundEnabled(bool enabled) async {
    final current = _preferences;
    if (current == null || _updating) return;
    setState(() => _updating = true);
    try {
      final updated = current.copyWith(backgroundRunningEnabled: enabled);
      await widget.service.updatePreferences(updated);
      if (mounted) setState(() => _preferences = updated);
    } finally {
      if (mounted) setState(() => _updating = false);
    }
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
        _message = allowed
            ? null
            : '精确提醒尚未允许；核心专注流程不受影响。';
      });
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preferences = _preferences;
    return Scaffold(
      appBar: AppBar(title: const Text('通知与后台状态')),
      body: _loading || preferences == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Card(
                  child: Column(
                    children: [
                      SwitchListTile.adaptive(
                        value: preferences.notificationsEnabled,
                        onChanged: _updating ? null : _setNotificationsEnabled,
                        title: const Text('专注流程通知'),
                        subtitle: const Text(
                          '预约进入专注和专注会话结束时提醒。任务截止时间不会通知。',
                        ),
                      ),
                      if (preferences.notificationsEnabled &&
                          !_notificationsAllowed)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text('系统通知权限未开放，提醒暂不可送达。'),
                          ),
                        ),
                      if (preferences.notificationsEnabled &&
                          Platform.isAndroid &&
                          !_exactAlarmsAllowed)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: _updating ? null : _allowExactAlarms,
                              icon: const Icon(Icons.alarm_add_outlined),
                              label: const Text('允许准确的专注提醒'),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: SwitchListTile.adaptive(
                    value: preferences.backgroundRunningEnabled,
                    onChanged: _updating ? null : _setBackgroundEnabled,
                    title: const Text('显示后台倒计时'),
                    subtitle: Text(
                      Platform.isWindows
                          ? '在系统托盘显示当前状态；会话进行中关闭窗口时保留在后台。'
                          : '在通知栏显示预约或专注状态，点击可返回当前会话。',
                    ),
                  ),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _message!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  '这些偏好仅保存在本设备，不会同步到其他设备。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
    );
  }
}
