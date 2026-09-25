import 'package:flutter/material.dart';

import 'auth_repository.dart';
import 'user_lifecycle_models.dart';

class AdminUserLifecycleCard extends StatefulWidget {
  const AdminUserLifecycleCard({super.key, required this.repository});

  final AuthRepository repository;

  @override
  State<AdminUserLifecycleCard> createState() => _AdminUserLifecycleCardState();
}

class _AdminUserLifecycleCardState extends State<AdminUserLifecycleCard> {
  List<ManagedUserLifecycle> _users = const [];
  bool _loading = true;
  String? _message;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final users = await widget.repository.listUserLifecycles();
      if (!mounted) return;
      setState(() {
        _users = users;
        _loading = false;
        _message = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = _friendlyError(error);
      });
    }
  }

  Future<void> _setSuspended(ManagedUserLifecycle user, bool suspended) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (suspended) {
        await widget.repository.suspendUser(user.userId);
      } else {
        await widget.repository.restoreUser(user.userId);
      }
      await _load();
    } catch (error) {
      if (mounted) setState(() => _message = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendlyError(Object error) =>
      error.toString().replaceFirst('Bad state: ', '');

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('管理员：用户停用与恢复', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text('停用后服务端拒绝业务写入。满 30 天仅标记可清除；本界面不会清除数据。'),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_users.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('当前没有可管理的用户。'),
            )
          else
            for (final user in _users) _userTile(user),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _message!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _busy || _loading ? null : _load,
              icon: const Icon(Icons.refresh),
              label: const Text('刷新用户列表'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _userTile(ManagedUserLifecycle user) {
    final status = user.isSuspended
        ? user.isEligibleForPurge
              ? '已停用 · 已达到可清除时间（尚未清除）'
              : '已停用 · ${_formatDate(user.purgeEligibleAt)} 后可清除'
        : '正常用户';
    final subtitle = <String>[
      status,
      if (user.isSuspended && user.suspendedAt != null)
        '本次停用：${_formatDate(user.suspendedAt)}',
      if (!user.isSuspended && user.restoredAt != null)
        '最近恢复：${_formatDate(user.restoredAt)}',
    ].join('\n');

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(user.email ?? user.userId),
      subtitle: Text(subtitle),
      isThreeLine: subtitle.contains('\n'),
      trailing: user.isSuspended
          ? OutlinedButton(
              onPressed: _busy ? null : () => _setSuspended(user, false),
              child: const Text('恢复'),
            )
          : FilledButton.tonal(
              onPressed: _busy ? null : () => _setSuspended(user, true),
              child: const Text('停用'),
            ),
    );
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '待计算';
    final local = value.toLocal();
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} ${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }
}
