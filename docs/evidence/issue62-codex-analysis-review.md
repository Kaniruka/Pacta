# 真实 Codex 模型输出的人工复核摘要

2026-10-22，主 agent 在真实 Android→已部署 MCP→桌面 Codex 模型运行后，读取了生成的完整中文报告并核查工具调用。此文件是人工复核记录，不是原始模型报告。

已实际读取的较早一轮报告：revision 1；来源 `Issue62 Android real-service demo` / `issue62-android`；真实上传时间 `2026-10-22T01:00:26.516728+00:00`。报告将其与整份业务更新时间 `2026-10-22T01:00:23+00:00` 分开，并明确不是手机实时状态。

- 当前树一张根卡、库为空；卡片 `ec7b4e87-3ff3-45e0-b159-548b70dfb6cf`，当前要求版本 `7a5dcdda-99fd-48bb-a55c-c71c894bd577` / v1，规则 “Before bed / Read 5 pages”。模型区分可计数行动与含糊触发时点，没有推断现实履行。
- 失败事件 `50d1e448-d456-4460-a111-8c6df54ca474` 是主动熄灭，冻结规则版本号 v1、历史版本 ID unknown；报告没有拿当前版本 ID 回填历史。
- 原始原因是合成说明 “Demo: the book was left in another room”，后续 `shared_explanation=null`；两者分开，单个事件没有被当成因果证明或失败率。
- 默认窗口锚定上传维护检查点的北京时间 2026-10-22 04:00，查询 2026-09-23—2026-10-22；读完一页、一件事件及冻结详情，注明 `truncated=false`、`next_cursor=null` 不代表完整历史，更早范围未查。
- 建议由用户手动采纳；未宣称写回、自动确认或测得真实习惯。

后续另一轮成功模型运行的安全工具记录保留在 [Android model trace](issue62-android-model-tools.json)。其独立临时身份与上述较早报告不同：失败 ID 为 `f453b5f1-4271-425d-98ae-335d17f1df14`。主 agent 在原报告尚存时实际执行 ID 比对，结果为 `Report/trace event ID matches: True`、`Trace completed: True`；五次工具分别为 metadata、tree、library、failure list、frozen detail，均固定 revision 1。不能把两轮临时卡片/事件 ID 混用。

后续 UI 测试重跑遇到账号额度耗尽，CLI 返回 `turn.failed`，未产生新分析。旧验收脚本在调用模型前删除输出文件，导致原报告没有保留；已修为成功后才替换正式文件。没有根据遗失文件伪造新的原始报告。原生流程重跑可显式使用 `--skip-analysis`，其证据记录 `model_analysis_skipped=true`，不把跳过当成新模型通过。
