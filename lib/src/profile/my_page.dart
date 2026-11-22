import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app_providers.dart';
import '../calendar/calendar_page.dart';
import '../national_focus/national_focus_ai_access.dart';
import '../national_focus/national_focus_ai_analysis_page.dart';
import '../notifications/focus_notification_settings_page.dart';
import '../sync/cloud_sync_card.dart';
import '../theme/pacta_spacing.dart';
import '../ui/pacta_grouped_list.dart';
import '../ui/pacta_page_header.dart';
import 'profile_card.dart';

/// 「我的」只留普通账号能做的事：名片、云同步、国策 AI、通知与设备权限、
/// 退出登录。管理入口已随管理员动作一起下线，页面因此没有异步身份判定，
/// 也不再是 StatefulWidget。
class MyPage extends ConsumerWidget {
  const MyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          authRepository: repository,
          lifecycleRepository: ref.watch(userLifecycleStatusRepositoryProvider),
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
        // 功能入口合成一块 Google 服务式分组列表：M3 Expressive 分段卡片，
        // 段间不画分隔线、只留透明缝隙，外角与内角统一收敛到 20dp / 4dp，
        // 每段仍是整行点击，不再各占一张独立卡片。
        PactaGroupedList(
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
          ],
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

void openAiManualSync(BuildContext context, WidgetRef ref) {
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('手动同步')),
        body: SafeArea(
          // 推入式二级页统一居中并限制正文宽度：手动同步在桌面宽屏下不再
          // 横向撑满整块画布。
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
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
      ),
    ),
  );
}
