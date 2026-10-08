# 卡片编辑、看板折叠与文案精简（2026-10-08）

关联需求：GitHub #54。用户已确认卡片详情应能编辑整张卡的信息。

## 设计与范围

Flutter/Material 3，面向 Windows 和 Android。使用 apple-design 的基础、布局、列表、输入和写作原则，不套用 Apple 导航约定。

- `lists-and-tables.md › Content`：“Keep item text succinct”，长目标/任务标题最多两行，完整名称可从编辑查看；目标独立收起任务，保留摘要和操作，默认展开保持选择任务的入口。
- `entering-data.md › Best practices`：“Be clear about the data you need”，名称与行动必填，触发条件标为可选；既有卡片填入当前基础内容，强化中的卡片说明覆盖字段继续沿用强化要求。
- `writing.md` 的简明写作原则：操作使用熄灭、确认、全部确认、上传、下载；覆盖数据的确认保留后果说明。
- 沿用现有语义亮暗颜色、系统字号、间距与控件；不增加装饰、动画或新领域概念。卡片版本保留有效要求修改历史，改名不改变版本，编辑不清空状态、记录或内化进度。

已有 CONTEXT.md 的 CTDP/RSIP 与内化研究改动及未跟踪研究资料属于用户原有工作，保留且不随本任务提交。

## 验证进度

- Windows Flutter `test test/national_focus/national_focus_repository_test.dart`：25项通过。
- Windows Flutter `test test/national_focus/card_editing_test.dart`：3项通过。
- `flutter test integration_test/card_editing_device_test.dart -d windows`：实际构建启动 Windows 应用，3项通过，验证卡片库详情、树节点详情完整编辑和新建时不填触发条件。
- Windows Flutter `test test/calendar/calendar_page_test.dart`：7项通过；修正文案后同步了两处旧断言。
- Windows Flutter `test test/board/board_integration_test.dart`：2项通过，包括320dp、2倍字体、长标题、逐目标折叠与完成状态。
- `flutter test integration_test/board_design_device_test.dart -d windows`：实际启动Windows应用，1项通过。测试兼容桌面侧栏；Windows真实视口尺寸不模拟为窄屏，窄屏证据来自widget测试。
- `flutter test integration_test/manual_cloud_sync_device_test.dart -d windows`：实际启动Windows应用；使用内存业务数据和内存远端验证上传/下载界面，非真实Supabase验证。首轮曾停滞并中止，阶段诊断版及最终无诊断版均通过（1项），没有证据将停滞归因于同步业务；清理等待设置15秒超时。
- `flutter analyze`：No issues found；完整 `flutter test`：255项全部通过。
- `dart format`：所有改动Dart文件检查；保留原CRLF文件的行尾以避免整文件改写，`git -c core.whitespace=cr-at-eol diff --cached --check` 通过。新增内容敏感值扫描未发现凭据。

## 双轴复核

固定点：`aa2878fba7987a91b7f48b0395d8f24960fa3ad2`。使用 code-review 技能并行 Standards/Spec 审查。

### Standards

无硬性标准违规。判断性建议1项：库卡、删除卡与详情页的空触发展示重复；已集中到 `_FieldText`。数据编辑沿用事务、生命周期、用户隔离、时间和历史版本边界。

### Spec

初审1项规格差异：文档所称折叠保留progress并无目标数值进度对应，折叠只显示任务数也遗漏完成状态。已将规格改为completion state，并以两行保留任务数和进行中/已完成，相关窄屏大字测试通过。长标题在320dp的可见字符较少，完整名称仍可从编辑查看；属于界面取舍，无阻断要求。

最终：Standards 0项未解决违规，Spec 0项未解决缺失。未更改数据库schema、RLS或云协议；设备测试均隔离于真实业务账号。

测试稳定性：新增看板测试用可控时间明确两个目标的先后顺序，避免同毫秒创建造成排序不确定及滚动方向错误；生产排序逻辑未改变。
