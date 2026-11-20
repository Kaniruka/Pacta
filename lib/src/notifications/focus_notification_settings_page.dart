import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../theme/pacta_fonts.dart';
import '../theme/pacta_spacing.dart';
import 'device_permission_gateway.dart';
import 'focus_device_preferences.dart';
import 'focus_notification_service.dart';

/// Picks a reminder time. Injected by tests; production uses [showTimePicker].
typedef ReminderTimePicker = Future<TimeOfDay?> Function(
  int minutesAfterMidnight,
  String helpText,
);

/// 《通知与设备权限》：后台运行、系统权限、专注通知与定时提醒的唯一设备级设置面。
///
/// 页面分三组：先讲清楚应用能不能在后台跑、通知/精确闹钟/日历权限是否开放，
/// 再放后台倒计时与专注流程通知，最后是国策待确认提醒与每日打开提醒。所有
/// 设置都只在本设备生效，不随云备份同步。
class FocusNotificationSettingsPage extends StatefulWidget {
  const FocusNotificationSettingsPage({
    super.key,
    required this.service,
    this.timePicker,
    this.isAndroid,
    this.permissionGateway,
    this.batteryOptimizationGateway,
    this.calendarSourcesBuilder,
  });

  final FocusNotificationService service;
  final ReminderTimePicker? timePicker;

  /// 测试用平台覆盖；生产按 [Platform.isAndroid]。
  final bool? isAndroid;

  /// 系统设置入口；为空时按平台取默认实现。
  final DevicePermissionGateway? permissionGateway;

  /// Android 后台运行（忽略电池优化）能力；为空时按平台取默认实现。
  final BatteryOptimizationGateway? batteryOptimizationGateway;

  /// 打开已有《系统日历导入》页的来源勾选与手动导入界面。
  ///
  /// 由《我的》注入，本页因此不依赖日历模块；为空时该行只解释入口尚未接入。
  final WidgetBuilder? calendarSourcesBuilder;

  @override
  State<FocusNotificationSettingsPage> createState() =>
      _FocusNotificationSettingsPageState();
}

class _FocusNotificationSettingsPageState
    extends State<FocusNotificationSettingsPage> {
  FocusDevicePreferences? _preferences;
  bool _notificationsAllowed = false;
  bool _exactAlarmsAllowed = false;
  bool _ignoringBatteryOptimizations = false;
  bool _loading = true;
  bool _updating = false;
  String? _message;

  bool get _isAndroid => widget.isAndroid ?? Platform.isAndroid;

  /// 真正的 Windows 桌面表现（系统托盘/前台进程保活）。
  ///
  /// 以 [_isAndroid] 为准而不是直接看宿主平台：注入 isAndroid 为 true 时一律
  /// 按移动端文案与分支走，桌面宿主的测试才能覆盖 Android 权限请求路径。
  bool get _isWindowsDesktop => !_isAndroid && Platform.isWindows;

  DevicePermissionGateway get _permissions =>
      widget.permissionGateway ?? createDevicePermissionGateway();

  BatteryOptimizationGateway get _battery =>
      widget.batteryOptimizationGateway ?? createBatteryOptimizationGateway();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final preferences = await widget.service.getPreferences();
    final permissions = await _readSystemPermissions();
    if (!mounted) return;
    setState(() {
      _preferences = preferences;
      _notificationsAllowed = permissions.$1;
      _exactAlarmsAllowed = permissions.$2;
      _ignoringBatteryOptimizations = permissions.$3;
      _loading = false;
    });
  }

  /// 三个系统权限状态并行读取；桌面端没有电池优化概念，固定为 false。
  Future<(bool, bool, bool)> _readSystemPermissions() async {
    final notificationsAllowed = await widget.service.notificationsAllowed();
    final exactAlarmsAllowed = await widget.service.exactAlarmsAllowed();
    final ignoringBattery = _isAndroid
        ? await _battery.isIgnoringBatteryOptimizations()
        : false;
    return (notificationsAllowed, exactAlarmsAllowed, ignoringBattery);
  }

  Future<void> _applyPreferences(FocusDevicePreferences updated) async {
    await widget.service.updatePreferences(updated);
    final permissions = await _readSystemPermissions();
    if (!mounted) return;
    setState(() {
      _preferences = updated;
      _notificationsAllowed = permissions.$1;
      _exactAlarmsAllowed = permissions.$2;
      _ignoringBatteryOptimizations = permissions.$3;
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
        if (_isAndroid) {
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
        _message = enabled && !_exactAlarmsAllowed && _isAndroid
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
          _isAndroid &&
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
        _message = enabled && !_exactAlarmsAllowed && _isAndroid
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
      if (_isAndroid) {
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

  Future<void> _requestNotifications() async {
    if (_updating) return;
    setState(() {
      _updating = true;
      _message = null;
    });
    try {
      final allowed = await widget.service.requestNotificationPermission();
      if (!mounted) return;
      setState(() {
        _notificationsAllowed = allowed;
        _message = allowed ? null : '系统未授予通知权限；可在系统设置中重新开启。';
      });
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
        _message = allowed ? null : '尚未允许精确提醒；专注流程不受影响。';
      });
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _openSystemNotificationSettings() async {
    // 走注入的网关而不是服务内部默认实现：系统屏幕入口可替换、可测试。
    await _permissions.openNotificationSettings();
    if (!mounted) return;
    final permissions = await _readSystemPermissions();
    if (!mounted) return;
    setState(() {
      _notificationsAllowed = permissions.$1;
      _exactAlarmsAllowed = permissions.$2;
      _ignoringBatteryOptimizations = permissions.$3;
      _message = permissions.$1 ? null : '系统仍未开放通知权限，提醒暂不可送达。';
    });
  }

  /// 从系统白名单页返回后重新读取状态：用户可能刚在系统里放行。
  Future<void> _openBatteryOptimizationSettings() async {
    setState(() {
      _updating = true;
      _message = null;
    });
    try {
      await _battery.openBatteryOptimizationSettings();
      if (!mounted) return;
      final permissions = await _readSystemPermissions();
      if (!mounted) return;
      setState(() {
        _notificationsAllowed = permissions.$1;
        _exactAlarmsAllowed = permissions.$2;
        _ignoringBatteryOptimizations = permissions.$3;
        _message = permissions.$3 ? '已加入电池优化白名单，后台倒计时与提醒更稳定。' : null;
      });
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _openCalendarSources() async {
    final builder = widget.calendarSourcesBuilder;
    if (builder == null) return;
    await Navigator.of(context)
        .push<void>(MaterialPageRoute<void>(builder: builder));
  }

  String _formatTime(int minutesAfterMidnight) =>
      '${(minutesAfterMidnight ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutesAfterMidnight % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final preferences = _preferences;
    return Scaffold(
      appBar: AppBar(title: const Text('通知与设备权限')),
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
                      _sectionTitle(context, '后台运行与系统权限'),
                      const SizedBox(height: PactaSpacing.sm),
                      _buildPermissionCard(context),
                      const SizedBox(height: PactaSpacing.md),
                      _sectionTitle(context, '后台倒计时与专注通知'),
                      const SizedBox(height: PactaSpacing.sm),
                      _buildBackgroundCard(preferences),
                      const SizedBox(height: PactaSpacing.sm),
                      _buildFocusCard(preferences),
                      const SizedBox(height: PactaSpacing.md),
                      _sectionTitle(context, '定时提醒'),
                      const SizedBox(height: PactaSpacing.sm),
                      _buildNationalFocusCard(preferences),
                      const SizedBox(height: PactaSpacing.sm),
                      _buildDailyReminderCard(preferences),
                      if (_message != null) ...[
                        const SizedBox(height: PactaSpacing.md),
                        Text(
                          _message!,
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: PactaSpacing.md),
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

  /// 分组标题：只用主题字阶 + 600 字重，不声明任何字体族。
  Widget _sectionTitle(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.only(left: PactaSpacing.xs),
    child: Text(
      title,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(fontWeight: PactaFonts.semibold),
    ),
  );

  /// 第一组：系统通知、精确闹钟、后台运行白名单与系统日历只读导入。
  Widget _buildPermissionCard(BuildContext context) {
    final divider = const Divider(height: 1, indent: 16, endIndent: 16);
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              _notificationsAllowed
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_off_outlined,
            ),
            title: const Text('系统通知权限'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _notificationsAllowed
                      ? '已允许通知；专注、国策与每日提醒可以送达。'
                      : '尚未允许通知；提醒仍保存在本机，但无法送达。',
                ),
                TextButton.icon(
                  key: const Key('open-notification-settings'),
                  onPressed: _updating ? null : _openSystemNotificationSettings,
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('去系统设置开启通知'),
                ),
                if (_isAndroid && !_notificationsAllowed)
                  TextButton.icon(
                    key: const Key('request-notification-permission'),
                    onPressed: _updating ? null : _requestNotifications,
                    icon: const Icon(Icons.notifications_outlined),
                    label: const Text('申请通知权限'),
                  ),
              ],
            ),
          ),
          divider,
          if (_isAndroid) ...[
            ListTile(
              leading: const Icon(Icons.alarm_on_outlined),
              title: const Text('精确提醒（闹钟）'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _exactAlarmsAllowed
                        ? '已允许精确闹钟；提醒按设定时刻送达。'
                        : '未允许精确闹钟；系统可能把提醒延迟送达。',
                  ),
                  if (!_exactAlarmsAllowed)
                    TextButton.icon(
                      key: const Key('allow-exact-alarms'),
                      onPressed: _updating ? null : _allowExactAlarms,
                      icon: const Icon(Icons.alarm_add_outlined),
                      label: const Text('允许精确提醒'),
                    ),
                ],
              ),
            ),
            divider,
            ListTile(
              leading: Icon(
                _ignoringBatteryOptimizations
                    ? Icons.battery_charging_full_outlined
                    : Icons.battery_alert_outlined,
              ),
              title: const Text('后台运行'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _ignoringBatteryOptimizations
                        ? '已加入电池优化白名单；锁屏或切到其他应用后倒计时与提醒仍会继续。'
                        : '系统可能限制后台运行；加入电池优化白名单后倒计时与提醒更稳定。',
                  ),
                  TextButton.icon(
                    key: const Key('open-battery-optimization-settings'),
                    onPressed: _updating
                        ? null
                        : _openBatteryOptimizationSettings,
                    icon: const Icon(Icons.battery_saver_outlined),
                    label: Text(
                      _ignoringBatteryOptimizations ? '查看电池优化设置' : '去电池优化白名单',
                    ),
                  ),
                ],
              ),
            ),
            divider,
          ] else
            const ListTile(
              leading: Icon(Icons.desktop_windows_outlined),
              title: Text('后台运行'),
              subtitle: Text('桌面端依赖系统托盘/前台进程保活，无需电池优化白名单。'),
            ),
          if (!_isAndroid) divider,
          ListTile(
            leading: const Icon(Icons.calendar_month_outlined),
            title: const Text('系统日历只读导入'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isAndroid
                      ? '只读取你勾选的系统日历，手动导入为自有日程副本，不修改源日历。'
                      : '桌面端暂不支持读取系统日历；已导入的副本仍可正常管理。',
                ),
                TextButton.icon(
                  key: const Key('open-calendar-sources'),
                  onPressed: _updating || widget.calendarSourcesBuilder == null
                      ? null
                      : _openCalendarSources,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: const Text('选择来源与导入'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 第二组：后台倒计时显示与专注流程通知。
  Widget _buildBackgroundCard(FocusDevicePreferences preferences) => Card(
    child: SwitchListTile.adaptive(
      value: preferences.backgroundRunningEnabled,
      onChanged: _updating ? null : _setBackgroundEnabled,
      title: const Text('显示后台倒计时'),
      subtitle: Text(
        _isWindowsDesktop
            ? '在系统托盘显示当前状态；关闭窗口后会话仍在后台运行。'
            : '在通知栏显示预约或专注状态，点按可返回会话。',
      ),
    ),
  );

  Widget _buildFocusCard(FocusDevicePreferences preferences) => Card(
    child: SwitchListTile.adaptive(
      value: preferences.notificationsEnabled,
      onChanged: _updating ? null : _setNotificationsEnabled,
      title: const Text('专注流程通知'),
      subtitle: const Text('预约开始专注或专注结束时提醒；不提醒任务截止时间。'),
    ),
  );

  /// 第三组：国策待确认提醒与每天打开 Pacta 的独立提醒。
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
                _isWindowsDesktop
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
      ],
    ),
  );
}
