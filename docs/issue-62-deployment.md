# Issue #62：国策 AI 部署与分发

本页是部署操作单，实际验收结果另记；执行命令示例不代表已执行部署。协议、授权有效期和错误语义以 [MCP runbook](../supabase/functions/national-focus-mcp/README.md) 为准。现有 #57–#61 证据中的真实后端使用共享开发项目内独立身份，不能充当本票要求的独立 Supabase 项目验收。

## 绑定目标环境

部署者在 Supabase 控制台建立独立验收项目，保留现有开发项目和正常用户数据。记录项目 ref、公开 URL、发布源码提交、客户端版本；访问令牌、数据库口令、service-role key 和测试身份留在受保护环境。使用仓库现有 [Supabase 配置](../supabase/README.md) 完成 Email Auth、注册资格及管理员初始化；这些前置设置不能由 MCP 的授权绕过。

从仓库根目录执行，先用 `supabase projects list` 核对 ref，再链接目标。`db push` 包含全部未应用迁移，执行前审阅 dry-run，不能只复制三份 MCP SQL 到缺少前置表的项目。

```powershell
supabase login
supabase projects list
$PactaProjectRef = Read-Host 'Target project ref'
supabase link --project-ref $PactaProjectRef
supabase db push --dry-run
supabase db push
$PactaIssuer = "https://$PactaProjectRef.supabase.co/functions/v1/national-focus-mcp"
supabase secrets set "PACTA_MCP_PUBLIC_URL=$PactaIssuer" --project-ref $PactaProjectRef
supabase functions deploy national-focus-mcp --project-ref $PactaProjectRef --no-verify-jwt
```

目标运行时必须具备 Supabase 自动提供的 `SUPABASE_URL` 和服务端密钥。`PACTA_MCP_PUBLIC_URL` 是公开 issuer，末尾无斜杠及 `/mcp`；MCP 地址是 issuer 加 `/mcp`。仅本函数关闭网关 JWT 验证，函数内部仍逐次验证委托。此版本不支持额外静态授权网站。自定义代理域名若未与 App 的地址生成规则统一，不属于本操作单支持的部署。

在目标项目核对函数部署和公开发现，再验证未认证 MCP 调用返回 401。发现文档成功不代表数据库迁移、App 授权或工具读取成功。

```powershell
Invoke-RestMethod "$PactaIssuer/resource-metadata"
Invoke-RestMethod "$PactaIssuer/.well-known/openid-configuration"
curl.exe -i -X POST "$PactaIssuer/mcp" -H 'Content-Type: application/json' --data '{}'
```

OAuth 使用 Codex 发起的动态客户端注册及精确 HTTP loopback 回调（显式端口的 `127.0.0.1`、`localhost`、`::1`）。无需手工粘贴 App session 或设置 Supabase Auth 重定向 URL；批准前在 App 核对刚发起的客户端与回调。请求和授权码 5 分钟过期，委托从 App 同意起 30 分钟到期，无 refresh token；到期后重新发起登录及同意。App 撤销立即拒绝后续所有 MCP 请求；App 退出登录本身不撤销独立委托。

## 构建匹配部署的 App

创建被忽略的 `.scratch/issue62-public.json`，仅含目标项目的公开配置：

```json
{
  "SUPABASE_URL": "https://PROJECT.supabase.co",
  "SUPABASE_PUBLISHABLE_KEY": "TARGET_PUBLIC_PUBLISHABLE_OR_ANON_KEY"
}
```

```powershell
python scripts/check_national_focus_deployment.py --config .env --public-output .scratch/issue62-public.json
flutter build apk --debug --dart-define-from-file=.scratch/issue62-public.json
flutter build windows --release --dart-define-from-file=.scratch/issue62-public.json
```

若已有上述手工创建的公开 JSON，先执行 `python scripts/check_national_focus_deployment.py --config .scratch/issue62-public.json`。从本机 `.env` 导出时不要预先创建输出文件；脚本拒绝覆盖已有文件，且只导出 URL 与 publishable/anon key。它拒绝服务端 key，验证 App 派生地址与公开资源/OAuth 发现、PKCE、范围、未授权 401 一致；不会创建授权、上传数据或打印 key。发现检查通过仍不能替代登录、RLS 与设备串联验收。

App 当前从同一 `SUPABASE_URL` 派生 `/functions/v1/national-focus-mcp/mcp`，没有独立 MCP 环境开关。登录、同步和国策 AI 必须使用同一目标项目；换配置后重新构建。不得传入根目录可能含 `TEST_*` 的 `.env`。Android 采用 `adb install -r` 保留数据；Windows 分发整个 Release 目录。设备测试遵循 [环境说明](development-environment.md)，有现有数据时先保护本机状态，测试用 `--no-uninstall`。

在“我的 → 国策 AI 分析”和国策树更多菜单分别打开引导，核对复制的 MCP 地址及连接命令与上面目标完全一致。未配置、服务断开、过期及撤销应给出可恢复提示，不以空树替代读取错误。上传继续走整份数据预览和覆盖确认；打开引导、登录或恢复联网不自动上传。

## 分发 skill

源码安装及首次问题见 [skill 使用说明](issue-60-skill.md)。发布时固定 App、服务、数据库迁移与 skill 的源码提交；GitHub 安装 URL 只有对应提交已推送后才可访问。当前源码也可生成无需联网下载的安装产物：

```powershell
python scripts/package_national_focus_skill.py
Get-FileHash build/skills/pacta-national-focus-analysis.zip -Algorithm SHA256
```

同时交付 ZIP、`.zip.sha256` 和源码提交标识。脚本只打包明确列出的四份 skill 文件，不包含应用配置或凭据；固定归档时间和权限，同一文件内容可重复生成相同字节。

接收者对照通过可信渠道收到的 SHA-256，将 ZIP 解压到临时目录，检查根目录恰为 `pacta-national-focus-analysis`，然后将该目录复制到自己的 Codex skills 目录（默认 `~/.codex/skills`；设置 `CODEX_HOME` 时使用其 `skills` 子目录）。已有同名目录先移到技能目录外备份，再复制新目录，保留其他技能。开启下一轮对话；若技能列表未刷新，重启 Codex。安装包仅提供分析流程，仍须按 MCP runbook 连接并在 App 同意。

## 发布验收记录要求

独立 Supabase 项目中的真实安全验收应执行三份 `supabase/tests/national_focus_mcp_{access,content,history}.sql`（实际文件名见目录），并测试真实 HTTP 委托、到期重新授权、撤销、停用、跨用户与模块范围。记录执行命令和项目隔离方式；生产 handler 的 mock 测试及共享项目内身份隔离不能替代独立项目证据。

真实演示须同时记录 Android、Windows、Codex 的版本和源码提交、上传 revision/源设备/时间、读取工具 trace，按顺序证明：

1. 手机上维护国策及失败记录，经预览和覆盖确认手动上传。
2. 另一设备 Codex 发起 OAuth，手机明确同意；安装 skill 后完成结构分析和冻结历史复盘。
3. 手机编辑但不上传，Codex 重读仍是旧 revision 和旧内容；再次手动上传后重读得到新 revision，跨版本分析重启。
4. 手机撤销后，包括 initialize、tools/list、tools/call 在内的后续请求均拒绝。
5. 两个平台验证两个入口、预览取消/覆盖确认、授权状态/撤销及失败恢复。未验证的平板不列为支持。

公开证据须去除口令、请求码、授权码、访问令牌和回调查询串。完成后移除独立测试身份、授权及临时凭据，保留发布所需服务和迁移。不得将“README 已有步骤”“后端可调用”或前序票独立测试写成上述串联已完成。
