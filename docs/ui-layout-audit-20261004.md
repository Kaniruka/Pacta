# Pacta 页面布局审查与实施方案 · 2026-10-04

## Summary

总体评价：Needs work。Pacta 的核心工作是把具体任务转换为专注承诺，再维护独立的国策规则；页面辨识点应是向下生长的国策分支。现有四入口符合 ADR 0004，但重复标题、默认展开的记录和操作、深层递归缩进让任务和树结构难以读懂。

本报告基于 Flutter 源码审查；未以截图推测对比度，也未声称已完成模拟器、TalkBack、Windows 键盘验收。采用 Apple HIG 的可访问性、布局和渐进呈现原则；Android 保留 Material 3，Windows 保留原生窗口惯例。范围不改变数据模型、确认规则、专注结果或四入口职责。

## 依据

已阅读 MISSION.md、CONTEXT.md、docs/product-design.md、ADR 0004，以及 apple-design 的 accessibility、layout、typography、color、designing-for-ios、tab-bars、toolbars、buttons、lists-and-tables、scroll-views 和 cross-platform 引用。Apple 平台专属菜单栏、玻璃材质和字号不机械套用到 Android。

- `accessibility.md › Vision`：“Support larger text sizes.” 布局需要承受至少 200% 字号。
- `accessibility.md › Vision`：“Convey information with more than color alone.” 节点状态保留明确文字与图标。
- `buttons.md › Style`：“Keep the number of prominent buttons to one or two per view.” 每个区块一个优先动作，其余进入菜单或详情。
- `scroll-views.md › Best practices`：“Avoid putting a scroll view inside another scroll view with the same orientation.” 页面使用一个主要纵向滚动区。
- `lists-and-tables.md › Platform considerations`：“Use an outline view instead of a table view to present hierarchical data.” 纵向结构需表达父子层级，不能靠编号猜测。

## Improvements

| 优先级 | 页面 / 证据 | 问题 | 具体布局 |
| --- | --- | --- | --- |
| High | 主壳，lib/main.dart 的 AppBar 与 FocusChainPage / NationalFocusTreePage 内容标题 | 同页重复“专注链”“国策树”，上下两层标题浪费首屏；壳标题没有承载页面动作 | 一级页只保留一个标题来源。保留内容页标题时删除空用途壳 AppBar，并补 SafeArea；二级流程保留 AppBar 与返回。Android 底部四入口，宽屏 NavigationRail。 |
| High | 国策树，_buildBranch | 当前已经纵向递归，实际问题是祖先缩进累积：每层既增加 min(depth,6)*12，又增加 30 dp 容器缩进；深层节点文字宽度被吃掉 | 父节点在上，连线向下，再分到子节点；紧凑宽度保持单卡正文宽度，横向平移查看并排分支；不再累计缩进，也不通过压缩字号适应。 |
| High | 国策结构卡，_StructureTreeCard | 卡片首行只显示“节点 1.1 · 状态”，缺少用户规则名称；记录与维护动作却常驻 | 卡首行显示实际主要触发条件，第二行行动摘要，文字状态 + 图标；节点编号只作次级定位。点击展开记录/强化/迁移等详情，常用“确认今日有效”保留清晰入口。 |
| High | 国策页 Column 的画布前置区域 | 标题、描述、卡库、核对提示、维护总结、位置说明、模式切换全在不滚动头部；小屏大字号挤压树 | 页面整体纵向滚动。标题右侧卡片库；下一行仅待确认数和确认动作；检查点与失败记录置为辅助信息；结构/详情切换后直接进入树。仅有待核对/放置流程时显示对应提示。 |
| High | MyPage | 管理员身份后立即铺开三个管理表单，日历、规则、设备设置被推到很下方 | 身份卡 → 日常设置分组（日历块、下必为例、通知后台）→ 待核对分组 → 管理员工具折叠区或独立页 → 退出。管理表单保持原权限与操作确认。 |
| Medium | 看板 _BoardContent | 首行口号与新建按钮挤在 Row，所有目标、状态、七日活动和日历同权重卡片堆叠 | 单标题“看板”与“新建目标”操作；可执行目标任务优先；国策今日摘要、七日活动、日历规划为安静辅助区。宽屏主任务列 + 320–360 dp 辅助列。 |
| Medium | 专注链 FocusChainPage | 模式筛选、全部任务、三条独立记录、历史均铺开；信息层级单一 | 单标题 + 一行任务用途说明；进行中/预约恢复优先；筛选 → 可开始任务；三链记录紧凑汇总；历史折叠或下方独立区。 |
| Medium | 专注 / 预约准备 | 任务名、倒计时、状态与规则说明需要明显先后顺序 | 二级 AppBar 只说明流程与返回；任务名 → 大倒计时 → 状态解释 → 主要继续/进入动作；下必为例和承认失败使用低干扰入口，保留既定确认。 |
| Medium | 卡片库 / 新建卡 / 强化 | 数据正文、状态、历史与编辑按钮易形成长页 | 卡片库采用真实触发条件 + 行动两行列表；新建/强化为短任务表单，单一保存动作，历史折叠；底部保存区避开键盘。 |
| Medium | 日历来源 / 通知设置 | 技术状态和解释可能与主要设置竞争 | 按来源、权限、后台状态分组；状态解释就近放置，仅异常强调。沿用真实权限和缓存边界，不把设置入口改为请求权限。 |
| Medium | 三类核对页面 | 原始记录和裁决操作信息密集 | 待处理优先、已处理历史折叠；每组先说明冲突 → 可选方案 → 原始证据；保留原始来源与业务裁决顺序。 |
| Low | 登录 / 目标和任务编辑 | 属于聚焦输入流程，无需另加品牌头或重复解释 | 保留单标题、正确键盘、字段提示和单一主动作；错误就近显示；检查小屏和键盘遮挡。 |

上述 High / Medium 的排序和美感取舍属于设计判断，引用用于支持清晰层级与可访问性原则。尚未把未经实测的字号溢出标为 Critical。

## 具体布局

紧凑宽度（Android，最小 320 dp；所有页 16 dp 左右边距）：

```text
看板                  + 新建目标
[可执行的目标 / 任务]
[国策今日待确认摘要]
[近期专注活动]
[日历规划参考]
────────────────────────────
看板     国策树     专注链     我的
```

```text
国策树                   卡片库
今日待确认 N       [确认今日有效]
下一检查点 · 次级信息 / 失败记录
[结构 | 详情]
            父节点
               │
          ┌────┴────┐
        子节点     子节点
          │
        后代节点
```

紧凑树以视口宽度决定单卡宽度，正文自动换行；并排分支通过水平平移访问。首次将父节点居中完整显示，生长方向始终向下。

常规宽度（建议 ≥ 840 dp，宽度判定而非 Platform 判定）：

```text
四入口 Rail │ 看板标题                 新建目标
            │ 任务主列       │ 今日国策摘要
            │ 目标与任务     │ 七日专注活动
            │                │ 日历规划参考
```

国策树可占主要内容宽度；详情在独立面板或展开区；树的父子方向始终从上向下。窗口收窄时功能保持一致。

## Token system

采用系统字体（Android Roboto / Windows 系统字体），中文由平台回退。沿用 Material 3 TextTheme 的 displayLarge（倒计时）、headlineSmall（页面标题）、titleLarge/titleMedium（区块）、bodyLarge/bodyMedium（正文）和 bodySmall（辅助说明）；字号随系统缩放，不缩小字体来适应布局。间距 4、8、12、16、24、32；主页面正文最大宽度 960 dp、二级页面 800 dp；Material 交互目标至少 48 dp。采用 ThemeData / ColorScheme 语义角色并跟随系统亮暗。

最终保留 Pacta 原有绿色 seed #385A52，使用 ColorScheme.fromSeed 派生亮暗语义色，而非采用初稿的蓝色候选。理由是突出国策与专注承诺本身，并延续应用身份。以下为运行时主题提取与 WCAG sRGB 计算的真实色值（纯色，无透明叠加）：

| 角色 | 浅色 | 深色 | 与各自 surface 对比 |
| --- | --- | --- | --- |
| surface | #F5FBF7 | #0E1513 | — |
| content | #171D1B | #DEE4E1 | 16.31 / 14.35 |
| secondary | #3F4946 | #BEC9C5 | 8.89 / 10.88 |
| accent | #056B5C | #84D6C3 | 6.13 / 10.91 |
| tertiary | #436278 | #ABCAE4 | 6.15 / 10.83 |
| error | #BA1A1A | #FFB4AB | 6.16 / 10.89 |

亮暗正文与主要操作的有效前景/背景对比度已由 ui_layout_test 自动验证 ≥4.5:1。signature 是国策树向下生长的清晰分支，不额外加入装饰纹理、渐变英雄数字或重复 logo。无需新增动作动画；遵循系统减少动态效果。

## Critique and scope

本布局来自 Pacta 的两种独立记录：任务进入专注、规则形成国策分支，并非通用仪表盘模板。可删除的配饰是重复的一级 AppBar 标题、每个树节点常驻的全部管理操作与我的页面常驻管理表单。四入口、任务和国策边界、三独立链、每日确认、权限确认保持既定语义。

实施顺序：深层宽度与大字可读性 → 单标题与导航 → 树卡真实名称与向下分支 → 我的分组与渐进呈现 → 看板/专注区层级 → 深色、焦点及模拟器视觉核验。

## Verification requirements

- 320 / 360 / 412 dp 与 200% 文字：不出现 RenderFlex 溢出，主要正文无需横向拖动。
- 树覆盖多个根、并列子节点、至少八层深度、无子节点、待核对和放置状态；卡名、状态、父子关系可辨认。
- TalkBack 顺序从标题到正文再到操作；图标按钮带 Tooltip / Semantics；颜色之外有状态文字。
- Android 验证系统返回、底部导航、键盘、SafeArea 与实际触摸目标；Windows 验证窄窗口和 Tab 焦点。
- dart format、flutter analyze、相关 widget tests，最终完整 flutter test。只报告真实执行的结果。


## 实施记录

- 主壳去除重复 AppBar，SafeArea 包住内容；≥840 dp 使用 NavigationRail，四入口职责保持 ADR 0004。
- 看板宽屏分为任务主列和320 dp辅助列；窄屏任务在前。专注连续记录移入副标题，历史折叠；倒计时正文可滚动。
- 我的日常入口在前，管理员表单收进“用户管理”折叠区，普通用户仍不可见。
- 国策父节点居中在上，连线向下分到子节点；结构卡显示实际条件、行动和文字状态，点亮/今日确认可直接操作，统计与强化在详情。多分支可水平平移，12层不再累积缩窄。
- 六个二级页面收敛正文宽度、安全区及大字号操作布局；没有改动数据模型、RLS、结算或裁决逻辑。
- Android 15模拟器已运行四入口集成验收并保存隔离示例截图；Windows原生构建与四入口集成验收通过。
- 暂未进行TalkBack完整朗读验收、真实Android输入法和实体Windows键盘人工验收。极大国策树仍一次构建，尚未虚拟化。


最终自动验证：`dart format` 完成；`flutter analyze` 无问题；完整 `flutter test` 181项通过。Android `flutter drive --driver=test_driver/ui_layout_acceptance_test.dart --target=integration_test/ui_layout_acceptance_test.dart -d emulator-5554` 与 Windows `flutter test integration_test/ui_layout_acceptance_test.dart -d windows` 均通过。日志与隔离示例截图在被Git忽略的 `build/ui-layout-*.log` 和 `build/ui-layout-evidence/`。Android测试使用本地替身用户与内存数据库，不访问真实用户数据。
