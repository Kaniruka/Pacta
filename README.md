# Pacta

Pacta 是基于 Flutter 的自我调节应用，用任务、专注链和国策树记录行动与进展。当前承诺支持 Android 和 Windows；客户端使用 Drift/SQLite 保存本地状态，并通过 Supabase Auth、PostgreSQL 和 RLS 同步与隔离用户数据。

## 新成员接入

1. 克隆仓库并进入项目目录：`git clone https://github.com/Kaniruka/Pacta.git`、`cd Pacta`。
2. 安装满足 `pubspec.yaml` 要求的 Flutter/Dart SDK，以及目标平台的工具链。运行 `flutter doctor -v` 检查环境；Android 需要 Android SDK，Windows 构建需要 Visual Studio 的 C++ 桌面开发组件。详细环境记录见[开发环境说明](docs/development-environment.md)。
3. 获取团队开发用 Supabase 项目的 **Project URL** 和 **publishable key**，在仓库根目录运行 `Copy-Item .env.example .env`，然后填写 `.env` 中的两个变量。`.env` 被 Git 忽略；它仅用于传递可公开的客户端配置，不要放数据库密码、`service_role`/secret key、管理员密码或测试账号密码。
4. 安装依赖并运行应用：

   ```powershell
   flutter pub get
   flutter devices
   flutter run -d windows --dart-define-from-file=.env
   # 或将 windows 换成 flutter devices 显示的 Android 设备 ID
   ```

   修改 `.env` 后重新运行应用，使新的编译期配置生效。未配置 URL 或 key 时，应用无法连接云端登录与同步。

5. 提交代码前运行 `flutter analyze` 和 `flutter test`。涉及平台权限、日历或通知的改动，还应在相应设备上验证。

项目术语见 [CONTEXT.md](CONTEXT.md)，行为与验收依据见[核心规格](docs/spec-focus-loop-and-core-shell.md)和[验收矩阵](docs/acceptance-matrix-20260914.md)，架构决定见 [ADR](docs/adr/)。需求与实施记录使用 GitHub Issues。

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

4. 部署两个管理员 Edge Function：

   ```powershell
   pnpm exec supabase functions deploy admin-reset-user-password
   pnpm exec supabase functions deploy admin-purge-user
   ```

   函数代码使用 Supabase 托管运行时注入的服务端环境变量。不要把服务端密钥写入 `.env`、Flutter 构建参数或仓库；函数的授权与生命周期细节见 [Supabase 说明](supabase/README.md)。

5. 在 Supabase Auth 后台创建首个管理员用户，确认其邮箱后取得该用户的 UUID。在 SQL Editor 中以项目管理员身份执行以下语句，将**实际 UUID** 替换占位符：

   ```sql
   insert into public.app_admins (user_id)
   values ('<管理员的 Auth User UUID>');
   ```

   然后以此账号登录 Pacta，在管理员界面向指定邮箱发放注册资格。普通用户获得资格后，才能用该邮箱和密码注册。`app_admins` 的首次写入是可信后台操作，普通客户端不能自行授予管理员权限。

6. 用至少一个非管理员账号验收注册、登录与数据隔离；在隔离测试项目验证权限和 RLS。相关 SQL 探针位于 `supabase/tests/`，执行前先阅读 [Supabase 说明](supabase/README.md) 中的测试前提。

## 构建客户端

构建时仍需传入所部署项目的客户端配置：

```powershell
flutter build apk --dart-define-from-file=.env
flutter build windows --dart-define-from-file=.env
```

Android APK 输出位于 `build/app/outputs/flutter-apk/`。**当前 `android/app/build.gradle.kts` 的 release 配置仍使用调试签名**；对外发布前，须按 [Flutter Android 发布文档](https://docs.flutter.dev/deployment/android)设置正式签名、核对应用 ID 与版本。Windows 构建产物位于 `build/windows/<架构>/runner/Release/`；分发时需要整个 Release 目录及相应 Visual C++ 运行库，详见 [Flutter Windows 分发文档](https://docs.flutter.dev/platform-integration/windows/building)。本仓库尚未提供安装包制作或自动发布流水线。

## 相关资料

- [开发环境与本机配置](docs/development-environment.md)
- [Supabase 迁移、管理员函数和权限验证](supabase/README.md)
- [产品设计](docs/product-design.md)与[核心规格](docs/spec-focus-loop-and-core-shell.md)
- [Supabase CLI 官方部署流程](https://supabase.com/docs/guides/local-development/cli-workflows)与[Edge Function 部署说明](https://supabase.com/docs/guides/functions/deploy)
