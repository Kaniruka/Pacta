# 头像裁剪实施与验收（2026-11-14）

用户要求头像支持裁剪、调整位置，不能选入后固定位置；明确调用 implement 技能。比较基点 `561a712`，实现提交 `48f2d9c`，当前分支 `feat/sync-profile-cards-20261113`。本次为客户端交互和图像处理，不修改共享云或资料存储契约。

## 最终行为

- 系统选图后打开固定圆形预览，可拖动、双指缩放或用滑杆缩放、重置；确认按钮固定在底部，裁剪区同时适应宽度和高度。
- “使用此头像”仅更新资料编辑草稿，“保存”才写入本地资料并同步。取消选图/裁剪保持此前头像与草稿；可重新裁剪既有头像，本次所选原图在编辑期间保留供继续调整。
- 预览和输出共用同一源矩形，选区限制在图像范围内；保存为方形 PNG，圆形仅用于显示。保持 PNG/JPEG、来源 5 MB、最长边 384 px、存储 256 KB 限制；解码先查元数据并限制分配，释放 codec、图像、picture 等资源。
- 修复测试发现的竖向拖动被页面滚动抢走的问题：正常高度用固定布局，极短窗口才允许滚动回退。昵称的晚到初次读取不覆盖用户已输入内容。

## TDD 与代码检查

沿用已确认边界：真实 ProfileEditPage、LocalProfileRepository 和内存 Drift；只替换外部选图器/remote。`.scratch/avatar-crop/red.log` 保存未实现时找不到裁剪页的失败；`green.log` 保存真实页面、草稿、取消和保存后图像像素的通过结果。

- `dart format`：完成。
- `flutter analyze`：无问题（`.scratch/avatar-crop/analyze.log`）。
- `flutter test test/profile`：58 项通过（`profile-tests.log`）；最终裁剪像素用例 3 项通过。
- 像素断言区分横图/竖图拖到蓝色区域与默认中央红色区域，并验证缩放、重置、取消保持已存头像、方形/字节上限与无额外透明空白。
- 独立代码评审固定 `git diff 561a712...48f2d9c`，Standards 与 Spec 两轴均无发现，报告在 `.scratch/avatar-crop/{standards,spec}-review.md`。主 Agent复核资源释放、保存边界、预览/输出矩形及实际双指截图。
- 所有代码和设备验收收尾后运行一次 `flutter test`：608 项全部通过，退出码 0（`.scratch/avatar-crop/full-tests.log`、`full-tests.rc`）。设计复核为 Good，无阻塞或高优先级问题。

## Android / Windows 实际运行

入口 `integration_test/avatar_crop_device_test.dart`，由 `.scratch/avatar-crop/run_ui.py` 调用 `flutter drive --keep-app-running --no-start-paused --driver=test_driver/ui_layout_acceptance_test.dart`。它使用合成 PNG、内存数据库与内存 remote，不读取真实头像、不触碰真实用户资料。

| 场景 | `build/ui-layout-evidence/avatar-crop/` 下目录 |
| --- | --- |
| Android 亮色，正常宽度 | `20261114-111959-android-light` |
| Android 深色，320 逻辑像素 | `20261114-112246-android-dark320` |
| Windows 深色，宽窗口 | `20261114-112038-windows-dark` |
| Windows 亮色，宽窗口 | `20261114-112235-windows-light-final` |

四组均测试退出码 0、`sourceUnchanged=true`；两组 Android 原生末帧无 ANR 遮罩。覆盖初始裁剪、拖动/滑杆、Android 双指、重置后位置、确认草稿、保存和已有头像重新裁剪后取消。主 Agent已目视核对 Android `02` 与 `02b` 的放大变化，`03` 的移动结果与保存头像一致；设计报告见 [设计复核](avatar-crop-validation-20261114-design.md)。

首轮 `20261114-111845-windows-light` 虽流程通过，但开跑后仍有换行/测试/布局收尾，源码指纹变化，因此不作为最终证据。独立 Windows `flutter test integration_test/avatar_crop_device_test.dart -d windows` smoke 也通过，不替代最终截图。

Android 使用原 AVD `PactaFocusPilot20261112`。原 5556/5557 端口被用户的另一个模拟器占用，故本次改用 `emulator-5580`，未操作该其他模拟器或实体手机 `b9680744`。320 场景执行 density=540，finally 恢复原 density=420。未清数据、未卸载应用；本次没有修改原生选图通道，因此系统单图选择器沿用此前已完成的两端验收，本次取证聚焦新增裁剪界面。

## 工作区边界

用户之前的未跟踪 `docs/shared-cloud-deployment-20261114.md` 保持原样且未纳入本次提交。已停止本轮 Windows 测试进程并通过 ADB 正常关闭本轮启动的 `emulator-5580`，保留应用数据。按 implement 要求在当前分支提交；本次没有推送、创建/合并新 PR 或部署共享云。
