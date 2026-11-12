# 改进分票与执行证据索引

本页连接 [现行规格](../spec-pacta-refinements-20261022.md#implementation-decisions)、发布拆分与实际执行证据。改行为先读规格相关章节；查实现历史或复现验证时，才读下表记录。**当前状态读取对应 GitHub Issue**；本地记录中的完成状态、测试数字及设备结论均只代表记录当时。

| 分票 / Issue | 现行要求 | 有日期的执行证据 |
| --- | --- | --- |
| [T01 描述](01.md) / [#64](https://github.com/Kaniruka/Pacta/issues/64) | 看板与描述 | [实施、两端与隔离云往返](../issue-64-validation.md) |
| [T02 折叠与分类](02.md) / [#65](https://github.com/Kaniruka/Pacta/issues/65) | 看板与描述 | [实施及复验入口](../issue-65-validation.md)；其读屏/键盘证据按 ADR 0007/0008 保留为历史 |
| [T03 任务选择与恢复](03.md) / [#66](https://github.com/Kaniruka/Pacta/issues/66) | 专注导航与模式 | [实施与两端验收入口](../issue-66-validation.md) |
| [T04 模式记忆](04.md) / [#67](https://github.com/Kaniruka/Pacta/issues/67) | 专注导航与模式 | [实施与保留数据重启](../issue-67-validation.md) |
| [T05 视图偏好](05.md) / [#68](https://github.com/Kaniruka/Pacta/issues/68) | 设备视图偏好 | [实施](../issue-68-validation.md)、[跨进程设备验收](../issue-68-device-validation.md) |
| [T06 同步卡片](06.md) / [#69](https://github.com/Kaniruka/Pacta/issues/69) | 云检查与元数据 | [实施](../issue-69-validation.md)、[跨入口修复](../issue-69-cross-entry-fix-validation.md) |
| [T07 设备型号](07.md) / [#70](https://github.com/Kaniruka/Pacta/issues/70) | 云检查与元数据 | [实施及服务证据入口](../issue-70-validation.md) |
| [T08 只读检查](08.md) / [#71](https://github.com/Kaniruka/Pacta/issues/71) | 云检查与元数据 | [实施](../issue-71-validation.md)、[原生生命周期](../issue-71-native-validation.md)、[隔离云](../issue-71-cloud-validation.md) |
| [T09 选择与延迟提醒](09.md) / [#72](https://github.com/Kaniruka/Pacta/issues/72) | 云检查与元数据 | [实施](../issue-72-validation.md)、[原生提醒](../issue-72-native-validation.md)、[隔离云](../issue-72-cloud-validation.md) |

## 发布拆分与依赖

每票承担自身实现和适用测试/设备取证，不拆数据库/UI/测试等横向票。共享文件或推荐顺序不形成硬阻塞。原生依赖为 T06 → T08 → T09：T08复用T06的成功版本/本地基线状态，T09消费T08发现的云版本。T01/T02和T03/T04是组合验证关系，后落地者补组合验收；T07可复用预览展示，不被T06阻塞。

历史发布时9张子Issue均关联 Spec #63、设置 ready-for-agent 并核验两条阻塞边。发布后的关闭、标签与阻塞变化见各 Issue 和执行记录，机器可读发布映射保留于 [publication.json](publication.json)。既有 [#54](https://github.com/Kaniruka/Pacta/issues/54) 不由本轮增量规格替代。
