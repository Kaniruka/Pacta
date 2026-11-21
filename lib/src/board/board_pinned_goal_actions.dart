import 'dart:async';

import 'package:flutter/material.dart';

import '../tasks/task_models.dart';
import '../tasks/task_repository.dart';
import '../ui/pacta_error_text.dart';
import '../ui/pacta_hold_action_reorder.dart';

/// 看板置顶目标的共用动作：宽屏左栏摘要与单栏融合卡顶槽共用这一份。
///
/// 两处原本各写一遍「在计划中查看 / 取消置顶」与顺序写回，异常处理也各写
/// 一半：停用账号（[UserOperationsSuspendedException]）、排序参数不合法
/// （[ArgumentError]）或离线时，写回会在按钮/拖拽回调里抛成未捕获异常。
/// 这里统一捕获并换成一条可读提示，界面不崩、也不假装成功。
void openPinnedGoalActions(
  BuildContext context, {
  required Goal goal,
  required TaskRepository repository,
  VoidCallback? onOpenPlan,
}) {
  unawaited(
    showPactaActionSheet(
      context,
      title: goal.title,
      subtitle: goal.nextTask == null ? '暂无任务' : '下一项：${goal.nextTask!.title}',
      actions: [
        if (onOpenPlan != null)
          PactaActionItem(
            id: 'open-plan',
            label: '在计划中查看',
            icon: Icons.event_note_outlined,
            onTap: onOpenPlan,
          ),
        PactaActionItem(
          id: 'unpin-goal',
          label: '取消置顶',
          icon: Icons.push_pin_outlined,
          onTap: () => unawaited(
            unpinPinnedGoal(
              context: context,
              repository: repository,
              goalId: goal.id,
            ),
          ),
        ),
      ],
    ),
  );
}

/// 取消置顶：失败只提示，不把异常留给事件循环。
Future<void> unpinPinnedGoal({
  required BuildContext context,
  required TaskRepository repository,
  required String goalId,
}) async {
  try {
    await repository.setGoalPinned(goalId, isPinned: false);
  } catch (error) {
    if (!context.mounted) return;
    _showWriteFailure(context, error);
  }
}

/// 写回置顶顺序：调用方负责算好完整 ID 顺序，这里只做写回与失败提示。
Future<void> savePinnedGoalOrder({
  required BuildContext context,
  required TaskRepository repository,
  required List<String> orderedGoalIds,
}) async {
  try {
    await repository.reorderPinnedGoals(orderedGoalIds);
  } catch (error) {
    if (!context.mounted) return;
    _showWriteFailure(context, error);
  }
}

void _showWriteFailure(BuildContext context, Object error) {
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(formatUserError(error))));
}
