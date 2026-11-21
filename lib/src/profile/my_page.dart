import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app_providers.dart';
import '../auth/admin_password_reset_card.dart';
import '../auth/admin_user_lifecycle_card.dart';
import '../auth/auth_repository.dart';
import '../calendar/calendar_page.dart';
import '../national_focus/national_focus_ai_access.dart';
import '../national_focus/national_focus_ai_analysis_page.dart';
import '../notifications/focus_notification_settings_page.dart';
import '../sync/cloud_sync_card.dart';
import '../theme/pacta_spacing.dart';
import '../ui/pacta_error_text.dart';
import '../ui/pacta_grouped_list.dart';
import '../ui/pacta_page_header.dart';
import 'profile_card.dart';

class MyPage extends ConsumerStatefulWidget {
  const MyPage({super.key});

  @override
  ConsumerState<MyPage> createState() => _MyPageState();
}

class _MyPageState extends ConsumerState<MyPage> {
  late Future<bool> _isAdministrator;

  @override
  void initState() {
    super.initState();
    _isAdministrator = ref.read(authRepositoryProvider).isAdministrator();
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(authRepositoryProvider);
    final calendarRepository = ref.watch(calendarRepositoryProvider);
    final scheduleRepository = ref.watch(scheduleRepositoryProvider);
    return ListView(
      padding: PactaSpacing.pageInsets(context),
      children: [
        const PactaPageHeader(title: '我的'),
        MyProfileCard(
          repository: ref.watch(profileRepositoryProvider),
          overview: ref.watch(profileOverviewSourceProvider),
          avatarPicker: ref.watch(avatarPickerProvider),
          accountIdentifier: repository.currentUserIdentifier,
        ),
        const SizedBox(height: PactaSpacing.md),
        CloudSyncCard(
          repository: ref.watch(cloudSnapshotRepositoryProvider),
          versionCheck: ref.watch(cloudVersionCheckProvider),
          autoUpload: ref.watch(cloudAutoUploadCoordinatorProvider),
          focusRepository: ref.watch(focusRepositoryProvider),
          onDownloaded: () async {
            ref.invalidate(taskRepositoryProvider);
            ref.invalidate(focusRepositoryProvider);
            ref.invalidate(nationalFocusRepositoryProvider);
            ref.invalidate(calendarRepositoryProvider);
            await ref
                .read(nationalFocusRepositoryProvider)
                .settleDueCheckpoints();
          },
        ),
        const SizedBox(height: PactaSpacing.md),
        NationalFocusAiAnalysisEntry(
          onOpenSync: () => openAiManualSync(context, ref),
          mcpUrl: ref.watch(nationalFocusMcpUrlProvider),
          repository: ref.watch(nationalFocusAiGrantRepositoryProvider),
        ),
        const SizedBox(height: PactaSpacing.md),
        // 功能入口合成一块 Google 服务式分组列表：通知/权限与管理员入口共用
        // 同一套 20dp 圆角、1dp 细分隔线与整行点击，不再各占一张独立卡片。
        FutureBuilder<bool>(
          future: _isAdministrator,
          builder: (context, snapshot) {
            final isAdministrator = snapshot.data == true;
            return PactaGroupedList(
              children: [
                PactaSettingsTile(
                  leadingIcon: Icons.tune_outlined,
                  title: '通知与设备权限',
                  subtitle: Platform.isAndroid
                      ? '后台运行、通知提醒与系统日历只读导入'
                      : '通知提醒与系统日历只读导入',
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => FocusNotificationSettingsPage(
                        service: ref.read(focusNotificationServiceProvider),
                        calendarSourcesBuilder: (_) => CalendarSourcesPage(
                          repository: calendarRepository,
                          isAndroid: Platform.isAndroid,
                          scheduleRepository: scheduleRepository,
                          displayTimeZoneIdLoader: () =>
                              resolveAccountDisplayTimeZoneId(
                                ref.read(profileRepositoryProvider),
                              ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (isAdministrator)
                  PactaSettingsTile(
                    tileKey: const ValueKey('admin-users-entry'),
                    leadingIcon: Icons.admin_panel_settings_outlined,
                    title: '用户管理',
                    subtitle: '注册资格、用户状态与密码重置',
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const AdminUsersPage(),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: PactaSpacing.xl),
        OutlinedButton.icon(
          onPressed: () async {
            final userId = ref.read(authRepositoryProvider).currentUserId;
            // 明确登出才取消已登记的提醒；正常关应用保留未来项。
            await ref
                .read(focusNotificationServiceProvider)
                .releaseUser(userId);
            await ref.read(authRepositoryProvider).signOut();
          },
          icon: const Icon(Icons.logout),
          label: const Text('退出登录'),
        ),
        const SizedBox(height: PactaSpacing.xl),
      ],
    );
  }
}

class AdminUsersPage extends ConsumerStatefulWidget {
  const AdminUsersPage({super.key});

  @override
  ConsumerState<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends ConsumerState<AdminUsersPage> {
  AuthRepository? _checkedRepository;
  late Future<bool> _isAdministrator;

  @override
  void initState() {
    super.initState();
    _checkAdministrator(ref.read(authRepositoryProvider));
  }

  void _checkAdministrator(AuthRepository repository) {
    _checkedRepository = repository;
    _isAdministrator = repository.isAdministrator();
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(authRepositoryProvider);
    if (!identical(_checkedRepository, repository)) {
      _checkAdministrator(repository);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('用户管理')),
      body: FutureBuilder<bool>(
        future: _isAdministrator,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done &&
              !snapshot.hasError) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('暂时无法确认管理员身份。'),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => _checkAdministrator(repository)),
                      icon: const Icon(Icons.refresh),
                      label: const Text('重试'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (snapshot.data != true) {
            return const Center(child: Text('仅管理员可访问用户管理。'));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              Text(
                '注册资格、用户状态与密码重置',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 12),
              AdminUserLifecycleCard(repository: repository),
              const SizedBox(height: 12),
              const AdminEligibilityCard(),
              const SizedBox(height: 12),
              AdminPasswordResetCard(repository: repository),
            ],
          );
        },
      ),
    );
  }
}

class AdminEligibilityCard extends ConsumerStatefulWidget {
  const AdminEligibilityCard({super.key});

  @override
  ConsumerState<AdminEligibilityCard> createState() =>
      _AdminEligibilityCardState();
}

class _AdminEligibilityCardState extends ConsumerState<AdminEligibilityCard> {
  final _email = TextEditingController();
  String? _message;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _grant() async {
    await _run(
      () => ref
          .read(authRepositoryProvider)
          .grantEligibility(email: _email.text.trim()),
      '资格已发放',
    );
  }

  Future<void> _revoke() async {
    await _run(() async {
      final changed = await ref
          .read(authRepositoryProvider)
          .revokeEligibility(email: _email.text.trim());
      if (!changed) throw StateError('资格不存在、已使用或已被撤销。');
    }, '资格已撤销');
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _message = '请输入有效的邮箱地址。');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
      if (mounted) {
        setState(() => _message = success);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = formatUserError(error));
      }
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
          Text('管理员：注册资格', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text('资格不发送消息，也不验证标识所有权。'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _email,
                  decoration: const InputDecoration(labelText: '邮箱'),
                ),
              ),
            ],
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_message!),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : _grant,
                  child: const Text('发放资格'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _revoke,
                  child: const Text('撤销未用资格'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

void openAiManualSync(BuildContext context, WidgetRef ref) {
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('手动同步')),
        body: SafeArea(
          child: ListView(
            padding: PactaSpacing.pageInsets(context),
            children: [
              const Text('选择上传本机，并在现有预览中核对整份覆盖范围。仅进入本页不会上传或下载。'),
              const SizedBox(height: 12),
              CloudSyncCard(
                repository: ref.read(cloudSnapshotRepositoryProvider),
                versionCheck: ref.read(cloudVersionCheckProvider),
                autoUpload: ref.read(cloudAutoUploadCoordinatorProvider),
                onDownloaded: () async {
                  ref.invalidate(taskRepositoryProvider);
                  ref.invalidate(focusRepositoryProvider);
                  ref.invalidate(nationalFocusRepositoryProvider);
                  ref.invalidate(calendarRepositoryProvider);
                  await ref
                      .read(nationalFocusRepositoryProvider)
                      .settleDueCheckpoints();
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
