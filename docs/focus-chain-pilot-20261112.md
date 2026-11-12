# 专注链 UI 小范围试点（2026-11-12）

已完成局部实现、正常字号同状态前后评审及Android／Windows代表视口实操。最终完整测试336项通过，analyze无问题；独立评审Good、无遗留设计项。原有改动、主题、三条链及业务口径保留。

## 边界与基线

- 起点 HEAD：`8aef5ca991312549342866924576290a52549212`。
- 首次 `git status --short`：已有 16 个文档修改及未跟踪 `android/build/`，保留，不纳入本次修改。应用源码与测试起点无改动。
- 仅调整启动区信息组织、链卡指标排版、零／少量记录密度。沿用主题、三条链、承诺动作、统计口径及恢复顺序。
- 适用 ADR 0007/0008：本次验收正常字号、鼠标／触摸、长内容、响应式与 Android 系统返回；不引入读屏、大字号或专门键盘专项。既有能力及测试保留。

## 查询与方案

ui-ux-pro-max：`visual hierarchy grouping metrics --domain ux` 结果偏 Web，不采用；收窄为 `text truncation content density --domain ux`，命中 All 平台 Essential Text Truncation 与 Truncation：重要信息换行或保留可见全文路径，不为了齐高裁掉意义。`responsive text layout --stack flutter` 命中 LayoutBuilder、Row/Column，适用于现有 Flutter 实现。

已在查看运行基线后落实：

- 启动区把区标题与可选任务数放在同一信息组，按钮紧随其后；恢复卡仍优先。
- 链卡连续／最佳构成第一组，累计／平均构成第二组，各组等宽列并统一数值基线；次数为主，时长为次，承诺动作为独立操作组。
- 收紧重复间距，零值不另占占位画面；三条链及所有原指标保留，不增加装饰或新空态。
- 长承诺动作完整换行；长时长按可用宽度纵向分组，不裁切、不缩小字体。编辑控件维持 48 逻辑像素命中区。

## 执行与证据

DSH worker：`focus_preflight` / `session-9b7089db-7879-428f-a727-a73a1f495f9a`，负责只读预检、现有设备 fixture 扩展和平台基线／复测。桥接确认 cwd 为当前仓库，preset `ptc`，provider `cc-switch-tencent-token-plan`，model `deepseek-v4.1-flash-1017`，effort `max`，实际请求工具数 1（编排工具）。尝试 medium 被宿主明确拒绝，不宣称切换成功。

独立评审由 `design_review` 使用 apple-design 适用基础原则执行，另记评审文件。前后截图必须同 fixture、同视口、正常字号对照；生成成功或无 overflow 不等于视觉通过。

### 已核对基线

- 2026-11-12 17:00:16 Windows Debug，当前源码编译的离线 fixture，Flutter 3.47.2 / Dart 3.13.2；应用声明版本 `1.0.0+1`。不以旧安装包或历史截图为当前实现。
- 最终产物复核：Windows exe 的 FileVersion／ProductVersion 均 `1.0.0+1`；Android 已安装测试包 `versionName=1.0.0`、`versionCode=1`。两应用源码文件与最终APK／EXE的SHA256保存在本地证据 `final-source-artifacts.json`。
- 逻辑窗口 1265.6×682.4，DPR 1.25，textScaler 1.0，padding/viewPadding/viewInsets 均为 0。原图 1582×853。
- 截图 `build/ui-layout-evidence/focus-pilot/before/focus-chain-normal.png` 已由主 Agent 和独立评审者实际打开；原源码、SHA256、工具版本留在相邻 `baseline-source/`，运行指标和命令见 `before/baseline.md`。
- 设备验收开始前，两处现有 SDK 的 `emulator.exe -list-avds` 均无输出；`adb devices -l` 无设备；`flutter emulators` 报 No emulators available。后来确认 Android 35 Google APIs x86_64 镜像已安装，建立独立试点 AVD；详见下节。

### 主 Agent 验证

- `dart format lib/main.dart lib/src/focus/chain_signals_card.dart test/focus/chain_signals_card_test.dart` 完成。
- `flutter analyze`：No issues found。
- 修改前，扩展的 `flutter test test/focus/chain_signals_card_test.dart`：19 项通过。
- 修改后，完整 `flutter test`：336 项通过，退出码 0。含现有行为／布局测试与新增正常字号 320/600/960 宽度亮暗长内容、取消编辑、零指标保留测试。历史 2×字号测试随完整测试保留执行，不扩大支持范围。

### 改后 Windows 证据

现有 fixture 扩展了可选 pilot 参数，默认保留原流程；driver 可选证据子目录。实际参数与复现命令见 `build/ui-layout-evidence/focus-pilot/progress.md`。正常字号 default/wide、default/narrow、zero/wide、few/wide、long/wide 五组均 `All tests passed`，各含首屏、滚动、编辑、取消、保存、执行、返回及恢复截图；日志位于 `logs/run-*.log`，成图归档 `after/`。

- default／few／long 为深色，zero 补测为浅色（零记录深色截图曾被同名浅色覆盖，不据此宣称同主题比较；浅色副本另加 `-light`）。
- wide 逻辑尺寸1265.6×682.4；narrow 是 `tester.view` 420×820 约束渲染，不能当作原生窗口调整。
- 全部 DPR1.25、textScaler1.0、padding/viewPadding/viewInsets0。long场景为长动作，不是长时长压力图；超长时长由正常字号 widget 测试覆盖。
- 脚本曾误点恢复提示标题，已修正点击“返回专注”，并验证恢复后的 session id 保持；旧失败日志及中间图保留，不作为最终通过证据。

人工操作使用相同内存 fixture 的 `FOCUS_PILOT_HOLD_SECONDS=300`；发现 Flutter 测试绑定默认拦截设备指针，已仅在 hold 内设置 `shouldPropagateDevicePointerEvents=true`，通过 finally 恢复。

`manual-drive-3.log`：起点1265.6×682.4，结束时真实客户端逻辑546.4×682.4，DPR1.25、textScaler1.0、三insets0，`All tests passed`。主 Agent 用 Computer Use 激活窗口、鼠标打开普通链编辑、取消、重开、保存原值、滚动到底部；通过原生系统菜单大小模式缩窄窗口，未覆盖 tester.view。窄窗口改为纵向链卡、底部导航；长动作自然换行，尾注可滚动看到。

真实截屏：`manual/native-narrow-top.jpg`、`native-narrow-bottom.jpg`、`native-narrow-editor.jpg`、`native-reopen-original.jpg`。结束时 Flutter 截图：`manual/focus-long-wide-overview-after-hold.png`。人工键入尝试没有改变文本，不宣称人工改值验证；改值取消／保存由自动流程实际 enterText 和仓储断言覆盖。

### 评审处理

独立评审初次宽图发现预约通栏卡的连续／最佳距离过大；已仅将预约计数改为紧邻分组（16间距），精锐／普通保留等宽列，取得新画面复查通过。完整位置、影响、适用依据、处理及后续实操画面复查见 `focus-chain-pilot-review-20261112.md`。

### 改后 Android 设备验收

- 使用现有 C 盘 SDK `C:\Users\Stray\AppData\Local\Android\sdk`、Android 35 Google APIs x86_64 system image rev 9；创建独立 AVD `PactaFocusPilot20261112`，不改/擦除其他 AVD 或用户数据。配置 1 核、2048 MiB RAM、2 GiB 数据分区；模拟器 emulator-5554，物理 1080×1920、density 420。
- `avdmanager` 解析时打印 D 盘 SDK 路径大小写不一致及 image `devices.xml` 缺失错误；第一次显式 `--skin pixel_2` 也报 skin 不存在。省略显式 skin 后仍生成 AVD config，模拟器实际启动并连接 ADB。宿主启动阶段可用 RAM 约 4.2 GiB；模拟器进程工作集观察到约 3.5 GiB，因此未额外启用 Android 并行构建。
- `focus_chain_design_device_test.dart` + `ui_layout_acceptance_test.dart` 在 Android default 与 long 运行通过，命令均使用 `flutter drive -d emulator-5554 --driver=test_driver/ui_layout_acceptance_test.dart --target=integration_test/focus_chain_design_device_test.dart --dart-define=FOCUS_PILOT_MODE=true`；long 加 `--dart-define=FOCUS_PILOT_SCENARIO=long`。两次皆 `All tests passed`。截图分别在 `build/ui-layout-evidence/focus-pilot/android/default/` 与 `android/long/`，含首屏、记录滚动、编辑对话框、取消、保存、活动专注、测试绑定 back 与恢复。
- Android 逻辑尺寸 411.4×731.4、DPR 2.625、textScaler 1.0，padding/viewPadding 顶部与底部均 24、viewInsets 为零。普通字号默认与长文本均无测试异常；长承诺动作可换行。集成 fixture 的 `binding.handlePopRoute()` 只验证 Flutter 测试绑定 PopRoute，不视为 ADB 真系统返回。
- zero 运行曾进入 hold 并留下 ADB 截图，但在外部输入后 hit-test finder 输出异常，随后主动中断该 driver，不计作通过。设备 UI 中尝试的 ADB tap/swipe 未能得到稳定、可复核的页面转换；一次主页 `keyevent 4` 返回 Android launcher，未证明活动专注返回/恢复。因此 Android 真正的系统返回与人工流程恢复仍待主 Agent 接管验证。
- Flutter drive stdout 在 exec 会话实时流出，未保存完整日志文件；对应零样例参数为 `FOCUS_PILOT_SCENARIO=zero`、`FOCUS_PILOT_HOLD_SECONDS=90`、未设置 `FOCUS_DESIGN_SNAPSHOT_ONLY=true`。临时 ADB 截屏留在 `android/zero/adb-*.png`，不能作为流程通过证据。

### 最终补证与结论（以上 Android 初次受阻记录已被本节补齐）

- 最终完整 `flutter test`：336项通过，退出码0，持久日志 `build/ui-layout-evidence/focus-pilot/final-tests.log`。最终五文件 `dart format` 无变化；`flutter analyze` 为 No issues found，见 `final-analyze.log`。预约卡修正后相关4个文件29项测试亦通过。
- 隔离HEAD副本的Windows default宽／窄、zero、few、long及浅色zero全部通过；日志 `logs-before/`，同状态改前截图 `before-states/`。DPR、逻辑尺寸、textScaler和insets与对应改后场景匹配。主Agent复核了原始基线、zero浅色及long改前图，独立评审者实际打开全部代表状态进行对照。
- 独立评审发现 `after/focus-default-wide-records-scroll.png` 混入预约计数修正前旧图。已用最终源码重新运行Windows default全流程，`after-final.log` All tests passed；最终 default宽屏截图以 `after-final/` 为准。独立评审已重看overview和records-scroll，预约计数紧邻、尾注完整，该证据归档问题闭环。旧目录及自动像素差分仅作历史，不能用差分比率代替视觉通过。
- Android真正触摸／系统返回补证已由主Agent完成，截图 `android/manual/03-live-picker.png` 至 `16-home.png`。ADB触摸进入任务选择、取消设置、重新设置并开始普通链；活动页 `input keyevent 4` 回到有进行中卡的专注首页，再触摸“返回专注”回到同任务／模式。此处只确认可见恢复路径；session id相等另有自动流程断言，不从手动图片推断。
- Android真实编辑：输入法打开时，输入 `pilot-cancel` 后取消，原值保留；再次输入 `pilot-save` 并保存，卡片与重开字段保留新值，没有cancel串。触摸滚动、IME弹出时的字段／取消／保存位置均已截图核对。完整坐标、命令及图片映射见 `android/manual/steps.md`，运行日志 `android/manual-live.log`。
- 根因仅在验收fixture：Android `convertFlutterSurfaceToImage` 转换后的 ImageView 在驱动截图时才 `acquireLatestImageViewFrame`；直接ADB截屏会保留旧帧。人工hold现在延后转换，保留原生表面接收输入；结束后才取驱动截图。此结论已核读当前Flutter SDK的 `integration_test/FlutterDeviceScreenshot.java` 与 `_callback_io.dart`，并用新画面验证。不改变应用代码或Android业务。
- 独立apple-design评审结论：Good，本轮范围内无遗留设计问题。已复核零／少量／长动作的同状态Windows前后图、正常窄布局、真实Windows缩窗／滚动／编辑，以及Android系统返回／恢复／改值取消保存与IME画面。详见 [独立评审记录](focus-chain-pilot-review-20261112.md)。未以构建、无overflow或生成图片作为视觉通过依据。

### 证据选择与边界

| 场景 | 最终证据入口（均在build/ui-layout-evidence/focus-pilot/下） |
| --- | --- |
| 改前源码、首次正常字号基线 | `baseline-source/`、`before/focus-chain-normal.png`、`before/baseline.md` |
| 同状态Windows前后 | `before-states/`；改后default宽使用`after-final/`，其余使用`after/`；浅色zero按`-light`配对 |
| 原生Windows缩窗、鼠标滚动／编辑 | `manual/native-narrow-*.jpg`、`manual/native-reopen-original.jpg`、`manual-drive-3.log` |
| Android默认／长内容自动流程 | `android/default/`、`android/long/`；通过结果来自设备子Agent实际命令输出，完整stdout未持久，不冒称具有完整日志 |
| Android真实输入、系统返回／恢复 | `android/manual/steps.md`、`03`至`16`截图、`android/manual-live.log` |
| 最终静态／完整测试检查 | `final-analyze.log`、`final-tests.log` |

范围遵循ADR0007／0008。没有穷举每个平台、主题、字号、状态的笛卡尔积；Android为模拟器而非物理真机，Windows同状态多场景对比与两平台代表视口／真实输入相互补充。long设备场景验证长中文动作；超长时长数值由正常字号widget测试覆盖。固定日期离线fixture执行页显示00:00不作为真实计时走时验收。没有验证真实账号、云同步、原生通知或日历边界，也未改其实现。

DSH完成fixture／driver扩展、隔离HEAD基线与Windows批次，主Agent验收实际diff／日志／图片；其隔离构建复用了已有SQLite源码缓存，并把INSTALL目录限制到隔离构建目录，没有改应用源码。worker已于任务完成后关闭。DSH阶段记录中“Android无设备”“原生缩窗未验证”仅描述其早期范围，已由本节后续证据补齐。

Android最终人工hold完整600秒正常结束，`android/manual-live.log` 两处 `All tests passed`，退出码0；结束时仍为411.4×731.4、DPR2.625、textScaler1.0、上下padding/viewPadding24及viewInsets0。最终驱动图在 `android/manual-live/focus-zero-wide-overview-after-hold.png`。这是修正fixture后的zero真实输入闭环，不把早期中断的zero批次追记为通过。

独立AVD `PactaFocusPilot20261112` 为本次使用现有镜像新建，已核对设备AVD名称后正常关闭，配置／磁盘保留供复用，不擦用户数据。DSH worker已释放，无本次未结束的验收任务。

## 公开 PR 截图副本（2026-11-12）

为 GitHub PR 提供可直接打开的图片，8 张代表图已复制到 `docs/evidence/focus-chain-pilot-20261112/`。均为上文既有批次的逐字节副本（复制前后 SHA-256 一致），保留 PNG 原格式、原始尺寸与元数据，未重新截图、未重新运行、未编辑像素，因此不构成新增补测。

| 文件 | 场景（同 fixture／视口／字号） | 来源原图（`build/ui-layout-evidence/focus-pilot/`） |
| --- | --- | --- |
| [windows-wide-default-before-overview.png](evidence/focus-chain-pilot-20261112/windows-wide-default-before-overview.png) | Windows 深色默认宽，隔离原 HEAD 基线 | `before-states/focus-default-wide-overview.png` |
| [windows-wide-default-after-overview.png](evidence/focus-chain-pilot-20261112/windows-wide-default-after-overview.png) | 同上状态，最终改后（预约紧邻版） | `after-final/focus-default-wide-overview.png` |
| [windows-narrow-default-before-overview.png](evidence/focus-chain-pilot-20261112/windows-narrow-default-before-overview.png) | Windows 深色窄（420×820 约束渲染），基线 | `before-states/focus-default-narrow-overview.png` |
| [windows-narrow-default-after-overview.png](evidence/focus-chain-pilot-20261112/windows-narrow-default-after-overview.png) | 同上状态，最终改后 | `after/focus-default-narrow-overview.png` |
| [windows-wide-zero-light-before-overview.png](evidence/focus-chain-pilot-20261112/windows-wide-zero-light-before-overview.png) | Windows 浅色零记录宽，基线 | `before-states/focus-zero-wide-overview-light.png` |
| [windows-wide-zero-light-after-overview.png](evidence/focus-chain-pilot-20261112/windows-wide-zero-light-after-overview.png) | 同上状态，最终改后 | `after/focus-zero-wide-overview-light.png` |
| [android-zero-system-back.png](evidence/focus-chain-pilot-20261112/android-zero-system-back.png) | Android 零记录，真实系统返回后出现进行中卡与“返回专注” | `android/manual/07-system-back.png` |
| [android-zero-edit-saved.png](evidence/focus-chain-pilot-20261112/android-zero-edit-saved.png) | Android 零记录，人工键入并保存后卡上显示新动作 | `android/manual/14-edit-saved.png` |

使用这些图时的限制：

- 配对全部取自既有批次（`before-states/`、`after-final/`、`after/`、`android/manual/`）；同状态指同 fixture 数据、同视口、同主题与正常字号，不是本轮新跑的场景。
- wide 为截图 1582×853（逻辑 1265.6×682.4、DPR1.25）；narrow 是 `tester.view` 420×820 约束渲染的 525×1025 图，不能当作原生窗口拖动，其首屏止于普通链，预约卡的紧邻计数与尾注见同批 `after/focus-default-narrow-records-scroll.png`（未复制）。
- zero 批次为浅色，与深色默认宽分别评判，不混作同主题前后对比；Windows 图数据分别对应“3 次／0 次”两组，不跨场景解释差值。
- Android 两张为 zero 场景人工 hold 的原生 ADB 截屏（emulator-5554 模拟器、1080×1920），非物理真机；`14-edit-saved` 的 `pilot-save` 是人工输入文本。图片只证明可见结果，Session id 相等仍由自动断言支撑，不从图片推断。
- 逐张打开核对：只含离线 fixture 文案、示例任务／链／动作与系统时钟状态栏，无账号、邮箱、令牌、云端界面或本机路径。
- 同批其余原图仍在未跟踪的 `build/ui-layout-evidence/focus-pilot/`（构建证据，不纳入版本库）。本目录只作为 PR 与评审的引用入口，原位保留不动。

