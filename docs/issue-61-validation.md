# Issue #61：有历史证据的失败复盘

基线：032c292（当前 master）；开始时工作区干净。

## 实现范围

扩展可安装的 `skills/pacta-national-focus-analysis`，保留既有结构分析；App 增加独立可复制失败复盘问题及历史范围说明。无模型 API、业务写入或数据库迁移。

默认历史范围仅约束失败查询；当前树/卡片库及当前规则完整读取。历史按国策日、revision 和游标查询，失败详情来自冻结树，反思与原始原因分开。缺少更早记录、版本或分页未完成必须披露。

skill、真实工具合同合成验证和 App 引导分工并行实现，主 agent 独立复核并执行平台及完整测试，实际结果如下。

## 已执行检查（2026-10-22）

- `cmd.exe /c flutter analyze`：No issues found。
- `cmd.exe /c flutter test --reporter compact`：263 passed。
- `cmd.exe /c flutter test test/national_focus/national_focus_ai_analysis_page_test.dart`：7 passed（执行 agent 记录，完整测试由主 agent 复跑）。
- `cmd.exe /c node --experimental-transform-types --test supabase/functions/national-focus-mcp/handler.test.ts supabase/functions/national-focus-mcp/history.test.ts`：25 passed（主 agent 独立复跑）。
- `python3 /mnt/c/Users/Stray/.codex/skills/.system/skill-creator/scripts/quick_validate.py skills/pacta-national-focus-analysis`：通过；`git diff --check`：通过。
- 独立 Standards 与 Spec 审查：0 项实现缺陷；Spec 要求补齐真实 Codex 调用与发布安装证据，完成情况见后续记录。

页面使用现有 Material 主题、标题层级和单滚动容器。设计复核依据 apple-design Layout / Visual hierarchy、Accessibility / Vision 与 Scroll views / Best practices，转译到 Flutter；窄屏、暗色与2倍字号由 widget 覆盖。原生设备用内存仓储测试替身，不调用真实授权服务或改动云端数据。

## 原生平台验收

- `cmd.exe /c flutter test integration_test/national_focus_ai_device_test.dart -d emulator-5554 --no-uninstall`：Android 15/API35，1 passed，运行43秒；构建111.5秒、安装3.1秒。实测两个入口、三份示例/安装说明复制（含真实系统剪贴板读取断言）、授权/撤销、手动同步预览与覆盖确认。
- `cmd.exe /c flutter test integration_test/national_focus_ai_device_test.dart -d windows`：Windows 11 10.0.22631.2506，1 passed，运行39秒；原生Debug构建64.8秒。相同流程通过。
- 两台模拟器开始时均未安装 `com.pacta.pacta`（`adb shell pm list packages com.pacta`空），本轮安装使用目标5554，无卸载/擦除现有设备数据。主 agent 实际截图检查 Android 引导的结构分析区及授权状态区；无溢出。截图只含合成测试身份，未把它作为失败复盘截图证据。
- Android构建提示既有 `flutter_timezone` Kotlin Gradle Plugin未来兼容警告及SDK XML工具版本警告；当前构建和测试通过。

本票未改变服务、数据库或授权语义；远端真实认证/RLS/跨用户验证沿用 #58/#59，合成合同测试不替代远端部署验收；完整跨设备串联留在 #62。

测试后已用仅含公开 `SUPABASE_URL` / `SUPABASE_PUBLISHABLE_KEY` 的临时JSON执行 `flutter build apk --debug --dart-define-from-file=.dart_tool/issue61-public.json`，成功（19.2秒），并 `adb -s emulator-5554 install -r .../app-debug.apk` 成功，替换测试入口为正常应用。临时JSON已删除；没有传入TEST_*或服务端密钥。

## 真实 Codex 复盘

实际 Codex CLI 0.163.0-alpha.10.2 使用更新 skill 连接本地合成 Store/生产 handler 的 MCP：基线读取同 revision 当前树/卡片库、4页失败及4条冻结详情，完成中文复盘。另一次在第二个历史读取切换 revision2→3，实际返回 `snapshot_changed`，Codex 重取元数据/树/库并重新读完4页与详情，最终只按 revision3 分析。主 agent 复核两个报告的同名ID、历史强化、漏确认、独立/连带、原始原因/反思与不完整历史边界。

完整命令、原始工具trace与语义逐项核对见 [合成验收](evidence/issue61-synthetic-evaluation.md)、[基线报告](evidence/issue61-codex-synthetic-analysis.md)、[revision恢复报告](evidence/issue61-codex-revision-analysis.md)。这是真实客户端调用真实工具合同，不是仅阅读提示词；合成 Store 无线上用户或认证数据，不代表重新验证远端 OAuth/RLS。
