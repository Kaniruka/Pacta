# 本轮纵向票发布索引

历史发布状态快照（2026-10-22，不代表后续进度）：[Spec #63](https://github.com/Kaniruka/Pacta/issues/63)仍打开；9张子Issue中[#64](https://github.com/Kaniruka/Pacta/issues/64)已完成验收并关闭、无标签，其余8票打开并保留ready-for-agent。当前状态读取对应 Issue；#65 后续结果见[验收记录](../issue-65-validation.md)。发布时已核验原生父子关系和两条阻塞边；[#64验收证据](../issue-64-validation.md)。

每票含自身实现和适用测试/设备取证，不拆数据库/UI/测试等横向票，无必须先行的纯prefactor。共享文件或推荐顺序不形成硬阻塞。

1. **[T01 描述贯通目标、任务与整份快照](01.md)** · [#64](https://github.com/Kaniruka/Pacta/issues/64) — **已完成并关闭**；提交`fece2f9`已推送。描述编辑、重启及隔离云同步均已验收。

2. **[T02 标题区域折叠与看板分类呈现](02.md)** · [#65](https://github.com/Kaniruka/Pacta/issues/65) — 阻塞：无。点击目标标题区域独立折叠，隐藏内部任务和添加入口，清楚区分任务分类与本次模式。

3. **[T03 专注链二级任务选择与执行恢复路径](03.md)** · [#66](https://github.com/Kaniruka/Pacta/issues/66) — 已实施验收（2026-10-23，[证据](../issue-66-validation.md)）；阻塞：无。完整任务列表已迁入二级页面，主页保留数量、入口、链记录、历史和现有流程恢复。

4. **[T04 统一预约和直接专注的上次模式记忆](04.md)** · [#67](https://github.com/Kaniruka/Pacta/issues/67) — 已实施验收（2026-10-23，[证据](../issue-67-validation.md)）；阻塞：无。两种成功启动均记住模式，全部任务入口沿用；试选、取消和失败不保存，已完成两端保留数据进程重启验证。

5. **[T05 国策树视图偏好跨进程重启恢复](05.md)** · [#68](https://github.com/Kaniruka/Pacta/issues/68) — 阻塞：无。本机按用户记住简洁/详细视图，切换立即保存，重启恢复，首次简洁。

6. **[T06 简洁同步卡片与可持久的安全同步结果](06.md)** · [#69](https://github.com/Kaniruka/Pacta/issues/69) — 阻塞：无。同步卡片以时间/状态摘要呈现，在适配平台的弹层内完成现有整份覆盖，并记住本机同步结果。

7. **[T07 云端来源设备型号与旧元数据兼容](07.md)** · [#70](https://github.com/Kaniruka/Pacta/issues/70) — 阻塞：无。上传并展示实际可用的设备名和型号，使用户能识别来源设备，旧数据未知信息明确标注。

8. **[T08 冷启动与前台只读检查云版本](08.md)** · [#71](https://github.com/Kaniruka/Pacta/issues/71) — 阻塞：T06。进入应用及符合节流条件的前台恢复可发现尚未处理的云快照，卡片显示待处理或失败并可重试，未选择前不写业务数据。

9. **[T09 云版本选择提醒、忽略与专注期间延迟](09.md)** · [#72](https://github.com/Kaniruka/Pacta/issues/72) — 阻塞：T08。未处理版本获得明确用户选择；忽略只抑制当前版本自动提醒，进行中流程不中断，结束后再提示。

真实阻塞链：T06 → T08 → T09。T08复用T06的成功版本/本地基线状态；T09消费T08发现的云版本。T01/T02和T03/T04是组合验证关系，不阻塞各自启动；后落地者补组合验收。T07可复用现有预览展示，不被T06阻塞。

历史发布记录：已按批准顺序发布；发布时每票均设置ready-for-agent并关联为spec原生子Issue。后续#64已完成并移除该标签，其余票待实施。原生阻塞链为 [#69](https://github.com/Kaniruka/Pacta/issues/69) → [#71](https://github.com/Kaniruka/Pacta/issues/71) → [#72](https://github.com/Kaniruka/Pacta/issues/72)，其他票无阻塞。既有#54未修改、仍打开。机器可读映射及核验记录见 publication.json。
