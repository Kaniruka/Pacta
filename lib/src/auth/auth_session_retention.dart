import 'dart:async';

/// 鉴权事件的轻量身份快照。
///
/// Supabase 的 `AuthState` 带完整 `Session`，离线时 token 刷新失败同样会
/// 抛出 `session == null` 的事件；仓储只关心「现在是谁」，所以先把事件压成
/// 身份快照再判定。这样离线掉线与会话保活可以在单测里直接推事件复现，
/// 不必伪造一个真实的 `Session`。
class AuthSessionSignal {
  const AuthSessionSignal({this.email, this.userId});

  /// 空会话：GoTrue 的 `signedOut` / 刷新失败后的 `tokenRefreshed`。
  const AuthSessionSignal.signedOut() : email = null, userId = null;

  final String? email;
  final String? userId;

  bool get isSignedIn => email != null || userId != null;
}

/// 登录身份保活状态机。
///
/// 只有「用户主动登出」或「从未登录过」这两条路径才会把身份清空并发射
/// `null`；离线时 token 刷新失败同样会给出空会话事件，那不是用户意图，
/// 必须保留身份，否则一断网就被踢回登录页，而本地数据其实还在。
///
/// 状态机独立于 Supabase 客户端：界面测试可以直接驱动它，不必在
/// `testWidgets` 的 FakeAsync 区里构造真实网络客户端。
class AuthSessionRetention {
  AuthSessionRetention({String? email, String? userId})
    : _retainedEmail = email,
      _retainedUserId = userId,
      _lastEmitted = email;

  final _emitted = StreamController<String?>.broadcast();

  String? _retainedEmail;
  String? _retainedUserId;

  /// 用户主动调用登出的标记：只有它为真时，空会话才算真登出。
  bool _explicitSignOut = false;

  String? _lastEmitted;
  bool _hasEmitted = true;

  String? get email => _retainedEmail;

  String? get userId => _retainedUserId;

  /// 稳定的流实例：每次 build 都返回新 `Stream` 会让 `StreamBuilder` 反复
  /// 重订阅，重放值再触发重建，形成无限循环（界面永远不 settle）。
  late final Stream<String?> state = Stream<String?>.multi((listener) {
    // 重放当前身份：新订阅者拿到的是「现在是谁」，不是「等下一次事件」。
    listener.add(_retainedEmail);
    final subscription = _emitted.stream.listen(
      listener.add,
      onError: listener.addError,
      onDone: listener.close,
    );
    listener.onCancel = () => unawaited(subscription.cancel());
  }, isBroadcast: true);

  /// 收到一次鉴权事件。
  void apply(AuthSessionSignal signal) {
    if (signal.isSignedIn) {
      _explicitSignOut = false;
      _retainedEmail = signal.email;
      _retainedUserId = signal.userId;
      _emit(signal.email);
      return;
    }
    // 空会话有两种来源：用户主动登出，或离线时刷新 token 失败。
    // 只有前者（以及从未登录过的匿名状态）才是真登出；后者保留身份并吞掉
    // 这次事件，界面继续停留在原页面。
    if (!_explicitSignOut && _retainedUserId != null) return;
    _retainedEmail = null;
    _retainedUserId = null;
    _emit(null);
  }

  /// 登录成功后记录身份，并重置「主动登出」标记。
  void recordSignIn({String? email, String? userId}) {
    _explicitSignOut = false;
    _retainedEmail = email;
    _retainedUserId = userId;
    _emit(email);
  }

  /// 用户主动登出：先清本地身份，界面立刻回到登录页，不等网络。
  void beginSignOut() {
    _explicitSignOut = true;
    _retainedEmail = null;
    _retainedUserId = null;
    _emit(null);
  }

  void _emit(String? value) {
    if (_hasEmitted && _lastEmitted == value) return;
    _lastEmitted = value;
    _hasEmitted = true;
    if (!_emitted.isClosed) _emitted.add(value);
  }

  Future<void> dispose() => _emitted.close();
}
