# Issue #62：真实服务与授权边界验收

日期：2026-10-22；本轮开始工作区干净。按 `cmd.exe /c gh issue view 62 --json title,body,comments` 读取验收条目。仅记录已执行边界，不把 SQL、HTTP 调用当成手机操作或 Codex 模型分析。

## 部署状态与项目隔离边界

通过已配置的受保护 Management API 凭据只读核查：项目 `wmutsplyqulanwkqtqhb`（Pacta），`ACTIVE_HEALTHY`，`ap-southeast-1`；`national-focus-mcp` 为 `ACTIVE`、version 9、`verify_jwt=false`。`202610210001`、`202610210002`、`202610220001` 均已记录在迁移历史。本轮未重部署服务或修改生产迁移。

项目列表只返回上述一个共享开发项目，无现成独立验收项目。组织列表只返回 Rukani。尝试只读查询 `/v1/organizations/{id}/billing/subscription` 和 `/usage` 均返回404，未能据此确认免费计划和剩余免费项目配额，因此没有创建可能产生费用的新资源。该阶段仅为共享开发项目身份隔离；后续通过官方正确接口确认免费计划后，已补独立项目验收，见下节。

实际服务地址为 `https://wmutsplyqulanwkqtqhb.supabase.co/functions/v1/national-focus-mcp`，MCP transport 使用其 `/mcp`。发现与授权使用服务的实际 canonical issuer；公开地址不含秘密。

## 真实 SQL 验证

通过 Management API `/database/query` 执行仓库中完整 SQL，均在 `begin`/`rollback` 中创建随机身份和 fixture：

- `supabase/tests/national_focus_mcp_access.sql`：通过。验证匿名/普通客户端表权限与服务 RPC 限制、显式同意、code/resource绑定、单次兑换、跨用户撤销拒绝、停用拒绝、当前 owner metadata、revision、幂等撤销。
- `supabase/tests/national_focus_mcp_content.sql`：通过。验证身份/范围隔离、当前树投影、无快照、无权限、撤销/过期/停用、revision 边界与读取不写 snapshot。
- `supabase/tests/national_focus_mcp_history.sql`：通过。验证历史服务范围、身份/权限边界、过期/撤销/停用、revision 和历史读取无业务副作用。

发现并修复 access 探针旧版会从已有无快照用户中挑选两人的问题，改为和 content/history 一样在事务内创建随机测试身份。首次原版执行返回400，事务失败回滚；未把该次当作通过。修改后完整执行通过。

新增真正“重新同意”续期回归：原委托已撤销后，新授权请求→当前用户显式同意→兑换新 code→新 token可读；有效期约1800秒，不返回refresh token；旧token仍被拒绝。该新增SQL完整在远端执行通过并回滚。没有等待真实30分钟，过期状态由受控fixture时间模拟。

完成这组SQL后实际Auth数量仍为2，`nf-%@probe.invalid`测试身份为0；迁移与服务保留。未选择普通身份作为fixture，未修改普通业务快照。

## 真实公开 HTTP 验证

执行本机忽略目录脚本 `python3 -u .scratch/issue62/service_http.py`，随机创建独立fixture身份/client/delegate，直接请求已部署HTTPS服务；凭据仅内存使用，不写入此文档或响应证据。

- 活跃委托、尚无上传：`get_snapshot_metadata` HTTP200，明确 `no_snapshot`，没有假空树。
- 委托过期：六个工具全部HTTP401 `invalid_token`。
- owner停用：六个工具全部HTTP401 `invalid_token`。
- 恢复owner后撤销委托：六个工具全部HTTP401 `invalid_token`，恢复不能复活撤销授权。

六工具是 metadata、tree、library、card、failure list、failure detail。fixture清理在finally执行，按本次随机UUID检查剩余fixture身份0。此运行不通过真实Codex，也没有浏览器/App交互；实际Codex与设备串联必须单独取证。

## 可解释范围和待完成边界

SQL与HTTP验证证明已部署服务上的授权/隔离拒绝及无副作用读取。expiry/renewal由真实服务SQL模拟时间及新授权交换验证；不声称手动等待30分钟或Codex自动刷新（协议本来没有refresh token）。真实断网/恢复的设备行为、手机真实上传→另设备Codex分析/复盘→手机撤销均不能从以上结果推导，须由本票其他证据补齐。HTTP503与版本变化的合成合同测试也不等同真实公网故障注入。


## 后续：独立免费项目从零部署（2026-10-22）

用户明确授权仅在免费配额内创建并最终清理。查阅官方 [Management OpenAPI](https://api.supabase.com/api/v1-json) 后，使用正确的 `GET /v1/organizations/{slug}`，实际组织返回 `plan: free`；`GET /v1/projects` 当时仅一个活跃项目。官方 [billing说明](https://supabase.com/docs/guides/platform/billing-on-supabase) 和 [FAQ](https://supabase.com/docs/guides/platform/billing-faq) 明确组织统一计划，Free最多两个活跃项目，超过免费用量是限制服务而非自动付费。项目创建请求的deprecated `plan` 字段被忽略，因此没有依赖它保证免费；未升级组织或选择付费附加项。来源细节见 [API研究](evidence/issue62-free-plan-api-research.md)。

在已确认Free的现有组织中创建临时独立项目 `bhlbrswfolrcvrhfuilq`，名称 `Pacta issue62 disposable validation`，`nano`，`ap-southeast-1`，`ACTIVE_HEALTHY`。未修改根 `.env` 或仓库项目链接。随机数据库口令和该项目配置留在忽略目录、权限0600，仅交本机验收运行时。

实际执行 `python3 -u .scratch/issue62/isolated_validate.py`，顺序从零应用仓库全部26份迁移，每份事务成功；三份 MCP rollback SQL（access/content/history）均通过，含重新显式同意续期、旧撤销token仍拒绝、跨用户、模块范围、RLS/权限和无副作用读取。SQL运行后Auth测试身份归零。

部署配置空204响应使本机脚本最初尝试JSON解析失败；这是脚本响应处理问题，已修复后仅继续服务部署，未重复应用迁移。`python3 -u .scratch/issue62/isolated_deploy.py` 完成服务部署：ACTIVE version1、verify_jwt=false，canonical issuer绑定独立项目。后续HTTP fixture执行采用独立脚本，部署产物不受本机脚本问题影响。

实际执行 `python3 -u .scratch/issue62/isolated_http.py`：活跃无快照HTTP200明确no_snapshot；expired/suspended/revoked分别六工具均HTTP401（共18次），fixture finally清理后按UUID检查剩余身份0。与共享项目结果分别成立，没有只沿用此前结论。

独立项目随后供主agent完成真实原生串联：Windows 44秒1 passed；Android 47秒1 passed，后者包含真实ADB wifi/data断网及恢复、重复读取与snapshot整行digest不变。两bridge均exit0且fixture cleanup=true；对应安全证据见 [Android](evidence/issue62-android-native-flow.json) 与 [Windows](evidence/issue62-windows-native-flow.json)。两轮显式skip-analysis，不把它们描述为新的模型分析。

主agent中止共享项目bridge后另行授权清理复核：按严格 `^issue62-[0-9a-f]{32}@probe[.]invalid$` 查询身份/资格及精确 `Issue62 desktop Codex` 客户端。清理前Auth总2、本轮身份0、客户端0，仅残留资格1；删除该范围残留后再次实查：Auth总2，本轮身份/资格/客户端均0。未触碰普通用户或独立项目。


## 最终独立资源清理

两平台验收结束后按用户授权清理。删除前再次真实查询组织：`plan=free`；精确核对目标 `bhlbrswfolrcvrhfuilq` 名称为本轮临时项目。随后 `DELETE /v1/projects/bhlbrswfolrcvrhfuilq` 成功；再次查询项目列表只剩原开发项目 `wmutsplyqulanwkqtqhb`（Pacta，ACTIVE_HEALTHY），再单独 `GET` 临时项目返回HTTP404。

已删除受保护 `.scratch/issue62/isolated.env` 和含随机数据库口令的 `isolated-state.json`。未删除或改写根 `.env`、共享项目public配置、原开发项目及其用户数据。本轮未升级组织、绑定付款方式或添加付费资源；创建前和删除前均确认同一组织Free，创建仅选nano临时实例。最终无本轮临时Supabase项目残留。
