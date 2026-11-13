# Issue #91 实施记录：国策卡轻量分层

分支：`impl/pacta91-card-layers`（worktree `C:/Users/Stray/.codex/worktrees/pacta-card-layers/Pacta`）
基线：`c76a59f`（`feat/sync-profile-cards-20261113`，与 `origin/feat/sync-profile-cards-20261113` 一致）
依据：`docs/spec-sync-profile-cards-20261113.md`、`docs/tickets-sync-profile-cards-20261113/01.md`、原型 `docs/prototypes/pacta-card-prototype-20261113.html` 的 `data-design=a`（轻量分层）。

## 实施结果

- **节点弹层**（`_NodeActionsSheet`）：只保留标题、当前规则（`effectiveAction`）与操作；删除两条 `Divider`、例外与判例区块和强化管理入口。状态首项仍为点亮/确认/熄灭，待核对与级联禁用原因仍作为该行副标题。
- **详情**（`_NationalFocusCardDetailPage`）：例外与判例改为默认折叠的 `ExpansionTile`（无记录时整块不显示）；记录摘要保留；单一“编辑卡片”按钮取代原 PopupMenu；强化入口从详情移除。规则标签在强化生效时显示“当前规则 · 强化等级 N”。
- **编辑卡片**（`NationalFocusCardEditorPage`）：名称、国策规则、折叠的例外与判例三字段保留；新增“强化要求”分组作为唯一强化入口，显示当前使用级别与已设级数，返回时重新读取卡片以刷新摘要。
- **未保存草稿**：强化管理是 push 路由，编辑页保持挂载，控制器文本不重建；返回后草稿仍在，保存仍写入全部字段。
- **强化管理**（`NationalFocusStrengtheningPage`）：顶部用 `secondaryContainer` 面板突出“当前使用 · 基础要求/强化等级 N”；“可用要求”按行紧凑列出基础与各级（`ValueKey('national-focus-strengthening-level-N')` / `-base`），当前行带“正在使用”，其他行带“选择”；“新建强化要求”在 5 级上限时禁用并显示“已达 5 级上限”；生效版本记录 `ExpansionTile` 保留。
- **强化等级编辑**：原左右对照改为“强化后的国策规则”输入 + 默认折叠的“对照基础规则”；旧触发覆盖继续原样透传，版本历史规则不变。

## 取舍与假设

1. 管理页按原型只允许编辑“当前归属”的那一级：其他等级先“选择”再“编辑”。切换立即生效且不改记录，因此编辑路径完整；基础要求仍在编辑卡片中修改，管理页不新增第二条基础规则写入路径。
2. 详情不再提供 PopupMenu，改为可见“编辑卡片”按钮（原型同位置）。
3. 卡片库列表的“管理强化要求”入口保留：票据约束的是详情与节点弹层，库卡菜单属另一入口，删除会减少现有能力。
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

既有用例按新结构更新：`national_focus_tree_page_test.dart`、`national_focus_strengthening_rule_test.dart`、`card_editing_test.dart`、`national_focus_exception_confirmation_test.dart`、`test/ui/experience_repro_test.dart`、`test/ui_secondary_layout_test.dart`；设备 fixture 仅同步标签：`national_focus_refinement_device_test.dart`、`experience_improvements_device_test.dart`、`ticket_17_national_strengthening_test.dart`。

## 截图 fixture

`integration_test/national_focus_card_layers_device_test.dart`：内存 Drift + 真实页面，可在 Android/Windows 重跑，输出 10 张状态图（树、弹层、详情折叠/展开、编辑、管理、切换、等级编辑对照、五级上限）。

```bash
flutter test integration_test/national_focus_card_layers_device_test.dart -d windows
flutter test integration_test/national_focus_card_layers_device_test.dart -d DEVICE_ID
```

可选 `--dart-define=NF_CARD_LAYERS_CAPTURE_DIR=...`、`NF_CARD_LAYERS_THEME=light|dark|system`、`NF_CARD_LAYERS_WIDTH=320`。默认目录 `build/ui-layout-evidence/national-focus-card-layers`，同名截图拒绝覆盖。Windows 用 `RepaintBoundary` 取图，Android 直接取 Flutter 表面（不含系统弹窗/输入法）。

## 实际执行的命令与结果

| 命令 | 结果 |
| --- | --- |
| `dart format <12 个改动文件>` | Formatted 12 files (5 changed) |
| `flutter analyze` | No issues found! |
| `flutter test test/national_focus/` | 115 tests passed |
| `flutter test test/ui/experience_repro_test.dart test/ui_secondary_layout_test.dart` | 10 tests passed |
| `flutter test`（全量） | 415 tests passed |

## 未完成的验收

- Android 与 Windows 真机/模拟器截图与目视判读：由主 agent 协调设备后运行上述 fixture；本轮未占用设备，未产生平台截图。
- 亮暗/窄宽的真实平台核对：仅完成 widget 级（320 逻辑像素、light/dark）与 fixture 参数化，尚无平台图象证据。
- 设计评审与 Standards/Spec 代码评审：尚未进行。
- 云/同步/通知/全局布局：按票据未改动，也未做相关验收。
