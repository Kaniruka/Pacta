# 国策操作与折叠 UI 修复验收（2026-11-14）

用户提供三张实际截图，要求修复确认/熄灭纵排、折叠区默认横线与字号失配，以及编辑例外输入框标签裁切，并明确调用 implement 与 retro。基点 `c5120ec`；保留此前头像裁剪提交和未跟踪的共享云部署记录。

## 改动

- 待今日确认时“确认／熄灭”同排等宽，触控区至少48逻辑像素；已点亮只显示“熄灭”，已熄灭只显示“点亮”。待核对、父节点阻断等原守卫保持。
- 六处折叠统一为 `PactaDisclosureSection`：编辑例外、详情例外、失败批次、强化生效版本、基础规则对照、完整来源操作。明确无外部上下装饰边线，同级标题使用一致语义字号，展开内容保留绘制空间。
- 编辑例外分组标题不再在输入框内重复；收起仅释放本区域输入焦点，重开保留草稿，其他输入框焦点不受影响。
- 逐图复核追加修正：Windows 编辑页保存按钮与正文同列；失败分类与原因完全相同时仅展示一次，原记录和不同原因内容不变。
- 本次不改内化公式、结算、记录、权限或云服务，也未修改头像裁剪实现。

## 测试与评审

- `dart format` 完成；`flutter analyze` 无问题，日志 `.scratch/national-ui-fix/final-analyze.log`。
- `flutter test test/national_focus test/ui/pacta_disclosure_section_test.dart test/ui/disclosure_usage_test.dart`：首轮相关139项通过；其后新增保存区、文案和输入法导航回归分别通过。
- 实际红→绿包括：待确认按钮纵排、共享折叠默认边框/已填标签绘制范围、收起隐藏输入仍获焦、宽屏保存区左右边界20与40不一致、重复失败原因。日志分别保存在 `.scratch/national-ui-fix/` 与实施回执中；初次测试编译/异步API使用错误单独保留，不冒充产品红态。
- 手机输入法 Next 的额外疑点经真实 `receiveAction` 页面回归在现有生产代码直接通过，没有据未复现猜测增加逻辑；回归保留，日志 `ime-next-current-pass.log`。
- 最终生产代码与主要平台取证冻结后，运行一次完整 `flutter test`：**623项全部通过，退出码0**，日志 `full-tests.log`、`full-tests.rc`。随后仅补可选Windows鼠标取证fixture，生产代码未变，最终analyze及该Windows流程通过。
- 独立 Standards / Spec 复核固定 `c5120ec...cc0780e`，再复核 `cc0780e...37ee3a2` 收尾，无未解决发现；报告 `.scratch/national-ui-fix/{standards,spec}-review.md`。后续提交只增强测试取证。
- 独立逐状态设计复核见[设计报告](national-ui-design-review-20261114.md)：88张应用图和6张原生图已打开判读。原型转译与漏检原因、防回归改进见[复盘](ui-retro-20261114.md)。

## 最终平台证据

均使用真实 Pacta 主题/MiSans、正常字号；测试数据留在内存，本机/云端真实资料不变。主要流程使用真实本地国策仓储；核对来源及禁用样例仅沿用已有公开页面测试边界提供只读布局数据，不宣称验证新的冲突处理行为。

运行命令由 `.scratch/national-ui-fix/run_ui.py` 记录：`flutter drive --keep-app-running --no-start-paused --driver=test_driver/ui_layout_acceptance_test.dart --target=integration_test/national_focus_card_layers_device_test.dart`，各自唯一目录、stdout/stderr、退出码及源码哈希随图保存。

| 平台 | `build/ui-layout-evidence/national-ui-fix/` 目录 | 覆盖 |
| --- | --- | --- |
| Android 亮色 | `20261114-120904-android-light-verified` | 21应用状态，含原生输入法显示/收起 |
| Windows 深色 | `20261114-120931-windows-dark-verified` | 21应用状态 |
| Windows 亮色 | `20261114-121549-windows-light-complete` | 23应用状态，补完整历史内容、基础对照收起 |
| Android 深色320窄屏 | `20261114-121559-android-dark320-complete` | 同上23状态，含原生输入法显示/收起 |

四组均 `run.rc=0`、`sourceUnchanged=true`。两组完整矩阵补齐六处折叠的收起与展开；另外两组验证主题和平台一致性，不把21态写成含未拍补图。前两组与当前代码仅fixture补拍/滚动定位差异，生产lib哈希一致；详见设计报告的逐项状态与哈希核验。现有 focus-pilot verify 工具不识别本轮 `sourceHashes` schema，未将其失败冒充验证通过，改为明确逐文件SHA-256核对。

原生 Android 图 `native-05c-...focused.png` 中例外框四边在键盘上方，`native-05c2-...collapsed.png` 中键盘消失，输入法服务记录 `mInputShown` true→false；fixture等待真实viewInsets并持续pump处理原生窗口变化，不用应用截图推断系统IME。测试含展开、输入、直接收起、重开保留、正常/禁用按钮状态。动画过程只做组件异常回归，不声称逐帧视频验收；空白输入等未目视状态在设计报告明确列出。

桌面鼠标补充：`20261114-122655-windows-mouse-verified`，额外启用 `NF_CARD_LAYERS_MOUSE_REVIEW=true`。在真实Windows窗口中以合成 `PointerDeviceKind.mouse` 执行节点/文本入口点击和确认按钮悬停，24张图、退出0、源码运行期间不变；`02d-windows-confirm-hover` 与同run `02b` 对照悬停反馈。这不是物理手工鼠标操作。可选flag默认关闭，四组原fixture的源差异仅为新增此取证分支及已说明的补图，生产代码一致。

## 未采用的运行与环境恢复

- `smoke-windows` 新增失败历史样例未跨结算点，正确失败；修正样例先结算后取历史，未改领域逻辑。
- `20261114-114836-windows-light` 用于发现宽屏保存与重复文案，已由最终新图替代。
- `20261114-115024-android-light` 原生图出现 System UI 无响应，runner退出4，排除；保留失败截图，重启原AVD并用host GPU渲染后重测。
- `20261114-120001-android-light-final` 揭示原生IME到达晚于测试pump；后续等待实际窗口insets后重拍，不把输入框被键盘遮住的旧帧当通过。
- `20261114-121211-android-dark320-verified` 在历史入口因脚本未滚回“更多”而失败，退出1，排除；增加ensureVisible后完整窄屏流程通过。
- `20261114-122426-windows-mouse` 因测试hover复用tap的指针设备ID触发MouseTracker断言，退出1，排除；hover使用独立设备ID后鼠标流程通过，没有改应用鼠标逻辑。
- 仅使用本次启动的原 AVD `PactaFocusPilot20261112` / `emulator-5580`；实体手机和其他模拟器未操作。窄屏density540在finally恢复420；已正常关闭该AVD及本次Windows测试进程。没有卸载或清数据。

## 提交与自动检查边界

按 implement 要求提交当前分支；本轮未推送、创建/合并PR或部署云端。新增CI配置在后续push/PR时执行字体校验、analyze和完整test；本地执行通过不等同于GitHub runner已通过。原未跟踪 `docs/shared-cloud-deployment-20261114.md` 保留且不纳入提交。
