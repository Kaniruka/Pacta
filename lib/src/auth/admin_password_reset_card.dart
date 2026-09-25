import 'package:flutter/material.dart';

import 'auth_repository.dart';

class AdminPasswordResetCard extends StatefulWidget {
  const AdminPasswordResetCard({super.key, required this.repository});

  final AuthRepository repository;

  @override
  State<AdminPasswordResetCard> createState() => _AdminPasswordResetCardState();
}

class _AdminPasswordResetCardState extends State<AdminPasswordResetCard> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _manualVerificationConfirmed = false;
  bool _passwordVisible = false;
  bool _busy = false;
  String? _message;
  bool _hasError = false;

  bool get _isValidEmail {
    final email = _email.text.trim();
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
  }

  bool get _canSubmit =>
      !_busy &&
      _isValidEmail &&
      _password.text.length >= 8 &&
      _manualVerificationConfirmed;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  void _updateInput() {
    setState(() {
      final passwordsMismatch =
          _password.text.isNotEmpty &&
          _confirmation.text.isNotEmpty &&
          _password.text != _confirmation.text;
      _message = passwordsMismatch ? '两次输入的密码不一致。' : null;
      _hasError = passwordsMismatch;
    });
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (!_isValidEmail) {
      setState(() {
        _message = '请输入有效的目标用户邮箱。';
        _hasError = true;
      });
      return;
    }
    if (password.length < 8) {
      setState(() {
        _message = '新密码至少需要 8 个字符。';
        _hasError = true;
      });
      return;
    }
    if (password != _confirmation.text) {
      setState(() {
        _message = '两次输入的密码不一致。';
        _hasError = true;
      });
      return;
    }
    if (!_manualVerificationConfirmed) return;

    setState(() {
      _busy = true;
      _message = null;
      _hasError = false;
    });
    try {
      await widget.repository.adminResetUserPassword(
        targetEmail: email,
        newPassword: password,
        manualVerificationConfirmed: true,
      );
      if (!mounted) return;
      setState(() {
        _message = '密码已重置。请通过安全的外部渠道将新密码告知该用户。';
        _manualVerificationConfirmed = false;
        _passwordVisible = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = error.toString().replaceFirst('Bad state: ', '');
        _hasError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('管理员：重置用户密码', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text('请先在线下人工核实用户身份。应用不会验证邮箱所有权，也不会发送邮件或短信。'),
          const SizedBox(height: 12),
          TextField(
            key: const Key('reset-target-email'),
            controller: _email,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(labelText: '目标用户邮箱'),
            onChanged: (_) => _updateInput(),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('reset-new-password'),
            controller: _password,
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: '新密码（至少 8 个字符）',
              suffixIcon: IconButton(
                tooltip: _passwordVisible ? '隐藏新密码' : '显示新密码',
                onPressed: _busy
                    ? null
                    : () =>
                          setState(() => _passwordVisible = !_passwordVisible),
                icon: Icon(
                  _passwordVisible ? Icons.visibility_off : Icons.visibility,
                ),
              ),
            ),
            obscureText: !_passwordVisible,
            onChanged: (_) => _updateInput(),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('reset-confirm-password'),
            controller: _confirmation,
            enabled: !_busy,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: '再次输入新密码'),
            onChanged: (_) => _updateInput(),
          ),
          CheckboxListTile(
            key: const Key('manual-verification-confirmation'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _manualVerificationConfirmed,
            onChanged: _busy
                ? null
                : (value) => setState(() {
                    _manualVerificationConfirmed = value ?? false;
                    _message = null;
                    _hasError = false;
                  }),
            title: const Text('我已完成人工核实，并会通过安全的外部渠道告知新密码'),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _message!,
                style: _hasError
                    ? TextStyle(color: Theme.of(context).colorScheme.error)
                    : null,
              ),
            ),
          FilledButton(
            onPressed: _canSubmit ? _submit : null,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('重置密码'),
          ),
        ],
      ),
    ),
  );
}
