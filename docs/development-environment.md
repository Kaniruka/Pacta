# 开发环境配置

## 当前状态

仓库目前只有规格和设计文档，没有 `pubspec.yaml`、`lib/main.dart`、平台工程、Supabase 迁移或应用测试。根目录 `.env` 是后续 Flutter 工程的配置约定，目前没有代码读取它；创建文件不代表应用或云端已经可以运行。

技术栈依据 ADR 0001 和 0003：Flutter/Dart、Material 3、Riverpod、Drift/SQLite、Supabase Auth/PostgreSQL/RLS。Riverpod 和 Drift 是未来 `pubspec.yaml` 中的依赖，不需要 API Key；设备日历需要平台权限，当前也没有云日历 API Key 的需求。

## 客户端配置

本次已创建被 Git 忽略的 `.env`。新克隆仓库时，仅在该文件不存在时执行：

```powershell
if (!(Test-Path -LiteralPath .env)) { Copy-Item -LiteralPath .env.example -Destination .env }
```

| 变量 | 内容 | 何时需要 |
| --- | --- | --- |
| `SUPABASE_URL` | 开发用 Supabase 项目的 URL | 登录和云端同步 |
| `SUPABASE_PUBLISHABLE_KEY` | 同一项目的 publishable key，或兼容的旧 anon key | 登录和云端同步 |

从 Supabase 项目的 Connect 面板获取真实值。模板留空，避免将占位值误认为可连接的服务。

2026-09-14 检查：当前本机根目录 `.env` 已填写上述两项，`SUPABASE_URL` 指向 Supabase 云端项目（`*.supabase.co`）。本次仅检查配置是否填写及地址类型，尚未验证 key 与项目是否匹配、网络连接或远端数据库状态。实际值只保留在被 Git 忽略的 `.env` 中，不复制到开发文档或模板。

Flutter 工程建立后，从仓库根目录传入配置：

```powershell
flutter pub get
flutter run --dart-define-from-file=.env
```

Flutter 不会自动加载 `.env`。应用初始化代码需要以 `const String.fromEnvironment('SUPABASE_URL')` 和 `const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY')` 读取编译期配置，再传给所选版本的 Supabase Flutter SDK。连接云端前应校验必填值和 URL；缺失时显示明确的配置错误。修改 `.env` 后重新运行上述命令，不依赖热重载。

以上是后续接入要求，尚未实现。纯界面和领域逻辑开发可以先使用本地存储或测试替身，但仓库当前还没有实现可用的离线开发模式。

客户端编译期配置可以从产物中提取。此文件只用于客户端公开配置，不可放入 `service_role`、`sb_secret_...`、数据库密码、Supabase access token 或签名材料。后台注册资格与用户管理操作需要可信服务端；部署凭据放入服务端环境或 CI secrets，不能随 `--dart-define-from-file` 传给客户端。

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

2026-09-14 已确定：本项目使用云端 Supabase 进行开发，Flutter 客户端在本机运行，通过根目录 `.env` 连接云端开发项目。日常开发不以本地 Supabase 实例或 Docker 为前提。

当前两项配置已为未来客户端接入准备好。下一步是创建 Flutter 工程并接入编译期配置，以及实现、配置和验证数据库表、迁移、RLS 与管理员授予注册资格的流程；客户端 key 不替代这些工作。数据库结构变更应保留为仓库中的迁移文件，后续按云端迁移与部署需要安装 Supabase CLI。若实际登录流程需要 Auth 深链，则在应用标识和流程确定后，同时配置平台工程与 Supabase redirect allow list。

仅在以后明确需要完全本地的后端时，再安装 Supabase CLI 和 Docker 兼容运行时，初始化本仓库的 Supabase 配置并使用本地实例给出的 URL/key。当前仓库没有 `supabase/config.toml`，本地后端不属于当前开发前置步骤。

## 参考

- [Supabase Flutter 接入](https://supabase.com/docs/guides/getting-started/quickstarts/flutter)
- [Supabase 本地开发工作流](https://supabase.com/docs/guides/local-development/cli-workflows)
- [Dart 编译期环境声明](https://dart.dev/libraries/core/environment-declarations)

本机 Flutter 工具源码也确认支持 `--dart-define-from-file` 读取 `.env` 文件。
