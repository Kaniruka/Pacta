import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'avatar_image.dart';
import 'avatar_crop_page.dart';
import 'avatar_picker.dart';
import 'profile_repository.dart';

/// Edits the account display name and selects one avatar through the system.
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
    });
  }

  Uint8List? get _visibleAvatar =>
      _clearAvatar ? null : (_pickedAvatar ?? _storedAvatar);

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
      if (mounted) setState(() => _error = '这张图片无法读取：$error');
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
      );
      if (!mounted) return;
      setState(() {
        _storedAvatar = saved.avatar?.bytes;
        _pickedAvatar = null;
        _error = saved.syncError;
        _syncFailed = saved.syncError != null;
      });
      if (saved.syncError == null) Navigator.of(context).pop();
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
          _error = '保存失败：${error is StateError ? error.message : error}';
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
      setState(() {
        _storedAvatar = synced.avatar?.bytes;
        _error = synced.syncError;
        _syncFailed = synced.syncError != null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatar = _visibleAvatar;
    return Scaffold(
      appBar: AppBar(title: const Text('编辑资料')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              Center(
                child: CircleAvatar(
                  radius: 44,
                  backgroundImage: avatar == null ? null : MemoryImage(avatar),
                  child: avatar == null
                      ? const Icon(Icons.person_outline, size: 32)
                      : null,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  OutlinedButton.icon(
                    onPressed: _picking || _busy ? null : _pickAvatar,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(_picking ? '正在读取图片…' : '选择图片'),
                  ),
                  if (_visibleAvatar != null)
                    TextButton(
                      onPressed: _busy || _picking ? null : _recropAvatar,
                      child: const Text('重新裁剪'),
                    ),
                  if (_visibleAvatar != null)
                    TextButton(
                      onPressed: _busy || _picking
                          ? null
                          : () => setState(() {
                              _pickedAvatar = null;
                              _cropSource = null;
                              _clearAvatar = true;
                            }),
                      child: const Text('移除头像'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '只会读取你在系统选择器中选中的这一张图片，不需要相册权限。'
                '头像会压缩到 256 KB 以内。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _nameController,
                onChanged: (_) => _nameEdited = true,
                enabled: !_busy,
                maxLength: maxDisplayNameLength,
                decoration: const InputDecoration(
                  labelText: '昵称',
                  helperText: '昵称和头像属于账号资料，业务备份恢复不会改变它们。',
                  border: OutlineInputBorder(),
                ),
              ),
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
              FilledButton(
                onPressed: _busy || _picking ? null : _save,
                child: Text(_busy ? '正在保存…' : '保存'),
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
}
