# Pacta 维护代理指南

本文件适用于整个仓库。开始工作时先查看 `git status`，辨认已有改动；只修改当前任务需要的文件，并保留他人的未提交工作。

## 先读取与任务有关的依据

- 涉及领域概念、业务行为或数据边界时，先读 `CONTEXT.md` 和 `docs/adr/` 中相关的已接受决策，沿用其中的术语；具体行为与验收依据见 `docs/spec-focus-loop-and-core-shell.md`、`docs/acceptance-matrix-20260914.md`。若实现需求与 ADR 冲突，先明确指出冲突。领域文档的使用约定见 `docs/agents/domain.md`。
- 涉及产品界面时，参考 `docs/product-design.md` 及 ADR 0004；涉及技术栈、平台范围时，参考 ADR 0003；涉及用户隔离、注册或管理操作时，参考 ADR 0001；涉及任务与设备日历时，参考 ADR 0002。
- 涉及本地环境、云端连接或测试凭据时，参考 `docs/development-environment.md`；涉及 Supabase 部署与管理函数时，参考 `supabase/README.md`。
- 需求和任务以 GitHub Issues 为跟踪入口，用 `gh` 读取和更新；操作约定见 `docs/agents/issue-tracker.md`。分诊时使用 `needs-triage`、`needs-info`、`ready-for-agent`、`ready-for-human`、`wontfix`，含义见 `docs/agents/triage-labels.md`。

## 实施与验证

- 客户端代码在 `lib/`，对应测试在 `test/`；平台验收测试在 `integration_test/`；数据库迁移、RLS 验证脚本和 Edge Functions 在 `supabase/`。修改行为时检查相应测试和文档，验证结果只报告实际执行过的命令、平台与结果。
- 修改 Dart 代码后，对改动文件运行 `dart format`，再运行 `flutter analyze` 和相关 `flutter test`；影响跨模块行为时运行完整 `flutter test`。修改 Drift 表结构后，按需运行 `dart run build_runner build --delete-conflicting-outputs`，检查生成文件差异。
- 修改同步、身份、权限或数据库行为时，核查离线恢复、重复同步、跨用户隔离和 RLS 影响；在隔离测试项目验证相关 SQL 或真实服务边界。Android/Windows 原生权限、通知和日历行为需要对应平台证据，不能仅以单元测试代替。
- 客户端只使用可公开的 Supabase URL 和 publishable/anon key。将服务端密钥、管理员凭据与真实测试账号信息留在受保护的环境中；提交前检查改动中没有这些值。

## 命令与文件操作

- 简单系统命令可以使用 PowerShell；批量文件、中文编码、复杂路径或大量文本处理优先编写一次性 Python 脚本。
- 同一种执行方式连续失败两次后立即停止重试；先说明失败原因，再选择其他方案，避免反复调整路径、引号和转义盲目执行。
- 文件操作前确认目标路径；完成后检查文件内容、`git diff` 和相关验证结果。
