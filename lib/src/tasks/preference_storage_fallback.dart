import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 读取本机偏好；"此环境没有可用的 SharedPreferences"统一返回 `null`。
///
/// 三种情况都算不可用：宿主没有插件（`MissingPluginException`）、纯 Dart
/// 单测未初始化绑定（`Binding has not yet been initialized`），以及
/// `testWidgets` 的 FakeAsync 里没有 `setMockInitialValues`。最后一种既不会
/// 抛错也不会 resolve：Windows 实现会发起真实 `dart:io` 读取，在 FakeAsync
/// 中永远等不到结果，若直接 await 会让 `getGoals()` 与页面读取永久挂起。
///
/// 因此测试环境下先给 loader 至多 16 个微任务窗口：mock 的内存存储在
/// 2–3 个微任务内完成；仍未完成即判定为"本测试未 mock"，返回 `null` 让
/// 调用方退回各自的内存兜底。其他错误原样重抛，并保留原始异步堆栈。
Future<SharedPreferences?> loadSharedPreferencesOrNull(
  Future<SharedPreferences> Function() loader,
) async {
  if (Platform.environment.containsKey('FLUTTER_TEST') &&
      identical(loader, SharedPreferences.getInstance)) {
    var completed = false;
    Object? caughtError;
    StackTrace? caughtStackTrace;
    SharedPreferences? loaded;
    final Future<SharedPreferences> future;
    try {
      future = loader();
    } catch (error, stackTrace) {
      if (_preferenceStorageUnavailable(error)) return null;
      Error.throwWithStackTrace(error, stackTrace);
    }
    unawaited(
      future.then<void>(
        (value) {
          loaded = value;
          completed = true;
        },
        onError: (Object error, StackTrace stackTrace) {
          caughtError = error;
          caughtStackTrace = stackTrace;
          completed = true;
        },
      ),
    );
    for (var attempt = 0; attempt < 16 && !completed; attempt++) {
      await Future<void>.microtask(() {});
    }
    if (!completed) return null;
    final error = caughtError;
    if (error != null) {
      if (_preferenceStorageUnavailable(error)) return null;
      Error.throwWithStackTrace(error, caughtStackTrace ?? StackTrace.current);
    }
    return loaded;
  }
  try {
    return await loader();
  } catch (error, stackTrace) {
    if (_preferenceStorageUnavailable(error)) return null;
    Error.throwWithStackTrace(error, stackTrace);
  }
}

/// 偏好存储不可用（无插件宿主 / 未初始化绑定）与真正的读取失败要分开。
bool _preferenceStorageUnavailable(Object error) {
  if (error is MissingPluginException) return true;
  return error.toString().contains('Binding has not yet been initialized');
}
