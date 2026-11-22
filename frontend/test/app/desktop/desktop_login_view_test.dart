import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/desktop/pages/desktop_login_page.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_theme.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/core/auth/login_page_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'desktop_test_harness.dart';
import 'package:omninest/app/l10n/omni_localizations_delegates.dart';

/// 登录提交的替身：只驱动状态机，不打网络。
class _ScriptedLogin extends LoginPageController {
  _ScriptedLogin(this.onSubmit);

  final Future<bool> Function(String username, String password) onSubmit;
  String? lastUsername;

  /// 直接把状态推进到两步验证挑战，等价于服务端返回 requiresTwoFactor。
  void enterChallenge() {
    state = const LoginPageState(
      challenge: AuthChallenge(challengeToken: 'challenge-1', type: 'verify'),
    );
  }

  @override
  Future<bool> submit({
    required String username,
    required String password,
  }) async {
    lastUsername = username;
    state = const LoginPageState(submitting: true);
    final ok = await onSubmit(username, password);
    state =
        ok
            ? const LoginPageState()
            : const LoginPageState(
              error: LoginPageMessage('Incorrect credentials'),
            );
    return ok;
  }
}

/// 记录两步验证调用，确认页面把整串码与挑战令牌原样交给认证控制器。
class _RecordingSession extends AuthSessionNotifier {
  String? verifiedCode;
  String? challengeToken;

  @override
  Future<AuthSessionState> build() async =>
      const AuthSessionState.unauthenticated();

  @override
  Future<void> signInWithTwoFactor({
    required String challengeToken,
    required String code,
  }) async {
    this.challengeToken = challengeToken;
    verifiedCode = code;
    state = AsyncData(
      AuthSessionState(
        user: UserProfile(id: 'u-1', username: 'mira', role: 'MEMBER'),
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpLogin(
    WidgetTester tester, {
    required LoginPageController Function() controller,
    AuthSessionNotifier Function()? session,
    Size viewport = kDesktopViewport,
  }) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: '/login',
      routes: [
        GoRoute(
          path: '/login',
          builder: (context, state) => const DesktopLoginPage(),
        ),
        GoRoute(
          path: '/portal',
          builder: (context, state) => const Text('route:/portal'),
        ),
        GoRoute(
          path: '/server-setup',
          builder: (context, state) => const Text('route:/server-setup'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...desktopSeedOverrides(session: session),
          loginPageControllerProvider.overrideWith(controller),
        ],
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          routerConfig: router,
          theme: DesktopTheme.resolve(isDark: true),
          localizationsDelegates: kOmniNestLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
  }

  testWidgets('宽屏是左画幅右凭据卡，窄屏只留凭据卡', (tester) async {
    await pumpLogin(
      tester,
      controller: () => _ScriptedLogin((_, _) async => true),
    );

    expect(find.text('WELCOME BACK'), findsOneWidget);
    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsWidgets);
    // 主按钮跟样例一致是 Continue（标题仍是 Sign in），别把两者混为一谈。
    expect(find.text('Continue'), findsOneWidget);
    expect(
      find.text('Everything you keep, quietly in one place.'),
      findsOneWidget,
    );
    expect(find.text('Set up a new server'), findsOneWidget);
  });

  testWidgets('窄屏不渲染左侧画幅', (tester) async {
    await pumpLogin(
      tester,
      controller: () => _ScriptedLogin((_, _) async => true),
      viewport: const Size(760, 900),
    );

    expect(
      find.text('Everything you keep, quietly in one place.'),
      findsNothing,
    );
    expect(find.text('Username'), findsOneWidget);
  });

  testWidgets('桌面最小宽度护栏 1024 下画幅与凭据卡并存且不溢出', (tester) async {
    await pumpLogin(
      tester,
      controller: () => _ScriptedLogin((_, _) async => true),
      viewport: const Size(1024, 700),
    );

    expect(tester.takeException(), isNull);
    expect(
      find.text('Everything you keep, quietly in one place.'),
      findsOneWidget,
    );
    expect(find.text('Username'), findsOneWidget);
  });

  testWidgets('极窄视口 403 下只留凭据卡且不溢出', (tester) async {
    await pumpLogin(
      tester,
      controller: () => _ScriptedLogin((_, _) async => true),
      viewport: const Size(403, 549),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Username'), findsOneWidget);
    final card = tester.getRect(find.text('Username'));
    expect(card.left, greaterThanOrEqualTo(0));
    expect(card.right, lessThanOrEqualTo(403));
  });

  testWidgets('提交成功后落到门户，失败时就地报错不跳转', (tester) async {
    var succeed = false;
    late _ScriptedLogin scripted;
    scripted = _ScriptedLogin((username, password) async {
      expect(username, 'mira');
      expect(password, 'secret');
      return succeed;
    });
    await pumpLogin(tester, controller: () => scripted);

    await tester.enterText(find.byType(TextField).at(0), 'mira');
    await tester.enterText(find.byType(TextField).at(1), 'secret');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('Incorrect credentials'), findsOneWidget);
    expect(find.text('route:/portal'), findsNothing);

    succeed = true;
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('route:/portal'), findsOneWidget);
  });

  testWidgets('两步验证渲染六格码位，粘贴整串自动分位并提交', (tester) async {
    late _ScriptedLogin scripted;
    scripted = _ScriptedLogin((_, _) async => false);
    final session = _RecordingSession();
    await pumpLogin(tester, controller: () => scripted, session: () => session);

    scripted.enterChallenge();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('TWO-FACTOR'), findsOneWidget);
    expect(find.text('Enter your code'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(6));

    await tester.enterText(find.byType(TextField).first, '482193');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(session.verifiedCode, '482193');
    expect(session.challengeToken, 'challenge-1');
    expect(find.text('route:/portal'), findsOneWidget);
  });
}
