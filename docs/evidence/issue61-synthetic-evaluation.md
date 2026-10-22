# Issue #61：真实 handler 合同与 Codex MCP 复盘验收

2026-10-22，Windows Node **v24.20.0**，WSL 启动 **codex-cli 0.163.0-alpha.10.2**。数据为隔离合成样例，无真实用户数据、云端写入或模型 API 新增。stdio 适配器将实际 MCP 请求转交生产 `createHandler`，只替换 Store。此证据证明本地生产合同和模型使用行为，不证明部署端服务身份或线上 RLS；设备验收另见 `../issue-61-validation.md`。

## 执行及产物

```bash
cmd.exe /c node --experimental-transform-types --test supabase/functions/national-focus-mcp/history.test.ts supabase/functions/national-focus-mcp/handler.test.ts
```

结果 **25 passed / 0 failed**。其中新增两个 Issue61 测试，实际通过 `Request → createHandler → Store.rpc → projection → JSON-RPC response`，不是提示词或手工编造工具响应。Node 仅报告实验性 TS 转换和模块类型警告。

- `issue61-handler-synthetic-tools.json`：新增合成场景测试直接导出的4页历史与一条详情，保留真实 handler 输出。
- `issue61-codex-synthetic-run.jsonl` / `issue61-codex-synthetic-analysis.md`：Codex 通过 MCP 实际调用当前树/库、4页历史、4条详情和末次元数据确认。
- `issue61-codex-revision-run.jsonl` / `issue61-codex-revision-analysis.md`：独立 revision 切换场景；第二次历史读取切换至 revision3。运行结果见下方。基线实际 12 次、revision 场景实际 16 次 MCP 调用。

stdio 启动命令为 Windows `node --experimental-transform-types F:/Workspace/Release/Flutter/Pacta/supabase/functions/national-focus-mcp/issue61-eval-stdio.ts`；revision 场景追加 `--revision-race`。配置通过 `codex exec -c mcp_servers.issue61.command='"cmd.exe"' -c mcp_servers.issue61.args='["/c","node","--experimental-transform-types","F:/Workspace/Release/Flutter/Pacta/supabase/functions/national-focus-mcp/issue61-eval-stdio.ts"]'` 注入；`cwd` 为仓库路径，执行沙箱 `read-only`，`--ephemeral --json`，`-o` 保存最终报告。未永久改动用户 MCP 配置。

实际基线 prompt：

> 使用 /mnt/f/Workspace/Release/Flutter/Pacta/skills/pacta-national-focus-analysis/SKILL.md及contract参考，用已连接issue61 MCP实际调用T2/T3做近30国策日失败复盘。现在锚点2026-10-22T12:00:00Z。合成隔离数据、生产handler；不读fixture/源码/已有报告代替工具。历史limit=1验收分页。revision变化后完整重取。分析当前规则与父子独立失败、连带、漏确认、强化、软删、事后反思、同名卡。中文报告区分事实/假设/建议并引用证据和局限。仅只读分析，禁止文件修改、子agent、外部网络与写回。

实际 revision prompt：

> 使用 /mnt/f/Workspace/Release/Flutter/Pacta/skills/pacta-national-focus-analysis/SKILL.md及contract参考，通过issue61 MCP实际调用T2/T3完成近30国策日失败复盘。固定现在2026-10-22T12:00:00Z。合成验收服务使用生产handler。历史limit=1；服务会在第2次历史读切换revision，必须遵循skill重取一致证据再完整分析。不要读fixture、源码或已有报告。中文输出事实/假设/建议、事件/规则证据、分页和revision恢复及边界。只读，不修改文件、不调用外部网络、不创建子agent。

两个 prompt 都曾给出固定“现在”，但模型实际按 maintenance checkpoint `2026-10-21T20:00:00Z` 取国策日 `2026-10-22`，并明确不按当前时间推进结算。后续复跑应直接声明 fixture checkpoint，不注入当前时钟。

## 合同与语义复核

| 场景 | 实际证据及结果 |
| --- | --- |
| 父子独立失败 | `independent-child` 的来源为子卡，父卡冻结状态 lit；`independent-parent` 来源为父卡。报告分别计数，不按父子关系合并。 |
| 连带影响 | 父卡事件中子卡 `cascade_source_card_id=tree-a`、prior=lit；报告区分4次独立失败与3条连带影响，不把连带节点另计失败。 |
| 漏确认 | `missed-confirmation.cause=missed_confirmation`、事件原因为 null。报告未判为未执行，并区分冻结卡原因与事件原因。 |
| 强化后失败 | 历史来源冻结 active=2、需求版本号3、有效“06:00前/两页”；当前 `tree-a/version-a4` 为强化1。报告按历史规则复盘，未把当前规则追溯套入历史，未宣称强化导致失败。 |
| 软删历史 | 当前 fixture 含软删 `deleted-d`；当前 tree/library 不返回该卡，历史详情仍返回完整冻结规则。报告保留历史，并注明工具不提供确切删除时间。 |
| 事后修改说明 | `original parent reason`、`edited later, not original cause`、冻结卡原因分别保留；报告明确三者来源不同。 |
| 同名卡 | 当前两卡名 Shared name，历史两卡名同名国策；报告始终按 tree-a/tree-b 区分。 |
| 分页 | limit=1，4页4个唯一事件，末页 truncated=false/next_cursor=null；报告声明读完查询范围，不等价完整历史。 |
| 历史不完整 | 所有真实历史结果携带 historical omissions 提示；既有合同测试覆盖缺表 unsupported、有效空历史、损坏冻结树。报告披露窗口外、上传遗漏、缺失版本ID/子卡版本信息。未单独运行 Codex `--missing-history` 模式。 |
| revision变化与重取 | 第2次历史调用实际返回 snapshot_changed；模型重读 metadata → tree/library（expected_revision=3）→ 从无cursor首页读取4页 → 4条详情。对真实JSONL执行断言：错误仅1次、重取后所有内容读取固定revision3、首页不含旧cursor、末页next_cursor=null，全部通过；最终报告只分析revision3，明确弃用旧页。 |
| 只读与既有结构分析 | 当前2张树卡、1张库卡，待确认不判失败，库卡熄灭不自动归于本窗口失败。Store 写入拒绝，报告仅提手动建议。 |

基线报告明确累计成功天数不提供每日成功日志、成功率分母、实际工作量或习惯形成证明。报告没有观测 revision 变化时也明确表示本轮不能证明恢复分支，通过下述独立运行补验。

## 限制与首次配置故障

首次采用 `--ignore-user-config` 时模型看不到自定义 issue61 工具，按 skill 如实说明工具不可用，没有伪造调用；该失败运行未当作成功证据。去掉该参数后实际 MCP 工具正常可用。

基线原先以 Linux 环境变量请求 revision race，但 Windows Node 未收到该变量，实际 trace 保持 revision2；故基线报告只声明稳定快照。之后改用显式 `--revision-race` 参数，独立运行恢复场景。适配器同时提供 `--missing-history`，本次只在合同测试层验证该分支。

合成 frozen 事件只保存版本号，不存在真实版本ID时报告使用 unknown。适配器 fixture 的当前版本和历史版本不是完整编辑史，不能据此重建所有变更。此次没有调用真实 Supabase 服务，也没有发布或更新远程安装源。

已对提交的两份工具trace、两份报告及handler输出扫描 Bearer、pacta_mcp_、sb_secret、service_role、refresh_token、access_token、password、API key 等标记，无命中。trace中的base64字符串仅为合成公开游标（revision、日期、limit、事件ID），无真实凭据。
