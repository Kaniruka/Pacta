# Pacta 维护代理指南

适用于全仓库。先查 `git status`；只改任务相关文件，保留他人未提交改动。

UI 实施、评审和验收先按 [ADR 0007](docs/adr/0007-accessibility-out-of-product-scope.md) 与 [ADR 0008](docs/adr/0008-large-text-and-keyboard-out-of-product-scope.md) 确定支持范围；技能建议服从已确认范围，已有实现、测试及历史证据保留。

## 按任务读取

先定位标题，再读取下列入口及相关章节；已取得受影响规则、边界、验收依据且无未决冲突即停止扩读。来源、历史和证据链接只在追溯问题或核验结果时跟随。文档职责与冲突处理见[领域指南](docs/agents/domain.md#文档职责与冲突)。

| 任务触发 | 必读入口与章节 | 扩读条件 |
| --- | --- | --- |
| 页面布局、文案、主题或交互改动 | [UI 指南](docs/agents/ui.md#流程与技能)及其「UI 要求」「验收」；按「页面章节入口」读取受影响页面 | 行为改变转领域路由；导航职责改变读 ADR 0004；平台/技术栈改变读 ADR 0003 |
| 领域行为、术语或数据归属改变 | [领域指南的任务章节入口](docs/agents/domain.md#任务章节入口)；仅相关 GLOSSARY 条目、规格行为章节和验收场景 | 触及决策边界时读取表中 ADR；定义缺失或冲突时追溯需求决定 |
| 数据库、同步、身份或权限改变 | [领域指南的数据库与同步入口](docs/agents/domain.md#数据库与同步) | 部署/真实服务验证读 supabase/README.md 对应功能；环境配置读开发环境「客户端配置」「Supabase 开发路径」 |
| Issue 实施、状态核对或分诊 | [Issue 指南](docs/agents/issue-tracker.md#when-a-skill-says-fetch-the-relevant-ticket)读取目标 Issue、评论和对应规格章节 | 修改分诊标签时读 docs/agents/triage-labels.md；有硬依赖才读依赖票；追溯决定才读访谈 |
| 构建、设备验收、云连接或凭据配置 | [开发环境](docs/development-environment.md)中对应的「工具与平台」「客户端配置」「Supabase 开发路径」 | 历史工具检查仅用于排错，不作为当前环境事实 |

## 实施与验证

- 代码/测试：`lib/`、`test/`；平台验收：`integration_test/`；迁移、RLS 脚本、Edge Functions：`supabase/`。行为改动同步检查测试和文档，只报告实际命令、平台及结果。
- Dart 改动：先对改动文件 `dart format`，再 `flutter analyze` 和相关 `flutter test`；跨模块改动跑完整测试。Drift 表变更按需运行 `dart run build_runner build --delete-conflicting-outputs` 并检查生成差异。
- 同步/身份/权限/数据库改动：核查离线恢复、重复同步、跨用户隔离及 RLS，在隔离项目验证 SQL/真实服务边界。原生权限、通知、日历须有 Android/Windows 对应证据，单元测试不能替代。
- 设备验收：可按任务启动现有 Android 模拟器、用 ADB 安装测试 APK，或在 Windows 构建/安装/运行测试版本；保留用户数据。路径、命令见[环境文档](docs/development-environment.md)，按实际平台取证。
- 客户端仅用公开 Supabase URL 和 publishable/anon key；服务端密钥、管理员凭据、真实测试账号留在受保护环境，提交前检查无泄漏。
