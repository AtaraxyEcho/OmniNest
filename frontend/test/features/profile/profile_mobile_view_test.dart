// 个人中心托管移动形态验证：样例形态（模块横幅 + 分组行 + 退出登录）、
// security 直达二级、视觉环境行打开移动端 EnvSettings 抽屉。
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/mobile_shell/mobile_shell_feature_bindings.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/app/environment_providers.dart';
import 'package:omninest/app/mobile_shell/mobile_shell_form.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/features/profile/application/profile_controller.dart';
import 'package:omninest/features/profile/domain/user_session.dart';
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

  Future<GoRouter> pumpProfile(
    WidgetTester tester, {
    String? initialSection,
    Brightness brightness = Brightness.dark,
    Future<List<UserSession>> Function()? sessionsBuilder,
    Size surface = const Size(390, 844),
  }) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation:
          initialSection == null
              ? '/profile'
              : '/profile?section=$initialSection',
      routes: [
        GoRoute(
          path: '/profile',
          // 经生产同款 MobileHostedRoute 宿主（历史教训：手动挂 scope 会
          // 掩盖路由缺宿主的缺口，必须走真实链路）。
          builder:
              (context, state) => MobileHostedRoute(
                child: Scaffold(
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
          if (sessionsBuilder != null)
            userSessionsProvider.overrideWith((_) async => sessionsBuilder()),
          authSessionProvider.overrideWith(_AuthedSessionNotifier.new),
          mobileShellLocalBackdropActiveProvider.overrideWithValue(false),
          appEnvironmentProvider.overrideWithValue(
            const AppEnvironment(
              apiBaseUrl: 'http://localhost',
              wsBaseUrl: 'ws://localhost',
            ),
          ),
        ],
        child: MaterialApp.router(
          theme:
              brightness == Brightness.dark
                  ? OmniNestTheme.dark()
                  : OmniNestTheme.light(),
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
    return router;
  }

  testWidgets('进入账户空间作废会话缓存，进入本身不多发请求', (tester) async {
    var sessionBuilds = 0;
    final router = await pumpProfile(
      tester,
      sessionsBuilder: () async {
        sessionBuilds += 1;
        return const <UserSession>[];
      },
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ProfilePage)),
    );
    await container.read(userSessionsProvider.future);
    expect(sessionBuilds, 1, reason: '分区首次打开取一次');

    // 账户子视图是页内状态：路由变更仍指向 /profile，监听器据此判定「进入」。
    router.go('/profile?section=appearance');
    await tester.pump(const Duration(milliseconds: 200));
    expect(sessionBuilds, 1, reason: '作废只清缓存，无人监听时不该发请求');

    await container.read(userSessionsProvider.future);
    expect(sessionBuilds, 2, reason: '下一次读取必须拿到新值，而不是页内旧缓存');
  });

  // 不锁竖屏的成立前提：横屏下账户页不抛异常、不溢出，退出登录只是落到
  // 折叠线以下（390 逻辑高减顶栏 64 与底栏 70 后约 256），滚一屏即可达。
  // 哪天某个页面在横屏真溢出，这条会先红。
  testWidgets('横屏手机（844×390）个人页可渲染，退出登录滚动可达', (tester) async {
    await pumpProfile(tester, surface: const Size(844, 390));
    expect(tester.takeException(), isNull, reason: '横屏渲染不得抛异常或溢出');
    expect(find.byType(MobileModuleHeader), findsOneWidget);
    expect(find.text('Alex Morgan'), findsOneWidget);
    expect(find.text('退出登录'), findsNothing, reason: '它落在折叠线以下，靠滚动到达而不是被裁掉');

    await tester.dragUntilVisible(
      find.text('退出登录'),
      find.byType(ListView),
      const Offset(0, -40),
    );
    await tester.pumpAndSettle();
    expect(find.text('退出登录'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('两极性下分组眉标取对应极性的墨色', (tester) async {
    Color groupInk() =>
        tester
            .renderObject<RenderParagraph>(find.text('外观'))
            .text
            .style!
            .color!;

    await pumpProfile(tester);
    expect(groupInk(), MobileEnvPalette.dark.groupLabelInk);

    await pumpProfile(tester, brightness: Brightness.light);
    expect(groupInk(), MobileEnvPalette.light.groupLabelInk);
  });

  testWidgets('外观分组：字号档位显示中文标签且三组按钮等宽', (tester) async {
    await pumpProfile(tester, initialSection: 'appearance');

    // 回归守卫：曾经直接把枚举名渲染成 comfortable，中文界面里是英文串。
    expect(find.text('comfortable'), findsNothing);
    expect(find.text('紧凑'), findsOneWidget);
    expect(find.text('标准'), findsOneWidget);
    expect(find.text('舒适'), findsOneWidget);
    expect(find.text('大'), findsOneWidget);

    double widthOf(String label) =>
        tester
            .getSize(
              find.ancestor(
                of: find.text(label),
                matching: find.byType(AnimatedContainer),
              ),
            )
            .width;

    double leftOf(String label) =>
        tester
            .getTopLeft(
              find.ancestor(
                of: find.text(label),
                matching: find.byType(AnimatedContainer),
              ),
            )
            .dx;

    // 主题（三档）、语言（两档）、字号（五档）都是 repeat(3,1fr)，
    // 同一列的左边缘必须对齐，否则就是分段控件的 max-content 宽度。
    for (final label in const ['浅色模式', 'English', '标准', '大']) {
      expect(
        widthOf(label),
        closeTo(widthOf('深色模式'), 0.01),
        reason: '$label 应与同列按钮等宽',
      );
    }
    expect(
      leftOf('English'),
      closeTo(leftOf('浅色模式'), 0.01),
      reason: '语言组只有两项，首列左边缘要与主题组同列',
    );
    expect(tester.takeException(), isNull);
  });

  // 子视图（会话/外观/资料…）是页内状态不是路由：系统侧滑要先关子视图，
  // 再一次才离开账户页。此前只有页头返回钮收敛子视图，侧滑直接把整页弹掉。
  testWidgets('子视图在场：系统返回先关子视图不离页', (tester) async {
    await pumpProfile(tester, initialSection: 'security');
    expect(find.text('设备与会话'), findsOneWidget);

    await tester.binding.handlePopRoute();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    expect(find.text('设备与会话'), findsNothing, reason: '第一次返回只关子视图');
    expect(find.text('退出登录'), findsOneWidget, reason: '仍停在账户页');
    expect(tester.takeException(), isNull);
  });
}
