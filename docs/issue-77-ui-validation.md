# Issue 77 看板支撑摘要与宽度切换验证

实施代码审查基点 `c9bbef2ee5b0fbea32987e2a6ca7e07437b4322d`（已接受 #76/#80）；设计基线 `ui-focus-pilot-accepted-20261112`。工作树 `C:/Users/Stray/.codex/worktrees/spec75-t77/Pacta`，分支 `ui/77-board-support`。范围为三张支撑摘要和既有看板离线取证；没有修改 production、统计、结算、日历读取、目标任务呈现或导航职责。

## 基线、判断与测试边界

开始工作树干净；原 `flutter test test/board test/ui_layout_test.dart` 16/16 通过（`build/t77-baseline.log`、`.rc`）。代码事实：看板实际分配宽度至少960时双列，支撑列320；活动行内容宽度小于360时日期/时长位于柱上方，否则横排。这两处是既有判断，未新增栅格或阈值。

已确认的公开测试边界是 PactaApp/AppShell + 真实内存 Drift 本地任务、专注、国策仓储；仅外部认证使用现有 fake。新增测试通过公开仓储创建目标、任务、活动及待确认国策，观察页面事实、几何、滚动和导航，不调用私有组件。

0/1/7日三条测试首轮失败是测试假设错误：零国策使用“国策树尚无节点。”而非虚构0计数；累计时长使用91分00秒；单列日历按惰性列表滚动后构建。修正预期和滚动步骤，没有把这些失败记为产品缺陷或红绿修复。当前没有复现需要改生产布局的问题，因此按票据要求保留 production。

## 设计依据与自查

读 UI 指南、product-design “Board content hierarchy”、父规格US5–6、ADR0007/0008。ui-ux-pro-max 查询 `responsive layout constraints --stack flutter` 返回 LayoutBuilder/constraints，适用于现有布局，不采用新视觉系统。apple-design 已读基础与跨平台、列表、标签及滚动参考；`layout.md › Visual hierarchy` “Order content by relative importance.”、`Adaptability` “Design a layout that adapts gracefully and consistently.” 转译为任务优先、随实际空间切列；`scroll-views.md › Best practices` 避免同方向嵌套滚动；`labels.md › Best practices` 使用系统字体和语义颜色。按ADR不新增读屏、大字号、键盘专项。

组件证据说明主操作和任务在支撑内容之前，三卡独立且顺序保持；正常字号日期、柱、时长关系未丢失，单日仍显示七日事实，零活动不绘制虚构活动。真实平台截图尚待执行，组件测试通过不等于视觉验收通过。设计轴独立打开宽窄图及Standards/Spec独立审查由主线程完成。

## 新增验证与fixture

- 活动0/1/7日：累计0分00秒/13分00秒/91分00秒，日期11月6日–12日，国策空/确认1，空日历。
- 正常字号动态宽度1200、1041、1040、1039、546、320、再1200（高800）。实测AppShell侧导航+分隔线81逻辑像素：1041窗口看板960并排，1040窗口看板959单列。断言依据公开BoardPage实际尺寸，未从窗口反推生产布局。
- 活动柱宽度有效并在视口内；320及双列窄卡为日期在柱上方，546单列为横排。日期不截断；七条日期/时长/柱仍在。
- 向下滚动到空日历，国策入口到树再返回看板；既有长目标/长任务测试保留。
- 既有设备fixture复用board场景：`default`=7日活动+长任务列，`few`=单日活动+短任务列，`zero`=空；default/few为待确认国策+空日历。`long`继续沿用#76任务交互fixture。每个活动13分钟，无真实账户、云数据或用户数据库。
- Windows `--manual-hold` 时 resetPhysicalSize，允许原生窗口尺寸实际影响布局；普通wide/narrow仍是测试视口override，不能称为原生拖窗。runner源码manifest补纳国策摘要及日历卡源码。

## 命令与证据

日志位于此工作树 `build/`，同名 `.rc` 保留退出码。`dart format` 已执行改动Dart文件。`flutter analyze --no-pub` 在fixture准备后No issues found（`t77-analyze-final.log`，rc0）。最终 `flutter test --no-pub test/board test/ui_layout_test.dart` 19/19通过（`t77-tests-final2.log`，rc0）；`python -m unittest scripts.test_run_focus_pilot` 12/12通过（`t77-runner.log`，rc0）。活动行关系断言首次将相邻边界写成严格大于，Ahem标签恰好填满118宽时失败；修为允许相邻后通过，没有改生产代码。fixture最终格式化后再次 analyze 结果见 `t77-analyze-ready.log`。

设备阶段完成的Windows证据见下；Android411×731单列顺序及触摸尚未执行，未将Windows图替代Android。


## Windows 实机证据（2026-11-12至13）

设备阶段先fast-forward集成 `a4e1177cf9a75b1b8e99af2684e58b96d818c218`。该轮 main SHA256 `A215B7CA7E9156F88AB2E92C12D3FBC5E3A48148DB4A45CA1C288D33CC96EF9B`；最终fixture SHA256 `4180256368A4870B82C6405AB9E88E478771B8FD5ED1BBF2FF5D4726135FF523`。每轮manifest记录HEAD、源码起止SHA256与参数，以下所有轮 `source_drift=[]`。后续合入同步/专注票时不把这些截图冒称为其新源码证据。

绝对证据根 `C:/Users/Stray/.codex/worktrees/spec75-t77/Pacta/build/ui-layout-evidence/board-pilot/runs/`。各目录均保留 `run.log`、`run.rc`、`manifest.json` 和独立PNG，不覆盖原图。所有Windows DPR1.25、正常字号。

| 目录 | 条件/结果 |
| --- | --- |
| `t77-seven-wide-default-wide` | 测试视口1265×682、七日91分00秒、长任务列、确认1/空日历、暗；rc0，展开/支撑两图 |
| `t77-seven-narrow-default-narrow-light` | 测试视口546×682、同七日fixture、亮；两图完成，返回看板后页头断言失败rc1（保持滚动位置后页头未构建），只修测试滚回顶部 |
| `t77-seven-narrow2-default-narrow-light` | 同窄亮fixture重跑，rc0；主操作首屏优先，滚动到完整三张支撑卡、进入国策树并返回 |
| `t77-one-narrow-few-narrow` | 测试视口546×682、短任务列、单日13分00秒/其余六日0、确认1/空日历、暗；rc0，展开/支撑两图 |
| `t77-native-long-long-wide-hold300` | 原生窗口1265.6×682.4→1041.6（Board960并排）→517.6（单列）→216（误操作，低于支持范围，不纳入验收）→最大化1536×792.8（Board960）；实际跨条件图保留，尾部SemanticsHandle断言rc1，不计整轮通过 |
| `t77-native-threshold-long-wide-hold120` | 原生窗口1265.6×682.4（Board960）→545.6×682.4（Board545.6单列）；rc0。目录名是初始计划，实际执行为正常窄窗操作；不声称取到了精确1040.8 |

固定视口轮是Windows app上的physicalSize override；只有两轮manualhold resetPhysicalSize、由sky系统窗口操作产生的native图是原生拖窗。新增最小fixture记录：仅首次及每2秒观测到尺寸改变时，复用shot保存新编号图，log同时写视口和公开BoardPage的实际宽度。没有新增测试框架或关闭框架检查。

实际拖窗方法按computer-use技能，仅sky：系统菜单Alt+Space→大小→Right选择右边框→drag；一次拖完用Return结束尺寸模式，再点页面。首轮第二次调整中的越界/unknown screenshotId后只刷新，不继续用旧状态；意外窄至216后退出模式并最大化恢复。该工具操作问题不作为产品缺陷；成功短轮从初始窗口直接拖545.6，未复用该异常流程。

### 实际打开的图与操作

实现者打开七日宽暗 `board-default-wide-expanded.png`、七日窄亮重跑的 `board-default-narrow-expanded.png` / `support.png`、单日窄暗 `board-few-narrow-support.png`、成功原生窄窗 `board-long-wide-native-0.png`。结论：任务首屏与新建操作优先；三卡独立，完整七日日期/时长/柱关系可读；窄窗单列横排活动行，宽窗窄支撑卡采用日期/时长在柱上方；待确认国策计数及空日历真实，无新增层级或密度问题。原生1041.6并排/517.6单列在sky中当场观察，截帧没有横向溢出。未录制拖动视频，不能以静态截帧保证每一过渡帧。

成功120秒轮的sky鼠标操作：真实545.6窄窗点长任务开始，看到完整“开始专注”与任务名并取消；点任务文字，看到“编辑任务”、原始名称/描述/120分钟/截止并取消；点击目标标题折叠并展开，任务按预期隐藏和恢复。操作图为该目录 `sky-narrow-start-dialog.png`、`sky-narrow-edit-dialog.png`、`sky-narrow-collapsed.png`（保存自已显示的sky截图，用于持久化验收证据）。首轮最大化窗口也完成开始/编辑与取消，保存 `sky-wide-start-dialog.png`、`sky-wide-edit-dialog.png`，因该轮rc1仅作为实际操作事实。未确认删除、未启动倒计时、未改变用户数据。

短轮鼠标滚动一次看到国策与近期活动；下一次滚动时120秒自然结束、窗口关闭，sky报告foreground没有process id，未继续输入；不把该动作算作完整滚动验收。完整支撑滚动和树往返已由上述rc0普通轮完成。

### 尾部框架失败边界

300秒轮尾部报 `A SemanticsHandle was active at the end of the test`，期间有引擎AXTree pending警告；原始日志保留，未关闭Semantics检查、未手工释放不属于fixture的handle、未归因成已修复产品缺陷。查本机Flutter源码：`semantics/binding.dart:162` 在平台semanticsEnabled改变为true时自动ensureSemantics，`widget_tester.dart:179/1066` 记录起始handle数并在结尾比较。平台动态启用可能解释尾部增量，但未插桩验证，根因仍未确定；同一源码短120秒sky操作轮rc0，普通自动轮也rc0，不能据此声称长轮问题已修复。

Android仍由主线程协调。独立设计轴需主审打开宽窄图给结论；实现Standards/Spec比较基点仍取本票开始的c9bbef2，集成的其他票差异应按commit/path区分。


完成设备取证后，将当前integration `7d11f13` 合入本票分支（merge `85d1e81`），包括其他票同步呈现与专注IME修正；本票生产看板代码仍未改变。最终 `flutter analyze --no-pub` 无问题（4.4s，`build/t77-integrated-analyze.log/.rc`，rc0）；`flutter test --no-pub test/board test/ui_layout_test.dart` 19/19通过（`build/t77-integrated-tests.log/.rc`，rc0）。Windows取证均在合并前的a4e1177源码上；合并后仅运行上述检查，未重新声称整合后平台截图通过。
