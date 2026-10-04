# Mission: 用 Apple Design skill 重构 Pacta 界面

## Why
把 Pacta 的功能入口和页面视觉做得清楚、易用、有辨识度，让用户更容易从任务进入专注，并在 Android 和 Windows 上保持一致的业务流程。

## Success looks like
- 能区分主导航、页面操作和次级流程，并为四个既定入口画出清晰的信息层级。
- 能用 `apple-design` skill 审查截图或 Flutter 页面，得到带依据、优先级和具体修改建议的反馈。
- 能将审查结果转成小范围 Flutter 改动，并核验 Android 与 Windows 的可用性。

## Constraints
- 遵守 ADR 0004 的四个主入口及各自职责。
- Flutter Material 3 是实现基础；首发平台为 Android 15 和 Windows 11。
- Apple HIG 用于设计原则和审查，平台约定要翻译到目标平台。

## Out of scope
- 暂不改变已接受的业务流程、数据模型或平台范围。
