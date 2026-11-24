import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app_providers.dart';
import '../calendar/calendar_page.dart';
import '../national_focus/national_focus_ai_access.dart';
import '../national_focus/national_focus_ai_analysis_page.dart';
import '../notifications/focus_notification_settings_page.dart';
import '../schedules/schedule_models.dart';
import '../sync/cloud_sync_card.dart';
import '../theme/pacta_spacing.dart';
import '../ui/pacta_grouped_list.dart';
import '../ui/pacta_page_header.dart';
import 'about_pacta_page.dart';
import 'profile_card.dart';

/// 「我的」只留普通账号能做的事：名片、云同步、国策 AI、通知与设备权限、
/// 关于 Pacta。管理入口已随管理员动作一起下线，页面因此没有异步身份判定，
/// 也不再是 StatefulWidget。
///
/// 退出登录不再占本页底部的一整行：它是账号安全动作，跟着《编辑资料》的
/// 「账号安全」分组成对出现，避免在浏览型页面里放一颗常驻的危险按钮。
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
          // 退出登录已移入《编辑资料》的「账号安全」分组：通知服务随依赖一起
          // 传下去，明确登出时先取消本机的提醒绑定再清登录状态。
          notificationService: ref.watch(focusNotificationServiceProvider),
          // 「重置所有记录」同样住在《编辑资料》底部：仓储、待传队列的取消
          // 入口与重置后的失效回调都从这里注入。
          cloudSnapshotRepository: ref.watch(cloudSnapshotRepositoryProvider),
          onCancelPendingUpload: ref
              .watch(cloudAutoUploadCoordinatorProvider)
              ?.cancelPending,
          onRecordsReset: () => _afterRecordsReset(ref),
        ),
        const SizedBox(height: PactaSpacing.md),
        CloudSyncCard(
          repository: ref.watch(cloudSnapshotRepositoryProvider),
          versionCheck: ref.watch(cloudVersionCheckProvider),
          autoUpload: ref.watch(cloudAutoUploadCoordinatorProvider),
          focusRepository: ref.watch(focusRepositoryProvider),
          accountTimeZoneIdLoader: () async =>
              (await ref.read(profileRepositoryProvider).getProfile())
                  .displayTimeZoneId,
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
          accountTimeZoneIdLoader: () async =>
              (await ref.read(profileRepositoryProvider).getProfile())
                  .displayTimeZoneId,
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
                    // 提醒时间与结算点说明保留账号原始可空时区：未配置时按
                    // 默认国策时区（Asia/Shanghai）展示对照，不写死北京时间。
                    accountTimeZoneIdLoader: () async =>
                        (await ref.read(profileRepositoryProvider).getProfile())
                            .displayTimeZoneId,
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
            PactaSettingsTile(
              tileKey: const ValueKey('my-about-entry'),
              leadingIcon: Icons.info_outline,
              title: '关于 Pacta',
              subtitle: '版本、理论出处与开源许可',
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (_) => const AboutPactaPage()),
              ),
            ),
          ],
        ),
        const SizedBox(height: PactaSpacing.xl),
      ],
    );
  }

  /// 重置记录之后：让受影响的仓储重新读表，并清掉已经不再成立的待发提醒。
  ///
  /// 仓储都是 autoDispose 的读表入口：invalidate 之后列表与统计重新订阅，
  /// 页面上不会残留刚刚被清空的旧行。提醒必须先取消，否则国策提醒会在没有
  /// 任何待确认卡片、日程也已经清空的情况下照常弹出。
  Future<void> _afterRecordsReset(WidgetRef ref) async {
    ref.invalidate(taskRepositoryProvider);
    ref.invalidate(focusRepositoryProvider);
    ref.invalidate(nationalFocusRepositoryProvider);
    ref.invalidate(calendarRepositoryProvider);
    ref.invalidate(scheduleRepositoryProvider);
    final notificationService = ref.read(focusNotificationServiceProvider);
    try {
      await notificationService.syncNationalFocusReminder(
        hasPendingConfirmations: false,
      );
      await notificationService.syncScheduleReminders(
        schedules: const <Schedule>[],
        timeZoneId: await resolveAccountDisplayTimeZoneId(
          ref.read(profileRepositoryProvider),
        ),
      );
    } catch (_) {
      // 取消提醒是尽力而为：记录已经清空，下一次对账会再取消一次。
    }
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
                    accountTimeZoneIdLoader: () async =>
                        (await ref.read(profileRepositoryProvider).getProfile())
                            .displayTimeZoneId,
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
