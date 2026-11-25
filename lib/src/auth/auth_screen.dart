import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app/app_providers.dart';
import '../app/app_shell.dart';
import '../theme/pacta_icon_sizes.dart';
import '../theme/pacta_spacing.dart';
import '../ui/pacta_error_text.dart';
import 'user_lifecycle.dart';

class UserPurgeCleanupLifecycleObserver extends StatefulWidget {
  const UserPurgeCleanupLifecycleObserver({
    super.key,
    required this.cleanupRepository,
    required this.child,
  });

  final UserPurgeCleanupRepository? cleanupRepository;
  final Widget child;

  @override
  State<UserPurgeCleanupLifecycleObserver> createState() =>
      UserPurgeCleanupLifecycleObserverState();
}

class UserPurgeCleanupLifecycleObserverState
    extends State<UserPurgeCleanupLifecycleObserver>
    with WidgetsBindingObserver {
  late final StreamSubscription<List<ConnectivityResult>>
  _connectivitySubscription;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      _,
    ) {
      unawaited(_runCleanup());
    });
    unawaited(_runCleanup());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_runCleanup());
  }

  Future<void> _runCleanup() async {
    final repository = widget.cleanupRepository;
    if (repository == null || _running) return;
    _running = true;
    try {
      await repository.purgeLocallyConfirmedUsers();
    } catch (_) {
      // Offline or invalid receipt responses keep local rows for a later retry.
    } finally {
      _running = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(authRepositoryProvider);
    return StreamBuilder<String?>(
      stream: repository.authState,
      initialData: repository.currentUserIdentifier,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            snapshot.data == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return snapshot.data == null
            ? const AuthScreen()
            : AppShell(key: ValueKey(repository.currentUserId));
      },
    );
  }
}

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscurePassword = true;
  bool _busy = false;

  /// 正在提交的那颗按钮：true = 受邀注册，false = 登录，null = 空闲。
  ///
  /// 两颗按钮共用同一份请求状态，但只有被点的那颗展示转圈指示器；另一颗
  /// 同步禁用，避免同一份邮箱/密码在请求未结束时再发一次。
  bool? _submittingRegister;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool registering}) async {
    if (_busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final email = _email.text.trim();
    final password = _password.text;
    if (!email.contains('@') || password.length < 8) {
      setState(() => _error = '请输入有效邮箱，以及至少 8 位密码。');
      return;
    }
    setState(() {
      _busy = true;
      _submittingRegister = registering;
      _error = null;
    });
    try {
      final repository = ref.read(authRepositoryProvider);
      if (registering) {
        await repository.signUp(email: email, password: password);
      } else {
        await repository.signIn(email: email, password: password);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _submittingRegister = null;
        });
      }
    }
  }

  /// 只取 message / code：`AuthException.toString()` 会把 `statusCode` 一起
  /// 打出来。code 与 message 都要过一遍对照表——GoTrue 的邀请制失败常在
  /// code 里写 `signup_not_allowed`，而 message 是不含 `eligib` 的英文句子。
  /// 命中的只有中文文案，`statusCode` / `code` 永远不上屏。
  String _friendlyError(Object error) {
    if (error is AuthException) {
      return describeKnownFailure(error.code ?? '') ??
          describeKnownFailure(error.message) ??
          formatUserError(error.message, fallback: '登录未完成，请稍后重试。');
    }
    return describeKnownFailure(error) ??
        formatUserError(error, fallback: '登录未完成，请稍后重试。');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: PactaSpacing.gutterFor(width),
            vertical: PactaSpacing.xl,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(PactaSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: colors.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.anchor_rounded,
                          size: PactaIconSizes.hero,
                          color: colors.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(height: PactaSpacing.lg),
                    Text(
                      '进入 Pacta',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: PactaSpacing.xl),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: '邮箱',
                        prefixIcon: Icon(Icons.alternate_email_rounded),
                      ),
                    ),
                    const SizedBox(height: PactaSpacing.md),
                    TextField(
                      controller: _password,
                      obscureText: _obscurePassword,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.done,
                      // 回车提交默认走登录：注册是低频的显式动作。
                      onSubmitted: (_) =>
                          unawaited(_submit(registering: false)),
                      decoration: InputDecoration(
                        labelText: '密码',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: PactaSpacing.md),
                      Text(
                        _error!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: PactaSpacing.xl),
                    // 邮箱与密码已经填在上面，底部不再用分段控件重复一遍
                    // 「登录 / 受邀注册」：两颗并排等宽按钮直接承载动作。
                    Row(
                      children: [
                        Expanded(
                          child: Tooltip(
                            message: '使用已开通注册资格的邮箱与密码（至少 8 位）激活账号',
                            child: OutlinedButton(
                              key: const ValueKey('auth-register-button'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 48),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                              ),
                              onPressed: _busy
                                  ? null
                                  : () => _submit(registering: true),
                              child: _busy && _submittingRegister == true
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('受邀注册'),
                            ),
                          ),
                        ),
                        const SizedBox(width: PactaSpacing.md),
                        Expanded(
                          child: FilledButton(
                            key: const ValueKey('auth-login-button'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 48),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                            ),
                            onPressed: _busy
                                ? null
                                : () => _submit(registering: false),
                            child: _busy && _submittingRegister == false
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('登录'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
