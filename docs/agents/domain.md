# 领域文档读取指南

## 文档职责与冲突

| 文档 | 权威职责 | 按需读取与维护 |
| --- | --- | --- |
| [GLOSSARY](../../GLOSSARY.md) | 领域词汇、定义及易混概念边界 | 只读受影响词条及其直接关联词；页面流程、存储实现和验收步骤放在规格中 |
| 已接受 ADR | 决策边界、理由、替代方案和取舍 | 按下表选相关 ADR，包含适用补充；保留决策理由及明确的替代范围 |
| [核心规格](../spec-focus-loop-and-core-shell.md)及专题规格 | 已确认行为、需求约束和测试边界 | 核心行为读对应章节；10月22日改进以[专题规格](../spec-pacta-refinements-20261022.md)为维护入口；AI/MCP读其专题规格 |
| [产品设计](../product-design.md)与页面设计 | 产品意图、信息层级、视觉和页面呈现 | 只读受影响页面；重复的领域行为链接规格，页面特有约束原地保留 |
| 需求访谈、D 系列决定 | 需求来源、确认理由和演变证据 | 仅在规格遗漏、来源追溯或冲突时读取相关问答；历史建议不自动成为现行要求 |
| [验收矩阵](../acceptance-matrix-20260914.md) | 行为对应的场景、预期与边界案例 | 只读受影响行及适用补充；场景编写不等于已执行 |
| Issue、票据与验收记录 | Issue 管当前实施状态；有日期的记录管实际命令、平台、结果及限制 | [Issue 读取方式](issue-tracker.md#when-a-skill-says-fetch-the-relevant-ticket)；本地状态快照与历史证据不替代当前状态 |

UI 支持范围以 [ADR 0007](../adr/0007-accessibility-out-of-product-scope.md) 和 [ADR 0008](../adr/0008-large-text-and-keyboard-out-of-product-scope.md) 为准；旧规格、票据或技能的被替代要求按这两份决定解释，历史证据保留。

沿用 GLOSSARY 的词汇；词条缺失时记录具体缺口。明确标注的后续决定仅替代其声明范围内的旧要求，其余约束继续有效。发现未被明确替代的真实冲突时，列出双方章节、证据及待决定问题，保留冲突内容，继续其他独立项。双向引用可供追溯，不要求递归读完两份文档。

## 任务章节入口

先选受影响概念，读取规格行为章节和对应验收场景，再查「现有实现与复用」。取得规则、适用决策、实现入口和验收边界即可停止；Implementation Decisions / Testing Decisions 仅取与改动相关的条目。

| 行为触发 | GLOSSARY 词条 | 规格章节与验收入口 | 决策边界触发 |
| --- | --- | --- | --- |
| 会话暂停、完成、失败、有效时间或恢复 | Focus Session、Focus Session Outcome、Focus Progress、Recent Focus Activity；涉及链时加 Focus Chain | 核心规格[Appointment preparation and automatic handoff](../spec-focus-loop-and-core-shell.md#appointment-preparation-and-automatic-handoff)[Abandon action and failed outcome](../spec-focus-loop-and-core-shell.md#abandon-action-and-failed-outcome)[Resumable Focus Session pause](../spec-focus-loop-and-core-shell.md#resumable-focus-session-pause)[Focus Session process recovery](../spec-focus-loop-and-core-shell.md#focus-session-process-recovery)[Daily focus allocation and display preferences](../spec-focus-loop-and-core-shell.md#daily-focus-allocation-and-display-preferences)中受影响章节；动作文本/时长摘要加「Chain signals and duration — 2026-10-07」；验收矩阵[有效时间补充](../acceptance-matrix-20260914.md#2026-09-21-有效时间口径补充验收)及 A06–A07、A20 中适用行 | 同步或多设备记录处理改变才加 ADR 0005 |
| 任务、目标生命周期或分类归属 | Goal、Task、Task Chain Classification、Focus Chain Mode | 核心规格「Goal and Task lifecycle」「Attempt mode, classification, and record scope」；10月22日界面/默认模式改进读专题规格「看板与描述」「专注导航与模式」及矩阵 R22-01–05 中相关行 | 一级导航职责改变读 ADR 0004 |
| 国策状态、结算、卡片或要求版本 | National Focus Card / Node、Daily Confirmation、Checkpoint、Requirement Version 等受影响词条 | 核心规格「Daily confirmation and node states」「National Focus settlement and retained records」及对应专节；矩阵对应 NF 行 | 时钟审查/云记录处理改变读 ADR 0005；设备视图偏好读改进规格「设备视图偏好」及 R22-06 |
| 日历与任务数据边界 | Task、Calendar Block | 核心规格「Read-only calendar lifecycle and occupancy」及矩阵日历场景 | [ADR 0002](../adr/0002-app-owned-tasks-read-only-system-calendar.md) |

## 数据库与同步

- 先读数据归属相关词条：User、Cloud Data Snapshot、Local Data Snapshot、Manual Cloud Sync；本机偏好相关改动再读对应概念。身份授权/隔离读 [ADR 0001](../adr/0001-supabase-single-project-invite-only-users.md)，快照传输、版本检查或旧记录兼容读 [ADR 0005](../adr/0005-manual-whole-data-cloud-sync.md)（包含只读检查补充）。AI/MCP云读取另读 ADR 0006 和 AI/MCP 专题规格对应行为。
- 核心契约读核心规格[Offline focus and Manual Cloud Sync](../spec-focus-loop-and-core-shell.md#offline-focus-and-manual-cloud-sync)；国策完整记录额外读[Offline National Focus and Manual Cloud Sync](../spec-focus-loop-and-core-shell.md#offline-national-focus-and-manual-cloud-sync)；身份生命周期读「Registration eligibility and password access」「Suspension retention and cloud purge」「Offline lifecycle during suspension and purge」中相关章节。
- 云版本/设备型号读改进规格[云检查与元数据](../spec-pacta-refinements-20261022.md#云检查与元数据)及适用用户故事、Testing Decisions；验收矩阵取 [R22-07–11](../acceptance-matrix-20260914.md#2026-10-22-已确认改进验收) 中相关行和[手动云同步补充验收](../acceptance-matrix-20260914.md#2026-10-04-手动云同步补充验收)。数据库契约看实际迁移、约束与 RLS；产品设计的数据组仅是概念示意。
- 实施与服务验证按根 AGENTS.md「实施与验证」；Supabase 部署按其 README 对应功能，环境文档只在配置、连接或实测时加载。保留离线恢复、重复操作、跨用户隔离和失败不部分替换的适用验证依据。

## 现有实现与复用

本表是经代码/测试抽查的定位入口，描述现有职责，产品要求仍以以上规格为准。只读命中行及待改符号；表内测试是选择回归范围的入口，不代表本次执行通过。新增能力先确认能否沿用这些边界，保持既有用户隔离、记录归属与时序。

| 改动 | 实现入口与复用边界 | 回归入口 |
| --- | --- | --- |
| 会话、预约、暂停/恢复与结算 | [FocusRepository / LocalFocusRepository](../../lib/src/focus/focus_repository.dart)：沿用启动、暂停、继续、提前结束、放弃和到期结算接口；页面不另算结算或创建第二流程 | [仓储行为](../../test/focus/focus_repository_test.dart)、[导航与恢复](../../test/focus/focus_task_navigation_test.dart) |
| 任务进度、日期分摊与链时长 | 同一仓储的 dashboard 投影和 [focusStatisticsByMode](../../lib/src/focus/focus_statistics.dart)：使用已接受的有效时间/区间；累计与平均不按页面另造计时口径，旧核对记录的排除规则继续保留 | [dashboard](../../test/focus/focus_dashboard_test.dart)、[statistics](../../test/focus/focus_statistics_test.dart) |
| 整份快照上传/下载 | [CloudSnapshotRepository](../../lib/src/sync/cloud_snapshot_repository.dart)：复用 inspect/capture/upload/download、预览指纹与云版本检查、完整校验和事务替换；remote 为外部云边界。原逐实体同步接口用于旧兼容，当前手动入口使用快照仓储 | [App 级同步](../../test/sync/manual_cloud_sync_app_test.dart)、[快照仓储](../../test/sync/cloud_snapshot_repository_test.dart)、[旧云转换](../../test/sync/legacy_cloud_snapshot_test.dart) |
| 云版本发现、忽略及提示协调 | [CloudVersionCheck](../../lib/src/sync/cloud_version_check.dart)管理检查/节流/版本状态；[AppShell](../../lib/main.dart)协调认证、生命周期与发起检查，沿用共享 provider；[CloudSyncCard](../../lib/src/sync/cloud_sync_card.dart)监听未结束流程并延后自动提示；[同步结果存储](../../lib/src/sync/cloud_sync_result.dart)记录本机成功结果，检查不冒充成功同步 | [App 级云检查](../../test/sync/cloud_version_check_app_test.dart)、[跨入口同步](../../test/sync/manual_cloud_sync_app_test.dart) |

手动云同步的真实服务入口是 [manual_cloud_sync_real_service_test](../../integration_test/manual_cloud_sync_real_service_test.dart)；生命周期、选择提醒的原生/云入口按 [T08/T09 证据索引](../tickets-pacta-refinements-20261022/README.md)查找。执行前读 [Supabase 测试前提](../../supabase/README.md)及环境配置，结果需区分替身、真实服务和实际平台。
