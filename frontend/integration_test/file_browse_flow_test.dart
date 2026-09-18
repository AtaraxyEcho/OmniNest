import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:omninest/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('File Browse Flow', () {
    testWidgets('app launches to login page', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // 未登录状态应显示登录页
      expect(find.byType(TextFormField), findsAtLeast(2));
    });

    testWidgets('login form rejects empty submission', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // 点击登录按钮
      final signInButton = find.byType(FilledButton);
      expect(signInButton, findsOneWidget);
      await tester.tap(signInButton);
      await tester.pumpAndSettle();

      // 仍在登录页（未跳转）
      expect(find.byType(TextFormField), findsAtLeast(2));
    });

    testWidgets('login form has username and password fields', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // 验证输入框存在
      final textFields = find.byType(TextFormField);
      expect(textFields, findsAtLeast(2));

      // 验证登录按钮存在
      expect(find.byType(FilledButton), findsOneWidget);
    });
  });
}
