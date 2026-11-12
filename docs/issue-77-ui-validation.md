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

设备尚未执行：Windows真实拖窗跨断点、1265×682/546×682平台宽窄图、Android411×731单列顺序及触摸复核。没有将 #76 的Windows physicalSize override旧图充作本票原生拖窗证据。
