import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';

import 'package:pacta/src/tasks/task_database.dart';

/// 测试用内存数据库：关闭查询流时不再排 drift 的零延迟计时器。
///
/// 生产路径保留 drift 默认的延迟关闭（短时间内复用缓存）。测试结束后没有
/// 下一帧来跑这个计时器，框架会以 “A Timer is still pending even after the
/// widget tree was disposed” 失败；这里显式改成同步关闭，测试只反映应用行为。
PactaDatabase openTestDatabase() => PactaDatabase(
  DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
);
