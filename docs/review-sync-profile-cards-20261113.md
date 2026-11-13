# #90 双轴评审

固定基点 `394e321`，首轮审查头 `3c73e0b`。命令 `git diff 394e321...3c73e0b`；提交清单 `.scratch/issue90/review-commits.txt`。两个独立只读 Agent 分别审查，主 Agent 核实后交给一个修复 worker；格式噪音用 `--ignore-space-at-eol` 辅助阅读。

## Standards

1. **首次资料读取失败不可见**：`profile_repository.dart` 空缓存读取失败只返回内存错误，`profile_card.dart` 丢弃同步返回值，只观察数据库流；用户看到正常占位名而无错误与重试入口。违反 UI 指南的加载／空内容／失败区分要求。应在名片持有首次同步错误，提供重试，不制造本地数据版本。
2. **统计读取失败被显示为零**：名片将尚未加载和失败均退回 `ProfileStatistics.empty`。应分别显示加载、真实零值与失败重试，不能把不可读记录当成零统计。

Standards：2项实质规范发现；最高影响是错误状态被呈现为正常数据。未确认其他可操作的Fowler smell，不针对已豁免要求或工具已检查格式另报问题。

## Spec

1. **P1 上传取消窗口**：`uploadLocal` 在 `remote.upload` 参数中等待设备ID，等待期间取消后仍发送旧快照；取消检查仅保护应答后的基线写入。违反“关闭开关、切换账号或恢复备份后不得继续执行旧请求”。须在最后异步准备步骤完成后、发出网络请求之前再查取消，并补阻塞设备ID读取的测试。
2. **P2 已清除资料被晚应答复活**：首次资料读取起点序号为0，若purge先删除所有资料，晚到读取结果在“行不存在”分支重新插入昵称头像；`dispose`也未失效在途操作。违反账号清除范围。须通过清除代次／持久标记和事务内检查阻止复活，覆盖首次读取与purge交错。

Spec：2项实质行为发现；最高为取消后继续覆盖云端。未发现确定的其他缺失或越界新增。

## 附加发现（主 Agent 原生选图验收，2026-11-13）

- **截断 PNG 前缀抛 RangeError**：`avatar_image.dart` 的 `detectAvatarFormat` 只守卫 `length < 3`，随后 PNG 分支访问 `bytes[7]`。3–7 字节且匹配 PNG 前缀的截断文件会抛 `RangeError` 而不是正常拒绝。允许格式范围不变（仍只 PNG/JPEG）。

## 修复（最终统一修复 worker，分支 `fix/pacta90-final-review`）

均按 red→green 修复，保留已确认 180 天公式与五项功能，未重做架构、未改云服务 RLS。

### 1. Standards 1 — 首次资料读取失败可见且可重试

- 事实：`initState` 里 `syncProfile()` 的返回值被丢弃，空缓存失败只存在于内存返回值，数据库流不会发出它，于是只显示占位昵称。
- 修复：`profile_card.dart` 自己持有首次同步的返回结果、错误文案与同步中标记；数据库里没有缓存行时显示该原因和“重试”；已有缓存行时仍以数据库记录的错误为准（仓储只在有行时写 `syncError`）。名片不写任何资料行，失败不会制造本机版本。
- 回归：`test/profile/profile_card_test.dart` → `首次资料读取失败在名片显示原因并可重试，且不编造本机资料`（断言失败文案可见、`saveCalls == 0`、重试后文案消失且 `syncCalls == 2`）。
- 复核边界（同步抛异常 + 已有缓存）：这次尝试捕获到的瞬态错误可能根本没写进缓存行，若只取 `stored.syncError`，已有缓存会把它掩盖。修复：`stored.syncError` 为空时回退到本次尝试的错误，并记录失败时缓存行的状态（`updatedAt` + `editSequence`，通过 `getProfile()` 读取而非等待流）；缓存行前进到另一状态即视为过期不再显示，成功重试也直接清除。回归：`已有缓存时同步抛异常仍显示这次尝试的错误，缓存更新后清掉`（断言缓存同行时显示原因与昵称、另一入口保存后原因消失）。

### 2. Standards 2 — 统计的加载与失败不再当成零

- 事实：两组统计共用 `cards == null || sessions == null ? ProfileStatistics.empty`，未加载与读取失败都显示“点亮 0 / 完成 0 次”。
- 修复：国策组只订阅卡片记录、专注组只订阅专注记录，各自区分加载（“正在读取… 稍后自动显示”）、失败（“统计暂时无法读取”+组内“重试”）与真实数据（含真实 0）。重试只以新 key 重建订阅，不触发资料或业务写入；明细页原有的加载／失败区分保持不变。
- 回归：`统计尚未读到记录时显示加载状态而不是零`、`统计读取失败显示失败与重试，不把不可读记录当成零`（后者同时断言另一组可读时照常显示，重试后恢复数字）。

### 3. P1 — 设备ID 等待期间取消后不再发送

- 事实：`deviceId: await _getDeviceId()` 写在 `remote.upload(...)` 实参里，取消只保护应答后的基线写入，等待期间取消仍发出旧快照。
- 修复：设备标识先解析为局部变量（新增可注入的 `deviceIdLoader`），在所有异步准备完成后、发出请求之前调用 `_throwIfUploadCancelled`；命中抛新的 `CloudUploadCancelled`，服务端不会收到请求、不写成功基线。应答到达后的基线保护保持不变。
- 回归：仓储级 `test/sync/cloud_snapshot_repository_test.dart` → `设备标识读取期间取消后不再发出上传请求，也不写基线`（用外部 `Completer` 控制设备标识读取完成时机，断言 `inspect` 无快照、无基线、历史为空）；协调器级 `test/sync/cloud_auto_upload_test.dart` → `设备标识读取期间关闭开关，不再发出这次上传`（断言 `uploadCalls == 0`、队列清空，重新开启后正常上传一次）。

### 4. P2 — 清除代次阻止晚到资料复活

- 事实：首次读取起点序号为 0，purge 删掉所有资料后，晚到读取走“行不存在”分支重新插入昵称与头像；`dispose()` 也未失效在途操作。
- 修复：
  - 新增 Drift 表 `local_profile_clear_marks`（`userId`、只前进的 `generation`、`clearedAt`），schema 28 → **29**，迁移 `if (from < 29) createTable`；`dart run build_runner build` 生成，g.dart 为纯新增（+462/−0）。
  - `PactaDatabase.purgeUserDataForReceipt` 在同一事务内删除资料行之后把该用户代次 +1 并保留标记。
  - `LocalProfileRepository` 的所有写路径（`saveProfile` 本地保存、`syncProfile` 采用远端、上传成功、上传失败状态、读取失败状态）都经 `_guardedWrite`：单个事务内先证明 `dispose` 未发生、且该 UUID 没有清除标记，否则放弃写入；`dispose()` 置失效标记，之后到达的应答不再写入。
  - 已确认清除标记是**旧 UUID 的永久写入禁令**，不是可被后续操作读成“已是最新”的计数器：依据 `supabase/README.md` 的 Explicit cloud purge，清除后重新注册会得到新的 auth UUID，因此在旧 UUID 上出现的任何资料写入都只可能是失效的旧操作（晚到应答、已排队的编辑）。立即读取代次仍会漏掉“排队时已失效、开始时才读到新代次”的编辑（复核反例），故改为存在性判断。
  - 边界保持：标记表不属于业务快照表清单（恢复不回滚、也不上传），不加入 `localUserIdsWithData`（不会被重复清扫），恢复点/资料/队列的 purge 边界与云服务 RLS 均未改。
- 回归：`test/profile/profile_repository_test.dart` → `账号清除后晚到的首次读取不得复活昵称与头像`、`账号清除后晚到的上传成功应答不再写回资料`、`账号清除后已排队的旧保存不再写入`（读取占住串行队列 → 编辑排队 → 清除 → 释放读取，断言无资料行、无上传）、`已清除账号的旧 UUID 不再接受资料写入（重新注册使用新 UUID）`、`dispose 之后晚到的读取结果不再写入`；`test/auth/user_purge_cleanup_repository_test.dart` → `清除后留下只前进的资料清除代次，且不会被重复清扫`。复核指出原“清除之后的新保存仍可写入”用例与既有账号永久清除契约冲突，已改为上述两个用例。

### 5. 附加 — 截断 PNG 前缀正常拒绝

- 修复：PNG 分支要求 `length >= 8`（`_hasPngSignature`），JPEG 仍用 3 字节前缀；`validateAvatarSelection` 因此对截断前缀抛出 `AvatarValidationException('仅支持 PNG 或 JPEG 图片。')`，不再泄漏 `RangeError`。
- 回归：`test/profile/avatar_image_test.dart` → `截断的 PNG 签名前缀被正常拒绝而不是越界读取`（1–7 字节逐长度断言识别为 null 且拒绝原因可读）。

### 红先证据（修复前实际输出）

```text
avatar_image_test: RangeError (length): Invalid value: Not in inclusive range 0..2: 3
                   package:pacta/src/profile/avatar_image.dart 57:12 detectAvatarFormat
profile_card_test（S1/S2 三条）: Some tests failed（点亮 0 / 保存失败文案均未出现）
cloud_snapshot_repository_test（P1）: Expected: throws CloudUploadCancelled
                   Actual: emitted <Instance of 'CloudSnapshotMetadata'>
profile_repository_test（P2 两条）: Expected: empty  Actual: [LocalProfileAccount(...)]
```

### 修复后实际命令与结果

环境：Windows 11；MSYS bash；Flutter 3.47.2 / Dart 3.13.2。

| 命令 | 结果 |
| --- | --- |
| `dart format <改动文件>` | 完成 |
| `dart run build_runner build --delete-conflicting-outputs` | 写出 425 个输出；工具提示该 flag 已移除并被忽略，g.dart 新增 `$LocalProfileClearMarksTable`（+462/−0） |
| `flutter analyze` | No issues found! |
| `flutter test test/profile/avatar_image_test.dart` | +6 All tests passed! |
| `flutter test test/profile/profile_card_test.dart` | +11 All tests passed! |
| `flutter test test/profile/profile_repository_test.dart` | +17 All tests passed! |
| `flutter test test/sync/cloud_snapshot_repository_test.dart` | 通过（含新增取消用例） |
| `flutter test test/sync/cloud_auto_upload_test.dart` | +21 All tests passed! |
| `flutter test test/auth/user_purge_cleanup_repository_test.dart` | +7 All tests passed! |
| `flutter test test/profile test/sync test/auth` | +243 All tests passed! |
| `flutter test`（全量） | +597 All tests passed! |

## 复验边界

- 原生与真实云验收仍由主 Agent 执行：本文件只记录本地代码与自动化测试证据，不把替身测试当设备或真实服务通过。
- Windows 当前系统仍返回 QUNS_BUSY；未观察到的气泡点击不得记为通过。
- 本记录不等于评审通过：修复后需按双轴复看，并补两端与隔离云项目的最终证据。
