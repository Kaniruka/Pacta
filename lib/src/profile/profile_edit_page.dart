import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../auth/auth_repository.dart';
import '../auth/user_lifecycle.dart';
import '../notifications/focus_notification_service.dart';
import '../theme/pacta_fonts.dart';
import '../theme/pacta_icon_sizes.dart';
import '../theme/pacta_spacing.dart';
import '../theme/pacta_surfaces.dart';
import '../ui/pacta_error_text.dart';
import '../ui/pacta_grouped_list.dart';
import '../ui/pacta_hold_action_reorder.dart';
import 'account_time_zone.dart';
import 'avatar_crop_page.dart';
import 'avatar_image.dart';
import 'avatar_picker.dart';
import 'change_password_page.dart';
import 'profile_repository.dart';

/// Edits the account display name, avatar and account-level display time zone.
///
/// 头像只有一个入口：可点的大圆头像 + 一颗「更换头像 / 选择头像」按钮，
/// 更换/重新裁剪/移除收进同一张操作面板；时区是一段与表单同语言的
/// [PactaSectionHeader] + 芯片组，规则说明折进行内 ⓘ，不再插一张风格不同
/// 的小卡片。保存失败只在页内呈现并可就地重试。
class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({
    super.key,
    required this.repository,
    required this.avatarPicker,
    this.authRepository,
    this.lifecycleRepository,
    this.notificationService,
  });

  final ProfileRepository repository;
  final AvatarPicker avatarPicker;

  /// 账号自助动作的依赖。未注入时（隔离组件测试、无 Supabase 环境）不渲染
  /// 「账号安全」分组：修改密码必须有可用的登录会话，入口缺省比点开再报错好。
  final AuthRepository? authRepository;
  final UserLifecycleStatusRepository? lifecycleRepository;

  /// 明确退出登录时先取消本机已登记的提醒；未注入时只清登录状态。
  final FocusNotificationService? notificationService;

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  final TextEditingController _nameController = TextEditingController();
  Uint8List? _pickedAvatar;
  Uint8List? _cropSource;
  Uint8List? _storedAvatar;
  bool _clearAvatar = false;
  bool _busy = false;
  bool _picking = false;
  bool _syncFailed = false;
  bool _nameEdited = false;
  String? _timeZoneId;
  String? _loadedTimeZoneId;
  String? _error;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final profile = await widget.repository.getProfile();
    if (!mounted) return;
    setState(() {
      if (!_nameEdited) _nameController.text = profile.displayName;
      _storedAvatar = profile.avatar?.bytes;
      _timeZoneId = profile.displayTimeZoneId;
      _loadedTimeZoneId = profile.displayTimeZoneId;
    });
  }

  Uint8List? get _visibleAvatar =>
      _clearAvatar ? null : (_pickedAvatar ?? _storedAvatar);

  /// 头像与「更换头像」共用这一个入口：没有头像时直接选图，已有头像时先
  /// 让用户在更换、重新裁剪和移除之间做一次明确选择。
  Future<void> _handleAvatarTap() async {
    if (_busy || _picking) return;
    if (_visibleAvatar == null) {
      await _pickAvatar();
      return;
    }
    await _showAvatarActions();
  }

  Future<void> _showAvatarActions() async {
    final hasAvatar = _visibleAvatar != null;
    await showPactaActionSheet(
      context,
      title: '头像',
      subtitle: hasAvatar ? '更换、重新裁剪或移除当前头像' : null,
      actions: [
        PactaActionItem(
          id: 'pick-avatar',
          label: '选择新图片',
          icon: Icons.photo_library_outlined,
          onTap: _pickAvatar,
        ),
        if (hasAvatar)
          PactaActionItem(
            id: 'recrop-avatar',
            label: '重新裁剪',
            icon: Icons.crop_outlined,
            onTap: _recropAvatar,
          ),
        if (hasAvatar)
          PactaActionItem(
            id: 'remove-avatar',
            label: '移除头像',
            icon: Icons.delete_outline,
            destructive: true,
            onTap: _removeAvatar,
          ),
      ],
    );
  }

  void _removeAvatar() {
    setState(() {
      _pickedAvatar = null;
      _cropSource = null;
      _clearAvatar = true;
    });
  }

  Future<void> _pickAvatar() async {
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final bytes = await widget.avatarPicker.pickSingleImage();
      if (bytes == null || !mounted) return;
      await _cropAvatar(bytes);
    } on AvatarValidationException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on AvatarPickException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error = formatUserError(error, fallback: '这张图片无法读取，请重新选择。'),
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _cropAvatar(Uint8List bytes) async {
    final image = await decodeAvatarForCrop(bytes);
    MaterialPageRoute<Uint8List>? route;
    try {
      if (!mounted) return;
      route = MaterialPageRoute<Uint8List>(
        builder: (_) => AvatarCropPage(image: image),
      );
      final cropped = await Navigator.of(context).push<Uint8List>(route);
      if (!mounted || cropped == null) return;
      setState(() {
        _pickedAvatar = cropped;
        _cropSource = bytes;
        _clearAvatar = false;
      });
    } finally {
      if (route == null) {
        image.dispose();
      } else {
        route.completed.then((_) => image.dispose());
      }
    }
  }

  Future<void> _recropAvatar() async {
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      await _cropAvatar(_cropSource ?? _visibleAvatar!);
    } catch (_) {
      if (mounted) setState(() => _error = '这张图片无法读取，请重新选择。');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    // 只有本页真正改过时才上传时区：仅改昵称/头像时省略，账号存储保留
    // 自己的值，避免把本机缓存的旧时区重新推成"最新选择"。
    final requestedTimeZoneId = _timeZoneId == _loadedTimeZoneId
        ? null
        : _timeZoneId;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await widget.repository.saveProfile(
        displayName: _nameController.text,
        avatar: _pickedAvatar == null
            ? null
            : ProfileAvatar(
                bytes: _pickedAvatar!,
                mimeType: AvatarImageFormat.png.mimeType,
              ),
        clearAvatar: _clearAvatar,
        timeZoneId: requestedTimeZoneId,
      );
      if (!mounted) return;
      // 账号时区可能已被另一台设备更新。账号存储按修订号保留了最新接受值，
      // 这里必须如实说明"采用的是账号最新值"，不能把本次点击说成已生效。
      final timeZoneReplaced =
          requestedTimeZoneId != null &&
          saved.syncError == null &&
          saved.displayTimeZoneId != requestedTimeZoneId;
      final saveError = saved.syncError;
      final effectiveZoneId = AccountTimeZones.effectiveId(
        saved.displayTimeZoneId,
      );
      setState(() {
        _storedAvatar = saved.avatar?.bytes;
        _pickedAvatar = null;
        _timeZoneId = saved.displayTimeZoneId;
        _loadedTimeZoneId = saved.displayTimeZoneId;
        _error =
            (saveError == null
                ? null
                : formatUserError(saveError, fallback: '保存未完成，请稍后重试。')) ??
            (timeZoneReplaced
                ? '账号时区已被其他设备更新，已采用最新值：$effectiveZoneId。'
                      '如仍想使用刚才的选择，请重新选择后再保存。'
                : null);
        _syncFailed = saveError != null;
      });
      if (saved.syncError == null && !timeZoneReplaced) {
        Navigator.of(context).pop();
      }
    } on AvatarValidationException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _syncFailed = false;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          // 保存失败就地显示在编辑页；退出编辑页后只读名片不继承这条报错。
          _error = formatUserError(error, fallback: '保存未完成，请稍后重试。');
          _syncFailed = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 修改密码是独立二级页：它有自己的表单与本页无关的失败原因，
  /// 因此不把输入框塞进资料表单。
  Future<void> _openChangePassword() async {
    final authRepository = widget.authRepository;
    if (authRepository == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChangePasswordPage(
          authRepository: authRepository,
          lifecycleRepository: widget.lifecycleRepository,
        ),
      ),
    );
  }

  /// 退出登录：与「修改密码」同属账号安全分组，因此放在同一段列表里。
  ///
  /// 先取消本机已登记的提醒（明确登出才取消，正常关应用保留未来项），再清
  /// 登录状态；若编辑页是推入的子页，登出后一并回根路由，避免停在已被登录门
  /// 替换掉的页面上。
  Future<void> _signOut() async {
    final authRepository = widget.authRepository;
    if (authRepository == null || _signingOut) return;
    setState(() {
      _signingOut = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    try {
      await widget.notificationService?.releaseUser(
        authRepository.currentUserId,
      );
      await authRepository.signOut();
      if (!mounted) return;
      navigator.popUntil((route) => route.isFirst);
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error = formatUserError(error, fallback: '退出登录未完成，请稍后重试。'),
        );
      }
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  Future<void> _retry() async {
    setState(() => _busy = true);
    try {
      final synced = await widget.repository.syncProfile();
      if (!mounted) return;
      final syncError = synced.syncError;
      // 重试成功也可能遇到并发时区覆盖：账号存储按修订号保留了最新接受值，
      // 这里与 _save() 用同一套说法，不静默停留在旧选择上。
      final timeZoneReplaced =
          syncError == null &&
          _timeZoneId != null &&
          synced.displayTimeZoneId != _timeZoneId;
      final effectiveZoneId = AccountTimeZones.effectiveId(
        synced.displayTimeZoneId,
      );
      setState(() {
        _storedAvatar = synced.avatar?.bytes;
        if (timeZoneReplaced) {
          _timeZoneId = synced.displayTimeZoneId;
          _loadedTimeZoneId = synced.displayTimeZoneId;
          _error =
              '账号时区已被其他设备更新，已采用最新值：$effectiveZoneId。'
              '如仍想使用刚才的选择，请重新选择后再保存。';
        } else {
          _error = syncError == null
              ? null
              : formatUserError(syncError, fallback: '保存未完成，请稍后重试。');
        }
        _syncFailed = syncError != null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PactaSurfaces.wrapIfMissing(
      context,
      Scaffold(
        appBar: AppBar(title: const Text('编辑资料')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _avatarSection(context),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _nameController,
                    onChanged: (_) => _nameEdited = true,
                    enabled: !_busy,
                    maxLength: maxDisplayNameLength,
                    decoration: const InputDecoration(
                      labelText: '昵称',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _timeZoneSection(context),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    if (_syncFailed)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _busy ? null : _retry,
                          icon: const Icon(Icons.refresh),
                          label: const Text('重试同步'),
                        ),
                      ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: _busy || _picking ? null : _save,
                      child: Text(_busy ? '正在保存…' : '保存'),
                    ),
                  ),
                  if (_busy) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                  ],
                  if (widget.authRepository != null) ...[
                    const SizedBox(height: PactaSpacing.xl),
                    const PactaSectionHeader(title: '账号安全'),
                    PactaGroupedList(
                      children: [
                        PactaSettingsTile(
                          tileKey: const ValueKey(
                            'profile-change-password-entry',
                          ),
                          leadingIcon: Icons.lock_outline,
                          title: '修改密码',
                          subtitle: '验证当前密码后更新登录密码',
                          onTap: _busy || _picking ? null : _openChangePassword,
                        ),
                        // 退出登录跟着账号安全走：浏览型的《我的》不再常驻一颗
                        // 危险按钮，这里与修改密码成对出现。
                        PactaSettingsTile(
                          tileKey: const ValueKey('profile-sign-out-entry'),
                          leadingIcon: Icons.logout,
                          title: '退出登录',
                          subtitle: '取消本机提醒并清空本机的登录状态',
                          showChevron: false,
                          enabled: !_busy && !_picking && !_signingOut,
                          onTap: _signOut,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 头像区：上方一个大圆，下方一颗按钮。两者都只做一件事——换头像。
  Widget _avatarSection(BuildContext context) {
    final avatar = _visibleAvatar;
    final label = avatar == null ? '选择头像' : '更换头像';
    final busy = _busy || _picking;
    return Column(
      children: [
        Tooltip(
          message: label,
          child: InkWell(
            key: const Key('profile-avatar'),
            onTap: busy ? null : _handleAvatarTap,
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(PactaSpacing.xs),
              child: CircleAvatar(
                radius: 44,
                backgroundImage: avatar == null ? null : MemoryImage(avatar),
                child: avatar == null
                    ? const Icon(Icons.person_outline, size: PactaIconSizes.lg)
                    : null,
              ),
            ),
          ),
        ),
        const SizedBox(height: PactaSpacing.xs),
        OutlinedButton(
          onPressed: busy ? null : _handleAvatarTap,
          child: Text(_picking ? '正在读取图片…' : label),
        ),
      ],
    );
  }

  /// 账号级时区：各设备共享同一值；这里只放可编辑的常见城市，完整的 IANA
  /// 校验仍由 FocusTimeZones 承担（导入事件的原始时区不因此收窄）。
  ///
  /// 摘要严格单行，规则（结算点跟着账号时区走）折进行内 ⓘ；选择器下方另有
  /// 一行账号结算点与本机墙钟的实时对照。
  Widget _timeZoneSection(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _timeZoneId;
    final currentCity = AccountTimeZones.cityFor(selected);
    final offList = AccountTimeZones.isKnown(selected) && currentCity == null;
    final cityLabel = currentCity?.label;
    final cityZoneId = currentCity?.timeZoneId;
    final summary = currentCity == null
        ? (offList ? selected! : '未设置')
        : '$cityLabel · $cityZoneId';
    final zoneLabel = selected ?? '未设置';
    final explanation = <String>[
      '时区 ID：$zoneLabel',
      '时区属于账号资料：各设备显示同一时区，城市按夏令时规则换算。',
      '国策检查点按账号时区的 04:00 结算，时区改变后结算时刻随之移动。',
    ].join('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PactaSectionHeader(
          title: '显示时区',
          // 外层不再包 Flexible：PactaSectionHeader 给 trailing 的是「最多 72%
          // 宽」而不是「与标题五五分」，摘要因此能完整渲染并贴齐右缘。
          trailing: Tooltip(
            triggerMode: TooltipTriggerMode.tap,
            message: explanation,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                const SizedBox(width: PactaSpacing.xs),
                Icon(
                  Icons.info_outline,
                  size: PactaIconSizes.sm,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        PactaGroupedList(
          children: [
            _checkpointComparison(context),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                PactaSpacing.lg,
                PactaSpacing.md,
                PactaSpacing.lg,
                PactaSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (index, group) in _timeZoneGroups(
                    offList ? selected : null,
                  ).indexed) ...[
                    if (index > 0) const SizedBox(height: PactaSpacing.sm),
                    Text(
                      group.label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: PactaFonts.medium,
                      ),
                    ),
                    const SizedBox(height: PactaSpacing.xs),
                    Wrap(
                      spacing: PactaSpacing.sm,
                      runSpacing: PactaSpacing.sm,
                      children: [
                        for (final city in group.cities)
                          _timeZoneChip(
                            context,
                            city,
                            selected == city.timeZoneId,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 把 17 个留学城市拆成 4 个大区组，避免所有芯片挤成一团。
  List<({String label, List<DisplayTimeZoneCity> cities})> _timeZoneGroups(
    String? offListTimeZoneId,
  ) {
    const regionDefs = <(String, Set<String>)>[
      (
        '亚太',
        {
          'Asia/Shanghai',
          'Asia/Hong_Kong',
          'Asia/Singapore',
          'Asia/Tokyo',
          'Asia/Seoul',
        },
      ),
      ('澳新', {'Australia/Sydney', 'Australia/Melbourne', 'Pacific/Auckland'}),
      (
        '欧洲与 UTC',
        {'Europe/London', 'Europe/Paris', 'Europe/Berlin', 'Etc/UTC'},
      ),
      (
        '北美',
        {
          'America/Toronto',
          'America/Vancouver',
          'America/New_York',
          'America/Chicago',
          'America/Los_Angeles',
        },
      ),
    ];
    final byId = <String, DisplayTimeZoneCity>{
      for (final city in AccountTimeZones.cities) city.timeZoneId: city,
    };
    final matched = <String>{};
    final groups = <({String label, List<DisplayTimeZoneCity> cities})>[];
    for (final (label, ids) in regionDefs) {
      final list = <DisplayTimeZoneCity>[
        for (final city in AccountTimeZones.cities)
          if (ids.contains(city.timeZoneId)) city,
      ];
      if (list.isNotEmpty) {
        groups.add((label: label, cities: list));
        matched.addAll(ids);
      }
    }
    final remaining = <DisplayTimeZoneCity>[
      for (final id in byId.keys)
        if (!matched.contains(id)) byId[id]!,
      if (offListTimeZoneId != null)
        DisplayTimeZoneCity(label: '当前时区', timeZoneId: offListTimeZoneId),
    ];
    if (remaining.isNotEmpty) {
      groups.add((label: '其他时区', cities: remaining));
    }
    return groups;
  }

  /// 账号结算点与本机墙钟的对照。
  ///
  /// 芯片选中即预览：`_timeZoneId` 是「当前选择」而不是「已保存值」，所以点
  /// 一颗尚未保存的城市也会立刻换算。偏移一致时对照行只说账号当地的 04:00，
  /// 不一致时才补上它落在本机几点——否则用户会以为结算漏了一天。
  Widget _checkpointComparison(BuildContext context) {
    final theme = Theme.of(context);
    final comparison = AccountTimeZones.formatCheckpointComparison(
      accountTimeZoneId: _timeZoneId,
      referenceUtc: DateTime.now().toUtc(),
    );
    return Padding(
      key: const ValueKey('profile-timezone-checkpoint-comparison'),
      padding: const EdgeInsets.symmetric(
        horizontal: PactaSpacing.lg,
        vertical: PactaSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.schedule,
            size: PactaIconSizes.sm,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: PactaSpacing.sm),
          Expanded(
            child: Text(
              comparison,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timeZoneChip(
    BuildContext context,
    DisplayTimeZoneCity city,
    bool selected,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return ChoiceChip(
      label: Text(city.label),
      tooltip: city.timeZoneId,
      selected: selected,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: const StadiumBorder(),
      selectedColor: colors.primaryContainer,
      backgroundColor: colors.surfaceContainerLow,
      side: BorderSide(
        color: selected ? colors.primary : colors.outlineVariant,
      ),
      labelStyle: theme.textTheme.labelLarge?.copyWith(
        color: selected ? colors.onPrimaryContainer : colors.onSurface,
        fontWeight: selected ? PactaFonts.medium : PactaFonts.regular,
      ),
      onSelected: _busy
          ? null
          : (_) => setState(() => _timeZoneId = city.timeZoneId),
    );
  }
}
