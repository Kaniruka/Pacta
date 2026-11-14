# 头像裁剪设计复核

**结论：Good；未发现阻塞或高优先级视觉问题。** 固定圆形裁剪窗、拖动定位、双指/滑杆缩放、重置和明确确认形成单一任务；资料页保留独立保存步骤，用户能看出“使用此头像”只完成裁剪选择。

## 复核结果

- Android 亮色与暗色 320 dp、Windows 亮色与暗色的裁剪页均显示标题、操作提示、圆形预览、缩放滑杆、重置、取消与“使用此头像”，主要控制没有被窄屏挤出或遮挡。Android 的 `02b-crop-pinch.png` 相比 `02-crop-adjusted.png` 显示更大倍率，`03-crop-positioned.png` 展示位置调整后的结果；桌面提供滑杆和鼠标拖动路径。
- 编辑页的头像草稿可见，且“重新裁剪”“移除头像”“保存”各自清楚。320 dp 下“移除头像”与说明文案换行，但没有相互覆盖；裁剪和编辑页在亮暗主题中保持相同层级。
- 规格依据是 `docs/spec-sync-profile-cards-20261113.md`「展示与行为」头像条目（固定圆形预览、拖动/缩放/重置、裁剪只改草稿、编辑页保存、取消保留旧头像及再次裁剪入口）。静态实现对应 `lib/src/profile/avatar_crop_page.dart` 中圆形预览、滑杆、重置与返回裁剪字节，以及 `lib/src/profile/profile_edit_page.dart` 中重新裁剪和独立保存。

## 设备截图证据

四组目录均来自冻结提交 `48f2d9c`，manifest 标记 `sourceUnchanged=true`，`run.rc=0`：

| 平台与状态 | 证据目录 |
| --- | --- |
| Android 亮色 | `build/ui-layout-evidence/avatar-crop/20261114-111959-android-light/` |
| Windows 暗色 | `build/ui-layout-evidence/avatar-crop/20261114-112038-windows-dark/` |
| Windows 亮色 | `build/ui-layout-evidence/avatar-crop/20261114-112235-windows-light-final/` |
| Android 暗色、320 dp | `build/ui-layout-evidence/avatar-crop/20261114-112246-android-dark320/` |

320 dp 运行通过密度覆盖 540 实现，`density-restored.txt` 记录物理密度恢复为 420；Android `native-end.png` 显示正常应用窗口，没有 ANR 遮罩。Flutter debug ribbon 出现在部分 debug 截图中，作为构建标识处理；它没有覆盖裁剪控件。

参考按 Flutter Android/Windows 转译：`gestures.md › Best practices` 要求直接操作及时反馈；`sliders.md › Best practices` 要求滑杆端点符合熟悉方向；`layout.md › Adaptability` 支持按可用空间响应；`cross-platform.md › Conventions to check` 将 Material 触摸目标映射为 48 dp。Android/Windows 的 normal-size 可读性、触摸/鼠标和窄屏响应保留为评审范围。ADR 0007/0008 退出的读屏/辅助技术、大字号和专项键盘支持不作为本次门槛。

## 限制

本复核检查了已保存的设备截图与静态 UI 实现，没有自行启动设备或计算像素级对比度；裁剪图由合成测试图片提供，不能代表不同真实照片在极限放大时的主观画质。截图和本报告只支持头像裁剪 UI 结论，不替代账号资料、真实云端头像同步或系统图片选择器的完整验收；行为结果见[头像裁剪验收记录](avatar-crop-validation-20261114.md)。
