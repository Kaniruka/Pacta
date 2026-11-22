# Pacta

Pacta 是基于 Flutter 的自我调节应用，用任务、专注链和国策树记录行动与进展。当前承诺支持 Android 和 Windows；客户端使用 Drift/SQLite 保存本地状态，并通过 Supabase Auth、PostgreSQL 和 RLS 同步与隔离用户数据。

## 新成员接入

1. 克隆仓库并进入项目目录：`git clone https://github.com/Kaniruka/Pacta.git`、`cd Pacta`。
2. 安装满足 `pubspec.yaml` 要求的 Flutter/Dart SDK，以及目标平台的工具链。运行 `flutter doctor -v` 检查环境；Android 需要 Android SDK，Windows 构建需要 Visual Studio 的 C++ 桌面开发组件。
3. 获取团队开发用 Supabase 项目的 **Project URL** 和 **publishable key**，在仓库根目录运行 `Copy-Item .env.example .env`，然后填写 `.env` 中的两个客户端变量。`.env` 被 Git 忽略；客户端只读 `SUPABASE_URL` 与 `SUPABASE_PUBLISHABLE_KEY`，不要放入数据库密码、管理员密码或测试账号密码。项目主 CLI 可另外从该文件读取 `SUPABASE_SECRET_KEY`（优先放在独立进程环境变量），但**含 secret key 的 `.env` 绝对不能传给 `--dart-define-from-file`**，详见下方「自行部署云端」第 4 步。
4. 安装依赖并运行应用：

   ```powershell
   python scripts/fetch_misans.py
   flutter pub get
   flutter devices
   flutter run -d windows --dart-define-from-file=.env
   # 或将 windows 换成 flutter devices 显示的 Android 设备 ID
   ```

   首次构建需安装 Python 3 并运行上述脚本，从小米官方下载、校验内置 MiSans 字体；已有正确文件时无需联网。字体许可与说明见 [MiSans](assets/fonts/README.md)。修改 `.env` 后重新运行应用，使新的编译期配置生效。未配置 URL 或 key 时，应用无法连接云端登录与同步。

5. 提交代码前运行 `flutter analyze` 和 `flutter test`；Python 侧运行 `python scripts/check_repository_hygiene.py`（仓库卫生检查）与 `python -m unittest discover -s scripts -p "test_*.py"`（与 CI 同一命令）。涉及平台权限、日历或通知的改动，还应在相应设备上验证。

## 国策树交互与预览

样例预览直接运行仓库内入口：`flutter run -t tool/national_focus_reference_demo.dart`（50 节点图片样例）或 `flutter run -t tool/national_focus_ui_review_demo.dart`（4 节点隔离 UI 预览）；两者使用内存数据库，不读取 `.env`。

## 自行部署云端

以下步骤适用于**新建的、由你管理的云端 Supabase 项目**。先准备 Node.js 20+ 和 pnpm；本仓库的 `package.json` 与 `pnpm-lock.yaml` 锁定了 Supabase CLI。日常客户端开发只需连接已有项目，不需要在本机运行 Docker 或 Supabase 服务。

1. 创建 Supabase 项目，在 Auth 设置中启用 Email 与用户注册，关闭 **Confirm email**。Pacta 由数据库中的注册资格限制可注册邮箱；应用不发送验证邮件，也不提供自助密码找回。记录该项目的 project ref，并用它替换下方命令中的 `<project-ref>` 占位符。
2. 从项目 Connect 页面取得 Project URL 与 publishable key，填入本机 `.env`：

   ```dotenv
   SUPABASE_URL=https://<project-ref>.supabase.co
   SUPABASE_PUBLISHABLE_KEY=<publishable-key>
   ```

3. 在仓库根目录安装 CLI、登录并关联目标项目。先预览迁移，再执行数据库迁移：

   ```powershell
   pnpm install --frozen-lockfile
   pnpm exec supabase login
   pnpm exec supabase link --project-ref <project-ref>
   pnpm exec supabase db push --dry-run
   pnpm exec supabase db push
   ```

   `db push` 会把 `supabase/migrations/` 中尚未应用的迁移推送到关联项目。执行前核对 project ref 和预览清单；已有数据的项目应先备份并核对迁移历史。

4. 账号治理统一在项目主本机终端完成，不需要部署管理员 Edge Function，也不需要写入 `app_admins`：

   ```powershell
   python scripts/pacta_admin.py
   ```

   [`scripts/pacta_admin.py`](scripts/pacta_admin.py) 是**项目主直连**工具：从进程环境变量或仓库 `.env` 读取 `SUPABASE_URL` 与 `SUPABASE_SECRET_KEY`（兼容旧名 `SUPABASE_SERVICE_ROLE_KEY`），直接调用 GoTrue Admin 与 PostgREST，不要求管理员邮箱／密码登录。能力覆盖全量用户与生命周期摘要、新建账号、注册白名单发放／撤销、停用／恢复、重置密码、查看／清理云端业务快照，以及即时彻底注销；交互菜单与同名子命令一一对应，均支持 `--json` 与 `--yes`。命令清单与权限边界见 [Supabase 说明的项目主终端工具](supabase/README.md#project-owner-terminal-tool)。

   > **安全**：`.env` 若写入了 `SUPABASE_SECRET_KEY`，**绝对不能**把该文件传给 `--dart-define-from-file`（包括客户端发布构建）：secret key 无法在客户端二进制里保密，客户端只使用 `SUPABASE_URL` 与 publishable key。该口径与 [`.env.example`](.env.example)、[Supabase 说明](supabase/README.md) 完全一致。

5. 用 `create-user`（或交互菜单）创建第一个账号，再用 `grant` 向其他邮箱发放注册资格。普通用户获得资格后，才能用该邮箱和密码注册；资格被撤销后未消费即失效，已彻底注销的邮箱重新注册会得到全新身份，不继承旧数据。

6. 用至少一个非管理员账号验收注册、登录与数据隔离；在隔离测试项目验证权限和 RLS。相关 SQL 探针位于 `supabase/tests/`，执行前先阅读 [Supabase 说明](supabase/README.md) 中的测试前提。

## 构建客户端

构建时仍需传入所部署项目的客户端配置：

```powershell
python scripts/fetch_misans.py
flutter build apk --dart-define-from-file=.env
flutter build windows --dart-define-from-file=.env
```

Android APK 输出位于 `build/app/outputs/flutter-apk/`。**当前 `android/app/build.gradle.kts` 的 release 配置仍使用调试签名**；对外发布前，须按 [Flutter Android 发布文档](https://docs.flutter.dev/deployment/android)设置正式签名、核对应用 ID 与版本。Windows 构建产物位于 `build/windows/<架构>/runner/Release/`；分发时需要整个 Release 目录及相应 Visual C++ 运行库，详见 [Flutter Windows 分发文档](https://docs.flutter.dev/platform-integration/windows/building)。本仓库尚未提供安装包制作或自动发布流水线。

版本迭代以 `pubspec.yaml` 中的 `version: MAJOR.MINOR.PATCH+BUILD` 为准，并同步更新 `windows/runner/Runner.rc` 的回退版本宏：破坏性不兼容变更升 `MAJOR`，新增/重构一级功能或升级本地/云端数据结构（如 Drift / Snapshot schema）升 `MINOR`（`PATCH` 归零），缺陷修复与体验微调升 `PATCH`；每次版本变更或分发构建时 `+BUILD` 单调递增且永不归零。正式发布仅在 `master` 节点使用 `vMAJOR.MINOR.PATCH` 格式的 Annotated Tag（特性分支合入后及时清理，日常仅保留 `master`）。

## 相关资料

- [Supabase 迁移、项目主终端工具与权限验证](supabase/README.md)
- [Supabase CLI 官方部署流程](https://supabase.com/docs/guides/local-development/cli-workflows)与[Edge Function 部署说明](https://supabase.com/docs/guides/functions/deploy)
