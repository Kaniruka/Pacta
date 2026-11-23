import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../profile/account_time_zone.dart';
import '../theme/pacta_icon_sizes.dart';
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
    this.accountTimeZoneIdLoader,
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

  /// 账号显示时区（IANA）。提醒时间按账号时区表达，结算点说明也跟着它走；
  /// 未注入时按账号尚无时区的统一回退值处理，不假设固定北京时间。
  final Future<String?> Function()? accountTimeZoneIdLoader;

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

  /// 账号时区：提醒时间与结算点说明都按它表达；未设时保留 null，
  /// 让检查点/提醒说明按默认国策时区（Asia/Shanghai）对齐。
  String? _accountTimeZoneId;

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
    final accountTimeZoneId = await _readAccountTimeZoneId();
    final permissions = await _readSystemPermissions();
    if (!mounted) return;
    setState(() {
      _preferences = preferences;
      _accountTimeZoneId = accountTimeZoneId;
      _notificationsAllowed = permissions.$1;
      _exactAlarmsAllowed = permissions.$2;
      _ignoringBatteryOptimizations = permissions.$3;
      _loading = false;
    });
  }

  /// 账号时区读取失败或未配置时保留 null：国策检查点与提醒说明跟随
  /// `checkpointTimeZoneId(null)`（Asia/Shanghai），不混成 Etc/UTC。
  Future<String?> _readAccountTimeZoneId() async {
    final loader = widget.accountTimeZoneIdLoader;
    if (loader == null) return null;
    try {
      final raw = await loader();
      return AccountTimeZones.isKnown(raw) ? raw : null;
    } on Object {
      return null;
    }
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
      helpText: '选择提醒时间（账号时区）',
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
    return PactaSurfaces.wrapIfMissing(
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
          size: PactaIconSizes.sm,
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
        // 已允许时状态胶囊已经给出结论，副标题只在缺权限时说明下一步动作。
        subtitle: _notificationsAllowed ? null : '未授予通知权限；点按前往系统设置开启。',
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
          onTap: _updating ? null : _requestNotifications,
        ),
      if (_isAndroid)
        PactaSettingsTile(
          tileKey: const Key('allow-exact-alarms'),
          leadingIcon: Icons.alarm_on_outlined,
          title: '精确提醒（闹钟）',
          subtitle: _exactAlarmsAllowed ? null : '未允许；系统可能延迟送达，点按即可允许。',
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
              ? null
              : '未加入电池优化白名单；点按加入后锁屏也能继续倒计时。',
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
            title: '提醒时间（账号时区）',
            // 机制说明不是每次都要读：折进行内 ⓘ，需要时点开读全文，
            // 设置行本身保持一行高。
            trailing: _timeTrailing(
              preferences.nationalFocusReminderMinutesAfterMidnight,
              note: _nationalFocusReminderNote(),
            ),
            onTap: _updating ? null : _setNationalFocusReminderTime,
          ),
          SwitchListTile.adaptive(
            key: const Key('daily-open-reminder-enabled'),
            value: preferences.dailyOpenReminderEnabled,
            onChanged: _updating ? null : _setDailyOpenReminderEnabled,
            title: const Text('每天打开 Pacta'),
            subtitle: const Text('提醒后点按通知直接打开看板。'),
          ),
          PactaSettingsTile(
            tileKey: const Key('daily-open-reminder-time'),
            title: '提醒时间（本机时间）',
            // 非桌面端的时间值本身就是答案；只有桌面端存在「退出后不送达」
            // 这条非显而易见的限制需要写清楚。
            subtitle: _isWindowsDesktop
                ? '仅在 Pacta 正在运行（含隐藏到托盘）时送达；完全退出后不会提醒。'
                : null,
            trailing: _timeTrailing(
              preferences.dailyOpenReminderMinutesAfterMidnight,
            ),
            onTap: _updating ? null : _setDailyOpenReminderTime,
          ),
        ],
      );

  /// 国策提醒的机制说明：提醒时刻只决定何时发出，结算点按账号时区表达。
  ///
  /// 纯北京时间不再是账号的既定事实，这里改成账号结算点与本机墙钟的对照，
  /// 偏移不同时（例如账号东六区、本机东八区）会直接写出设备上的实际时刻。
  String _nationalFocusReminderNote() {
    final cityLabel = AccountTimeZones.cityFor(_accountTimeZoneId)?.label;
    final zoneNote = cityLabel == null ? '' : '账号时区：$cityLabel。';
    final comparison = AccountTimeZones.formatCheckpointComparison(
      accountTimeZoneId: _accountTimeZoneId,
      referenceUtc: DateTime.now().toUtc(),
    );
    return '不影响国策检查点：这个时间只决定提醒何时发出，$zoneNote$comparison。';
  }

  /// 行尾时间值 + 行内说明 + 箭头：整行仍是唯一命中区，时间只是它的右侧读数。
  ///
  /// [note] 非空时多一枚 [PactaIconSizes.micro] 的「ⓘ」：机制说明挂在
  /// tooltip 里，不再常驻成副标题把设置行撑成两行。
  Widget _timeTrailing(int minutesAfterMidnight, {String? note}) {
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
        if (note != null) ...[
          const SizedBox(width: PactaSpacing.xs),
          Tooltip(
            key: const Key('national-focus-reminder-time-note'),
            triggerMode: TooltipTriggerMode.tap,
            message: note,
            child: Icon(
              Icons.info_outline,
              size: PactaIconSizes.micro,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(width: PactaSpacing.xs),
        Icon(
          Icons.chevron_right,
          size: PactaIconSizes.compact,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ],
    );
  }
}
