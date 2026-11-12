# #75 全局 UI 推广验收

实施日期：2026-11-12 至 2026-11-13（Asia/Shanghai）。设计基线 `ui-focus-pilot-accepted-20261112`，仓库起点 `b0332493dd5b8184a036aab925e0ebdec0b3a71b`，初始工作树干净。

## 范围

- #76：目标摘要合为一组；任务预计、已专注、待核对、截止按可用宽度换行。
- #77：未发现支撑区生产布局缺陷，保留三卡和原断点；补0/1/7日及真实窗口核验。
- #78：纠正结算返回文案；错误提示和聚焦时长在输入法压缩内容区后保持可见。返回落点与时长规则不变。
- #79：窄卡完整状态独占一行；覆盖后果紧邻方向，取消与忽略分开，下载限制保持。
- #80：未发现国策页头生产缺陷，保留现状；补窄窗、短窗、放置、视图错误与画布证据。

不改字段、数据库、身份、同步协议或导航规则，#54 保持范围外。设备使用隔离本地fixture，无真实账号或云端往返；不将替身验收称为真实服务通过。

## 主线程验证

| 检查 | 实际结果 | 本地原始日志 |
| --- | --- | --- |
| 国策三个相关测试文件 | 28通过 | build/spec75/root-checks/t80-tests.log |
| 看板、布局、专注导航 | 24通过 | build/spec75/root-checks/t76-tests.log |
| 集成分支完整 flutter test --no-pub | 354通过，rc0；提交3ee23311 | build/spec75/root-checks/full-tests.log |
| 原有issue66 Android导航 | 1完整场景通过；旧fixture仅作回归线索 | build/spec75/baseline-focus-android/run.log |

各票补充测试、red/green、失败轮、源码清单和截图见各票验证记录。设备续验仍在进行，本表不将待验项写为通过。

## 独立审查

实现者与主线程分工：独立 merger 检查范围、祖先关系和工作树；主线程亲自运行上述检查并打开实际图。Standards 和 Spec 使用两个新上下文并行审查，固定整体比较 `b033249...3ee23311`，逐票基点保留在票据记录中。

- Standards：0硬性违规；1项P3测试fixture重复建议，安排单个fresh implementer处理。
- Spec：0新增违约；平台待验项单列，不伪记完成。
- 原报告：build/spec75/review-standards.md、review-spec.md。

设计轴依据项目UI指南，借用apple-design的 `layout.md / Visual hierarchy` 相关信息分组与顺序、`typography.md / Conveying hierarchy` 语义文字层级、`modality.md / Best practices` 明确退出、`writing.md / Best practices` 动作与落点一致。遵循ADR0007/0008，不移植Apple专属布局，不扩展读屏/大字号/键盘专项。

已实际打开：#76同fixture窄暗/宽亮前后及空态；#79 Android亮色和Windows暗色同态前后；#80正常字号绿色主题小树、放置、短窗、50节点和暗色失败；#78原始IME及修复后native-ime。#78首次图虽按钮可见但输入框被裁切，主审要求补完整字段边界断言；第二次实际图确认输入框、光标、键盘、开始按钮同时可用。该轮发现不能被早先测试通过掩盖。

## 证据限制与运行记录

Windows #76固定图来自原生app内的逻辑view override，不声称原生拖窗；#77另核验实际拖窗。#79原生窄窗实测536.8×682.4，宽1265.6×682.4，不写成精确546。Android为PactaFocusPilot20261112模拟器，1080×1920、density420，约411×731；没有操作物理设备b9680744。

本轮DSH bridge可启动会话但执行通道未注册，预检无法完成。经用户明确允许改用Codex子Agent；两个DSH worker均已关闭。后续实现、合并和双轴审查使用独立Codex子Agent。

主线程首轮board Android取图停在截图转换，原生画面为Test starting；另与集成合并发生源码漂移。该轮明确无效，日志及interrupted.txt保留，已停止其进程树，不作验收。修复与复跑结果待补。
