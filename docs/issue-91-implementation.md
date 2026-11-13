# Issue #91 实施记录：国策卡轻量分层

分支：`impl/pacta91-card-layers`（worktree `C:/Users/Stray/.codex/worktrees/pacta-card-layers/Pacta`）
基线：`c76a59f`（`feat/sync-profile-cards-20261113`，与本地 `origin/feat/sync-profile-cards-20261113` 一致）
提交：`385dc56` feat(national-focus): layer card sheet, detail, editor and strengthening (#91)

合并记录：集成分支为 `feat/sync-profile-cards-20261113`（不需要名为 `integration` 的分支或远端 fetch）。已在本分支合并其本地 tip `b11f426`（`docs: record accepted sync retention decision and implementation baseline (#90)`），合并提交 `a1f46d8`，仅新增 ADR 0005 补充与 `docs/implementation-sync-profile-cards-20261113.md`，无冲突。
依据：`docs/spec-sync-profile-cards-20261113.md`、`docs/tickets-sync-profile-cards-20261113/01.md`、原型 `docs/prototypes/pacta-card-prototype-20261113.html` 的 `data-design=a`（轻量分层）。

## 实施结果

- **节点弹层**（`_NodeActionsSheet`）：只保留标题、当前规则（`effectiveAction`）与操作；删除两条 `Divider`、例外与判例区块和强化管理入口。状态首项仍为点亮/确认/熄灭，待核对与级联禁用原因仍作为该行副标题。
- **详情**（`_NationalFocusCardDetailPage`）：例外与判例改为默认折叠的 `ExpansionTile`（无记录时整块不显示）；记录摘要保留；单一“编辑卡片”按钮取代原 PopupMenu；强化入口从详情移除。规则标签在强化生效时显示“当前规则 · 强化等级 N”。
- **编辑卡片**（`NationalFocusCardEditorPage`）：名称、国策规则、折叠的例外与判例三字段保留；新增“强化要求”分组作为唯一强化入口，显示当前使用级别与已设级数，返回时重新读取卡片以刷新摘要。
- **未保存草稿**：强化管理是 push 路由，编辑页保持挂载，控制器文本不重建；返回后草稿仍在，保存仍写入全部字段。
- **强化管理**（`NationalFocusStrengtheningPage`）：顶部用 `secondaryContainer` 面板突出“当前使用 · 基础要求/强化等级 N”；“可用要求”按行紧凑列出基础与各级（`ValueKey('national-focus-strengthening-level-N')` / `-base`），当前行带“正在使用”，其他行带“选择”；“新建强化要求”在 5 级上限时禁用并显示“已达 5 级上限”；生效版本记录 `ExpansionTile` 保留。
- **强化等级编辑**：原左右对照改为“强化后的国策规则”输入 + 默认折叠的“对照基础规则”；旧触发覆盖继续原样透传，版本历史规则不变。

## 取舍与假设

1. 管理页每行同时提供“选择”（切换生效）与编辑按钮，二者分离：非当前等级可直接编辑，不会改变当前有效要求，也不会新增要求版本；切换仍只在用户点“选择”时发生。基础要求仍在编辑卡片中修改，管理页不新增第二条基础规则写入路径。
2. 详情不再提供 PopupMenu，改为可见“编辑卡片”按钮（原型同位置）。
3. 按票据 AC“强化入口只从编辑卡片进入”，卡片库菜单与库卡操作区不再提供直接的“管理强化要求”按钮；库卡经“编辑卡片”进入同一管理页，能力未减少。
4. 管理页不再重复展示例外与判例（原型当前要求只显示规则），避免与详情/编辑重复。

## TDD 切片

新增 `test/national_focus/national_focus_card_layers_test.dart`（10 个用例），按切片先红后绿：

1. 弹层只有标题、当前规则与操作（无分割线/例外/强化入口）。
2. 详情折叠例外与判例、保留记录与编辑入口、无强化入口。
3. 编辑卡片进入强化管理后返回保留未保存草稿并成功保存。
4. 管理页突出当前要求、紧凑列出其他等级、手动切换落库。
5. 五级上限禁用新建并保留版本记录。
6. 强化等级编辑的基础规则对照默认折叠、按需展开并保存。
7. 待核对状态阻断弹层操作与详情编辑入口（`UnavailableNationalFocusRepository` 替身提供待核对卡）。
8. 窄屏 320 逻辑像素 + light/dark 下弹层、详情、编辑、管理可操作且无异常。
9. 空例外时详情不显示分组。
10. 卡片库不再直接提供强化管理，改从“编辑卡片”进入（AC：强化入口只从编辑卡片进入）。
11. 强化管理可直接编辑非当前等级，不改变当前有效要求、不新增要求版本；编辑与“选择”分离。

既有用例按新结构更新：`national_focus_tree_page_test.dart`、`national_focus_strengthening_rule_test.dart`、`card_editing_test.dart`、`national_focus_exception_confirmation_test.dart`、`test/ui/experience_repro_test.dart`、`test/ui_secondary_layout_test.dart`；设备 fixture 仅同步标签：`national_focus_refinement_device_test.dart`、`experience_improvements_device_test.dart`、`ticket_17_national_strengthening_test.dart`。

## 截图 fixture

`integration_test/national_focus_card_layers_device_test.dart`：运行**真实 `PactaApp`**（真实 Pacta 主题与 MiSans，未另造 ThemeData）+ `FakeAuthRepository` + 真实本地仓储（内存 Drift 的 task/focus/national focus），经 `NavigationBar`/`NavigationRail` 进入“国策树”，输出 9 张状态图：树、弹层、详情折叠/展开、编辑卡片、强化生效详情、管理页、等级编辑（对照基础规则）、五级上限；并逐步断言返回路径回到树（成功路径）。

```bash
# Windows：RepaintBoundary 写入显式目录
flutter test integration_test/national_focus_card_layers_device_test.dart -d windows

# Android：surface 截图经共享 UI 证据 driver 导出到 host
#   PowerShell: $env:UI_EVIDENCE_SUBDIR='national-focus-card-layers'; $env:UI_EVIDENCE_FAIL_ON_EXIST='1'
flutter drive --driver=test_driver/ui_layout_acceptance_test.dart \
  --target=integration_test/national_focus_card_layers_device_test.dart -d DEVICE_ID
```

Windows 输出目录由 `--dart-define=NF_CARD_LAYERS_CAPTURE_DIR=...` 指定，默认 `build/ui-layout-evidence/national-focus-card-layers`，同名截图拒绝覆盖；Android 图片由 `test_driver/ui_layout_acceptance_test.dart` 写入 `build/ui-layout-evidence/$UI_EVIDENCE_SUBDIR/`。两端可选 `NF_CARD_LAYERS_THEME=light|dark|system`、`NF_CARD_LAYERS_WIDTH=320`（沿用真实主题，不替换）。Android 图为 Flutter 表面，不含系统弹窗/输入法。

## 实际执行的命令与结果

| 命令 | 结果 |
| --- | --- |
| `dart format <12 个改动文件>` | Formatted 12 files (5 changed) |
| `flutter analyze` | No issues found! |
| `flutter test test/national_focus/` | 115 tests passed |
| `flutter test test/ui/experience_repro_test.dart test/ui_secondary_layout_test.dart` | 10 tests passed |
| `flutter test`（全量） | 417 tests passed |
| `flutter test integration_test/national_focus_card_layers_device_test.dart -d windows` | 真实 PactaApp 走查 9 张截图，全部用例通过（构建 20.2s，用例 13s） |

## 已产出的平台证据

- Windows：`build/ui-layout-evidence/national-focus-card-layers/national-focus-card-layers-01..09-*.png`（1582×853，真实 Pacta 主题 + MiSans，dark 系统外观）。本轮在该 worktree 实跑 fixture 通过，已人工打开核对弹层、详情折叠、管理页与五级上限。

## 未完成的验收

- Android：fixture 已改用 `convertFlutterSurfaceToImage`/`takeScreenshot` + 共享 driver，但本轮未占用设备，未产生 Android 截图。
- 亮暗/窄宽的真实平台核对：Windows 仅系统 dark 外观；窄宽仅有 widget 级（320 逻辑像素）与 `NF_CARD_LAYERS_WIDTH` 参数化，尚无窄宽平台图。
- 设计评审与 Standards/Spec 代码评审：尚未进行。
- 云/同步/通知/全局布局：按票据未改动，也未做相关验收。