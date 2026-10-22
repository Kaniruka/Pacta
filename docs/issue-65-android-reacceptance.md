# Issue #65 Android 15 实际读屏复验

2026-10-22，PactaT24Peer / emulator-5554，Android 15 API 35，TalkBack 15。
本轮使用 `integration_test/board_talkback_fixture.dart` 独立入口：普通
WidgetsFlutterBinding、内存 Drift、fake auth，无 tester、无持久业务库和云连接。
构建：`cmd.exe /c flutter build apk --debug -t integration_test/board_talkback_fixture.dart`，成功。

## 输入与证据边界

ADB `input tap` 会直接触发普通点击，不能证明读屏双击。`uiautomator dump` 会
临时抑制 TalkBack，连续验收不调用它。实际 TalkBack 验收使用模拟器原始
`/dev/input/event2` 多点触摸事件；`dumpsys input` 的活动显示实际位于物理
2560×1600画面的 [911,0]–[1649,1600]，因此先转换坐标。
逐个 `sendevent` 进程过慢不能形成双击，改为二进制 `input_event` 一次写入按下/
抬起事件，40ms按下、70ms间隔，在独立fixture可稳定识别双击。
本轮按 ui-ux-pro-max Flutter screen-reader/Semantics 指导及 apple-design 的
Accessibility › Vision/Mobility 原则检查真实标签、状态和独立操作；转译为Android
TalkBack行为，不套用Apple控件。

截图取 `screencap`；TalkBack 自身详细日志及 Display speech output 展示真实输出。
这是实际 TalkBack 服务处理 GESTURE_DOUBLE_TAP 的证据，不是 tester 点击。

## 首次复验发现

真实双击能折叠/展开；折叠隐藏任务及任务描述，保留目标描述、数量和完成状态。
目标编辑和删除各自获得独立绿色焦点，双击打开对应对话框，背景任务保持展开。

- [读屏双击折叠](evidence/issue65-talkback-real-collapsed.png)
- [读屏双击展开](evidence/issue65-talkback-real-expanded.png)
- [读屏激活编辑目标](evidence/issue65-talkback-edit.png)
- [读屏激活删除目标确认](evidence/issue65-talkback-delete.png)

TalkBack日志明确出现 `GESTURE_DOUBLE_TAP` → `CLICK_CURRENT`，目标为季度规划。
但首次版本的原生节点 `collapsedOrExpandedState=`、`stateDescriptionIsEmpty=true`；
实际朗读只有标题、目标描述、1项任务和进行中，没有展开/折叠状态。
这说明 Flutter expanded 语义断言通过不能证明 Android TalkBack 收到状态。
已报告主代理，补充可朗读语义value后重新验收。

## 修复后复验与恢复

语义 value 补充后，TalkBack SpeechControllerImpl 日志实际输出“已展开,”和“已折叠,”。
恢复模拟器后，连续激活另发现焦点缺陷：聚焦已折叠目标→双击展开→再次双击，
第二次打开任务编辑。展开后的绿色焦点框包住整张卡片，第二次日志只有
CLICK_CURRENT成功而没有目标nodeAction；读屏退化为卡中心坐标点击命中任务。
已反馈修复独立header语义节点，修复后继续复验。

- [连续激活错误截图](evidence/issue65-talkback-repeat-activation-before-fix.png)
- [连续激活日志](evidence/issue65-talkback-repeat-activation-before-fix.txt)

设备曾保存10月21日时钟日志，恢复模拟器后日志日期为10月22日；未手动调整设备时钟。

`container: true` 后重新构建独立fixture，等看板完成冷启动才开始有效操作。
Android原始触摸连续3次双击（展开→折叠→展开→折叠）均保持标题区绿色焦点，
不再误开任务。空目标也连续折叠/展开/折叠成功；各目标状态独立。
TalkBack SpeechControllerImpl 在重新聚焦时分别实际输出“已展开,”、“已折叠,”，
随后读出完整标题、描述、数量和进行中状态。这里核验的是读屏服务发给TTS的
实际语句及成功回调，未以静态Semantics值代替；未录制音频或声称人工听辨中文发音。

此轮使用1080px宽、density480，即360逻辑宽；Android系统font_scale=2.0，
fixture默认不覆盖TextScaler。目视无标题/数量/状态裁剪；目标描述按现有单行省略，
TalkBack读完整描述，任务标题换行。编辑/删除保持单独焦点和触控目标。

- [修复后折叠及独立标题焦点](evidence/issue65-talkback-fixed-collapsed.png)
- [同一焦点再次激活展开](evidence/issue65-talkback-fixed-expanded.png)
- [空目标折叠](evidence/issue65-talkback-fixed-empty-collapsed.png)
- [实际TalkBack双击与状态输出日志](evidence/issue65-talkback-fixed.txt)

全部实际手势结束后才运行一次uiautomator dump作静态补证：两目标均折叠时，
原生树无任务、任务描述、空态及添加任务节点，保留完整目标描述。
[原生树](evidence/issue65-talkback-fixed-native-collapsed.xml)不作为连续读屏交互证据。

## 数据和系统恢复

普通入口 `flutter build apk --debug --dart-define-from-file=<临时公开配置JSON>` 成功，
仅传SUPABASE_URL和SUPABASE_PUBLISHABLE_KEY，无TEST_*；临时JSON已删除。
`adb install -r` 成功，随后保持应用停止，不启动普通入口。
force-stop后将本轮开始前的归档push到/data/local/tmp，再以run-as tar就地恢复，
清理1个新增文件；7个原文件逐一SHA-256完全一致，最终文件集合无额外文件。
没有卸载、清数据或访问真实云业务数据。

TalkBack临时debug日志级别和Display speech output恢复为修改前完整XML，逐字节一致；
启用服务=null、accessibility_enabled=0、font_scale=1.0、density override420均已读回。
本轮没有通过命令授予/撤销通知权限。设备临时tar、事件文件和脚本已删除。
保留原始备份在工作区以外的本机临时目录供恢复审计，未入提交。

独立fixture保留供两平台复验；BOARD_TEXT_SCALE_PERCENT仅显式大于0时覆盖字体，
Android本轮未传该define。最终安装包和build/app输出已恢复普通入口。
