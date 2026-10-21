# 国策树 AI 分析访谈（2026-10-20）

本文保留 2026-10-20 访谈时的决策与核对结果。用户已授权入队：[规格](spec-national-focus-ai-mcp.md)、[Issue #56](https://github.com/Kaniruka/Pacta/issues/56)。下文“尚未提供”“待实施设计”等表述描述访谈时点，不代表当前实现状态。

2026-10-22 整理：授权、当前树和失败历史接口已分别完成 #57、#58、#59；实际能力与限制见 [MCP 合同](../supabase/functions/national-focus-mcp/README.md)，验收见 [#57](issue-57-validation.md)、[#58](issue-58-validation.md)、[#59](issue-59-validation.md)。配套 skill 和复盘引导的剩余工作以父 Issue 为准。

## 已确认

- 用途：审视规则清晰度、父子关系、执行负担；结合历史复盘失败并建议下一步尝试。
- 第一版只读，由用户在 App 采纳建议；远程 MCP 供 Codex 使用，本机连接后续补充。
- 用户主要在手机维护，平板也装有 Codex。流程：手机维护→手动上传整份业务快照→Codex 分析；MCP 不触发同步，返回仅限国策，附来源设备和真实上传时间。
- 范围：当前树结构/内容/状态、卡片库、强化等级、要求版本、连续记录、内化进度、失败事件/原因/历史树快照；排除目标、任务、专注及日历。
- 面向所有 Pacta 用户，独立授权且只读本人数据；首轮由需求提出者验证。
- 登录 Pacta 后明确授予国策只读权限，持续有效至到期/撤销；App 可撤销后续读取，不能收回已进入对话的数据。授权协议待实施设计。
- 配套 skill：解释术语、区分事实/解释/建议及独立失败/连带熄灭，引用卡片/历史证据并说明缺失。
- 写回另行设计。用户建议配套 skills 减少误操作，范围/实现未定；skill 不替代接口授权和业务校验。

## 已核对

- 国策独立于目标/任务，现实履行由用户判断：见 GLOSSARY.md、核心规格。
- 现有模型含树位置、卡片库、规则、强化、要求版本、连续记录、内化进度及失败完整树快照：见 lib/src/tasks/task_database.dart、lib/src/national_focus/national_focus_models.dart。
- 手动云同步为整份替换，普通编辑不上传，云端可能陈旧；不是国策导出/合并接口：见 ADR 0005、lib/src/sync/cloud_snapshot_repository.dart。目前无国策 MCP/专用 AI 接口。
- 云快照在 cloud_business_snapshots JSON payload，含 revision、设备、data_updated_at、数据库生成的 uploaded_at；RLS 限正常用户读本人数据。data_updated_at 是全数据派生时间，不等于上传或国策最后编辑时间。
- 累计成功日数不是每日成功日志。来源日志含可重建状态，但完整性、分支、设备时钟影响可信度，不能虚构成功日历/完整编辑史。
- 同批次 sharedExplanation 可事后编辑，冻结 treeSnapshot 不变；独立失败和连带影响分别呈现。

## 架构与实施约定

手机本地库→手动上传整份快照→Supabase；Codex→授权的 Pacta 只读 MCP→按用户/国策范围查询云快照。

MCP 负责协议、授权、白名单投影及结构化返回，Codex+skill 负责分析。拟提供快照信息、树/库/规则、分页失败查询，名称/合同待定；评估 Edge Functions，承载及 OAuth/撤销仍需验证。现有 Supabase 登录不等于 MCP 授权；RLS 行隔离之外须有只读国策委托，禁止向 Codex 提供管理员密钥或完整应用会话。

规格补齐的约定：revision 变更重读、不混版本；默认复盘近 30 个国策日、可分页扩展，缺失历史须说明。实施时确定凭据有效期/续期，每次校验授权和用户状态。

用户确认公开 MCP 为主要测试边界，补充 App 引导/撤销及真实服务隔离验证。App 必须有“我的”主入口和树页快捷入口，引导上传、连接、授权、skill、首次问题、时效和撤销。

取舍见 ADR 0006；暂无新领域词条。执行 Agent 按规格细化接口、部署和授权并验证。
