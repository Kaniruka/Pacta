import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/auth/auth_repository.dart';
import 'package:pacta/src/auth/auth_session_retention.dart';
import 'package:pacta/src/auth/user_lifecycle_models.dart';

/// 用生产的状态机 [AuthSessionRetention] 承载身份，但不构造真实网络客户端。
///
/// `testWidgets` 跑在 FakeAsync 区里，构造 `SupabaseClient` 会启动后台
/// JSON isolate，其 Future 在该区域内永远不完成——那属于测试夹具的假死，
/// 不是 `AuthGate` 的行为。保活语义由 retention 单测（真实客户端）覆盖，
/// 这里只验证界面在「离线空会话 / 主动登出」两种事件下的去留。
class _RetainingAuthRepository implements AuthRepository {
  _RetainingAuthRepository({String? email, String? userId})
    : _retention = AuthSessionRetention(email: email, userId: userId);

  final AuthSessionRetention _retention;

  @override
  Stream<String?> get authState => _retention.state;

  @override
  String? get currentUserIdentifier => _retention.email;

  @override
  String? get currentUserId => _retention.userId;

  @override
  Future<void> signIn({required String email, required String password}) async {
    _retention.recordSignIn(email: email, userId: email);
  }

  @override
  Future<void> signUp({required String email, required String password}) async {
    _retention.recordSignIn(email: email, userId: email);
  }

  @override
  Future<void> signOut() async => _retention.beginSignOut();

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async => throw UnimplementedError();

  @override
  Future<UserLifecycleStatus> getCurrentUserLifecycle() async =>
      throw UnimplementedError();

  @override
  Future<UserPurgeReceipt?> lookupPurgeReceipt(String oldUserId) async =>
      throw UnimplementedError();

  /// 模拟 GoTrue 在离线刷新失败后发出空会话事件。
  void pushOfflineSignedOut() =>
      _retention.apply(const AuthSessionSignal.signedOut());

  void dispose() => _retention.dispose();
}

void main() {
  testWidgets('离线空会话事件不会把已登录用户踢回登录页', (tester) async {
    final repository = _RetainingAuthRepository(
      email: 'user@example.com',
      userId: 'user-id',
    );
    addTearDown(repository.dispose);

    await tester.pumpWidget(PactaApp(authRepository: repository));
    await tester.pumpAndSettle();
    expect(find.byType(AppShell), findsOneWidget);

    // 离线：Supabase 刷新 token 失败后发来空会话。
    repository.pushOfflineSignedOut();
    await tester.pumpAndSettle();

    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byType(AuthScreen), findsNothing);

    // 卸载整棵树：AppShell 的定时器/动画不能留到测试收尾检查之后。
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('主动退出登录才回到登录页', (tester) async {
    final repository = _RetainingAuthRepository(
      email: 'user@example.com',
      userId: 'user-id',
    );
    addTearDown(repository.dispose);

    await tester.pumpWidget(PactaApp(authRepository: repository));
    await tester.pumpAndSettle();
    expect(find.byType(AppShell), findsOneWidget);

    await repository.signOut();
    await tester.pumpAndSettle();

    expect(find.byType(AuthScreen), findsOneWidget);
    expect(find.byType(AppShell), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
