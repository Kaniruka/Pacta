import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/auth/auth_repository.dart';
import 'package:pacta/src/auth/supabase_auth_repository.dart';
import 'package:pacta/src/auth/user_lifecycle_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

/// 只记录调用与注入失败的仓储：界面断言关心「拦下了什么」和「显示了什么」，
/// 不需要真实网络。
class _ScriptedAuthRepository implements AuthRepository {
  String? identifier;
  String? userId;
  Object? signInFailure;
  Object? signUpFailure;

  /// 请求挂起闸门：非空时 signIn/signUp 停在 await 上，用来观察转圈与禁用态。
  Completer<void>? signInGate;
  Completer<void>? signUpGate;
  int signInCalls = 0;
  int signUpCalls = 0;
  final _changes = StreamController<String?>.broadcast();

  @override
  Stream<String?> get authState async* {
    yield identifier;
    yield* _changes.stream;
  }

  @override
  String? get currentUserIdentifier => identifier;

  @override
  String? get currentUserId => userId;

  @override
  Future<void> signIn({required String email, required String password}) async {
    signInCalls++;
    final gate = signInGate;
    if (gate != null) await gate.future;
    final failure = signInFailure;
    if (failure != null) throw failure;
    identifier = email;
    userId = email;
    _changes.add(email);
  }

  @override
  Future<void> signUp({required String email, required String password}) async {
    signUpCalls++;
    final gate = signUpGate;
    if (gate != null) await gate.future;
    final failure = signUpFailure;
    if (failure != null) throw failure;
    identifier = email;
    userId = email;
    _changes.add(email);
  }

  @override
  Future<void> signOut() async {
    identifier = null;
    userId = null;
    _changes.add(null);
  }

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

  void dispose() => unawaited(_changes.close());
}

class _ErrorCase {
  const _ErrorCase(
    this.description,
    this.failure,
    this.expected, {
    this.registering = false,
  });

  final String description;
  final Object failure;
  final String expected;
  final bool registering;
}

final _errorCases = <_ErrorCase>[
  _ErrorCase(
    '无注册资格',
    AuthException(
      'Signup not allowed: user is not eligible for this project',
      statusCode: '422',
      code: 'signup_not_allowed',
    ),
    '该邮箱尚未获得注册资格，请联系管理员开通。',
    registering: true,
  ),
  _ErrorCase(
    '无注册资格（message 不含 eligib）',
    AuthException(
      'Signups not allowed for this instance',
      statusCode: '422',
      code: 'signup_not_allowed',
    ),
    '该邮箱尚未获得注册资格，请联系管理员开通。',
    registering: true,
  ),
  _ErrorCase(
    '无注册资格（只有 code 可识别）',
    AuthException(
      'Unprocessable Entity',
      statusCode: '422',
      code: 'signup_not_allowed',
    ),
    '该邮箱尚未获得注册资格，请联系管理员开通。',
    registering: true,
  ),
  _ErrorCase(
    '邮箱已注册',
    AuthException(
      'User already registered',
      statusCode: '400',
      code: 'user_already_exists',
    ),
    '该邮箱已注册，请直接切换到「登录」。',
    registering: true,
  ),
  _ErrorCase(
    '账号停用',
    AuthException('User is banned', statusCode: '403', code: 'user_banned'),
    '该账号已被停用，请联系管理员。',
  ),
  _ErrorCase(
    '账号或密码错误',
    AuthException(
      'Invalid login credentials',
      statusCode: '400',
      code: 'invalid_credentials',
    ),
    '邮箱或密码错误，请核对后重试。',
  ),
  _ErrorCase(
    '频率限制',
    AuthException(
      'Request rate limit reached',
      statusCode: '429',
      code: 'over_request_rate_limit',
    ),
    '操作过于频繁，请稍后再试。',
  ),
  _ErrorCase(
    '网络连接失败',
    SocketException('Failed host lookup: pacta.supabase.co'),
    '无法连接到云端服务，请检查网络后重试。',
  ),
  _ErrorCase(
    '数据库连接失败',
    Exception('database error: connection refused'),
    '无法连接到云端服务，请检查网络后重试。',
  ),
];

Future<void> _setSize(
  WidgetTester tester, {
  required Size logicalSize,
  double devicePixelRatio = 1,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.devicePixelRatio = devicePixelRatio;
  tester.view.physicalSize = logicalSize * devicePixelRatio;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearPlatformBrightnessTestValue();
  });
}

void main() {
  testWidgets('登录卡片并排等宽双按钮，移除顶部重复分段入口', (tester) async {
    final repository = _ScriptedAuthRepository();
    addTearDown(repository.dispose);
    await tester.pumpWidget(PactaApp(authRepository: repository));
    await tester.pumpAndSettle();

    // 邮箱与密码只有一份，顶部再放「登录 / 受邀注册」分段只是重复标题。
    expect(find.byType(SegmentedButton<bool>), findsNothing);
    expect(find.text('进入 Pacta'), findsOneWidget);
    expect(find.text('把注意力带回眼前的一步。'), findsNothing);
    expect(find.text('没有注册资格？联系管理员。'), findsNothing);

    final register = tester.getRect(
      find.widgetWithText(OutlinedButton, '受邀注册'),
    );
    final login = tester.getRect(find.widgetWithText(FilledButton, '登录'));

    // 同排：中心线相差 <= 1dp，且左右顺序固定为「受邀注册 | 登录」。
    expect((register.center.dy - login.center.dy).abs(), lessThanOrEqualTo(1));
    expect(register.right, lessThan(login.left));
    expect(register.width, closeTo(login.width, 2));
    // 触屏命中区：两颗都不低于 48dp。
    expect(register.height, greaterThanOrEqualTo(48));
    expect(login.height, greaterThanOrEqualTo(48));

    // 资格说明只存在于受邀注册入口的 Tooltip 上，不再占正文一行。
    final tooltips = tester.widgetList<Tooltip>(
      find.ancestor(
        of: find.byKey(const ValueKey('auth-register-button')),
        matching: find.byType(Tooltip),
      ),
    );
    expect(
      tooltips.map((tooltip) => tooltip.message),
      contains('使用已开通注册资格的邮箱与密码（至少 8 位）激活账号'),
    );
    expect(find.text('使用已开通注册资格的邮箱与密码（至少 8 位）激活账号'), findsNothing);
  });

  testWidgets('受邀注册按钮直接提交注册，不经过任何模式切换', (tester) async {
    final repository = _ScriptedAuthRepository();
    addTearDown(repository.dispose);
    await tester.pumpWidget(PactaApp(authRepository: repository));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'user@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'correct-password');
    await tester.tap(find.widgetWithText(OutlinedButton, '受邀注册'));
    await tester.pumpAndSettle();

    expect(repository.signUpCalls, 1);
    expect(repository.signInCalls, 0);
  });

  testWidgets('密码框可切换明文，图标与状态同步', (tester) async {
    final repository = _ScriptedAuthRepository();
    addTearDown(repository.dispose);
    await tester.pumpWidget(PactaApp(authRepository: repository));
    await tester.pumpAndSettle();

    bool obscured() =>
        tester.widget<TextField>(find.byType(TextField).at(1)).obscureText;

    expect(obscured(), isTrue);
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();

    expect(obscured(), isFalse);
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
  });

  testWidgets('有效凭据在密码框回车触发登录而不是注册', (tester) async {
    final repository = _ScriptedAuthRepository();
    addTearDown(repository.dispose);
    await tester.pumpWidget(PactaApp(authRepository: repository));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'user@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'correct-password');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(repository.signInCalls, 1, reason: '回车默认走登录');
    expect(repository.signUpCalls, 0, reason: '回车不得触发受邀注册');
  });

  testWidgets('登录请求挂起时只有登录按钮转圈，受邀注册保持文字并禁用', (tester) async {
    final repository = _ScriptedAuthRepository();
    addTearDown(repository.dispose);
    final gate = Completer<void>();
    repository.signInGate = gate;
    await tester.pumpWidget(PactaApp(authRepository: repository));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'user@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'correct-password');
    await tester.tap(find.byKey(const ValueKey('auth-login-button')));
    await tester.pump();

    final loginButton = find.byKey(const ValueKey('auth-login-button'));
    final registerButton = find.byKey(const ValueKey('auth-register-button'));
    // 只有被点的那颗展示转圈指示器。
    expect(
      find.descendant(
        of: loginButton,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: registerButton,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );
    // 另一颗保持一致的文字与 48dp 命中区，但同步禁用。
    expect(
      find.descendant(of: registerButton, matching: find.text('受邀注册')),
      findsOneWidget,
    );
    expect(
      tester.widget<OutlinedButton>(registerButton).onPressed,
      isNull,
      reason: '请求期间另一颗同步禁用，避免同一份凭据再发一次',
    );
    expect(
      tester.widget<FilledButton>(loginButton).onPressed,
      isNull,
      reason: '请求期间登录按钮自身也不可重复点按',
    );

    gate.complete();
    await tester.pumpAndSettle();
    expect(repository.signInCalls, 1);
    expect(repository.signUpCalls, 0);
  });

  testWidgets('密码框回车直接提交', (tester) async {
    final repository = _ScriptedAuthRepository();
    addTearDown(repository.dispose);
    await tester.pumpWidget(PactaApp(authRepository: repository));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'user@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'short');

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('请输入有效邮箱，以及至少 8 位密码。'), findsOneWidget);
    expect(repository.signInCalls, 0, reason: '本地校验不通过时不得发请求');
  });

  for (final testCase in _errorCases) {
    testWidgets('${testCase.description}显示精准中文提示', (tester) async {
      final repository = _ScriptedAuthRepository();
      addTearDown(repository.dispose);
      if (testCase.registering) {
        repository.signUpFailure = testCase.failure;
      } else {
        repository.signInFailure = testCase.failure;
      }

      await tester.pumpWidget(PactaApp(authRepository: repository));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), 'user@example.com');
      await tester.enterText(find.byType(TextField).at(1), 'correct-password');
      await tester.tap(
        testCase.registering
            ? find.widgetWithText(OutlinedButton, '受邀注册')
            : find.widgetWithText(FilledButton, '登录'),
      );
      await tester.pumpAndSettle();

      expect(find.text(testCase.expected), findsOneWidget);
      expect(find.textContaining('statusCode'), findsNothing);
      expect(find.textContaining('Exception'), findsNothing);
      expect(find.textContaining('code:'), findsNothing);
    });
  }

  testWidgets('未注入客户端配置时提示改用构建脚本注入', (tester) async {
    const repository = UnavailableAuthRepository();
    await tester.pumpWidget(PactaApp(authRepository: repository));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'user@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'correct-password');
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();

    expect(find.text('尚未配置云端服务。请使用构建脚本注入客户端配置后启动。'), findsOneWidget);
    expect(find.textContaining('.env'), findsNothing);
    expect(find.textContaining('dart-define'), findsNothing);
  });

  for (final logicalSize in const [Size(320, 640), Size(1280, 1024)]) {
    for (final brightness in Brightness.values) {
      testWidgets('${logicalSize.width.toInt()}dp / ${brightness.name} 无溢出', (
        tester,
      ) async {
        await _setSize(
          tester,
          logicalSize: logicalSize,
          devicePixelRatio: logicalSize.width == 320 ? 2 : 1,
          brightness: brightness,
        );
        final repository = _ScriptedAuthRepository();
        addTearDown(repository.dispose);

        await tester.pumpWidget(PactaApp(authRepository: repository));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // 并排双按钮在 320dp 下也必须同排不溢出，资格说明不占正文。
        final register = tester.getRect(
          find.widgetWithText(OutlinedButton, '受邀注册'),
        );
        final login = tester.getRect(find.widgetWithText(FilledButton, '登录'));
        expect(register.right, lessThan(login.left));
        expect(
          (register.center.dy - login.center.dy).abs(),
          lessThanOrEqualTo(1),
        );
        expect(login.right, lessThanOrEqualTo(logicalSize.width));
        expect(find.text('使用已开通注册资格的邮箱与密码（至少 8 位）激活账号'), findsNothing);
      });
    }
  }
}
