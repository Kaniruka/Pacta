# #90 同步分层最终设计审查

**结论：Good；未发现阻塞或高优先级视觉问题。** 设计主旨清楚：常驻卡片只给出“数据同步”和本机最近成功时间；低频操作集中在短面板；整份覆盖的时间、记录数、来源和丢弃后果放到执行前确认。这个分层在 Android 与 Windows、亮色与暗色中保持一致。

## 审查结果

- 主卡片摘要简洁；操作层能快速识别云端来源、下载（可用时为主操作）、上传、今日确认后自动上传、历史备份，以及保留的忽略/关闭入口。未把时间、记录数和覆盖说明提前堆进面板。
- 上传/下载确认清楚说明会替换哪一端的整份业务数据、独有记录会丢弃；展示两端更新时间和记录数、云端来源/上传时间及“哪端较新”提示。本机未同步修改在下载确认中有单独警告。取消与“确认上传/确认下载”并列，恢复历史备份也有独立的覆盖确认。
- Android 用带拖拽柄的底部弹层；Windows 用居中限宽对话框。320 dp 截图中操作与确认内容可换行，动作仍可见。亮暗主题层级一致，历史页在稳定帧中可读。

## 截图与实现证据

以下四个运行目录均有 `run.rc=0`，manifest 标记 `sourceUnchanged=true`：

1. Windows 暗色：`build/ui-layout-evidence/issue90/20261113-221801-sync-final-windows-dark/`
2. Android 亮色：`build/ui-layout-evidence/issue90/20261113-222227-sync-final-android-light-unpaused/`（`--no-start-paused`）
3. Android 暗色、320 dp：`build/ui-layout-evidence/issue90/20261113-222407-sync-final-android-dark320/`（`--no-start-paused`；密度覆盖 540，测试后恢复 420）
4. Windows 亮色：`build/ui-layout-evidence/issue90/20261113-222538-sync-final-windows-light/`

卡片标题见 [Windows 亮色总览截图](../build/ui-layout-evidence/issue90/20261113-222538-sync-final-windows-light/my-overview.png)；操作层与覆盖确认可参见同目录的 `sync-operations.png`、`download-confirmation.png`、`upload-confirmation.png`。Android 320 dp 的稳定历史页取 `history-after-cancel.png`；其 `cloud-history.png` 带有进入页面时的残影与粉色标记，未用作视觉判断。

实现与产品依据：`lib/src/sync/cloud_sync_card.dart:274–322` 按 Android/其他平台选择底部弹层或对话框；`:458–563` 放来源与操作入口；`:565–630` 放执行前数据细节和覆盖后果；`:694–710` 渲染常驻卡片。`docs/spec-pacta-refinements-20261022.md` 的 User Stories 38–61 与“云检查与元数据”第 105–108 行确认这组分层和保留忽略语义。`docs/agents/ui.md` 的“UI 要求/验收”约束常规字号可读、窄屏响应和 Android/Windows 平台验收。

设计参考按 Android/Windows Flutter 转译：`layout.md › Visual hierarchy` 支持分组与渐进披露；`alerts.md › Best practices / Buttons` 支持在可能丢失数据的操作前说明后果并提供取消；`sheets.md › Best practices` 支持单一任务和明确退出；`cross-platform.md › Conventions to check` 对应 Flutter 触摸目标与桌面指针/窗口适配。ADR 0007/0008 将读屏/辅助技术、大字号和专项键盘支持移出当前验收范围，本审查未将其作为门槛。

## 限制

本报告判读已保存截图并静态对照上述实现，没有自行启动设备或计算像素级对比度；截图未覆盖旧版云数据分支。Android 默认 paused 启动曾出现 ANR；本次用于设计判读的 Android 运行采用 `--no-start-paused`，状态截图无 ANR 遮罩，运行记录另见 [#90 恢复验收记录](issue90-resume-validation-20261113.md)。此报告只结论同步分层视觉；后续 Windows 原生通知点击与恢复已于 2026-11-14 通过，整体验收结果见恢复验收记录的最终收口。
