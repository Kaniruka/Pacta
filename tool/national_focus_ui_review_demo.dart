import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_tree_page.dart';
import 'package:pacta/src/tasks/task_database.dart';

/// Four isolated cards for checking readable layout and all three node states.
/// Uses memory only; it never loads credentials or connects to user accounts.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var now = DateTime.utc(2026, 10, 5, 19, 59);
  final database = PactaDatabase(NativeDatabase.memory());
  final repository = LocalNationalFocusRepository(
    database: database,
    userId: 'isolated-ui-review',
    cloudSyncEnabled: false,
    now: () => now,
  );
  Future<NationalFocusCard> card(
    String name,
    String trigger,
    String action,
    String? parentId, {
    bool light = false,
  }) async {
    final value = await repository.createCard(
      NationalFocusCardDraft(
        name: name,
        triggerCondition: trigger,
        action: action,
      ),
    );
    await repository.placeCard(cardId: value.id, parentId: parentId);
    if (light) await repository.lightCard(value.id);
    return value;
  }

  final root = await card('根国策', '每天开始时', '按自己的规则安排今天', null, light: true);
  final reading = await card(
    '每日阅读',
    '晚饭后',
    '读十页书，记下一条收获',
    root.id,
    light: true,
  );
  await card('规律运动', '结束工作后', '到户外步行二十分钟', root.id, light: true);
  await card('记录收获', '读书结束后', '写下一条可以实践的想法', reading.id);
  now = DateTime.utc(2026, 10, 5, 20, 1);
  await repository.settleDueCheckpoints();
  await repository.lightCard(root.id);
  await repository.lightCard(reading.id);
  runApp(
    MaterialApp(
      title: '国策树隔离界面预览',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xff385a52)),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xff385a52),
      ),
      home: Scaffold(
        body: NationalFocusTreePage(
          repository: repository,
          now: () => now,
          displayTimeZoneLoader: () async => 'Asia/Shanghai',
        ),
      ),
    ),
  );
}
