# Pacta 维护代理指南

适用于全仓库。先查 `git status`；只改任务相关文件，保留他人未提交改动。

## 先读取与任务有关的依据

- 领域、行为、数据边界：先读 `GLOSSARY.md`、相关已接受 ADR；沿用术语，需求与 ADR 冲突时先指出。行为/验收见 `docs/spec-focus-loop-and-core-shell.md`、`docs/acceptance-matrix-20260914.md`；领域文档约定见 `docs/agents/domain.md`。
- UI：先读 `docs/product-design.md`、ADR 0004、[UI 与技能规范](docs/agents/ui.md)，按任务调用技能。技术栈/平台读 ADR 0003；隔离/注册/管理读 ADR 0001；任务/设备日历读 ADR 0002。
- 环境、云连接、测试凭据：读 `docs/development-environment.md`；Supabase 部署/管理函数读 `supabase/README.md`。
- 需求跟踪：用 `gh` 读写 GitHub Issues，操作见 `docs/agents/issue-tracker.md`；分诊标签 `needs-triage`、`needs-info`、`ready-for-agent`、`ready-for-human`、`wontfix` 的含义见 `docs/agents/triage-labels.md`。

## 实施与验证

- 代码/测试：`lib/`、`test/`；平台验收：`integration_test/`；迁移、RLS 脚本、Edge Functions：`supabase/`。行为改动同步检查测试和文档，只报告实际命令、平台及结果。
- Dart 改动：先对改动文件 `dart format`，再 `flutter analyze` 和相关 `flutter test`；跨模块改动跑完整测试。Drift 表变更按需运行 `dart run build_runner build --delete-conflicting-outputs` 并检查生成差异。
- 同步/身份/权限/数据库改动：核查离线恢复、重复同步、跨用户隔离及 RLS，在隔离项目验证 SQL/真实服务边界。原生权限、通知、日历须有 Android/Windows 对应证据，单元测试不能替代。
- 设备验收：可按任务启动现有 Android 模拟器、用 ADB 安装测试 APK，或在 Windows 构建/安装/运行测试版本；保留用户数据。路径、命令见[环境文档](docs/development-environment.md)，按实际平台取证。
- 客户端仅用公开 Supabase URL 和 publishable/anon key；服务端密钥、管理员凭据、真实测试账号留在受保护环境，提交前检查无泄漏。
