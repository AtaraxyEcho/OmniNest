import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/app.dart';
import 'package:omninest/app/router.dart' show authRedirectPath;
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/core/widgets/app_loading.dart';

/// 回归：登出后根 builder 门控若丢弃 child（Router），refreshListenable
/// 无法再执行 redirect，路径永不更新，加载遮罩永久卡死。
void main() {
  testWidgets('门控开启时 child 仍在树上，关闭后不重挂', (tester) async {
    final mountCounter = ValueNotifier<int>(0);
    final child = _CountingProbe(mountCounter: mountCounter);
    final routeListenable = ValueNotifier<int>(0);
    var gated = true;

    Widget buildGate() {
      return MaterialApp(
        home: UnauthenticatedRenderGate(
          routeListenable: routeListenable,
          shouldGate: () => gated,
          child: child,
        ),
      );
    }

    await tester.pumpWidget(buildGate());
    expect(find.byType(AppLoading), findsOneWidget);
    expect(find.byType(_CountingProbe), findsOneWidget);
    expect(mountCounter.value, 1);

    gated = false;
    await tester.pumpWidget(buildGate());
    expect(find.byType(AppLoading), findsNothing);
    expect(find.byType(_CountingProbe), findsOneWidget);
    // 门控开关不得重挂 child。
    expect(mountCounter.value, 1);
  });

  testWidgets('门控在路由变化后自动解除，child 不被丢弃', (tester) async {
    final routeListenable = ValueNotifier<int>(0);
    final mountCounter = ValueNotifier<int>(0);
    var path = '/portal';

    await tester.pumpWidget(
      MaterialApp(
        home: UnauthenticatedRenderGate(
          routeListenable: routeListenable,
          shouldGate: () => path != '/login',
          child: _CountingProbe(mountCounter: mountCounter),
        ),
      ),
    );
    expect(find.byType(AppLoading), findsOneWidget);

    path = '/login';
    routeListenable.value++;
    await tester.pump();
    await tester.pump();
    expect(find.byType(AppLoading), findsNothing);
    expect(mountCounter.value, 1);
  });

  testWidgets('登出后 redirect 能落到登录页，不卡死在加载遮罩', (tester) async {
    final authRefresh = ValueNotifier<int>(0);
    final auth = _ToggleAuth();
    addTearDown(auth.dispose);

    final router = GoRouter(
      initialLocation: '/portal',
      refreshListenable: authRefresh,
      redirect: (context, state) {
        final session = auth.value;
        return authRedirectPath(
          isChecking: session == null,
          isAuthenticated: session?.isAuthenticated ?? false,
          location: state.uri.toString(),
        );
      },
      routes: [
        GoRoute(
          path: '/portal',
          builder: (context, state) => const Text('portal-page'),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => const Text('login-page'),
        ),
        GoRoute(
          path: '/boot',
          builder: (context, state) => const Text('boot-page'),
        ),
      ],
    );
    addTearDown(router.dispose);

    Widget buildApp() {
      return MaterialApp.router(
        routerConfig: router,
        builder: (context, child) {
          return UnauthenticatedRenderGate(
            routeListenable: Listenable.merge([auth, router.routerDelegate]),
            shouldGate: () {
              final session = auth.value;
              final definitelySignedOut =
                  session != null && !session.isAuthenticated;
              return definitelySignedOut &&
                  gatesUnauthenticatedRender(
                    isAuthenticated: false,
                    path: router.routerDelegate.currentConfiguration.uri.path,
                  );
            },
            child: child ?? const SizedBox.shrink(),
          );
        },
      );
    }

    // 会话恢复完成前停泊引导页。
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    expect(find.text('boot-page'), findsOneWidget);

    // 登录成功。
    auth.signIn(
      AuthSessionState(
        user: UserProfile(id: 'u1', username: 'alice', role: 'MEMBER'),
      ),
    );
    authRefresh.value++;
    await tester.pumpAndSettle();
    expect(find.text('portal-page'), findsOneWidget);
    expect(find.byType(AppLoading), findsNothing);

    // 退出登录：redirect 应回到 /login，不得停留在遮罩。
    auth.signOut();
    authRefresh.value++;
    await tester.pumpAndSettle();
    expect(find.text('login-page'), findsOneWidget);
    expect(find.byType(AppLoading), findsNothing);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/login');
  });

  test('未认证时受保护路径门控、公开路径放行', () {
    expect(
      gatesUnauthenticatedRender(isAuthenticated: false, path: '/portal'),
      isTrue,
    );
    expect(
      gatesUnauthenticatedRender(isAuthenticated: false, path: '/login'),
      isFalse,
    );
    expect(
      gatesUnauthenticatedRender(isAuthenticated: true, path: '/portal'),
      isFalse,
    );
  });
}

class _CountingProbe extends StatefulWidget {
  const _CountingProbe({required this.mountCounter});

  final ValueNotifier<int> mountCounter;

  @override
  State<_CountingProbe> createState() => _CountingProbeState();
}

class _CountingProbeState extends State<_CountingProbe> {
  @override
  void initState() {
    super.initState();
    widget.mountCounter.value += 1;
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand();
  }
}

class _ToggleAuth extends ValueNotifier<AuthSessionState?> {
  _ToggleAuth() : super(null);

  void signIn(AuthSessionState session) {
    value = session;
  }

  void signOut() {
    value = const AuthSessionState.unauthenticated();
  }
}
