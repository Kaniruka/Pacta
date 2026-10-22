# Issue #62：发布交付与验收记录

日期：2026-10-22。基线 `a3c78ce`，开始时工作区干净。此页记录实际执行结果，未完成项不能由前序票证据或模拟仓储测试代替。

## 交付

- [部署与分发步骤](issue-62-deployment.md)：项目绑定、迁移、服务、授权回调、有效期、重新同意、撤销、公开客户端配置及 skill 安装包。
- `scripts/check_national_focus_deployment.py`：只读检查公开 key 被目标 Auth 接受，以及 App 派生 URL、resource、issuer、DCR、PKCE、scope 和未授权 401；可从本地配置提取仅含两个公开字段的构建 JSON，拒绝 server key 和覆盖既有文件。
- `scripts/package_national_focus_skill.py`：四文件白名单生成固定 ZIP 和 SHA-256，重复打包与逐文件比对见 [交付检查](evidence/issue62-delivery-audit.md)。
- access SQL 探针不再挑选普通用户作夹具，改为事务内随机身份；增加新同意续期且不复活旧撤销 token 的回归。
- 真实原生验收脚本与集成测试分别驱动 App UI、生产仓储、已部署 MCP 和实际 Codex 工具；可选 Android 网络中断，结束恢复原网络并清理身份；明确区分模型运行和 `--skip-analysis`。

## 本轮主 agent 验证

- `python3 scripts/check_national_focus_deployment.py --config .env --public-output .scratch/issue62-public.json`：真实公开 HTTPS 检查通过；仅导出 `SUPABASE_URL`、`SUPABASE_PUBLISHABLE_KEY`。临时输出不提交。
- Python 临时配置用例：公开字段白名单、旧 anon JWT 兼容、server-role JWT、secret key、空值和错误 key 拒绝，全部通过。
- `python3 -m py_compile scripts/check_national_focus_deployment.py scripts/package_national_focus_skill.py`：通过。
- `cmd.exe /c flutter test --reporter compact`：263 passed。
- 收尾格式化（`dart format`）、`flutter analyze` 再跑：无问题；完整 `flutter test --reporter compact` 再跑仍263 passed（21秒）。三份 Python 脚本 `py_compile`、证据 JSON 解析、凭据模式扫描及 `git diff --check` 通过。
- `cmd.exe /c node --experimental-transform-types --test supabase/functions/national-focus-mcp/handler.test.ts supabase/functions/national-focus-mcp/history.test.ts`：25 passed。包括无快照/旧格式/服务错误、revision 变化、历史分页、同用户范围和每次请求重查委托。
- `cmd.exe /c flutter test integration_test/national_focus_ai_device_test.dart -d emulator-5554 --no-uninstall`：Android 15/API35，1 passed，测试43秒。真实平台 UI，内存业务仓储和授权替身；两个入口、复制、显式同意和撤销、同步预览及覆盖确认通过，不把它描述为真实公网授权。
- `cmd.exe /c flutter test integration_test/national_focus_ai_device_test.dart -d windows`：Windows 11 10.0.22631.2506，1 passed，测试40秒；相同流程通过。
- `cmd.exe /c flutter build apk --debug --dart-define-from-file=.scratch/issue62-public.json` 与 `adb -s emulator-5554 install -r .../app-debug.apk`：成功，构建48.5秒，恢复普通应用入口；未卸载、清除业务数据或传入测试账号/服务端配置。App 版本 `1.0.0+1`，Flutter/Dart `3.47.2/3.13.2`。
- 主 agent 实际查看 [真实 Android 引导截图](evidence/issue62-android-real-guide.png)：深色主题、文字换行与滚动视口可读，底部授权卡随页面继续滚动；无请求码/密钥，未见该视口溢出。不是平板或完整无障碍验收。

Android 构建仍提示既有 `flutter_timezone` Kotlin Gradle Plugin 未来兼容警告，当前构建与测试成功。未验证平板、键盘全流程或屏幕阅读器，不声明其兼容性。

## 独立审查

Standards 审查对当前 diff 与新文件独立检查：修复验收脚本的错误表名/工具名、异常路径资源清理、国策日日期边界，以及清理失败必须返回失败。Spec 审查分别保留独立项目、原生 OAuth 发起方式与真实网络恢复的证据边界，不以已有单元测试抵消缺口。主 agent 复核源码和实际结果；本轮测试过程中发现的定位、fixture时钟和CLI传参问题属于新增验收工具，修复后须重跑到完整成功。

apple-design 独立审查采用 Android/Windows 跨平台原则，依据 `layout.md › Visual hierarchy / Adaptability`、`accessibility.md › Vision`、`scroll-views.md › Best practices` 和 `generative-ai.md › Transparency / Privacy`。单滚动容器、语义主题、只读范围及状态分组未见阻断缺陷；截图与已有窄屏/大字号测试不能证明精确对比度、触点尺寸、TalkBack、桌面焦点或平板兼容。

## 本轮独立项目原生闭环

以下均由主 agent 执行，目标为独立临时 Free 项目 `bhlbrswfolrcvrhfuilq`。App `1.0.0+1`，Flutter/Dart `3.47.2/3.13.2`，Codex CLI `0.163.0-alpha.10.2`。每轮独立随机身份，临时 SQLite，未使用普通用户数据。细节和复现入口见 [演示记录](issue-62-demo.md)。

- Windows 11：`cmd.exe /c flutter test integration_test/national_focus_ai_real_cross_device_test.dart -d windows --dart-define-from-file=.dart_tool/issue62-demo-control.json`，**1 passed，44秒**；原生构建19.3秒。真实 UI 手动上传、覆盖确认、同意、授权状态与撤销；桌面 Codex app-server 读取当前树/库/失败冻结详情，未上传编辑不可见，再次上传为 revision 2，旧 revision 返回 `snapshot_changed`，App 撤销后六工具及 initialize/tools/list 全拒绝。[证据](evidence/issue62-windows-native-flow.json)。
- Android 15/API35，重新启动 `PactaT24Secondary` 后实际序列号 `emulator-5554`：同一测试加 `--no-uninstall`，**1 passed，47秒**，构建18.8秒、安装1.1秒。桥接加 `--android-device emulator-5554`；实际关闭 Wi-Fi/移动数据后，App 授权刷新显示“无法读取授权状态”；恢复原网络后授权可重新读取。恢复及三次重复工具请求前后云端 snapshot 整行 digest 相同，随后第二次上传与撤销仍通过。[证据](evidence/issue62-android-native-flow.json)。

独立项目回放显式跳过新模型调用（证据 `model_analysis_skipped=true`），实际 Codex 工具读取没有跳过。此前本轮在共享项目的随机身份上已完成真实模型结构分析及失败复盘，主 agent 实读报告并核对五次成功 MCP 工具与引用；同一较早流程 App 实际撤销后八项拒绝由 host 补查通过。报告与后续原生测试分别取证，不宣称它们是同一条全成功的自动测试。原报告被旧验收脚本的失败重跑删除，保留工具 trace 和[人工复核摘要](evidence/issue62-codex-analysis-review.md)，已修复为成功后才替换正式报告；额度耗尽的后续模型运行明确失败，不计通过。

维护场景由设备上的生产仓储建立，上传、同意和撤销驱动真实 UI；本轮 OAuth 由协调脚本 DCR/PKCE 发起，原生 `codex mcp login` 浏览器流程承接 #57 的独立证据，不重复宣称本轮验证。前序 #57–#61 均已关闭且保有独立证据。

## 隔离部署与清理

真实部署、三组 rollback SQL、新同意续期及拒绝验证见 [服务验收](issue-62-service-validation.md)。在用户只授权免费资源的前提下，通过官方组织详情接口确认 `plan=free`，创建第二个 nano 项目，应用全部26份迁移、部署 ACTIVE v1、执行三组 SQL 与18次 HTTP 拒绝检查，均通过。未升级计划或建立付费资源。

两平台结束后，临时身份/资格/client 清理成功；临时项目已删除，GET 返回404，项目列表仅保留原开发项目 `wmutsplyqulanwkqtqhb` 且健康。独立项目配置和数据库口令文件已删除；根 `.env` 未改。共享项目的本轮 fixture 也复查为0、Auth恢复原2个。没有遗留需要用户手工清理的测试资源。

收尾用原开发项目的两字段公开 JSON 重建普通 Android Debug APK（13.5秒）和 Windows Debug 应用（11.9秒），均成功；避免产物仍指向已删除项目或测试入口。Android `adb install -r` 恢复普通入口，Wi-Fi/mobile_data均为原启用状态1，已删除本轮 ADB reverse 30348；未卸载、清除数据或擦除 AVD。
