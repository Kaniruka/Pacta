# Android 国策跨夜结算排查（2026-10-20）

跟踪：[GitHub Issue #55](https://github.com/Kaniruka/Pacta/issues/55)。

## 结论（平板核查后）

2026-10-20 用户连接出问题的 Android 平板并展示失败记录。截图中的 2026-10-20 04:00 批次只有一个独立失败来源：顶层父国策。完整不可变快照显示父节点为 Pending Today Confirmation、当前连续 1 天，部分子节点仍为 Lit、当前连续 0 天，后代均标注因父节点连带熄灭。由此确认本次事件属于父节点漏确认导致的级联失败，不是全部点亮节点在首个检查点被误判失败。用户核对后确认理解并说明此次不是 bug。

现行规格明确允许单独确认子节点而不确认待确认父节点，但父节点到检查点仍未确认时，其后代会受影响。代码与已存在回归测试“父漏确认会连带熄灭已确认的子且子当天不增加成功日”一致。无需修改结算规则，也未修改平板业务数据。

设备安装信息：Android，应用 `com.pacta.pacta`，版本 `1.0.0` / code `1`，最后安装更新时间为 2026-10-12 02:38:08。安装包为非 debuggable，未读取私有数据库。截图仅留在被 Git 忽略的 `build/overnight-tablet/`，不提交用户具体国策内容。

以下为取得设备证据前的排查过程，保留以说明早期验证的范围。

## 用户报告

Android，凌晨 01:00 节点已点亮，关闭应用跨过北京时间 04:00，08:00 重开后节点全部未点亮；失败记录原因为“未完成今日确认”，时间为当天 04:00。这里按同一次睡眠、间隔约 7 小时排查。

## 依据与预期

沿用 GLOSSARY.md、核心规格“Daily confirmation and node states”“National Focus settlement and retained records”及 ADR 0005。第一个检查点应累计一个成功日并转为待今日确认，无新增失败。若跨过再下一个检查点仍未确认，才正式失败。关闭应用本身不是失败条件。

## 已验证

- 基线提交：`9be3337b985d0f8a058c0496a8b261b8af57344e`；开始时工作区干净。
- `flutter test test/national_focus/national_focus_repository_test.dart --reporter expanded`：26 项通过，含新增的同一检查点并发结算/树读取/卡片库读取/失败记录读取场景。父子节点都仅累计一天，进入待今日确认，无失败。
- `flutter analyze`：通过，无问题。
- `flutter test --reporter expanded`：完整单元/组件测试共 256 项通过。
- `flutter test integration_test/national_focus_overnight_checkpoint_test.dart -d windows`：构建并启动 Windows 原生应用，真实临时 SQLite 在北京时间 01:00 保存父子点亮状态并关闭，08:00 重开；两节点均待确认，成功日各为 1，无失败。再过一个检查点未确认的对照场景正常失败；重复结算未增加记录。1 项设备测试通过。
- Android 模拟器 `PactaT24Secondary` 已启动，但 ADB 持续显示 `offline`，未在 Android 上执行成功，不能当作 Android 验证证据。
- 尚未获得能复现用户症状的失败测试，不能据此认定根因或宣称已修复。

## 代码边界

`LocalNationalFocusRepository._settleCheckpointsThrough` 按维护游标逐日补算；`_settleCheckpoint` 在更新状态前计划失败来源。单次结算时 Lit 只会成功并转 Pending Today Confirmation；missedConfirmation 来源必须是原本已待确认的节点（或其父失败的影响）。`settleDueCheckpoints` 的事务在并发测试中保持幂等。

## 早期未决事项（已由平板快照查明本次失败来源）

出问题设备的安装版本、失败快照及本地操作时间线，特别是点亮操作、维护游标、两次结算的实际时间和父节点状态。没有这些证据，不应通过跳过补算、延长确认窗口或清除失败历史来掩盖症状。

## 复核边界

Standards 复核未发现阻止提交的问题。Windows 集成测试直接重开数据库并挂载国策页面，未覆盖 Android AppShell 前后台恢复和实际设备时区；不能单独排除设备生命周期问题。当前只增加测试和证据，不构成缺陷修复。
