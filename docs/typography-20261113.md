# 全平台 MiSans 字体验收（2026-11-13）

## 已确认范围与实现

用户确认 Windows、Android 全平台统一内置字体，并指定采用 MiSans。保留现有 Material 3 字号、语义颜色与页面结构；普通中英文、数字、标点使用同一字体族。仅在共用 ThemeData 设置字体，「我的」页展示使用声明，协议与版权随 assets 打包。

使用小米官网 MiSans.zip 中未修改的 Version 4.009 静态 TTF：Regular/Medium/Semibold/Bold 映射 400/500/600/700，共 32,270,460 字节（约 30.8 MiB，非 APK 压缩后增量）。原包 VF 的命名实例 Regular=330、Medium=380、Semibold=520、Bold=630，与 Flutter 的常见数值不等；使用静态原件可沿用页面的常规 FontWeight，避免逐页覆盖或修改字体。

字体不作为独立文件镜像到 Git；首次构建从官网取得、SHA256 锁定版本，后续离线构建。详见 [获取与许可](../assets/fonts/README.md)。系统仍负责 emoji 和字库未覆盖字符；不承诺跨平台所有语言字形相同。

## 自动验证

- `dart format lib/main.dart`：无格式差异。
- `flutter analyze`：通过，No issues found。
- `flutter test --reporter compact`：377 项通过，完整日志 `build/font-task/flutter-test.log`，退出码 `build/font-task/flutter-test.rc`。
- 四个静态原件的 cmap 只读检查均覆盖当前 `lib/**/*.dart` 全部非 ASCII 字符。
- `python scripts/fetch_misans.py`：本机四个文件 hash 正确；用下载函数必定抛错的替身确认文件齐全时不联网。
- 临时目录验证首次提取、已有文件跳过、损坏文件拒绝覆盖，全部通过；日志 `build/font-task/font-verification.log`。
- `flutter build windows --release`：通过，日志/退出码 `build/font-task/windows-release.log` / `.rc`。产物 `build/windows/x64/runner/Release/pacta.exe`；FontManifest 的四档映射及打包字体/许可 SHA256 与源文件一致。本次未注入云配置，也未替换用户已安装应用。

## Windows 11 / Flutter 3.47.2 实际运行

使用现有离线 fixture 和 `scripts/run_focus_pilot.py`。以下独立目录均在 `build/ui-layout-evidence/focus-pilot/runs/`，各自包含 stdout/stderr 合并日志、退出码、源码指纹和截图。

| 运行 | 参数 / 结果 |
| --- | --- |
| `font-before-20261113-default-wide-light` | 系统字体基线，`--scenario default --view wide --theme light --device windows --snapshot-only`，rc=0 |
| `misans-after-20261113-default-wide-light` | 同 fixture/视口/主题的 MiSans 截图，rc=0 |
| `misans-dark-20261113-default-wide` | `--scenario default --view wide --theme dark --device windows`，完整编辑取消/保存、开始专注、返回/恢复流程，rc=0 |

已打开判读亮暗主页面截图：基线中文同句粗细割裂，MiSans 后相同层级笔画统一，数字与中文协调；按钮、导航、卡片内容保持可读。窗口实际渲染图约 1582×853，未以 widget 默认测试字体代替字体目视判断。

## Android

模拟器 `emulator-5554`。系统字体基线与 MiSans/Skia 的 integration driver 均在截图转换阶段卡住；原生截图停留在 Test starting，两个运行在终止测试应用后 rc=1，不能计作通过。失败目录保留为 `font-before-android-20261113-default-narrow-light`、`misans-android-skia-20261113-default-narrow-light`。

后续使用普通 `runApp(PactaApp)` 的离线内存样例，命令 `flutter run -d emulator-5554 -t build/font-task/preview.dart --no-resident`，rc=0。样例复用产品共用主题，使用 FakeAuth 和内存 Drift，不连接云服务或持久化用户业务数据。证据目录 `build/font-task/android-run-20261113-01/` 含 run.log、run.rc、environment.txt 和 screenshots；屏幕 1080×1920、420 dpi。

ADB 原生截图已判读 `board-light.png`、`board-dark.png`、`focus-chain-light.png`、`focus-chain-dark.png`、`my-light-attribution.png`、`my-dark-attribution.png`：中英文/数字协调，无缺字方框，正常字号未见新增裁切，导航点击及页面滚动正常，MiSans 声明完整可见。夜间模式由 no 改 yes 取证后恢复 no。未使用连接的真机，模拟器结果不替代真机验收。

## 设计评审

依据 apple-design `typography.md` 的 Ensuring legibility / Conveying hierarchy / Using custom fonts：限制字体数量、用字号/字重表达层级、在实际平台验证可读性；转译为 Flutter ThemeData/TextTheme，保留 Material 规范，不套用 Apple 的字体或字号。依据 `layout.md` 的 Adaptability 与项目 UI 指南检查窄宽屏、长中文；亮暗沿用既有 ColorScheme，自动对比度测试包含在完整测试中。ADR 0007/0008 已退出的专项要求不新增。

## 代码评审与复盘

比较基线是本任务开始时的工作树快照（`build/font-task/baseline/`），只审查本次字体现行 diff，保留原有未提交业务变更。

- Standards：独立审查未发现可操作问题，共用 ThemeData、资源映射和下载校验符合项目规则。
- Spec：独立审查确认全平台字体、四档映射、许可/声明及构建来源满足已确认需求；发现 README 首次运行/构建命令缺少字体获取步骤，已在两处补齐并复审关闭。剩余问题 0。

字体与 pubspec/main 的额外 SHA256 记录在 `build/font-task/font-inputs.json`；现有 pilot manifest 不覆盖字体资源，不能单凭旧 pilot 指纹证明字体未变。最终资源逐个 hash 已复核。

本次确认普通 widget 测试无法发现 Windows 系统中文回退的观感问题；以后替换字体需要同 fixture 的真实平台截图和字体 hash 证据。既有 UI 指南已经要求真实平台取证，无需重复增加代理规则。
