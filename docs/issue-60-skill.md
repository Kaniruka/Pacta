# 国策只读分析 skill（Issue #60）

发布目录是 [`skills/pacta-national-focus-analysis`](../skills/pacta-national-focus-analysis/SKILL.md)，名称 `pacta-national-focus-analysis`。它只提供分析流程，不携带账号、密钥或服务器访问权限；MCP 连接仍需用户在 Pacta 中批准。

## 安装与首次使用

在 Codex 中发送：

```text
$skill-installer Install the skill from https://github.com/Kaniruka/Pacta/tree/master/skills/pacta-national-focus-analysis
```

该 URL 只有在产物发布到 master 后才可使用；发布分支测试应将 `master` 替换为已推送分支或提交 SHA。也可对 Codex 自带安装器执行（安装器路径取当前 Codex 安装目录）：

```sh
python3 <skill-installer>/scripts/install-skill-from-github.py --repo Kaniruka/Pacta --path skills/pacta-national-focus-analysis --ref master
```

安装到 Codex 的 skills 目录后，在下一轮输入以下问题；若当前客户端尚未刷新技能列表，重启 Codex 再试。此目录可安装，无需复制 Pacta 应用源码。技能安装方式依据 [OpenAI skill 文档](https://learn.chatgpt.com/docs/build-skills) 和当前内置 skill-installer 的 GitHub 安装器。

```text
$pacta-national-focus-analysis 请读取最新手动上传的国策树和卡片库，按事实、可能解释、调整建议审视规则清晰度、父子依赖和执行负担；引用卡片 ID 与要求版本，说明数据时效和证据不足。
```

先在 Pacta 通过现有整份同步预览及覆盖确认手动上传，再按 [MCP 连接说明](../supabase/functions/national-focus-mcp/README.md#connect-and-renew) 配置连接和批准授权。连接、安装、读取不会自动上传、下载或推进检查点。手机完成上传后无需保持 App 运行。只读分析依据最近上传快照，设备后来发生的编辑不会自动出现。

## 可重复评估

`skills/pacta-national-focus-analysis/evals/cases.json` 是公开合成导出证据，刻意简化为分析所需字段，不冒充服务完整响应：同名卡不同 ID、当前强化版本与历史版本、待确认/熄灭状态、空树与空库、含糊规则与缺失版本。没有真实用户数据。

将 skill 目录复制到临时目录，在 Codex 只读沙箱运行：

```sh
codex exec --ignore-user-config --ephemeral --skip-git-repo-check -s read-only -C <temporary-directory> --json -o <result.md> 'Read skill/SKILL.md and use this skill to analyze each case in skill/evals/cases.json. These are user-supplied synthetic exported evidence, not live MCP data. Review rule clarity, dependencies and burden, including provided historical contrast. Use Chinese. Do not edit files or connect external services.'
```

人工检查语义，避免逐字比对模型输出：

| 场景 | 通过条件 |
| --- | --- |
| 事实/推测 | 记录边与规则原文可核对；实际依赖、负担、原因保持假设；建议留给用户 |
| 同名卡 | `card-a`、`card-b` 分别引用，不按“晨间”合并 |
| 要求版本 | 当前 `version-a2` 与历史 `version-a1` 分开；历史不套用当前强化要求 |
| 状态 | 待确认没有直接视为失败；不会按现在时钟结算上传状态 |
| 空树 | 明确树/库均为空，不创造节点或诊断 |
| 证据不足 | `card-c` 版本未知；不从含糊文本推断履行、成功率或完整行为史 |
| 时效与权限 | 声明合成来源、revision 7 和上传时间；不声称真实服务已连接，不写回 |

## 实际验证记录（2026-10-22）

- `python3 .../skill-creator/scripts/quick_validate.py skills/pacta-national-focus-analysis`：通过。
- Codex CLI `0.163.0-alpha.10.2`，只读沙箱、实际模型分析三组合成导出：成功（退出 0）。人工逐项复核上述语义条件均通过；报告见 [合成分析](evidence/issue60-codex-synthetic-analysis.md)。使用实际合同字段 `version_number`，缺失版本场景明确为不完整导出。
- 同一 Codex CLI 实际模型通过真实远端 MCP 读取 `get_snapshot_metadata`、`get_national_focus_tree(expected_revision: 1)`、`get_national_focus_library(expected_revision: 1)`，完成同名双卡的规则、依赖与负担分析，退出 0。见 [调用证据](evidence/issue60-codex-live-tools.json)、[分析报告](evidence/issue60-codex-live-analysis.md)。测试使用独立合成账号及云快照和受保护管理接口创建的短期测试 delegate，完成后 finally 删除临时账号及客户端。此次不重复验证 OAuth DCR/PKCE/App 同意，也不是普通用户上传行为证据。
- 发布提交 `754365b` 推送 master 后，使用 Windows Python 3.14.7 执行内置 `install-skill-from-github.py --url https://github.com/Kaniruka/Pacta/tree/master/skills/pacta-national-focus-analysis --dest <隔离临时目录>`：成功。下载后的 4 个文件与已发布源码逐字节一致。WSL 下载尝试因传输停滞中止，改用同一官方安装器的 Windows 运行时完成验证。未改用户现有 skill 安装。
