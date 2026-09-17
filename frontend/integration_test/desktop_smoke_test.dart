import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:omninest/main.dart' as app;

/// 0.1.0 Windows/桌面业务冒烟：登录 → Portal → 模块入口 → 退出。
///
/// 需后端可达（dart-define API）且账号 admin / TestAdmin!2026。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('login then visit modules and logout', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 冷启动可能已有会话，先等一帧；若在登录页则登录。
    final usernameField = find.widgetWithText(TextFormField, '用户名');
    final passwordField = find.widgetWithText(TextFormField, '密码');
    // 兜底：按顺序取前两个文本框
    final fields = find.byType(TextFormField);

    if (usernameField.evaluate().isNotEmpty &&
        passwordField.evaluate().isNotEmpty) {
      await tester.enterText(usernameField, 'admin');
      await tester.enterText(passwordField, 'TestAdmin!2026');
      final loginBtn = find.widgetWithText(FilledButton, '登录');
      if (loginBtn.evaluate().isEmpty) {
        final btns = find.byType(FilledButton);
        expect(btns, findsWidgets);
        await tester.tap(btns.first);
      } else {
        await tester.tap(loginBtn);
      }
      await tester.pumpAndSettle(const Duration(seconds: 3));
      // 等 Portal 网络请求
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle(const Duration(seconds: 1));
    } else {
      // 可能已在 Portal；仍要求至少有一个可滚动主界面
      expect(tester.any(find.byType(Scaffold)), isTrue);
    }

    // Portal 或任意已登录壳：应存在 Scaffold，且不是空崩溃树
    expect(tester.any(find.byType(Scaffold)), isTrue);

    // 尝试点导航标签（桌面左侧/移动端底部文案可能相同）
    Future<void> tryNav(String label) async {
      final byText = find.text(label);
      if (byText.evaluate().isNotEmpty) {
        await tester.ensureVisible(byText.first);
        await tester.tap(byText.first, warnIfMissed: false);
        await tester.pumpAndSettle(const Duration(milliseconds: 800));
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.any(find.byType(Scaffold)), isTrue);
      }
    }

    for (final label in const ['文件', '照片', '媒体', '音乐', '阅读']) {
      await tryNav(label);
    }

    // 回首页/Portal
    await tryNav('首页');
    await tryNav('Portal');

    // 退出登录（若可见）
    final logout = find.text('退出登录');
    if (logout.evaluate().isNotEmpty) {
      await tester.ensureVisible(logout.first);
      await tester.tap(logout.first, warnIfMissed: false);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }
  });
}
