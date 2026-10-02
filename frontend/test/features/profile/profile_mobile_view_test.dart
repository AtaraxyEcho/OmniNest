// 个人中心托管移动形态验证：样例形态（模块横幅 + 分组行 + 退出登录）、
// security 直达二级、视觉环境行打开移动端 EnvSettings 抽屉。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/app/environment_providers.dart';
import 'package:omninest/app/mobile_shell/mobile_shell_form.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/features/profile/presentation/pages/profile_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _AuthedSessionNotifier extends AuthSessionNotifier {
  @override
  Future<AuthSessionState> build() async {
    final user = UserProfile(
      id: 'u1',
      username: 'alex',
      displayName: 'Alex Morgan',
      email: 'alex@omninest.local',
      role: 'ADMIN',
    );
    return AuthSessionState(
      user: user,
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> pumpProfile(
    WidgetTester tester, {
    String? initialSection,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation:
          initialSection == null ? '/profile' : '/profile?section=$initialSection',
      routes: [
        GoRoute(
          path: '/profile',
          // 经生产同款 MobileHostedRoute 宿主（历史教训：手动挂 scope 会
          // 掩盖路由缺宿主的缺口，必须走真实链路）。
          builder:
              (context, state) => MobileHostedRoute(
                child: Scaffold(
                  backgroundColor: const Color(0xFF0B1110),
                  body: ProfilePage(
                    initialSection: state.uri.queryParameters['section'],
                  ),
                ),
              ),
        ),
        GoRoute(
          path: '/portal',
          builder:
              (context, state) =>
                  const Scaffold(body: Center(child: Text('portal'))),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(_AuthedSessionNotifier.new),
          appEnvironmentProvider.overrideWithValue(
            const AppEnvironment(
              apiBaseUrl: 'http://localhost',
              wsBaseUrl: 'ws://localhost',
            ),
          ),
        ],
        child: MaterialApp.router(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('托管态渲染样例个人中心（横幅+分组行+退出登录）', (tester) async {
    await pumpProfile(tester);
    expect(find.byType(MobileModuleHeader), findsOneWidget);
    expect(find.text('Alex Morgan'), findsOneWidget);
    expect(find.text('退出登录'), findsOneWidget);
    expect(find.text('个人信息'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('security 直达：会话面板在场并可返回分组列表', (tester) async {
    await pumpProfile(tester, initialSection: 'security');
    expect(find.text('设备与会话'), findsOneWidget);
    expect(find.text('退出登录'), findsNothing);
  });

  testWidgets('分组行返回列表：security 返回后分组行在场', (tester) async {
    await pumpProfile(tester, initialSection: 'security');
    final back = find.byType(MobileGlassIconButton).first;
    await tester.tap(back);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(find.text('设备与会话'), findsNothing);
    expect(find.text('退出登录'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
