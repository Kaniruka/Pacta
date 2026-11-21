import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../theme/pacta_spacing.dart';
import '../theme/pacta_surfaces.dart';
import '../ui/pacta_grouped_list.dart';
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
/// 页面按 Google 服务式分组呈现：每个分组只有一个 [PactaSectionHeader] 标题
/// 和一块 [PactaGroupedList]。行内不再内嵌跳转按钮，也不再用缩进分割线把
/// 卡片割裂成碎片——整行点击、尾部状态胶囊与箭头承担全部入口与状态。所有
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

  String _formatTime(int minutesAfterMidnight) {
    final hour = (minutesAfterMidnight ~/ 60).toString().padLeft(2, '0');
    final minute = (minutesAfterMidnight % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final preferences = _preferences;
    final theme = Theme.of(context);
    return _withPactaSurfaces(
      context,
      Scaffold(
        appBar: AppBar(title: const Text('通知与设备权限')),
        body: _loading || preferences == null
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: ListView(
                      padding: PactaSpacing.pageInsets(
                        context,
                        top: PactaSpacing.xs,
                      ),
                      children: [
                        const PactaSectionHeader(title: '后台运行与系统权限'),
                        _buildPermissionGroup(),
                        const PactaSectionHeader(title: '后台倒计时与专注通知'),
                        _buildFocusGroup(preferences),
                        const PactaSectionHeader(title: '定时提醒'),
                        _buildReminderGroup(preferences),
                        if (_message != null) ...[
                          const SizedBox(height: PactaSpacing.md),
                          _buildMessage(theme),
                        ],
                        const SizedBox(height: PactaSpacing.lg),
                        Text(
                          '这些提醒仅保存在本设备，不随云备份同步。',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  /// 提示只用一行轻量说明，不再把页面变成第二张告警卡片。
  Widget _buildMessage(ThemeData theme) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: PactaSpacing.xs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: PactaSpacing.sm),
        Expanded(
          child: Text(
            _message!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    ),
  );

  /// 第一组：系统通知、精确闹钟、后台运行白名单与系统日历只读导入。
  ///
  /// 每项都是一整行入口：状态放在右侧胶囊里，需要去系统设置的动作由点击整行
  /// 触发，不在副标题里再塞一行按钮。
  Widget _buildPermissionGroup() => PactaGroupedList(
    children: [
      PactaSettingsTile(
        tileKey: const Key('open-notification-settings'),
        leadingIcon: _notificationsAllowed
            ? Icons.notifications_active_outlined
            : Icons.notifications_off_outlined,
        title: '系统通知权限',
        subtitle: _notificationsAllowed
            ? '已允许通知；专注、国策与每日提醒可以送达。'
            : '尚未允许通知；提醒仍保存在本机，但无法送达。',
        statusBadge: PactaStatusBadge(
          label: _notificationsAllowed ? '已开启' : '未开启',
          tone: _notificationsAllowed
              ? PactaStatusBadgeTone.success
              : PactaStatusBadgeTone.warning,
        ),
        onTap: _updating ? null : _openSystemNotificationSettings,
      ),
      if (_isAndroid && !_notificationsAllowed)
        PactaSettingsTile(
          tileKey: const Key('request-notification-permission'),
          leadingIcon: Icons.notifications_outlined,
          title: '申请系统通知权限',
          subtitle: '直接向系统请求通知授权',
          onTap: _updating ? null : _requestNotifications,
        ),
      if (_isAndroid)
        PactaSettingsTile(
          tileKey: const Key('allow-exact-alarms'),
          leadingIcon: Icons.alarm_on_outlined,
          title: '精确提醒（闹钟）',
          subtitle: _exactAlarmsAllowed
              ? '已允许；提醒按设定时刻送达。'
              : '未允许；系统可能延迟送达，点按即可允许。',
          statusBadge: PactaStatusBadge(
            label: _exactAlarmsAllowed ? '已允许' : '待开启',
            tone: _exactAlarmsAllowed
                ? PactaStatusBadgeTone.success
                : PactaStatusBadgeTone.warning,
          ),
          onTap: _updating ? null : _allowExactAlarms,
        ),
      if (_isAndroid)
        PactaSettingsTile(
          tileKey: const Key('open-battery-optimization-settings'),
          leadingIcon: _ignoringBatteryOptimizations
              ? Icons.battery_charging_full_outlined
              : Icons.battery_alert_outlined,
          title: '后台运行',
          subtitle: _ignoringBatteryOptimizations
              ? '已加入电池优化白名单；锁屏或切到其他应用后倒计时与提醒仍会继续。'
              : '系统可能限制后台运行；加入白名单后倒计时与提醒更稳定。',
          statusBadge: PactaStatusBadge(
            label: _ignoringBatteryOptimizations ? '已加白名单' : '建议开启',
            tone: _ignoringBatteryOptimizations
                ? PactaStatusBadgeTone.success
                : PactaStatusBadgeTone.warning,
          ),
          onTap: _updating ? null : _openBatteryOptimizationSettings,
        )
      else
        const PactaSettingsTile(
          leadingIcon: Icons.desktop_windows_outlined,
          title: '后台运行',
          subtitle: '桌面端保活运行，无需电池优化',
          showChevron: false,
        ),
      PactaSettingsTile(
        tileKey: const Key('open-calendar-sources'),
        leadingIcon: Icons.calendar_month_outlined,
        title: '系统日历只读导入',
        subtitle: _isAndroid
            ? '只读取你勾选的系统日历，导入为自有日程副本，不改源日历。'
            : '桌面端暂不支持读取系统日历；已导入的副本仍可正常管理。',
        enabled: !_updating && widget.calendarSourcesBuilder != null,
        onTap: _openCalendarSources,
      ),
    ],
  );

  /// 第二组：后台倒计时显示与专注流程通知。
  Widget _buildFocusGroup(FocusDevicePreferences preferences) =>
      PactaGroupedList(
        children: [
          SwitchListTile.adaptive(
            value: preferences.backgroundRunningEnabled,
            onChanged: _updating ? null : _setBackgroundEnabled,
            title: const Text('显示后台倒计时'),
            subtitle: Text(
              _isWindowsDesktop
                  ? '在系统托盘显示当前状态；关闭窗口后会话仍在后台运行。'
                  : '在通知栏显示预约或专注状态，点按可返回会话。',
            ),
          ),
          SwitchListTile.adaptive(
            value: preferences.notificationsEnabled,
            onChanged: _updating ? null : _setNotificationsEnabled,
            title: const Text('专注流程通知'),
            subtitle: const Text('预约开始专注或专注结束时提醒；不提醒任务截止时间。'),
          ),
        ],
      );

  /// 第三组：国策待确认提醒与每天打开 Pacta，各自带整行可点的时间值。
  Widget _buildReminderGroup(FocusDevicePreferences preferences) =>
      PactaGroupedList(
        children: [
          SwitchListTile.adaptive(
            key: const Key('national-focus-reminder-enabled'),
            value: preferences.nationalFocusReminderEnabled,
            onChanged: _updating ? null : _setNationalFocusReminderEnabled,
            title: const Text('国策待确认提醒'),
            subtitle: const Text('有国策待确认时提醒一次；预约、专注或暂停中的会话结束后再提醒。'),
          ),
          PactaSettingsTile(
            tileKey: const Key('national-focus-reminder-time'),
            title: '提醒时间（北京时间）',
            subtitle: '不影响国策检查点',
            trailing: _timeTrailing(
              preferences.nationalFocusReminderMinutesAfterMidnight,
            ),
            onTap: _updating ? null : _setNationalFocusReminderTime,
          ),
          SwitchListTile.adaptive(
            key: const Key('daily-open-reminder-enabled'),
            value: preferences.dailyOpenReminderEnabled,
            onChanged: _updating ? null : _setDailyOpenReminderEnabled,
            title: const Text('每天打开 Pacta'),
            subtitle: const Text('默认关闭。按本机当地时间每天提醒一次，点按打开看板。'),
          ),
          PactaSettingsTile(
            tileKey: const Key('daily-open-reminder-time'),
            title: '提醒时间（本机时间）',
            subtitle: _isWindowsDesktop
                ? '仅在 Pacta 正在运行（含隐藏到托盘）时送达；完全退出后不会提醒。'
                : '每天按本机当地时间提醒',
            trailing: _timeTrailing(
              preferences.dailyOpenReminderMinutesAfterMidnight,
            ),
            onTap: _updating ? null : _setDailyOpenReminderTime,
          ),
        ],
      );

  /// 行尾时间值 + 箭头：整行仍是唯一命中区，时间只是它的右侧读数。
  Widget _timeTrailing(int minutesAfterMidnight) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _formatTime(minutesAfterMidnight),
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(width: PactaSpacing.xs),
        Icon(
          Icons.chevron_right,
          size: 20,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ],
    );
  }
}

/// 独立路由兜底：预览或测试宿主可能只提供裸 [ThemeData]，此时补一层
/// [PactaSurfaces]，让分组列表的卡片与分割线令牌始终有定义；已注入完整
/// 主题时原样返回，不叠加第二套表面。
Widget _withPactaSurfaces(BuildContext context, Widget child) {
  final theme = Theme.of(context);
  if (theme.extension<PactaSurfaces>() != null) return child;
  return Theme(
    data: theme.copyWith(
      extensions: [
        ...theme.extensions.values,
        theme.brightness == Brightness.dark
            ? PactaSurfaces.dark
            : PactaSurfaces.light,
      ],
    ),
    child: child,
  );
}
