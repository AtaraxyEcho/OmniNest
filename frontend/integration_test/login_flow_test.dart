import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:omninest/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Login Flow', () {
    testWidgets('app launches and shows login page', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // 登录页应包含用户名和密码两个输入框
      expect(find.byType(TextFormField), findsAtLeast(2));
    });

    testWidgets('login form validates empty fields', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // 点击登录按钮（不填写任何内容）
      final signInButton = find.byType(FilledButton);
      expect(signInButton, findsOneWidget);
      await tester.tap(signInButton);
      await tester.pumpAndSettle();

      // 仍在登录页（未跳转），验证未提交成功
      expect(find.byType(TextFormField), findsAtLeast(2));
    });

    testWidgets('login page has sign in button', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // 验证登录按钮存在
      expect(find.byType(FilledButton), findsOneWidget);
    });
  });
}
