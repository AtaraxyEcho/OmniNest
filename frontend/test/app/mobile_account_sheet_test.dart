import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/mobile_shell/mobile_account_sheet.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/features/notifications/application/notification_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 账户面板规范测试：矮屏/大字号不溢出，行副标题与双行状态在位。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> pumpSheet(
    WidgetTester tester, {
    Size surface = const Size(390, 600),
    double textScale = 1.0,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = surface;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
          unreadCountProvider.overrideWith(_ZeroUnread.new),
        ],
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            theme: OmniNestTheme.dark(),
            home: Scaffold(
              body: Builder(
                builder:
                    (context) => Center(
                      child: TextButton(
                        onPressed: () => showOmniAccountSheet(context),
                        child: const Text('open'),
                      ),
                    ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('矮屏（600 逻辑高）默认字号无溢出且副标题在位', (tester) async {
    await pumpSheet(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('通知中心'), findsOneWidget);
    expect(find.text('暂无新动态'), findsOneWidget);
    expect(find.text('外观、隐私、存储'), findsOneWidget);
    expect(find.text('刚刚同步完成'), findsOneWidget);
    expect(find.text('管理账户'), findsOneWidget);
    // 工作区工具入口行（原型账户表 Workspace tools）。
    expect(find.text('工作区工具'), findsOneWidget);
    expect(find.text('全部路由与工具页'), findsOneWidget);
  });

  testWidgets('大字号（1.6x）无溢出', (tester) async {
    await pumpSheet(tester, textScale: 1.6);
    expect(tester.takeException(), isNull);
    expect(find.text('管理账户'), findsOneWidget);
    // 面板可滚动：滚动到底部后管理按钮仍可达。
    await tester.dragUntilVisible(
      find.text('管理账户'),
      find.byType(SingleChildScrollView),
      const Offset(0, -40),
    );
    expect(tester.takeException(), isNull);
  });
}

class _ZeroUnread extends UnreadCountNotifier {
  @override
  int build() => 0;
}
