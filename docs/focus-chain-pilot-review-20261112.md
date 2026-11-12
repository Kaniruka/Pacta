# 专注链小试点评审 · 2026-11-12

## 范围与当前结论

总体结论：Good，本轮范围内设计复查通过，当前无未解决视觉发现。启动区信息更紧凑，链指标可连续扫读；保留现有主题、三条链、动作编辑及统计业务口径。专注工具保持安静实用的视觉表达，未加入装饰性指标。独立评审未修改源代码。

已通过 view_image 实际打开 Windows 默认宽／窄、零值浅色、少量和长动作的同状态 before／after；复查真实 Windows 缩窗、滚动和编辑弹窗，以及 Android 浅色默认和真实返回／恢复、IME、改值取消／保存。唯一视觉改善项“预约最佳过远”已修复并经最终新图复查；旧图归档差异也已通过 after-final 闭环。

证据边界：不是每个平台每个数据与主题组合的穷举；Android改前同状态图未由独立评审打开，Android默认／long自动通过来自执行Agent报告且日志未持久，不能冒称独立核读；Android真实操作有原生截图及hold日志，600秒hold终态现已独立核读为 All tests passed。手动恢复只确认同任务／模式，Session id相等来自自动断言。未从截图虚构精确对比度，long场景不充作长时长数值压力证据。这些限制不构成本轮新增缺陷。

依据 ADR 0007／0008，读屏、Semantics、大字号、专门键盘操作均不列为本轮缺陷或门槛。保留正常字号可读性、亮暗主题、长中文、窄宽响应、鼠标／触摸和 Android 系统返回。

## 适用依据

已读取 apple-design 技能及 11 份参考：cross-platform、accessibility、layout、typography、color、designing-for-ios、designing-for-macos、buttons、lists-and-tables、writing、dark-mode。只转译基础原则，不引入 Apple 平台导航、菜单、字体尺寸、玻璃材质或键盘习惯。

| 检查 | 参考及原文 | Pacta 适用方式 |
| --- | --- | --- |
| 主操作层级 | `layout.md › Visual hierarchy`: “Order content by relative importance.” | 流程恢复／任务启动先于历史统计；历史保留页头次级入口。 |
| 指标扫读 | `layout.md › Visual hierarchy`: “Align elements to make them easier to scan” | 连续／最佳及累计／平均形成可辨关系，窄屏不挤压或断义。 |
| 同类归组 | `layout.md › Visual hierarchy`: “Group related items to clearly express related information or functions.” | 链自己的承诺动作与指标仍归该链；指标组内不被无关层级切断。 |
| 正常文字层级 | `typography.md › Conveying hierarchy`: “Adjust font weight, size, and color as needed to emphasize important information” | 使用现有 TextTheme；连续优先，次级指标清晰可读。 |
| 操作显著性 | `buttons.md › Style`: “use a button that has a prominent visual style for the most likely action” | 选择任务保持主操作，编辑和历史保持次级。命中区遵循项目 Android 48×48。 |
| 简明与空状态 | `writing.md › Getting started`: “If you can use fewer words, do so.”；`Best practices`: “Provide clear next steps on any blank screens.” | 压缩启动区重复引导；零值仍真实可见，不替换为虚构趋势。 |
| 亮暗可读 | `dark-mode.md › Best practices`: “Ensure that your app looks good in both appearance modes.” | 延用 ColorScheme；由实际截图和色值复核，不能仅凭截图断言精确对比度。 |

项目依据：`docs/agents/ui.md` 的 UI 要求／验收，`docs/product-design.md › Chain commitment actions and duration`，`docs/spec-pacta-refinements-20261022.md › 专注导航与模式`。

## 历史阶段记录（后续闭环见文末）

以下保留发现位置、用户影响、依据、处理与逐轮新图复核轨迹；“待补”“尚未通过”等均指该阶段，当前结论及限制以上方为准。

### 代码初评

1. 启动区现为说明句、分区标题、任务数、选择按钮四个纵向台阶。可将任务数归入标题或说明并减少台阶；此为设计判断，需截图比较。
2. 链卡当前将连续／最佳放在顶部，累计／平均放在承诺动作之后。可形成一个清晰指标组并保留连续优先，减少视线跨越动作区；此为设计判断，需截图比较。
3. 零记录当前同样铺满大连续值、最佳、未设动作和时长。可收紧分组间距，但不能删去三条链、隐藏真实零值或将预约链混入独立时长口径。
4. 保留项：现有 Material 3 主题；精锐／普通在足够宽度并排；预约链独立紧凑卡；三个动作各自编辑；统计包含失败有效时间、不含暂停；标题历史入口；恢复操作优先；主页不随任务数量增长。

## 待复查证据

需要同数据、同尺寸、同主题的 before／after：Android 窄屏，Windows 窄／宽窗口；零与少量记录；至少一组亮暗；长时长和长承诺动作；滚动涵盖三张卡。实际操作应覆盖任务选择取消、历史往返、三个动作编辑取消／保存、已有流程恢复。

后续评审逐条记录截图位置、用户影响、依据、处理及新画面复查；截图必须通过 view_image 实际打开。截图不足的状态明确列作未验证，不推断通过。

## 基线画面与实现方向复查

已实际打开 `build/ui-layout-evidence/focus-pilot/before/focus-chain-normal.png`（1582×853，Windows 深色、正常字号，精锐／普通各连续3次、最佳3次、累计1小时25分钟、平均21分钟15秒；预约零记录）。

| 位置与影响 | 依据 | 当前实现处理 | 新画面复查 |
| --- | --- | --- | --- |
| 启动区约 y134–254，标题、任务数和按钮占三行，使链区起点下移 | layout › Visual hierarchy，同类归组；writing › Getting started，简明 | 启动标题和任务数置同一 Wrap，次要任务数用 onSurfaceVariant | 待 after；不得预记通过 |
| 精锐／普通卡约 y424–627，连续／最佳与累计／平均被标志区切断，扫读需跨越动作 | layout › Visual hierarchy，对齐和归组 | 时长移到动作前，与计数同一指标组；连续／最佳等宽基线对齐 | 待 after；额外关注预约通栏卡中两列距离是否过大 |
| 三卡累积高度导致预约卡动作区落在首屏之外；基线首屏非裁切错误，可正常滚动仍需操作证据 | designing-for-macos › Best practices，舒适信息密度（转译为可调窗口基础原则） | 卡 padding20→16，标题与计数间距16→12，时长组顶间距20→12 | 待 after；比较信息密度，不要求三卡强制塞入首屏 |

源码 diff 显示改动仅涉及上述组织和间距，保留三个链记录、编辑入口与实际统计取值；视觉判断仍以新画面为准。

## 同状态宽屏改后复查

实际打开 `after/focus-default-wide-overview.png` 和 `after/focus-default-wide-records-scroll.png`。overview 与基线均1582×853、同数据及深色主题。滚动图展示预约动作与统计口径尾注。

- 启动区：通过。标题与任务数同组，按钮从约 y214 上移到 y174，链区随之上移约40截图像素；主按钮仍最显著，历史保持页头。
- 精锐／普通指标：通过。两张卡的连续与最佳、累计与平均形成两列，时长不再跨越动作区；卡高从约323缩至298截图像素。数值、标签、动作区分隔清晰；没有新增颜色或装饰。
- 少量记录密度：本组通过。默认3次记录的三卡主体均更接近首屏，滚动后尾注完整；不要求尾注强行塞入首屏。
- [Low] 预约卡最佳距离：当前连续约 x282，最佳约 x849，两项隔开约567截图像素，而预约无下方时长列呼应。没有信息丢失或误读风险，不阻塞本轮；建议仅预约卡使用间距16的紧邻计数组，精锐／普通保持等宽列。依据 `layout.md › Visual hierarchy` 的相关内容归组与对齐原则；具体距离取舍属于设计判断。等待主Agent采纳或明确保留，若改需再看新画面。

测试状态由主Agent报告：flutter analyze 通过、完整 flutter test 336通过；独立评审未重复执行。平台流程恢复断言曾误点标题，尚待修正重跑，因此恢复截图不能作为通过证据。零记录、长内容、窄屏与亮色仍待后续图像及操作记录。

## 预约项闭环与正常窄屏复查

实际打开 current 下 `focus-default-wide-overview.png`、`focus-default-narrow-overview.png`、`focus-default-narrow-records-scroll.png`、`focus-default-wide-restore.png`、`focus-default-wide-after-back.png`。

- 预约 Low 项已解决：新宽图连续与最佳为紧邻组（连续 x282、最佳 x385），消除原567截图像素分离；精锐／普通两列仍保持原对齐。新画面复查通过。
- 正常窄屏当前画面通过：启动标题／任务数单行归组，主按钮清晰；两张主链卡纵向排列，连续／最佳与累计／平均的列关系稳定，动作长短适中且编辑入口可见。滚动图完整展示预约链、触发信号及尾注，未见遮挡或截断。
- 窄屏证据边界：Windows 运行中 tester.view 420×820逻辑像素、DPR1.25的约束渲染；不能据此声称真实 Windows 窗口拖动或 Android 设备触摸通过。窄屏基线尚未收到，因此这里只确认当前布局可读，不宣称该状态前后改善。
- 恢复证据已补齐：实际打开的 after-back 图显示进行中卡及“返回专注”按钮，restore 图显示原任务“阅读一章，留下三个要点”的专注进行中页面。核读 `logs/run-default-wide.log` 末尾为 All tests passed，并核查 `integration_test/focus_chain_design_device_test.dart` 操作点已为“返回专注”，随后断言活动 Session id 保持。该 Windows 自动运行路径通过；这不替代人工鼠标操作或 Android 系统返回证据。

零记录、长内容、亮色及对应基线仍待后续证据，未作通过结论。

## 零／少量／长动作当前图复查

实际打开 after 下 `focus-zero-wide-overview.png`、`focus-few-wide-overview.png`、`focus-long-wide-overview.png` 与 `focus-long-wide-edit-dialog.png`。

- 零记录当前图通过：连续、最佳、累计、平均均保留真实0；未用虚构趋势填空。主操作优先级和三链结构稳定。该文件实际为浅色截图，不能与深色基线宣称同条件对比。
- 少量记录当前图通过：1次、累计25分钟、平均25分钟均清楚，指标组与动作组分隔自然。尚待同状态 before 评价具体改善。
- 长动作策略通过：普通链完整中文自然换行成两行，卡片随内容增高，编辑图标与文字互不遮挡；精锐一行与普通两行造成的卡底不同高是合理内容适应，无需强制等高。依据 `layout.md › Adaptability` 的“Design a layout that adapts gracefully and consistently.” 与 `Visual hierarchy` 归组原则。
- 编辑弹窗当前画面通过：完整长动作、字段标题、清除说明及取消／保存均可读；不能仅凭静态图宣称取消／保存持久化成功，仍以操作脚本和日志为证。
- 新画面未引入额外问题。此处 long 场景主要是长动作，画面时长仍为1小时25分钟／21分钟15秒，不能充作长时长数字压力证据。

真实 Windows 窗口尺寸调整／鼠标滚动仍待截图和操作证据。所有当前图的通过仅指已打开画面的可见布局；不扩展为未见状态通过。

## 真实 Windows 窄窗口复查

实际打开 manual 下 `native-narrow-top.jpg`、`native-narrow-bottom.jpg`、`native-narrow-editor.jpg` 与 `focus-long-wide-overview-after-hold.png`。主Agent使用原生系统菜单大小模式缩窗并通过 sky 鼠标操作；此批是真实窗口证据，区别于前述 tester.view 渲染。

- 顶／底图通过：主操作和分区清楚，主链单列、指标两列；长动作完整换行，图标未压字。滚动到预约卡及尾注后底部导航不遮最终内容。
- 窄弹窗通过：字段动作两行完整、清除提示和取消／保存按钮均在可见区域。未见本轮布局缺陷。
- 操作范围按主Agent证据记录：真实鼠标打开、取消、重开、保存原值，以及滚动；sky键入尝试未改变字段，不声称人工修改文本验证。自动 enterText＋仓储断言与人工操作应分别记录。
- 已通过绝对路径独立核读 `build/ui-layout-evidence/focus-pilot/manual-drive-3.log`：platform=windows，最终逻辑窗口546.4×682.4、DPR1.25、正常字号1.0、三项insets为0，起点1265.6×682.4；hold300s后记录新尺寸并截图，最后 All tests passed。此前误查 logs 子目录，加上 rg 默认忽略 build 未找到；现已闭环。日志保留 integration_test plugin 未检测到的提示，不将自动驱动结果扩展为未执行的原生框架验证。

Android与同状态before仍待补；真实Windows窄窗口可见布局没有未解决项。

## Android 默认当前图复查

实际打开 `android/default/focus-default-wide-overview.png` 与 `focus-default-wide-records-scroll.png`，浅色、正常字号。文件名 wide 只是脚本参数，画面为411.4×731.4逻辑像素移动窄视口，不称桌面宽屏。主Agent提供设备参数：独立Android35/API35 AVD，1080×1920、density420、DPR2.625、字号1.0、上下padding/viewPadding24、viewInsets0。

当前画面通过：启动主操作明显，标题与任务数归组；主链纵向堆叠，两列计数与时长保持可读且有独立动作区；预约连续／最佳紧邻，触发信号明确。滚动图包含普通、预约及口径尾注，尾注没有被底部导航遮住。普通文字和图标在浅色画面清楚，未从截图推算精确对比度。

默认自动流程通过由主Agent报告，独立设计评审尚未核读本批日志；真实ADB系统返回尚未通过，不能用当前截图替代。Android同状态before、zero／long仍待补，未判相应前后改善或完整移动验收通过。

## 隔离原HEAD基线同状态对比

实际打开 before-states 与 after 各自的 default-wide／default-narrow overview 和 records-scroll（共8张）。主Agent说明 before 源为原HEAD lib、fixture相同、metrics相同；画面可见数据和主题一致。

- 默认宽／窄同状态对比通过：启动按钮与链区均上移约40截图像素，主链卡高约323→298截图像素。窄屏原普通卡累计／平均落在导航后，改后首屏完整可见。指标顺序调整后无需跨过动作区寻找累计／平均，各项值与动作文字均保留。
- 正常窄屏前后证据缺口已补齐，采用现有两组分组和可读性，不再列为待补。
- 证据批次待整理：`after/focus-default-wide-records-scroll.png` 仍显示预约最佳位于约x849的旧版；同目录 overview 与 current 修复图已是约x385的紧邻组。该问题是归档图不一致，不能据此回报源码回归。已请主Agent补更新scroll或明确标识旧版，之后再复查；narrow scroll 为正确紧邻版本。

## 零／少量／长动作同状态基线补齐

实际打开 before-states 下 zero-wide-overview-light、few-wide-overview、long-wide-overview，另打开 after 下确切改名后的 zero-wide-overview-light，并与此前已打开的 after few／long 比较。三个场景主题、数据和宽度匹配。启动区减少一行，指标先成组再到动作，三卡内容密度改善；0、1次25分钟、3次及长动作均完整保留，同状态改善通过。浅色零值与深色少量／长动作分别评判，不混作同一主题对比。

## Android 真实系统返回与改值闭环

实际打开 android/manual 下 06-active、07-system-back、08-restored、09-scroll、10-editor、11-edit-cancel-input、12-edit-cancel-result、14-edit-saved、15-edit-reopen 共9张原生截图。

- 真实系统返回／恢复通过：主Agent执行ADB keyevent4后，画面从专注执行回到进行中卡，点击返回专注后回到同任务“阅读一章，留下三个要点”的普通链执行画面。图片只佐证同任务和模式，不声称人工路径Session id相等；自动恢复id断言另有前述脚本证据。
- 输入法布局通过：IME打开时动作字段、清除提示、取消和保存均在键盘上方可见；输入变两行后无控件遮挡。
- 真实改值取消／保存通过：输入pilot-cancel后取消，列表保留原动作；另行输入pilot-save保存，列表显示追加值，重新打开字段仍为pilot-save且没有pilot-cancel。改值与取消／保存的结果可见，未将仅截图当作数据库内部id证据。
- 滚动图主链和动作正常，没有新问题。此操作批次为zero场景，可同时作为零记录真实移动界面证据。
- 独立核读 `android/manual-live.log`，记录platform=android、scenario=zero、411.4×731.4、DPR2.625、正常字号、上下padding/viewPadding24、viewInsets0及hold600。所读日志未出现最终 All tests passed，不把持有人工操作窗口等同于自动完成结果。

当前已查看的视觉无未解决项；仅宽屏旧scroll归档待最终新版图复查，Android改前同状态图尚未由独立评审打开。

## 最终复核与证据优先级

实际打开 `after-final/focus-default-wide-overview.png` 与 `focus-default-wide-records-scroll.png`，并独立核读根目录 `after-final.log` 末尾 All tests passed。两张图均为修复后预约连续／最佳紧邻布局，scroll中最佳约x385，尾注完整，未见新问题。

旧 `after/focus-default-wide-records-scroll.png` 只作历史中间态，不用于最终验收；最终Windows默认宽屏以 after-final 为准。归档差异闭环，预约 Low 项已闭环。其余已打开的同状态基线及真实Windows／Android证据结论保持；本轮无 Critical／High／Medium／Low 遗留设计项。

Android hold终态补充：已独立核读 `android/manual-live.log` 最后22行，600秒后 overview-after-hold 仍为411.4×731.4、DPR2.625、字号1.0、上下padding/viewPadding24、viewInsets0；随后截图路径记录为 `android/manual-live/focus-zero-wide-overview-after-hold.png`，tearDownAll后两处 All tests passed。此处仅按请求核读终态日志，没有追加场景或把日志截图路径记作已打开图像。主Agent最终报告完整 flutter test 336通过、final analyze No issues found；独立设计评审不重复冒称执行。评审结束。
