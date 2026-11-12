# #75 全局 UI 推广：交付与验收

2026-11-12 至 2026-11-13（Asia/Shanghai）。设计基线 `ui-focus-pilot-accepted-20261112`；仓库起点 `b0332493dd5b8184a036aab925e0ebdec0b3a71b`，初始工作树干净。

## 交付范围

| 票 | 结果 | 独立 PR |
| --- | --- | --- |
| #76 | 目标摘要合为一组；任务预计、已专注、待核对、截止按可用宽度换行 | [#83](https://github.com/Kaniruka/Pacta/pull/83) |
| #77 | 未复现生产布局缺陷，保留三张支撑卡与既有断点；补0/1/7日及真实窗口核验 | [#84](https://github.com/Kaniruka/Pacta/pull/84) |
| #78 | 输入法压缩内容区后保持时长框及错误提示可见；结算返回文案准确 | [#85](https://github.com/Kaniruka/Pacta/pull/85) |
| #79 | 窄卡完整状态独占一行；覆盖后果紧邻方向，取消/忽略及下载限制保持 | [#86](https://github.com/Kaniruka/Pacta/pull/86) |
| #80 | 未复现国策页头生产缺陷，保留现状；补短窗、放置、视图恢复与画布证据 | [#82](https://github.com/Kaniruka/Pacta/pull/82) |

汇总分支 `integration/spec-75-ui`，总 PR [#81](https://github.com/Kaniruka/Pacta/pull/81)。独立 PR 按80→76→77→78→79堆叠，以保持每票差异可审查；集成分支包含全部实现。未代替用户合并远端 PR；合并总 PR 后通过 closing references 关闭规格与实施票。#54 不修改、不关闭。

没有新增业务字段、状态或导航目的地，没有改变数据库、身份、同步协议、任务分类或结算规则。设备只用隔离本地fixture、真实本地仓储与外部服务替身，无真实账号或云端往返。

## 主线程最终检查

Flutter 3.47.2 / Dart 3.13.2；Windows 主机，Android 模拟器。最终源检查基于 `169dd44`；随后仅补充证据文档和审查链合并，源路径 `lib/test/integration_test/scripts` 保持等价。

| 命令/边界 | 实际结果 | 主树本地原始日志 |
| --- | --- | --- |
| 改动Dart文件format检查 | 17文件，0 changed，rc0 | build/spec75/root-checks/final-format.log |
| flutter analyze --no-pub | No issues found，rc0 | build/spec75/root-checks/final-analyze.log |
| flutter test --no-pub | 完整354项通过，rc0 | build/spec75/root-checks/final-full-tests.log |
| Python runner unittest | 12项通过，rc0 | build/spec75/root-checks/final-runner-tests.log |
| 国策三个相关测试文件 | 主线程独立复跑28项通过 | build/spec75/root-checks/t80-tests.log |
| 看板/布局/专注导航 | 主线程独立复跑24项通过 | build/spec75/root-checks/t76-tests.log |

每票的red/green、相关回归及实际命令见各票验证记录。普通单元测试不冒充设备测试；设备替身不冒充真实云服务。版本库改动未发现疑似凭据内容，检查记录在 `build/spec75/root-checks/secret-scan.json`。

## 平台与设计轴

- Android：专用AVD `PactaFocusPilot20261112`，1080×1920、DPR2.625，实际约411.43×731.43，正常字号。未操作已连接的物理设备。
- Windows：固定渲染图1265×682 / 546×682；另有真实窗口1265.6×682.4→545.6×682.4、断点两侧与鼠标操作证据。同步票的真实窄窗为536.8×682.4，不能写成精确546。
- Widget：正常字号320×800 / 1200×800及页面实际断点两侧。没有跑平台/字号/主题完整笛卡尔积。
- #76：主线程打开同fixture窄暗/宽亮前后和空态，确认截止由不可见变为完整可读，主操作与开始图标保留，摘要层级清楚。Windows鼠标和Android仪器化触摸覆盖折叠、编辑取消/保存、开始取消。
- #77：主线程打开七日宽暗/窄亮、单日及原生窄窗图，确认三卡独立、零值真实、日期/柱/时长关系完整。实际拖窗及国策树往返有单独证据。
- #78：主线程发现初轮IME图中时长框被遮，要求补完整可见断言；最终实际打开native-ime，确认字段边框、值、光标、键盘与两个开始按钮同时可用。两入口落点及唯一流程恢复不变。Windows宽窄前后均通过。
- #79：主线程打开Android亮色、Windows暗色同态前后图，方向后果对应清楚，取消/忽略与禁下载原因可辨；去除新增分组后的重复通用覆盖句。
- #80：主线程打开绿色主题小树、放置、短窗、50节点与错误态；再核对原生Windows窄图、Android亮色图及Windows四节点预览。两平台均有两个不同PID读取相同隔离SQLite、恢复详细视图的证明；Android手势与节点操作各1完整场景通过。

设计依据是项目UI指南，借用apple-design `layout.md / Visual hierarchy` 的分组与顺序、`typography.md / Conveying hierarchy` 的文字层级、`modality.md / Best practices` 的明确退出、`writing.md / Best practices` 的动作与落点一致。遵循ADR0007/0008，不移植Apple专属风格，不扩读屏、大字号或专门键盘专项。生成PNG或无overflow本身不等于视觉通过。

## Android系统触摸与失败边界

主线程已实际打开ADB系统截图，区别于不含系统弹窗的FlutterView图。修正后的三轮保持原生surface到手动检查结束，再转换截图：

| 主树原生证据目录 | 实际完成 |
| --- | --- |
| build/spec75/native-board-touch-fixed-20261113 | 目标折叠/展开、任务编辑取消 |
| build/spec75/native-board-touch-fixed-retry-20261113 | 追加`_BoardTouch20261113`并保存，回看板可见新标题 |
| build/spec75/native-board-touch-focus-cancel-20261113 | 开始设置打开、取消、回看板，无系统遮挡 |

三轮均在fixture HEAD `45343184e` 自然结束，run.rc/process_rc=0，source_drift=[]、git_status=[]；READY及nativeSurface=true在转换前。动作分布在三轮，不声称单轮覆盖全部。前两轮中超出hold窗口的动作没有计入通过。组合说明在首个目录的notes.md。

失败记录全部保留：初轮Android强制物理视口造成截图等待，撤覆盖并显式重绘解决挂死与首帧空图；手动模式另复用已接受专注试点的延后转换规则。早期调试启动曾记录FocusEvent等待约5秒的ANR，未修复轮点Wait后仍遮挡，未作触摸验收。修正后三轮READY/实际操作截图无遮挡、未点Wait，但不把取证机制修正宣称为根治ANR或验证了启动性能。

Windows部分较长手动轮出现SemanticsHandle清理断言，保留rc1；同源码短轮通过，未关闭检查、未声称已确定原因。国策手势首次真运行发现fixture无滚动空间，最终仅将测试页面约束为500高并明确overflow前提，全部原手势断言保留；生产画布未改。

## 实现轴独立审查

Standards与Spec由两个新上下文并行审查，固定整体 `b033249...3ee23311` 并按票实施基点隔离差异；审查修复再做独立增量双轴检查。

- Standards：0硬性违规；唯一P3重复冻结时间fixture由共享test/support helper解决，增量复核0新增问题。
- Spec：0新增违约/范围膨胀；各平台待验项逐项完成，没有以未执行的命令冒充通过。

原报告保存在主树 `build/spec75/review-standards.md`、`review-spec.md`、`review-final-standards.md`、`review-final-spec.md`。主线程另核对最终手势fixture约束及Android manual分支，与既有公开测试边界和已接受试点一致。独立merger验证范围、祖先关系和工作树；重组后的PR审查链源码与集成分支逐文件等价，不声称每个重组HEAD都重新运行设备。

## 证据与清理

稳定本地索引：`build/spec75/evidence/README.md`，三个不可覆盖manifest记录原路径、目标路径、SHA256和大小。76/77/79/80工作树证据保存到对应编号目录，Android截图诊断保存到review-fixes目录；78及系统原生触摸图原本就在主树build/spec75，直接保留。历史失败、空帧与中断记录不删除、不覆盖。清理临时工作树前先保全ignored证据，原分支与审查历史仍保留。

DSH预检发现执行通道未注册，两个worker已关闭；用户明确同意改由Codex子Agent实现。没有暗中绕过DSH连接；实现、合并与审查分工已按票留证。
