<div align="center">

# Pacta

**把每天过成一条可回看的承诺链：任务、专注、国策与日程落在同一条时间线上。**

[![Flutter checks](https://github.com/Kaniruka/Pacta/actions/workflows/flutter-checks.yml/badge.svg?branch=master)](https://github.com/Kaniruka/Pacta/actions/workflows/flutter-checks.yml)
[![Release](https://github.com/Kaniruka/Pacta/actions/workflows/release.yml/badge.svg)](https://github.com/Kaniruka/Pacta/actions/workflows/release.yml)
[![version](https://img.shields.io/badge/version-0.3.0%2B3-blue)](pubspec.yaml)
[![license](https://img.shields.io/badge/license-GPL--3.0-blue)](LICENSE)

[简体中文](README.md) · [English](README.en.md)

</div>

Flutter 编写的自我调节应用，支持 Android 与 Windows。本地用 Drift/SQLite 保存全部状态，登录后经 Supabase Auth、PostgreSQL 与 RLS 在设备间同步，数据按用户隔离。

## 核心模块

| 模块 | 源码 | 作用 |
| --- | --- | --- |
| 看板 | `lib/src/board` | 今日承诺、国策提示与专注入口 |
| 专注链 | `lib/src/focus` | 计时、链路历史、时钟跳变核对 |
| 国策树 | `lib/src/national_focus` | 国策卡、检查点与提醒 |
| 计划 | `lib/src/plan`、`lib/src/schedules` | 目标、任务与日程安排 |
| 我的 | `lib/src/profile`、`lib/src/sync` | 账号、同步状态、Cloud Snapshot 历史 |

## 快速开始

需要 Flutter 3.47.2 / Dart 3.13.2、Python 3 与 JDK 17；Windows 构建需 Visual Studio 的 C++ 桌面组件，Android 构建需 Android SDK。先跑 `flutter doctor -v`。

```powershell
git clone https://github.com/Kaniruka/Pacta.git
cd Pacta
Copy-Item .env.example .env          # 填 SUPABASE_URL 与 SUPABASE_PUBLISHABLE_KEY
python scripts/fetch_misans.py       # 首次：从小米官方拉取并校验 MiSans 字体
python scripts/pacta_build.py run -d windows
```

`scripts/pacta_build.py` 是唯一推荐的运行与构建入口：它只把 `SUPABASE_URL`、`SUPABASE_PUBLISHABLE_KEY` 写进临时 JSON（构建结束即删除）再交给 `--dart-define-from-file`，原始 `.env` 永不进入 Flutter 命令行。

| 命令 | 作用 |
| --- | --- |
| `python scripts/pacta_build.py` | 交互式菜单（也可显式传 `interactive` 或 `-i`），按提示选择运行、打包或生成签名 |
| `python scripts/pacta_build.py run -d windows` | 桌面调试；`-d android` 自动取第一台 Android 设备，或 `-d <device-id>` |
| `python scripts/pacta_build.py run -d emulator-5554 --profile` | 指定设备与构建模式（`--debug`/`--profile`/`--release`） |
| `python scripts/pacta_build.py build --target apk --release --split-per-abi` | 分 ABI 的 APK |
| `python scripts/pacta_build.py build --target appbundle --release` | Google Play AAB |
| `python scripts/pacta_build.py build --target windows --release` | Windows Release |
| `python scripts/pacta_build.py build --target all --release --require-release-signing` | 全平台，缺正式签名即失败 |
| `python scripts/pacta_build.py build --target apk --dry-run` | 只打印脱敏执行计划，不执行任何命令 |
| `python scripts/pacta_build.py init-keystore` | 生成本机 Android Release 签名 |

白名单之外的键（`SUPABASE_SECRET_KEY`、`SUPABASE_SERVICE_ROLE_KEY`、`SUPABASE_ACCESS_TOKEN`、`TEST_*`、`ANDROID_KEYSTORE_*`）一律不注入、不写入临时文件、不出现在日志里；构建缺少两个客户端键时给出中文报错并以退出码 `2` 结束。

## Android Release 签名

```powershell
python scripts/pacta_build.py init-keystore
```

生成两个被 `.gitignore` 忽略的文件：`android/app/upload-keystore.jks` 与 `android/key.properties`（`storeFile=upload-keystore.jks`、24 位随机字母数字密码、`keyAlias=pacta-upload`）。脚本只报告路径与待填写的 Secret 名，从不打印密码；已存在时默认不覆盖，需要 `--force`。

`android/app/build.gradle.kts` 的取值顺序是 `android/key.properties` → 环境变量 `ANDROID_KEYSTORE_PATH` / `ANDROID_KEYSTORE_PASSWORD` / `ANDROID_KEY_ALIAS` / `ANDROID_KEY_PASSWORD`。信息齐全才创建 `signingConfigs.release`；本地缺签名时回退 debug 签名并给出明显告警，加 `--require-release-signing`（或 `-PrequireReleaseSigning=true`）则在 Gradle 配置期直接失败。

### GitHub Secrets

| Secret | 内容 |
| --- | --- |
| `SUPABASE_URL` | Supabase 项目 URL |
| `SUPABASE_PUBLISHABLE_KEY` | publishable key |
| `ANDROID_KEYSTORE_BASE64` | 下一行命令的输出 |
| `ANDROID_KEYSTORE_PASSWORD` | `key.properties` 的 `storePassword` |
| `ANDROID_KEY_ALIAS` | `key.properties` 的 `keyAlias`（默认 `pacta-upload`） |
| `ANDROID_KEY_PASSWORD` | `key.properties` 的 `keyPassword` |

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("android/app/upload-keystore.jks"))
```

`release.yml` 在 Tag 构建时缺任一签名 Secret 会显式失败；手动 `workflow_dispatch` 缺签名时跳过 Android 任务并说明原因，Windows 产物照常构建。

## 自行部署 Supabase

1. 新建 Supabase 项目，Auth 开启 Email 登录、关闭 **Confirm email**；注册资格由数据库白名单控制，应用不发验证邮件也不做自助找回。
2. 从项目 Connect 页取得 Project URL 与 publishable key，填入本机 `.env`。
3. 推送数据库迁移：

   ```powershell
   pnpm install --frozen-lockfile
   pnpm exec supabase login
   pnpm exec supabase link --project-ref <project-ref>
   pnpm exec supabase db push
   ```

4. `python scripts/pacta_admin.py` 创建第一个账号并发放注册资格。该工具只用 `SUPABASE_SECRET_KEY`（项目主 CLI 权限），**绝不进入客户端**。
5. 用普通用户验收注册、登录与数据隔离；权限与 RLS 探针位于 `supabase/tests/`。

细节见 [Supabase 说明](supabase/README.md) 与 [Supabase CLI 流程](https://supabase.com/docs/guides/local-development/cli-workflows)。

## 版本与 Tag

- 唯一真源是 `pubspec.yaml` 的 `version: MAJOR.MINOR.PATCH+BUILD`，`windows/runner/Runner.rc` 的 `#else` 回退宏同步。
- `MAJOR` 不兼容变更；`MINOR` 新增或重构一级目的地、结构版本升级；`PATCH` 修复与体验收敛；`+BUILD` 单调递增，永不随进位归零。
- 只在 `master` 发布节点打 `vMAJOR.MINOR.PATCH` Annotated Tag。`release.yml` 校验 Tag 与 `pubspec.yaml` 一致（仅忽略 `+BUILD`），不一致即失败。
- `0.x` 为测试阶段：接口与数据格式仍会变动，`v0.*` 的 GitHub Release 一律标记为 prerelease。

## 提交前检查

```powershell
flutter analyze
flutter test
python scripts/check_repository_hygiene.py
python -m unittest discover -s scripts -p "test_*.py"
```

## 许可

[GPL-3.0](LICENSE)。MiSans 字体按小米官方授权分发，说明见 [assets/fonts/README.md](assets/fonts/README.md)。
