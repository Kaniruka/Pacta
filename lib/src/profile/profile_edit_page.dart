import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/pacta_spacing.dart';
import '../ui/pacta_error_text.dart';
import '../ui/pacta_grouped_list.dart';
import '../ui/pacta_hold_action_reorder.dart';
import 'account_time_zone.dart';
import 'avatar_image.dart';
import 'avatar_crop_page.dart';
import 'avatar_picker.dart';
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
  });

  final ProfileRepository repository;
  final AvatarPicker avatarPicker;

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
    return Scaffold(
      appBar: AppBar(title: const Text('编辑资料')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
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
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: Theme.of(context).colorScheme.error),
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
            ],
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
                    ? const Icon(Icons.person_outline, size: 32)
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
  /// 摘要严格单行，规则（含国策检查点固定北京时间 04:00）折进行内 ⓘ。
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
      '国策检查点始终按北京时间 04:00 结算，不随时区移动。',
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
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        Wrap(
          spacing: PactaSpacing.sm,
          runSpacing: PactaSpacing.sm,
          children: [
            for (final city in AccountTimeZones.cities)
              _timeZoneChip(context, city, selected == city.timeZoneId),
            if (offList)
              _timeZoneChip(
                context,
                DisplayTimeZoneCity(label: '当前时区', timeZoneId: selected!),
                true,
              ),
          ],
        ),
      ],
    );
  }

  Widget _timeZoneChip(
    BuildContext context,
    DisplayTimeZoneCity city,
    bool selected,
  ) => ChoiceChip(
    label: Text(city.label),
    tooltip: city.timeZoneId,
    selected: selected,
    onSelected: _busy
        ? null
        : (_) => setState(() => _timeZoneId = city.timeZoneId),
  );
}
