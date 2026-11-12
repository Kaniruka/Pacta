# Issue 78：专注设置、执行与返回验收

实施比较基点：`7732db0`（开始实施前合并 integration/spec-75-ui 后的 HEAD）；checkout 来源 `b033249`。设计基线为 `ui-focus-pilot-accepted-20261112`。规格为 #75 用户故事 7–8 与 #78；ADR 0007/0008 适用，正常字号与移动输入法仍在范围内。

> 验收修正：主线程独立目视复核发现初轮 Android final/native-ime.png 的聚焦时长框被裁掉。初轮 104/11 与设备通过结果只代表当时的断言，不能作为完整 IME 通过。下方“聚焦输入框复核”补充更强断言、实际失败和修复后证据，取代初轮 IME 结论。旧图原样保留。

## 实证与局部修改

- 设置弹层沿用任务、模式、时长、信号及预约自动交接说明。长中文信号是用户实际动作，说明段解释手动执行及自动交接，未发现内容重复到需要删除的实证；保留原文及层级。
- 320×800、300 逻辑像素模拟 IME 下，非法时长提示尾部落在内容视口之外（bottom 291 > 284）。新增完整矩形可见断言复现失败；仅在非法时长提示渲染后滚动到该提示，仍保留输入法、输入值及设置弹层。两种开始方式共用该提示处理，校验规则不变。
- 结算按钮原写“返回专注链”，但看板入口实际 `Navigator.pop` 回到看板。先执行原按钮验证实际落点，再使文案断言失败；仅改为“返回上一页”，不改压栈、落点或领域行为。

## 返回与恢复结果

| 入口 / 状态 | 操作 | 实际结果 |
| --- | --- | --- |
| 看板 / 无流程 | 设置开始倒计时 | 执行页；25 分钟默认保留 |
| 看板 / 进行中 | 顶部返回，再点开始图标 | 回看板；恢复同一会话，无第二条会话 |
| 专注链 / 进行中 | 顶部返回，再点选择任务 | 回专注主页；恢复同一会话，不回任务选择列表 |
| 看板 / 已结算 | 底部返回上一页 | 回看板 |
| 专注链 / 已结算 | 底部返回上一页 | 回专注主页 |
| 看板 / 已预约 | 返回，再点开始图标 | 恢复同一预约，不再次打开设置 |
| 设置 / 非法时长 | 点任一开始方式 | 就地提示；不关闭，不创建流程 |
| 设置 / 取消 | 改模式后取消 | 沿用原成功模式记忆；不保存取消的选择 |

真实本地仓储通过 AppShell/PactaApp 边界验证；未通过直接数据库查询代替用户入口。原有专注导航测试继续覆盖已删除任务恢复、成功模式持久化、取消保持筛选与滚动等规则。

## 设计轴

弹层的工作是选择任务执行方式，按钮直接表达动作；任务、模式、时长在前，用户信号与自动交接说明可滚动，开始按钮在内容滚动区外。亮暗主题继续使用现有 Material 3 语义主题。

依据：UI 指南“状态/文案/布局”；apple-design `alerts.md` 的 Content/Buttons（简明动作及仅保留有用说明）、`layout.md` 的适应可用空间、`virtual-keyboards.md` 的匹配输入类型，按 `cross-platform.md` 翻译为 Flutter/Android/Windows 原则，不套用 Apple 平台尺寸。ui-ux-pro-max 首次 `dialog keyboard inset` 无结果，重查 `responsive layout --stack flutter` 命中基于约束布局建议；现有弹层已适配，未新增固定尺寸。

目视检查区分输入内容滚动和固定动作，错误提示需完整露出。辅助技术、大字号与专门键盘支持按 ADR 不作为新增门槛。

## 实现轴

- Standards：生产差异局限于 FocusSetupDialog 的提示可见性和 FocusSessionPage 的结算返回文字；复用现有校验、仓储、错误色、滚动与 Navigator。无新增业务数据、导航规则、默认值、时长限制或主题。
- Spec：用户故事 7 的可操作性与非法时长提示、故事 8 两入口一致性分别有公开 UI 断言；进行中会话和预约按 ID/数量核验不重复。恢复分支与成功模式持久化沿用原实现。
- 独立复核由主线程完成；本子任务按协调约束不再委派审查代理。

## 测试与证据

证据根目录：`F:/Workspace/Release/Flutter/Pacta/build/spec75/`。每轮独立目录，不覆盖同名文件。

- Widget 基线：`t78-widget-baseline2/`，长中文任务与三种信号，正常字号，320×800、411×731、546×682、1265×682，亮暗；320/411 模拟 300 像素 IME。`t78-baseline2.log` 8 个布局通过、2 个返回文案失败。
- 返回 red：`t78-return-red2.log`，两入口实际 pop 落点断言通过后，旧返回文案失败。
- 提示 red/green：`t78-error-red.log` / `t78-error-green.log`，原布局 bottom 291 超出 284；局部滚动修复后完整可见。
- Android 同状态证据与最终验证结果将在完成后记入下方。

历史 `baseline-focus-android` 仅为旧 #66 无 signals/IME 的回归线索，不用作本票完整验收。早期 `t78-widget-baseline`/`t78-baseline.log` 有 fixture 的 connectivity 插件缺失；修正平台边界 mock 后重新取证。Android baseline2 的原生键盘截图存在系统键盘已出现但 Flutter 尚未处理 metrics 的时差，最终改为等待键盘 metrics 后重新取同状态基线，不以该过渡帧判断产品。

### 已完成结果（合并其他票前）

- `dart format lib/main.dart test/focus/focus_setup_evidence_test.dart integration_test/issue_66_focus_navigation_device_test.dart`：通过。
- `flutter analyze`：No issues found（7.0s），日志 `t78-analyze-final.log`。
- `flutter test test/focus test/ui_layout_test.dart test/ui_secondary_layout_test.dart --reporter expanded`：104 通过，日志 `t78-regression.log`。
- 字体截图轮 `PACTA_UI_FONT=C:/Windows/Fonts/msyh.ttc`：11 通过，`t78-final2.log`；最终图 `t78-widget-final2/`。目视确认 320-light-invalid 的红提示完整显示，546-dark-setup 的说明与动作有层次，board-settled 文案不再误指专注链。
- Android：`flutter test integration_test/issue_66_focus_navigation_device_test.dart -d emulator-5554 --no-uninstall --plain-name "Issue 78" --reporter expanded`。baseline4 与 final 都通过 1 个完整场景，各退出码 0；目录 `t78-android-baseline4/` 与 `t78-android-final/` 各有 run.log、run.rc、manifest.json、11 个状态图、native-ime.png 及 input-method.txt。manifest 保存同 fixture 与 main 源码前后 SHA256。1080×1920、density420（约411×731）、fontScale1.0；仅使用 emulator-5554，没有操作物理设备。保持已安装数据，隔离本地 fixture 内存数据库。
- Android baseline3：rc79，测试连接 did not complete，未作为验收；同源重试 baseline4 通过。baseline4/final 等待键盘异步尺寸更新后再截图，input-method.txt 记载 mInputShown=true。

本票设备 fixture 允许旧/新结算返回文字以便使用完全相同源码获取基线与最终落点；最终文字严格由 widget 行为测试断言“返回上一页”。既有 issue66 测试保持原样，本轮 Android filter 没有重跑该旧场景。


## 聚焦输入框复核

主线程在 `t78-android-final/native-ime.png` 发现时长框完全裁切，光标水滴落在动作区。这是有效缺陷，不能因开始按钮可点而判定 IME 通过，也不能仅归于截图转场。

补充公开 UI 几何断言：聚焦 TextField 的完整上下边界必须位于弹层滚动内容视口内，既用于 widget 320/411+模拟 IME，也用于真实 Android。红线：

- Widget：`t78-field-widget-baseline.log`，320 时 input.bottom306 > viewport.bottom284；411 时 input.bottom282 > viewport.bottom215，亮暗四例失败。
- Android：`t78-android-field-red/`，input 为 Rect(64,250,347.4,306)，内容底部227.43，真实键盘 mInputShown=true；相同 fixture 截图后断言失败，退出1。`native-ime.png` 保留失败状态，manifest 前后源码哈希一致。

原因是 AlertDialog 的 AnimatedPadding 在输入法尺寸通知之后仍继续缩小可视内容。单次聚焦/metrics 回调太早，不能保证最后一帧完整显示。最小修复仅在 FocusSetupDialog 内使用 FocusNode 和 SizeChangedLayoutNotifier：当时长框保持焦点、弹层内容实际尺寸改变时，在该帧布局完成后将整个输入框（已有错误时优先提示）滚入可视区。保留 mounted、焦点与 context 有效性检查；取消时释放 FocusNode。没有固定延时、全局 metrics 监听或输入法关闭行为。

- 完整同 fixture widget 截图轮：`t78-widget-field-final/`，日志 `t78-widget-field-final.log`，11 通过。320/411 的 field 矩形完整可见；时长提示仍完整可见，亮暗及宽窄布局保持通过。
- `flutter analyze`：No issues found（7.4s），`t78-field-analyze.log`。
- Windows宽窗初轮在构建阶段按主线程要求中止，目录 `t78-windows-wide-baseline/` 的 interrupted.txt 如实记录；尚无Windows本票设备通过结论。fixture新增 `ISSUE78_VIEW=wide|narrow` 渲染视口 override，明确不是原生窗口缩放验收；默认 Android 行为不受影响。Windows已释放给#77。

补充修复最终结果：`t78-android-field-final/` 完整设备场景1通过、run.rc=0（40s）；同 fixture 与 field-red 的源前后哈希各自一致，fixture相同。最终duration Rect(64,171.4,347.4,227.4)完整落在content Rect(64,120,347.4,227.4)内。主线程实际打开新native-ime.png，确认label、完整边框、25与光标在内容区，两个开始按钮与数字键盘同时可见，设计复查通过。模式顶部随内部滚动裁切属当前输入时长状态的正常滚动。

`flutter test test/focus test/ui_layout_test.dart test/ui_secondary_layout_test.dart --reporter expanded`：104通过（19s），`t78-field-regression.log`，包括完整错误提示断言；Android和Windows设备均已释放。Windows两档最终验收仍待主线程安排，未追记为通过。
