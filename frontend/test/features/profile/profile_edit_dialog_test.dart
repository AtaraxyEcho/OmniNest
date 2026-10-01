import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/profile/presentation/widgets/profile_account_panel.dart';

/// 编辑个人资料窗口契约：
/// - 由账号卡「编辑资料」入口打开，字段预填当前值；
/// - 保存携带修改后的昵称/邮箱，成功后关闭；
/// - 昵称为空时内联报错且不触发保存回调。
void main() {
  Future<void> pumpPanel(
    WidgetTester tester, {
    required Future<bool> Function(String, String) onSave,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: OmniNestTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: Center(
            child: ProfileAccountPanel(
              displayName: 'Ataraxy',
              username: 'admin',
              email: 'ataraxy@omninest.local',
              userId: 'u-1',
              role: 'SUPER_ADMIN',
              avatarUrl: null,
              unreadCount: 2,
              onEditAvatar: () {},
              canEditProfile: true,
              onSaveProfile: onSave,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('编辑资料入口打开窗口并携带修改值保存', (tester) async {
    String? savedName;
    String? savedEmail;
    await pumpPanel(
      tester,
      onSave: (displayName, email) async {
        savedName = displayName;
        savedEmail = email;
        return true;
      },
    );

    await tester.tap(find.text('编辑资料'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), '  New Name  ');
    await tester.enterText(fields.at(1), 'new@example.com');
    await tester.tap(find.text('保存修改'));
    await tester.pumpAndSettle();

    expect(savedName, 'New Name');
    expect(savedEmail, 'new@example.com');
    expect(find.text('编辑个人资料'), findsNothing, reason: '保存成功后窗口应关闭');
  });

  testWidgets('昵称清空时内联报错且不触发保存', (tester) async {
    var saveCalls = 0;
    await pumpPanel(
      tester,
      onSave: (displayName, email) async {
        saveCalls += 1;
        return true;
      },
    );

    await tester.tap(find.text('编辑资料'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '   ');
    await tester.tap(find.text('保存修改'));
    await tester.pumpAndSettle();

    expect(saveCalls, 0);
    expect(find.text('显示昵称长度须为 1-120 个字符'), findsOneWidget);
    expect(find.text('编辑个人资料'), findsOneWidget, reason: '校验失败窗口保持打开');
  });
}
