# 国策卡独立设计复核（2026-11-14）

结论：本轮目标设计缺陷已修复；最终四组共 88 张应用截图与 6 张 Android 原生截图均已实际打开判读，未发现仍需修复的本轮设计缺陷。结论仅覆盖下列状态，不以命令成功或无 overflow 代替设计验收。

## 范围与依据

已实际打开用户提供的三张原始 JPG：`codex-clipboard-890803c5-b537-4fec-9d23-418e6abed203.jpg`、`codex-clipboard-fc3654c0-1356-418e-ab7f-ddeb240a6799.jpg`、`codex-clipboard-ffa61b38-ffdd-42f0-a510-597b79b5177b.jpg`（`C:/Users/Stray/AppData/Local/Temp/`）。确认原缺陷为状态动作纵排、详情例外标题层级失配及默认上下横线、编辑例外标签上半裁切与重复标题。

已读根 AGENTS、UI 指南、ADR 0007/0008，及 apple-design 的 cross-platform、accessibility、layout、typography、color、designing-for-ios/macos、entering-data、text-fields、modality、disclosure-controls、buttons、dark-mode。引用仅转译为 Flutter Android/Windows 的正常字号、触摸/鼠标、亮暗与布局原则；读屏、大字号与专门键盘支持不在本轮验收范围。

- `typography.md › Conveying hierarchy`：“Adjust font weight, size, and color as needed”——同级章节使用一致语义字号。
- `layout.md › Visual hierarchy`：“Align elements to make them easier to scan”——表单与对应保存动作应共享对齐关系。
- `text-fields.md › Best practices`：“include a separate label describing the field”——外部章节标题可承担标签职责，输入框不必重复 floating label；四边和内容须完整。
- `disclosure-controls.md › Best practices`：“hide details until they’re relevant”——渐进展开应保留清楚的标题和内容关系；不机械套用 Apple 原生箭头或数量限制。
- `buttons.md › Style`：“Use style — not size — to visually distinguish”——确认/熄灭用等宽同排和不同强调样式表达一组选项。

## 最终已判读证据

证据根：`build/ui-layout-evidence/national-ui-fix/`。以下四组均 `exitCode=0`、`sourceUnchanged=true`，正常字号。截图统一前缀 `national-focus-card-layers-`。

| run | 实际打开范围 | 当前源 SHA256 核对 |
| --- | --- | --- |
| 20261114-120904-android-light-verified | Android 亮色：21 应用图及 native-focused、native-collapsed、native-end | 278 match；唯一不同为 fixture |
| 20261114-120931-windows-dark-verified | Windows 暗色：21 应用图 | 278 match；唯一不同为 fixture |
| 20261114-121549-windows-light-complete | Windows 亮色：23 应用图 | 278 match；唯一不同为 fixture |
| 20261114-121559-android-dark320-complete | Android 暗色、320 逻辑宽：23 应用图及 native-focused、native-collapsed、native-end | 278 match；唯一不同为 fixture |

最终补充后重新逐项 SHA256 核实：四组均为278 match，唯一不同均为 `integration_test/national_focus_card_layers_device_test.dart`，生产 `lib/` 全部一致。前两组后 fixture 追加 `07c`/`08a` 和滚动取景，四组后又追加默认 false 的可选 `NF_CARD_LAYERS_MOUSE_REVIEW` 分支；属于明确的取证变化。故保留四组视觉结论，不声称前两组含未拍的两个补充状态。指定 `run_focus_pilot.py --verify` 对本批 sourceHashes manifest 不兼容，详见下方历史记录；本次逐项当前 SHA256 比对补足一致性核对。

补充鼠标证据：`20261114-122655-windows-mouse-verified`，manifest `exitCode=0`、`sourceUnchanged=true`，当前279项全部 match。仅额外实际打开 `02b-pending-actions-row` 与 `02d-windows-confirm-hover` 两帧：确认按钮悬停后填充色轻微变深，文字/图标、同排熄灭按钮和布局保持稳定，反馈可见。该 run 在真实 Windows 窗口中运行合成 `PointerDeviceKind.mouse`，不是物理鼠标手工操作；其余22张重复帧未额外目视、不增加本报告覆盖计数。原四组88张之外仅补充这两帧。失败的 `20261114-122426-windows-mouse` 指针设备复用断言不作为通过证据。

| 后缀/状态 | 已打开组与设计结论 |
| --- | --- |
| 01-tree | 四组：节点、名称、状态图标清楚 |
| 02-node-sheet / 02b-pending-actions-row / 02c-extinguished-single-action | 四组：已点亮仅“熄灭”、待今日确认“确认/熄灭”等宽同排、已熄灭仅“点亮”；320 宽仍完整可读 |
| 12-review-blocked-actions-row | 四组：待核对禁用动作仍同排，提示说明原因，详情入口保留；不混同“待今日确认” |
| 03-detail-collapsed / 04-detail-exceptions / 06-detail-strengthened | 四组：例外收起/展开无旧默认上下横线；国策规则/例外/记录同级标题相称，正文左对齐，间距区分章节；强化规则标题完整 |
| 05-card-editor / 05b-card-editor-exceptions-expanded | 四组：已填例外展开后仅一处章节标题；输入框四边完整，无浮动标签重复或半截字符；宽屏保存与字段同列 |
| 05c-card-editor-exceptions-focused / 05c2-card-editor-exceptions-collapsed / 05d-card-editor-exceptions-reopened | 四组：获焦边框完整，直接收起后内容隐藏，再展开正文保留、没有残留焦点边框。两 Android 原生 focused 图：四边及文本完整位于键盘上方；collapsed 图键盘确实消失，无系统 ANR；native-end 均正常应用画面 |
| 07-strengthening-manager / 07b-strengthening-history-expanded | 四组：生效版本分组收起/展开标题与箭头清楚，无旧外横线；Android 亮组07b仅版本内容开头可见，不据此宣称完整历史内容通过 |
| 07c-strengthening-history-content | 两 complete 组：滚动后两版本规则和时间区间均可读；320 换行正常，无外横线或内容裁切 |
| 08a-strengthening-base-collapsed / 08-strengthening-level-editor | 08a 两 complete 组、08 四组：基础规则对照收起/展开均清楚，展开文本与表单间隔稳定，强化字段浮动标签完整；320 AppBar长标题按平台省略，保存按钮完整，不影响正文辨识 |
| 09-strengthening-cap | 四组：已达5级上限信息清楚；Windows图含禁用新建按钮，Android图下部列表在可滚动区域，不宣称画面未见部分已逐项目视通过 |
| 10-failure-history-collapsed / 10b-failure-history-expanded | 四组：失败卡收起/展开外边界完整；内部列表/快照 Divider 有内容分组职责。重复原因已消除；Windows亮 complete 组额外说明与原因组合展示完整。320图长快照为滚动内容，仅判读可见部分 |
| 11-review-source-collapsed / 11b-review-source-expanded | 四组：来源操作收起/展开标题、内容关系清楚；无默认外横线穿透卡片；320下卡片长内容滚动、底部动作换行正常 |

六个共享折叠用法均有收起与展开证据：编辑例外、详情例外、强化版本、基础对照、失败批次、完整来源。前两组缺少的基础对照收起/完整版本内容，由后两 complete 组明确补足。

## 本轮发现与关闭

初轮发现 Windows 保存按钮横跨全窗而表单居中（Medium）；已修复为同列，最终两 Windows 组逐图复查关闭。初轮失败原因重复（Low）；最终四组复查关闭。旧用户图中的三类原缺陷在最终四组相应状态均未复现。

安静的 Material 内容层保留了清楚的主动作与低频展开层级，没有为去横线删除有分组职责的内部 Divider。此为本轮设计判断；没有宣称对比度数值达标（未测量颜色值）。

## 初轮记录（不作最终通过依据）

证据根：`build/ui-layout-evidence/national-ui-fix/`。截图统一前缀 `national-focus-card-layers-`。

`20261114-114836-windows-light`：20 张全部已实际打开，manifest `exitCode=0`、`sourceUnchanged=true`。运行 `python scripts/run_focus_pilot.py --verify <run>` 返回 `error reason=no-source-files`（manifest 使用 sourceHashes，与该脚本读取结构不同），随后逐项 SHA256 比对 manifest 279 项，279 match、0 missing/mismatch。开跑 HEAD 为 c5120ec；不能仅因随后提交改变 HEAD 否定内容一致性。

| 截图后缀 | 画面判读 |
| --- | --- |
| 01-tree | 三个节点、名称与状态图标清楚 |
| 02-node-sheet / 02b-pending-actions-row / 02c-extinguished-single-action | 已点亮仅熄灭；待今日确认时确认/熄灭等宽同排；已熄灭仅点亮；层级清楚 |
| 03-detail-collapsed / 04-detail-exceptions / 06-detail-strengthened | 规则、例外、记录的同级标题相称；例外收起/展开无旧默认上下横线；展开正文完整 |
| 05-card-editor / 05b-card-editor-exceptions-expanded / 05c-card-editor-exceptions-focused / 05c2-card-editor-exceptions-collapsed / 05d-card-editor-exceptions-reopened | 已填例外展开、获焦、直接收起、再展开已判读；框四边完整，外部标题只出现一次，重开内容仍在；保存动作横跨全窗口，与居中表单不对齐（Medium，已反馈主 Agent 修复后重拍） |
| 07-strengthening-manager / 07b-strengthening-history-expanded / 08-strengthening-level-editor / 09-strengthening-cap | 版本记录收起/展开无默认外横线；对照基础规则展开完整；上限禁用状态清楚；08未提供该控件收起图 |
| 10-failure-history-collapsed / 10b-failure-history-expanded | 卡片圆角边界完整；外横线已去除；内部列表/树快照之间 Divider 有分组职责，予以保留；两条副文案重复“未完成今日确认 · 未完成今日确认”（Low，已反馈） |
| 11-review-source-collapsed / 11b-review-source-expanded | 来源操作收起/展开布局清楚，无新增外横线或卡片边线穿透 |

## 限制

Android 输入法结论来自上述两组同源原生图，不能用仅应用截图替代。动画仅看展开、收起、再展开的最终稳定态，未观看连续动画，不宣称过渡帧通过。未覆盖空白例外输入框（本轮复现与目标为已填字段），不将其记为已目视验收。Windows 鼠标补充目视限于上述正常/悬停两帧及合成指针边界，本复核没有操作 GUI 或运行测试。

`20261114-115024-android-light` 的 rc4/系统 ANR 与 `20261114-120001-android-light-final` 的取景时序问题均排除，不用于最终通过；smoke 与其余候选图同样不替代上述四组。
