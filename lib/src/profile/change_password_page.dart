import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_repository.dart';
import '../auth/user_lifecycle.dart';
import '../auth/user_lifecycle_models.dart';
import '../theme/pacta_icon_sizes.dart';
import '../theme/pacta_spacing.dart';
import '../ui/pacta_error_text.dart';

/// 账号自助修改密码。
///
/// 三个输入框只服务于一次提交：当前密码用来向服务端复核身份，新密码与
/// 确认项在本页做长度与一致性校验。页面从不回显任何密码文本，失败原因
/// 只用中文提示落在按钮上方。
class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({
    super.key,
    required this.authRepository,
    this.lifecycleRepository,
  });

  final AuthRepository authRepository;

  /// 可选的账号状态仓储：提交前先刷新云端状态，刷新失败才退到本机缓存；
  /// 停用或状态不可核验都会在密码修改请求之前停下。
  final UserLifecycleStatusRepository? lifecycleRepository;

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final TextEditingController _current = TextEditingController();
  final TextEditingController _next = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNext = true;
  bool _obscureConfirm = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final current = _current.text;
    final next = _next.text;
    final confirm = _confirm.text;
    final invalid = _validate(current: current, next: next, confirm: confirm);
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _ensureNotSuspended(widget.lifecycleRepository);
      await widget.authRepository.changePassword(
        currentPassword: current,
        newPassword: next,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('密码已更新。')));
      Navigator.of(context).pop();
    } on FormatException catch (error) {
      // 用 message 而不是 toString()：后者会带上 'FormatException: ' 前缀。
      if (mounted) {
        setState(
          () => _error = error.message.isEmpty ? '密码格式不符合要求。' : error.message,
        );
      }
    } on UserOperationsSuspendedException catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } on AuthException catch (error) {
      if (mounted) {
        setState(
          () => _error = formatUserError(
            error.message,
            fallback: '密码修改未完成，请稍后重试。',
          ),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error = formatUserError(error, fallback: '密码修改未完成，请稍后重试。'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 停用核验按「刷新优先、失败闭环」执行。
  ///
  /// 管理员在云端恢复账号后，本机缓存可能还留着旧的停用标记：先信刷新
  /// 结果，才不会把已经恢复的用户误拦在改密之前。刷新失败时退回缓存判断，
  /// 没有缓存就按「不可核验」拦下 —— 改密本身依赖联网，放行状态未知的
  /// 账号等于给已停用账号留一条绕过拦截的路。
  Future<void> _ensureNotSuspended(
    UserLifecycleStatusRepository? lifecycle,
  ) async {
    if (lifecycle == null ||
        lifecycle is UnavailableUserLifecycleStatusRepository) {
      return;
    }
    try {
      final refreshed = await lifecycle.refresh();
      if (refreshed.isSuspended) {
        throw const UserOperationsSuspendedException();
      }
    } on UserOperationsSuspendedException {
      rethrow;
    } catch (_) {
      final cached = await _readCachedStatus(lifecycle);
      if (cached?.isSuspended == true) {
        throw const UserOperationsSuspendedException();
      }
      throw const FormatException('暂时无法核验账号状态，请联网后重试。');
    }
  }

  /// 缓存读取本身失败等同没有缓存：状态不明时同样按不可核验处理。
  Future<UserLifecycleStatus?> _readCachedStatus(
    UserLifecycleStatusRepository lifecycle,
  ) async {
    try {
      return await lifecycle.readCachedStatus();
    } catch (_) {
      return null;
    }
  }

  /// 本地校验与仓储校验保持同一套文案：界面先拦下明显输入，服务端仍会
  /// 再判一次，两层说法一致才不会让用户以为自己点错了。
  String? _validate({
    required String current,
    required String next,
    required String confirm,
  }) {
    if (current.isEmpty) return '请输入当前密码。';
    if (next.length < 8) return '新密码至少需要 8 个字符。';
    if (next.length > 256) return '新密码长度不能超过 256 个字符。';
    if (next == current) return '新密码不能与当前密码相同。';
    if (confirm != next) return '两次输入的新密码不一致。';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('修改密码')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: PactaSpacing.pageInsets(context),
            children: [
              Text(
                '为保护账号安全，请先验证当前密码。新密码至少 8 位。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: PactaSpacing.lg),
              _passwordField(
                fieldKey: const ValueKey('change-password-current'),
                controller: _current,
                label: '当前密码',
                obscure: _obscureCurrent,
                autofillHints: const [AutofillHints.password],
                onToggle: () =>
                    setState(() => _obscureCurrent = !_obscureCurrent),
              ),
              const SizedBox(height: PactaSpacing.md),
              _passwordField(
                fieldKey: const ValueKey('change-password-new'),
                controller: _next,
                label: '新密码',
                obscure: _obscureNext,
                autofillHints: const [AutofillHints.newPassword],
                onToggle: () => setState(() => _obscureNext = !_obscureNext),
              ),
              const SizedBox(height: PactaSpacing.md),
              _passwordField(
                fieldKey: const ValueKey('change-password-confirm'),
                controller: _confirm,
                label: '确认新密码',
                obscure: _obscureConfirm,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                onToggle: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
              ),
              if (_error != null) ...[
                const SizedBox(height: PactaSpacing.sm),
                Text(
                  _error!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: PactaSpacing.lg),
              SizedBox(
                height: 48,
                child: FilledButton(
                  key: const ValueKey('change-password-submit'),
                  onPressed: _busy ? null : _submit,
                  child: Text(_busy ? '正在修改…' : '确认修改'),
                ),
              ),
              if (_busy) ...[
                const SizedBox(height: PactaSpacing.md),
                const LinearProgressIndicator(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 密码框统一形状：密文输入、行尾显隐切换；输入值只进控制器，从不进
  /// 文本树，因此页面里任何地方都读不到密码本身。
  Widget _passwordField({
    required Key fieldKey,
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required List<String> autofillHints,
    required VoidCallback onToggle,
    TextInputAction textInputAction = TextInputAction.next,
    ValueChanged<String>? onSubmitted,
  }) => TextField(
    key: fieldKey,
    controller: controller,
    enabled: !_busy,
    obscureText: obscure,
    autofillHints: autofillHints,
    textInputAction: textInputAction,
    onSubmitted: onSubmitted,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      suffixIcon: IconButton(
        tooltip: obscure ? '显示密码' : '隐藏密码',
        onPressed: _busy ? null : onToggle,
        icon: Icon(
          obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          size: PactaIconSizes.compact,
        ),
      ),
    ),
  );
}
