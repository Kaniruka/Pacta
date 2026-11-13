# #90 实施与验收进度

本文件记录当前实施证据，不将草案或替身测试当成真实服务、设备通过。

## 已完成准备

- 2026-11-13 用户确认全部五项、依赖和测试范围，授权发布及完整实施。
- 父规格 [#90](https://github.com/Kaniruka/Pacta/issues/90)；子票 #91–#95。已读回验证原生父子关系及 #92 阻塞 #93。
- 集成分支 `feat/sync-profile-cards-20261113`；比较基点 `394e321`，规格与已完成内化公式基线 `c76a59f`。内化公式保留，不重复实施。
- 已保存用户选定原型到 `docs/prototypes/pacta-card-prototype-20261113.html`，只采用data-design=a。

## DSH配置与工单

预检worker `pacta90_preflight`，session `session-4c430916-4322-416e-8ecd-21a13316cb5a`。只读检查确认Windows11/MSYS bash、PowerShell5、Git2.56、Flutter3.47.2/Dart3.13.2、Python3.14可用；仓库/HEAD匹配。桥接有效preset=ptc、provider=cc-switch-tencent-token-plan、model=deepseek-v4.1-flash-1017；实际请求toolCount=1。预检未设置effort，实际字段缺省；实现工单显式请求high，需完成回执再核对实际请求。

| 工单 | Worker/session | Worktree/分支 | 状态 |
| --- | --- | --- | --- |
| #91 | pacta91_cards / session-0c9bd49f-8719-4f83-aafc-fee7e09e5e9c | C:/Users/Stray/.codex/worktrees/pacta-card-layers/Pacta / impl/pacta91-card-layers | 3c112c7经79f0307合入；worker已关闭 |
| #92 | pacta92_backups / session-3538425b-4617-4520-a42e-50e36c889634 | C:/Users/Stray/.codex/worktrees/pacta-snapshot-history/Pacta / impl/pacta92-backup-history | a044b51经1fb1851合入；worker已关闭 |
| #95 | pacta95_reminders / session-24a59a18-e96c-40a1-b1b7-eccfd3e01973 | C:/Users/Stray/.codex/worktrees/pacta-daily-reminder/Pacta / impl/pacta95-reminders | 实施中 |
| #94 | pacta94_profile / session-addb0e2a-6335-4ce4-81ea-3213f78c8be3 | C:/Users/Stray/.codex/worktrees/pacta-profile-stats/Pacta / impl/pacta94-profile-stats | 实施中；DSH接受独立执行位 |
| #93 | pacta93_auto / session-39b9885b-2d48-465d-99fe-4d2033636823 | C:/Users/Stray/.codex/worktrees/pacta-auto-upload/Pacta / impl/pacta93-auto-upload | 已从集成分支1fb1851启动 |

主Agent独立复核和执行集成检查，worker不得直接部署共享云、操作真实用户数据或关闭Issue。合并后按implement-spec双轴评审。

## 验收环境

- Android：已启动现有AVD PactaFocusPilot20261112，序列emulator-5556，Android15。未擦除数据。发现另有实体设备，默认验收只使用该模拟器。
- 云：通过受保护管理凭据读回仅有共享Pacta项目；沿用已有脚本的免费组织/独立项目保护创建 `Pacta issue90 disposable validation`。状态文件保存在忽略目录 `.scratch/issue90/isolated-state.json`。仅该明确隔离项目可应用测试迁移；共享项目未修改。
- 凭据留在受保护环境，不传入Flutter构建配置；运行时会话经本地受控通道提供。尚未执行本轮云验收。

## 已执行的基线验证

- 隔离项目全部既有迁移已应用；`cloud_business_snapshots.sql`回滚探针通过，真实owner读取、跨用户RLS拒绝、旧数据读取、只读前后摘要、revision和legacy token变化通过。临时探针用户和快照已清理。新迁移仍待各票交付后验证。
- Android15：`flutter drive --driver=test_driver/ui_layout_acceptance_test.dart --target=integration_test/ui_layout_acceptance_test.dart -d emulator-5556`通过；5张图在`build/ui-layout-evidence/issue90/20261113-171635-baseline-android`。manifest记录源码指纹，`sourceUnchanged=true`。已打开My页基线图；该旧fixture显示时区回退UTC，已提醒通知worker核实本机时区读取，不据此扩改无关模块。
- Windows：同一fixture以`-d windows`运行通过，证据`build/ui-layout-evidence/issue90/20261113-172107-baseline-windows`。Windows旧fixture不产截图；没有宣称Windows目视验收。
- #91初版`385dc56`已复核，返回worker修复库卡直达强化入口、非当前等级编辑不应要求先切换生效，以及fixture应使用真实主题和Android host截图导出。尚未合入。

## 集成复核进展

- 草稿PR [#96](https://github.com/Kaniruka/Pacta/pull/96)，明确关联关闭父规格与五个子票；保持draft直到验收完成。
- 合并worker `pacta90_merger` / `session-f3076a72-d876-4122-9f88-2e3802c0ded2` 已分别合并#91（79f0307）和#92（1fb1851），均无冲突；主检出工作区干净后再开始各次合并。
- #91主Agent复跑 `flutter test test/national_focus test/ui`：123通过；Android真实主题fixture light运行9张图，目录`build/ui-layout-evidence/issue90/20261113-174252-cards-android-light`，已打开判读弹层、强化管理和编辑截图。发现编辑页“同时显示基础规则”旧文案与折叠交互不符，待设计收尾修正。
- #91深色窄屏使用`NF_CARD_LAYERS_WIDTH=320`的一次运行卡在框架Test starting页，经原生截图确认后停止，未计通过。该过程中集成代码有合并，不作为最终证据；改用模拟器实际density=540（1080px/3.375=320逻辑像素）重跑，结束恢复原物理density420。
- #92主审查修复：请求重试返回原请求版本，独立无载荷请求台账避免淘汰后重写；不同内容复用ID拒绝；带ID不得降级旧RPC；恢复点读回身份/指纹校验；事务内取消直到提交前都可回滚。
- #92真实SQL探针先后发现测试角色非法读取auth.users/内部请求台账及SQL语法问题，均修正测试而非放宽生产权限。主Agent最终独立执行`.scratch/issue90/probe_history.py --source C:/Users/Stray/.codex/worktrees/pacta-snapshot-history/Pacta --apply`通过；证据`.scratch/issue90/history-probe-20261113-175430.json`记录文件哈希、passed=true、applied=true。迁移仅应用到明确隔离项目，临时身份已清理。
- #95初版4630a17尚未合入，退回修正：本机当前用户隔离、退出/切换取消、首次实际能力使用时请求权限、原生fixture不能覆盖既有设置及不能以人工注入点击代替原生证据。其无关换行差异已清理。

## 后续

收集各票提交 → 独立合并 → 运行完整测试和两端/真实云证据 → Standards/Spec及设计复核 → 修复 → 发布可评审PR并清理临时worktree与隔离验收资源。禁止在验收未完成时宣称整体验收通过。
