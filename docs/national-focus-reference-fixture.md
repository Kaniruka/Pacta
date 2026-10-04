# 国策树图片样例

`assets/fixtures/national_focus_tree/reference_v13_8_18.json` 保存参考图中可辨认的标题、正文和分类，并同时作为测试和演示的唯一数据源。Flutter assets 让独立预览可以在 Windows 与 Android 读取相同数据。矩形规则卡会映射为 `NationalFocusCard`：卡片标题进入触发条件，卡片正文进入行动，分类路径保存为 scope。

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
