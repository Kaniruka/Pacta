# Agent 文档路由调整与验证（2026-10-23）

本记录是文档结构调整与阅读验证的历史证据，不是新产品规格。基线为 `afc50c3`，开始时工作区干净；本轮只修改前两轮审计涉及的文档，未运行应用、数据库迁移、Flutter 测试或平台验收。

## 调整与权威来源

- 根 AGENTS.md 以任务触发、章节入口、扩读条件和停止条件路由；领域指南集中说明 GLOSSARY、ADR、规格、产品设计、需求来源、验收场景和实施证据的职责。
- 产品设计的同步摘要及10月22日行为补充改为精确规格引用；专题规格增加四个任务分节，保留或承接全部原有展示、默认值、恢复、旧数据、平台与原型排除约束。核心规格保留旧界面的明确替代范围。
- GLOSSARY 的本次模式词条保留记录归属定义，选择流程引用规格；建议数据组明确为概念示意。ADR 本文完全未改，决策理由、替代方案及取舍保留。ADR 的决策记录与规格的执行契约职责不同，本轮保留其必要交叠。
- T02、改进规格/访谈、票索引的旧进度标明历史快照；矩阵链接 #64/#65 的有日期证据，不推定其他场景已通过。国策旧方案增加停止阅读提示，原始过程和验收事实保留。

## 冲突复核

- 手动整份替换与只读版本检查不冲突：ADR 0005 的补充明确授权后者，并未授权自动替换。历史核对结果保留不等于继续产生新核对案例。
- 无障碍旧要求由 ADR 0007 明确替代；旧 TalkBack 修复记录和已有测试按该 ADR 保留。普通键盘、可见状态与大字号要求继续适用。
- T02 页首待实施与页尾已验收属于过时状态矛盾，本轮标记原状态为发布快照并链接后续证据，没有重新裁定产品需求或远端关闭状态。
- 已定位范围内没有剩余待决定的真实产品冲突。若后续出现未被明确替代的冲突，按领域指南保留双方内容、列证据与待决定问题，独立项继续处理。

## 计量口径与证据等级

- **修改前静态推演**：取基线旧入口直接要求或直接列为依据的整文件，构成可复现的宽读路径示例；旧文档没有强制全部全文加载，因此该数值不是必要最低量，也不是上一轮真实消耗。只跟第一层依据，不递归追溯链接。
- **修改后静态计划**：为下列三个具体任务选定文档片段，按 UTF-8 字节计量（KB = 1000 bytes）；每条任务内重复行只计一次。为保守计量，短入口和测试决定取全文/完整节，未追求绝对最小。
- **实际读取证据**：本轮用 Python 从当前保存文件按下列行号提取正文，输出到工具结果并由主 Agent 逐项读取复核。共用 AGENTS、领域指南复用已读取内容；各路径逻辑总量仍各自包含入口。这是指定路径读取回放，不是新 Agent 的独立盲测，也不是应用功能验证。
- 数值排除技能正文、标题发现输出、工具包装、代码、迁移/RLS、Issue 远端内容、环境配置和设备操作；它比较的是产品/领域文档的初始上下文包。实际实施涉及这些边界时按路由追加，不能用本表宣称任务全过程只需这些内容。

| 任务 | 修改前静态文件数 / bytes | 修改后文件数 / bytes（已实际读取） |
| --- | --- | --- |
| UI 小改：看板摘要卡间距 | 6 / 80467 | 3 / 10061 |
| 领域行为变更：暂停时间的有效专注计算 | 5 / 123184 | 5 / 17726 |
| 数据库变更：云快照来源设备型号兼容 | 7 / 128568 | 8 / 22659 |

## UI 小改：看板摘要卡间距

### 修改前：整文件静态推演

| 文件 | 章节口径 | UTF-8 bytes |
| --- | --- | --- |
| [AGENTS.md](../AGENTS.md) | 全文（18行） | 2179 |
| [docs/agents/ui.md](agents/ui.md) | 全文（49行） | 4887 |
| [docs/product-design.md](product-design.md) | 全文（321行） | 52351 |
| [docs/adr/0004-core-screen-information-architecture.md](adr/0004-core-screen-information-architecture.md) | 全文（9行） | 1180 |
| [docs/adr/0003-flutter-dart-client-stack.md](adr/0003-flutter-dart-client-stack.md) | 全文（22行） | 2469 |
| [GLOSSARY.md](../GLOSSARY.md) | 全文（200行） | 17401 |

### 修改后：计划及实际读取清单

| 文件 | 章节/条目 | 行号 | UTF-8 bytes | 片段 SHA-256 前12位 |
| --- | --- | --- | --- | --- |
| [AGENTS.md](../AGENTS.md) | 全文 | 1–23 | 3058 | `d9888aee1627` |
| [docs/agents/ui.md](agents/ui.md) | 全文 | 1–56 | 5529 | `40949a9e44d8` |
| [docs/product-design.md](product-design.md) | Board content hierarchy — 2026-10-07 | 152–157 | 1474 | `06a3ec03e320` |

必要性：入口确定技能与验收要求；Board 层级章节提供既有间距、字号、窄宽布局约定。例子不改变导航或行为，故不加载 ADR 0003/0004、整份术语表和领域规格。若实际实施或评审，另按 UI 指南加载适用技能与相邻代码；本轮只验证路由。

## 领域行为变更：暂停时间的有效专注计算

### 修改前：整文件静态推演

| 文件 | 章节口径 | UTF-8 bytes |
| --- | --- | --- |
| [AGENTS.md](../AGENTS.md) | 全文（18行） | 2179 |
| [docs/agents/domain.md](agents/domain.md) | 全文（31行） | 965 |
| [GLOSSARY.md](../GLOSSARY.md) | 全文（200行） | 17401 |
| [docs/spec-focus-loop-and-core-shell.md](spec-focus-loop-and-core-shell.md) | 全文（481行） | 83399 |
| [docs/acceptance-matrix-20260914.md](acceptance-matrix-20260914.md) | 全文（123行） | 19240 |

### 修改后：计划及实际读取清单

| 文件 | 章节/条目 | 行号 | UTF-8 bytes | 片段 SHA-256 前12位 |
| --- | --- | --- | --- | --- |
| [AGENTS.md](../AGENTS.md) | 全文 | 1–23 | 3058 | `d9888aee1627` |
| [docs/agents/domain.md](agents/domain.md) | 全文 | 1–33 | 5046 | `8f85dbee4213` |
| [GLOSSARY.md](../GLOSSARY.md) | 词条：Focus Session, Focus Session Outcome, Focus Progress, Recent Focus Activity | 19–26, 51–58 | 1820 | `88c9ea24dcee` |
| [docs/spec-focus-loop-and-core-shell.md](spec-focus-loop-and-core-shell.md) | Resumable Focus Session pause | 282–291 | 1581 | `c5e58b3d4dca` |
| [docs/spec-focus-loop-and-core-shell.md](spec-focus-loop-and-core-shell.md) | Daily focus allocation and display preferences | 358–364 | 1408 | `abe5a131c095` |
| [docs/spec-focus-loop-and-core-shell.md](spec-focus-loop-and-core-shell.md) | Testing Decisions | 196–210 | 4102 | `50ae0bca9efc` |
| [docs/acceptance-matrix-20260914.md](acceptance-matrix-20260914.md) | 2026-09-21 有效时间口径补充验收 | 50–55 | 711 | `83881903c60f` |

必要性：四个词条区分会话、结果与两种时间投影；暂停和日分配章节确定哪些时间计入；Testing Decisions 与有效时间验收节保留测试边界和20分钟完成、10分钟失败计入且另5分钟暂停不计入的案例。例子不改同步决策，故不加载 ADR 0005 或全部需求历史。

## 数据库变更：云快照来源设备型号兼容

### 修改前：整文件静态推演

| 文件 | 章节口径 | UTF-8 bytes |
| --- | --- | --- |
| [AGENTS.md](../AGENTS.md) | 全文（18行） | 2179 |
| [docs/agents/domain.md](agents/domain.md) | 全文（31行） | 965 |
| [GLOSSARY.md](../GLOSSARY.md) | 全文（200行） | 17401 |
| [docs/adr/0001-supabase-single-project-invite-only-users.md](adr/0001-supabase-single-project-invite-only-users.md) | 全文（18行） | 1643 |
| [docs/adr/0005-manual-whole-data-cloud-sync.md](adr/0005-manual-whole-data-cloud-sync.md) | 全文（21行） | 3741 |
| [docs/spec-focus-loop-and-core-shell.md](spec-focus-loop-and-core-shell.md) | 全文（481行） | 83399 |
| [docs/acceptance-matrix-20260914.md](acceptance-matrix-20260914.md) | 全文（123行） | 19240 |

### 修改后：计划及实际读取清单

| 文件 | 章节/条目 | 行号 | UTF-8 bytes | 片段 SHA-256 前12位 |
| --- | --- | --- | --- | --- |
| [AGENTS.md](../AGENTS.md) | 全文 | 1–23 | 3058 | `d9888aee1627` |
| [docs/agents/domain.md](agents/domain.md) | 全文 | 1–33 | 5046 | `8f85dbee4213` |
| [GLOSSARY.md](../GLOSSARY.md) | 词条：User, Cloud Data Snapshot, Local Data Snapshot, Manual Cloud Sync | 15–18, 27–38 | 1145 | `1a11112a900e` |
| [docs/adr/0001-supabase-single-project-invite-only-users.md](adr/0001-supabase-single-project-invite-only-users.md) | 全文 | 1–18 | 1643 | `956e67359d5d` |
| [docs/adr/0005-manual-whole-data-cloud-sync.md](adr/0005-manual-whole-data-cloud-sync.md) | 全文 | 1–21 | 3741 | `824598d87a98` |
| [docs/spec-focus-loop-and-core-shell.md](spec-focus-loop-and-core-shell.md) | Offline focus and Manual Cloud Sync | 378–389 | 2407 | `02ca5f79205a` |
| [docs/spec-pacta-refinements-20261022.md](spec-pacta-refinements-20261022.md) | 云检查与元数据 | 100–108 | 1752 | `303aedab2eb0` |
| [docs/spec-pacta-refinements-20261022.md](spec-pacta-refinements-20261022.md) | User Stories 59–61 | 77–79 | 363 | `b87c6b2b9efe` |
| [docs/spec-pacta-refinements-20261022.md](spec-pacta-refinements-20261022.md) | Testing Decisions | 109–120 | 2142 | `e606b4dcec93` |
| [docs/acceptance-matrix-20260914.md](acceptance-matrix-20260914.md) | 2026-10-04 手动云同步补充验收 | 63–71 | 1091 | `37f0fe0d386c` |
| [docs/acceptance-matrix-20260914.md](acceptance-matrix-20260914.md) | R22-11 | 123 | 271 | `4b1f5fb04a7d` |

必要性：用户/快照定义确定归属；ADR 0001/0005保留隔离与覆盖决策及理由；核心同步契约确定替换和失败边界；专题规格与R22-11覆盖实际型号、未知旧数据与禁止伪造。涉及真实schema、部署或平台型号读取时，必须追加实际迁移/RLS、Supabase对应说明、环境及设备证据；本次未执行。新路径多一个文件是专题规格显式进入，而非要求文件数量下降。

## 检查与复现

本地 Markdown 行内链接检查：初轮检查 239 个本地路径/标题锚点，0 个失败。包含本报告的最终检查共278个本地路径/标题锚点，0个失败；`git diff --check` 通过。外部 HTTP/GitHub 链接未联网验证；普通反引号路径及表内章节名另经标题核对。

实际读取清单的复现：按上表文件和行号，用 `Path(path).read_text().splitlines(keepends=True)` 选取1基行号，依序拼接，再以 `len(text.encode("utf-8"))` 和 `sha256` 核对。修改前整文件可用 `git show afc50c3:<path>` 重建；将这些文件去重求和。本表哈希仅约束对应片段，不包含输出包装。

文档职责和停止条件已按三个例子复核：UI只需呈现规则；领域任务需行为与验收边界；数据库任务需快照归属、决策与兼容契约。来源/历史回链只有遇到具体追溯问题才跟随。
