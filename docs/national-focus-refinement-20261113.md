# 国策编辑、例外确认与蓝白主题验收（2026-11-13）

## 本轮确认的范围

- 应用版本从 `1.0.0+1` 改为 `0.1.0+1`；Android namespace/applicationId/MainActivity 包名改为 `com.rukani.pacta`。Windows CompanyName 和 MethodChannel 名不改，避免无关偏好目录与协议变化。
- 编辑页仅有卡片名称、国策规则、例外与判例（可选）。用户明确无需合并旧触发条件与适用范围；新保存将其置为空/空值。保留数据库列、旧要求版本和失败快照，不做擦库或历史改写。
- 当前卡片信息与强化编辑统一国策规则文案。旧强化等级仍可继承基础规则，历史触发覆盖保持兼容。
- 待确认节点的确认与熄灭相邻；点亮受阻原因归入该 ListTile 副标题。节点面板与熄灭框完整显示非空例外。
- 全部确认先处理无例外的待确认节点。有例外的节点逐项显示规则与例外，用户确认或熄灭；关闭后未处理者继续待确认。单点面板已经显示例外，确认不再重复弹窗。
- 批次及单点面板捕获检查点窗口；仓储在事务内校验，防止旧确认跨 04:00 重新点亮已结算节点。熄灭原因框跨日也退出旧操作。没有新增自动豁免或自动追加判例功能。
- 用户看过蓝白预览后确认正式实施，并要求更接近 Google 风格。共用 Material 3 主题采用蓝色操作、白/浅蓝背景、圆角卡片与弹层；点亮绿色、待确认暖黄色。保留 MiSans 与导航结构。

## 设计依据与复核

颜色按 [Material 3 官方颜色角色](https://m3.material.io/styles/color/the-color-system/) 配对。共用 `ThemeData` 管理操作/容器颜色与形状，`PactaStatusColors` 管理绿色成功反馈；不把成功状态与导航选中色混用。

实际颜色对比度：亮色主按钮 6.39:1，暗色主按钮 7.50:1，绿色状态 7.32:1 / 8.01:1，暖黄色状态 12.07:1 / 7.73:1。设计自查按项目 UI 范围，使用 apple-design 的布局分组/对齐、颜色前景配对原则和 ui-ux-pro-max 的 Flutter 指导，未扩大到已退出产品范围的专项要求。

Standards 独立审查无未解决发现。Spec 独立审查发现旧例外面板跨检查点可能重新点亮节点，已修复并二次复核关闭。主代理另发现旧强化等级留空继承被表单误拦截、单点重复确认，均已修复。

## 实际验证

- DSH 相关回归：`flutter test test/national_focus test/ui_secondary_layout_test.dart`，106 项通过。
- 主代理：`flutter analyze` 通过；`flutter test --reporter compact`，392 项通过。正式蓝白主题加入后重跑仍为 392 项通过。
- 最终主题完整测试日志：`build/session-20261113-national-focus/verification-20261113-115308/`，源码哈希检查无运行期间漂移。
- Windows 11 实际 Flutter 集成运行，内存数据库隔离样例，正常字号：1280 逻辑宽亮色、420 宽暗色、420 宽亮色均通过；每次 7 张截图，主代理目视检查三字段、待确认面板、阻塞提示、例外逐项对话框。
- Windows 运行目录：`device-20261113-115512-light-1280`、`device-20261113-115558-dark-420`、`device-20261113-115654-light-420`，均位于 `build/session-20261113-national-focus/`，含 `run.log`、`run.rc`、带源码哈希的 `manifest.json`，均 rc=0、drift=[]。
- 前两次 Windows fixture 失败为测试断言/操作问题（错误强求已结算后的级联源名称、对底部弹窗使用 pageBack 查找返回按钮），修复为检查阻塞副标题和点击遮罩关闭后重跑通过，旧失败记录保留。

截图是 Flutter 应用画面，不包含操作系统弹窗；本轮未做 Android 设备运行、原生权限或真实云服务验收。无云/身份/数据库结构修改，沿用既有同步载荷。Android 更换包名会使用新沙箱；旧包和数据未删除，也没有自动迁移旧沙箱。

## 协作与基线

会话开始 HEAD `df4d098a18e9025fb8ea3ca1435c1c728546e98c`，已有大量未提交改动。本轮使用 `build/session-20261113-national-focus/baseline/` 保存会话前副本并核对本次增量，未把其他已有修改提交或回退。

DSH workers：版本切片 `session-e74e52b7-c2a8-4b46-a9b0-d0e48f302744`；国策切片 `session-7309ac7d-c16d-44ef-a6d7-624ead7001db`，均已关闭释放。桥接有效配置：`ptc`、`cc-switch-tencent-token-plan/deepseek-v4.1-flash-1017`、`high`；执行环境为 Windows 11 上 MSYS Bash，Flutter 3.47.2 / Dart 3.13.2。主代理独立执行上述全量检查、截图验收和最终构建。

## 最终构建

- `flutter analyze`：No issues found（最终 fixture 修正后再检查）。
- `flutter build apk --debug`：成功；独立 aapt2 核验包名 `com.rukani.pacta`、versionName `0.1.0`、versionCode `1`。
- `flutter build windows --release`：成功，产物 `build/windows/x64/runner/Release/pacta.exe`。
- 日志：`build/session-20261113-national-focus/final-analyze.log`、`final-android-build.log`、`final-windows-build.log`；命令与退出码见同目录 `build-results.json`。这些构建没有传入云端客户端配置，不作为已登录真实服务或可发布签名包的验证。
- 所有改动保留在工作树，未提交、推送、发布或删除用户数据。

## PR 收尾复核（2026-11-13）

合并前独立 Spec 审查补查出：已点亮节点的单点熄灭未传打开时的检查点窗口，原因弹窗跨04:00可能作用于新一天。现已统一传递捕获窗口，并新增公开 UI 红绿回归；该例外确认测试文件10项通过。此修复不改变前文截图中的正常日期布局。
