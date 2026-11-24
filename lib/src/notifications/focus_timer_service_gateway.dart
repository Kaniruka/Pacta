import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// 一次专注 / 预约准备的前台计时请求。
///
/// 时间用绝对毫秒交给原生侧：Dart 与 Kotlin 之间不做时区换算，剩余时间由同一
/// 个结束时刻推导，界面与通知因此不会出现一秒的偏差。
class FocusTimerRequest {
  const FocusTimerRequest({
    required this.notificationId,
    required this.titlePrefix,
    required this.taskTitle,
    required this.modeLabel,
    required this.startedAt,
    required this.endsAt,
    required this.totalSeconds,
    required this.payload,
  });

  final int notificationId;
  final String titlePrefix;
  final String taskTitle;
  final String modeLabel;
  final DateTime startedAt;
  final DateTime endsAt;

  /// 进度条分母；必须为正，服务端会再兜一次底。
  final int totalSeconds;

  /// 点按通知时回传给 Dart 的会话负载。
  final String payload;
}

/// 专注进度前台服务的可测试边界。
///
/// 生产只在 Android 上调用真实通道；桌面端与测试注入的假实现都是空操作，
/// 因此 [FocusNotificationService] 的任何计划逻辑都不依赖真实服务。
abstract interface class FocusTimerServiceGateway {
  Future<void> startOrUpdate(FocusTimerRequest request);

  Future<void> stop();
}

FocusTimerServiceGateway createFocusTimerServiceGateway() => Platform.isAndroid
    ? MethodChannelFocusTimerServiceGateway()
    : const NoopFocusTimerServiceGateway();

/// 非 Android 平台的实现：没有前台服务，也没有任何副作用。
class NoopFocusTimerServiceGateway implements FocusTimerServiceGateway {
  const NoopFocusTimerServiceGateway();

  @override
  Future<void> startOrUpdate(FocusTimerRequest request) async {}

  @override
  Future<void> stop() async {}
}

/// 生产实现：`com.pacta/focus_timer_service`。
///
/// 启动与更新共用一条通道方法族：[startOrUpdate] 第一次发 `start`，之后的
/// 刷新发 `update`，原生侧两者都按"重绘同一张通知"处理。点按通知由原生侧
/// 反向推送 `notificationTapped`，冷启动的点击则通过
/// [takePendingLaunchPayload] 取走。
class MethodChannelFocusTimerServiceGateway
    implements FocusTimerServiceGateway {
  MethodChannelFocusTimerServiceGateway({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'com.pacta/focus_timer_service';

  final MethodChannel _channel;

  bool _handlerAttached = false;
  bool _running = false;
  void Function(String payload)? _onTapped;

  /// 连接原生侧的点击回调；重复调用只替换回调，不重复注册 handler。
  void attach({void Function(String payload)? onTapped}) {
    _onTapped = onTapped;
    if (_handlerAttached) return;
    _handlerAttached = true;
    _channel.setMethodCallHandler(_handlePlatformCall);
  }

  void detach() {
    if (!_handlerAttached) return;
    _handlerAttached = false;
    _onTapped = null;
    _channel.setMethodCallHandler(null);
  }

  Future<Object?> _handlePlatformCall(MethodCall call) async {
    if (call.method != 'notificationTapped') return null;
    final payload = call.arguments;
    if (payload is! String || payload.isEmpty) return null;
    _onTapped?.call(payload);
    return null;
  }

  /// 冷启动时被通知点按拉起：原生侧留存的一次性负载。
  Future<String?> takePendingLaunchPayload() async {
    try {
      return await _channel.invokeMethod<String>('takePendingLaunchPayload');
    } catch (_) {
      // 宿主没有该能力时等同"没有待处理点击"。
      return null;
    }
  }

  @override
  Future<void> startOrUpdate(FocusTimerRequest request) async {
    await _channel.invokeMethod<void>(_running ? 'update' : 'start', {
      'notificationId': request.notificationId,
      'titlePrefix': request.titlePrefix,
      'taskTitle': request.taskTitle,
      'modeLabel': request.modeLabel,
      'startedAtMs': request.startedAt.millisecondsSinceEpoch,
      'endsAtMs': request.endsAt.millisecondsSinceEpoch,
      'totalSeconds': request.totalSeconds,
      'payload': request.payload,
    });
    _running = true;
  }

  @override
  Future<void> stop() async {
    _running = false;
    await _channel.invokeMethod<void>('stop');
  }
}
