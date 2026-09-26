# 开发环境配置

## 当前状态

仓库已包含 Flutter/Dart 客户端、Android/Windows 平台工程、Supabase 迁移和应用测试。T01 的认证实现使用邮箱与密码注册、登录，注册资格由管理员按邮箱发放。根目录 `.env` 只保存本机验收配置，不纳入版本库。

技术栈依据 ADR 0001 和 0003：Flutter/Dart、Material 3、Riverpod、Drift/SQLite、Supabase Auth/PostgreSQL/RLS。Riverpod、Drift 和 Supabase Flutter SDK 已在 `pubspec.yaml` 中声明；设备日历需要平台权限，当前也没有云日历 API Key 的需求。

## 客户端配置

本次已创建被 Git 忽略的 `.env`。新克隆仓库时，仅在该文件不存在时执行：

```powershell
if (!(Test-Path -LiteralPath .env)) { Copy-Item -LiteralPath .env.example -Destination .env }
```

| 变量 | 内容 | 何时需要 |
| --- | --- | --- |
| `SUPABASE_URL` | 开发用 Supabase 项目的 URL | 登录和云端同步 |
| `SUPABASE_PUBLISHABLE_KEY` | 同一项目的 publishable key，或兼容的旧 anon key | 登录和云端同步 |
| `TEST_REGISTRATION_EMAIL` | 本地注册验收使用的邮箱 | 仅本机测试，不由客户端读取 |
| `TEST_ADMIN_EMAIL` | 本地 Supabase 管理员验收账号 | 仅本机测试，不由客户端读取 |
| `TEST_ADMIN_PASSWORD` | 本地管理员验收密码 | 仅本机测试，禁止提交、记录到公开文档或传给 Flutter |

从 Supabase 项目的 Connect 面板获取真实值。模板留空，避免将占位值误认为可连接的服务。

2026-09-22 检查：当前本机根目录 `.env` 已填写上述变量，`SUPABASE_URL` 指向 Supabase 云端项目（`*.supabase.co`）。应用会在启动时通过 `--dart-define-from-file=.env` 读取 `SUPABASE_URL` 和 `SUPABASE_PUBLISHABLE_KEY`；`TEST_*` 变量仅供人工验收脚本或控制台操作使用。实际值只保留在被 Git 忽略的 `.env` 中，不复制到开发文档或模板。

从仓库根目录传入配置：

```powershell
flutter pub get
flutter run --dart-define-from-file=.env
```

Flutter 不会自动加载 `.env`。应用初始化代码需要以 `const String.fromEnvironment('SUPABASE_URL')` 和 `const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY')` 读取编译期配置，再传给所选版本的 Supabase Flutter SDK。连接云端前应校验必填值和 URL；缺失时显示明确的配置错误。修改 `.env` 后重新运行上述命令，不依赖热重载。

客户端已实现未配置 Supabase 时的明确错误提示和本地任务缓存；联网同步失败不会清空本地业务数据。纯界面和领域逻辑测试可继续使用测试替身。

客户端编译期配置可以从产物中提取。此文件只用于客户端公开配置，不可放入 `service_role`、`sb_secret_...`、数据库密码、Supabase access token 或签名材料。后台注册资格与用户管理操作需要可信服务端；部署凭据放入服务端环境或 CI secrets，不能随 `--dart-define-from-file` 传给客户端。

`.env` 还可以保存本机验收账号变量，但这些变量不是客户端配置：`TEST_*` 只供人工验收脚本或控制台操作使用。测试密码属于敏感凭据，只保存在被 Git 忽略的本机 `.env`，不要复制到 `.env.example`、提交记录、截图或聊天记录。管理员账号必须先在 Supabase Auth 中确认邮箱，再用该账号登录客户端；`app_admins` 表中的管理员绑定由可信 SQL 迁移初始化，普通客户端不能自行授予管理员权限。

## 工具与平台

2026-09-12 本机检查结果（`flutter doctor -v`）：

| 检查项 | 结果 |
| --- | --- |
| Flutter / Dart | 已安装 3.47.2 / 3.13.2；doctor 提示 Scoop 版本目录与 `current` 路径不一致，建议统一 PATH 到 `current/bin` |
| Windows / Web | Visual Studio C++ 工具链、Windows SDK 和 Chrome 检查通过 |
| Android | SDK 36.1.0 已发现，但缺少 cmdline-tools，许可证状态未知 |
| 网络资源 | doctor 检查通过 |
| Git / gh / Java | PATH 中可找到；尚未验证 GitHub 登录或具体构建兼容性 |
| Docker / Supabase CLI | 当时 PATH 中未找到；云端客户端连接不需要二者，后续迁移或部署工作流可按需安装 CLI |

Android 的下一步：在 Android Studio 的 SDK Manager → SDK Tools 中安装 Android SDK Command-line Tools，然后运行 `flutter doctor --android-licenses` 阅读并接受许可证，再运行 `flutter doctor -v` 复查。根目录 `.env` 无法替代 SDK 安装或许可证处理。

2026-09-13 更新：已从 Google 官方下载 Command-line Tools（15859902），核对官网 SHA-256 后安装到现有 SDK 的 `cmdline-tools/latest`。`flutter doctor -v` 已识别工具、Android 36.1 平台、36.1.0 build-tools 和 Android Studio 自带 JDK 21。用户接受许可证后，已再次运行 `flutter doctor -v`：Android toolchain 检查通过，显示 `All Android licenses accepted.`。目前尚无已连接的 Android 真机或运行中的模拟器；Windows、Chrome 和网络检查通过。仍有 Flutter/Dart 的 Scoop 版本目录与 `current` 路径提示。

- 基础工具：Flutter SDK（包含 Dart）、Git；工程创建时确定 SDK 约束并提交应用的依赖锁文件。
- Android：Android SDK、command-line tools、平台构建工具、兼容的 JDK，以及模拟器或真机；用 `flutter doctor -v` 检查，按结果处理 licenses。
- Windows 桌面：Visual Studio 的 Desktop development with C++ 工作负载和 Windows SDK。
- iOS/macOS：需要 macOS 和 Xcode，不能在本机 Windows 上完成原生构建。
- GitHub Issues 工作流使用 `gh`，不影响客户端本地运行。

依据 ADR 0003，当前承诺平台为 Android 和 Windows，首轮验收使用 Android 15 和 Windows 11；更早系统版本需兼容性验证后确定。

## Supabase 开发路径

2026-09-22 已确定：本项目使用云端 Supabase 进行开发，Flutter 客户端在本机运行，通过根目录 `.env` 连接云端开发项目。日常开发不以本地 Supabase 实例或 Docker 为前提。远端 Auth 已启用 Email；为满足 T01 的无验证邮件约束，Supabase 控制台的 Confirm email 必须关闭。

数据库结构变更保留为仓库中的迁移文件；管理员授予注册资格、资格原子消费、RLS 和用户隔离由远端 Supabase 真实验证。客户端 key 不替代可信服务端权限。当前注册流程不使用 Auth 深链，因为 T01 不发送邮箱验证或恢复消息。

仅在以后明确需要完全本地的后端时，再安装 Supabase CLI 和 Docker 兼容运行时，初始化本仓库的 Supabase 配置并使用本地实例给出的 URL/key。当前 `supabase/config.toml` 仅声明云端管理员密码重置 Edge Function 的 JWT 校验，不配置本地 Supabase 服务；本地后端不属于当前开发前置步骤。

## 参考

- [Supabase Flutter 接入](https://supabase.com/docs/guides/getting-started/quickstarts/flutter)
- [Supabase 本地开发工作流](https://supabase.com/docs/guides/local-development/cli-workflows)
- [Dart 编译期环境声明](https://dart.dev/libraries/core/environment-declarations)

本机 Flutter 工具源码也确认支持 `--dart-define-from-file` 读取 `.env` 文件。
