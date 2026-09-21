import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';

import 'support/fake_auth_repository.dart';

void main() {
  testWidgets('未登录用户看到登录入口而不是伪造业务数据', (tester) async {
    await tester.pumpWidget(PactaApp(authRepository: FakeAuthRepository()));
    await tester.pumpAndSettle();

    expect(find.text('进入 Pacta'), findsOneWidget);
    expect(find.text('还没有资格？请联系管理员发放注册资格'), findsOneWidget);
    expect(find.text('示例任务'), findsNothing);
  });

  testWidgets('登录后默认进入看板并可访问四个目的地', (tester) async {
    final repository = FakeAuthRepository()..signedInUser = 'user@example.com';
    await tester.pumpWidget(PactaApp(authRepository: repository));
    await tester.pumpAndSettle();

    expect(find.text('看板'), findsWidgets);
    expect(find.text('今天先做什么'), findsOneWidget);
    expect(find.text('暂无任务'), findsOneWidget);

    await tester.tap(find.text('国策树'));
    await tester.pumpAndSettle();
    expect(find.text('国策树还是空的'), findsOneWidget);

    await tester.tap(find.text('专注链'));
    await tester.pumpAndSettle();
    expect(find.text('从任务开始一次专注'), findsOneWidget);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(find.text('user@example.com'), findsOneWidget);
  });
}
