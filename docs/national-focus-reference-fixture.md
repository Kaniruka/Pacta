# 国策树图片样例

`assets/fixtures/national_focus_tree/reference_v13_8_18.json` 保存参考图中可辨认的标题、正文和分类，并作为这套50节点图片样例测试和演示的唯一数据源。Flutter assets 让独立预览可以在 Windows 与 Android 读取相同数据。矩形规则卡会映射为 `NationalFocusCard`：卡片标题写入独立名称，并在这套隔离样例中同时保留为触发条件；卡片正文进入行动，分类路径保存为 scope。这一样例映射不是旧用户卡片的名称回填策略。

参考图使用椭圆展示分组，但当前国策领域模型没有 Group 类型。为了在现有页面上预览完整树形层级，fixture helper 会把椭圆标签生成为带有“仅演示”scope 和“非实际行为规则”行动文案的结构演示卡。它们只为展示层级和测试父子交互服务，不是业务规则，也不属于 Group 模型。图片规则卡和这些演示卡只写入 `NativeDatabase.memory()`，不连接真实用户或云端。

图片中的“水密隔舱”“休养日”“万物皆生灵”等内容作为普通卡片文字保留。fixture 不实现冻结树分支、自动作废任务、容错或其他图片文案暗示但现行规范没有的业务行为。卡片的现实执行情况仍由用户判断；应用不会自动评估。标记 `needs_review` 的内容有转录不确定性，应在使用样例前人工核对。

运行独立页面预览：

```sh
flutter run -d windows -t tool/national_focus_reference_demo.dart
flutter run -d <android-device-id> -t tool/national_focus_reference_demo.dart
```

预览使用临时内存数据库，重启后数据会消失。

Android 模拟器上的双指缩放和平移验收：

```sh
flutter test integration_test/national_focus_canvas_gestures_test.dart -d <android-device-id>
```

## 四节点界面预览

`tool/national_focus_ui_review_demo.dart` 使用独立的四张样例卡，不依赖上述图片JSON：根国策、每日阅读、规律运动、记录收获。它通过固定时间的本地检查点与手动点亮覆盖点亮、待今日确认和熄灭三态，方便检查菜单首项、独立详情、低频改名入口以及适应屏幕单图标按钮。

```sh
flutter run -d windows -t tool/national_focus_ui_review_demo.dart
flutter run -d <android-device-id> -t tool/national_focus_ui_review_demo.dart
```

两种预览均仅用内存、关闭云同步，不读取账号凭据、不创建测试用户、不向开发项目灌入业务数据。正常运行前无需传入 `.env`。

页面及50节点画布回归：

```sh
flutter test test/national_focus/national_focus_tree_page_test.dart test/national_focus/national_focus_reference_canvas_test.dart
flutter test integration_test/national_focus_tree_actions_device_test.dart -d <android-device-id>
```

当前图标控件之外的缩放/平移使用手势；不再有比例读数或缩放菜单。详细的现行交互与历史验证记录见 [画布设计](national-focus-canvas-design.md)。本机生成截图位于被Git忽略的 `build/national_focus_polish_preview/`，最终单图标截图为 `fit-icon-only.png`；截图不作为仓库中的持久资产。
