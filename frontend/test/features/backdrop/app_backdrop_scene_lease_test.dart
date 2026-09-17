import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_controller.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_scene_controller.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop_policy.dart';
import 'package:omninest/features/backdrop/presentation/app_backdrop_host.dart';

class _StubBackdropController extends AppBackdropController {
  @override
  Future<AppBackdropState> build() async => const AppBackdropState();
}

class _MountProbe extends StatefulWidget {
  const _MountProbe({required this.onMounted});

  final VoidCallback onMounted;

  @override
  State<_MountProbe> createState() => _MountProbeState();
}

class _MountProbeState extends State<_MountProbe> {
  @override
  void initState() {
    super.initState();
    widget.onMounted();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

void main() {
  group('场景租约握手', () {
    test('整树重挂后新作用域持新租约，旧作用域按旧租约释放不得误删', () async {
      final container = ProviderContainer.test();
      addTearDown(container.dispose);
      final controller = container.read(
        appBackdropSceneControllerProvider.notifier,
      );

      final oldLease = controller.request(
        'app.mobile.shell',
        AppBackdropPolicy.portalMobile,
      );
      final newLease = controller.request(
        'app.mobile.shell',
        AppBackdropPolicy.portalMobile,
      );

      expect(newLease, isNot(equals(oldLease)));

      controller.release('app.mobile.shell', lease: oldLease);
      var state = container.read(appBackdropSceneControllerProvider);
      expect(state.owner, 'app.mobile.shell');
      expect(state.policy, AppBackdropPolicy.portalMobile);

      controller.release('app.mobile.shell', lease: newLease);
      // 清空策略延迟一拍落到 hidden，给同帧新注册留出手。
      await Future<void>.delayed(Duration.zero);
      state = container.read(appBackdropSceneControllerProvider);
      expect(state.owner, isNull);
      expect(state.policy.scene, AppBackdropScene.hidden);
      expect(state.policy.visible, isFalse);
    });

    test('清空后同微任务内重新注册不会先闪 hidden', () async {
      final container = ProviderContainer.test();
      addTearDown(container.dispose);
      final controller = container.read(
        appBackdropSceneControllerProvider.notifier,
      );

      controller.request('a', AppBackdropPolicy.portalMobile);
      controller.release('a');
      controller.request('b', AppBackdropPolicy.musicDeck);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(appBackdropSceneControllerProvider);
      expect(state.owner, 'b');
      expect(state.policy, AppBackdropPolicy.musicDeck);
      expect(state.policy.visible, isTrue);
    });

    test('同所有者重复注册相同策略不发布新状态', () {
      final container = ProviderContainer.test();
      addTearDown(container.dispose);
      final controller = container.read(
        appBackdropSceneControllerProvider.notifier,
      );
      controller.request('portal', AppBackdropPolicy.portal);

      var publishes = 0;
      container.listen(appBackdropSceneControllerProvider, (_, _) {
        publishes++;
      });

      controller.request('portal', AppBackdropPolicy.portal);

      expect(publishes, 0);
    });
  });

  group('AppBackdropHost 场景翻转稳定性', () {
    testWidgets('可见性翻转不重建路由内容子树', (tester) async {
      final container = ProviderContainer.test(
        overrides: [
          appBackdropControllerProvider.overrideWith(
            _StubBackdropController.new,
          ),
        ],
      );
      addTearDown(container.dispose);

      var mounts = 0;
      Widget probe() => _MountProbe(onMounted: () => mounts++);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: AppBackdropHost(child: probe())),
        ),
      );
      await tester.pump();
      final mountsBefore = mounts;
      expect(mountsBefore, 1);

      final controller = container.read(
        appBackdropSceneControllerProvider.notifier,
      );
      controller.request('app.mobile.shell', AppBackdropPolicy.portalMobile);
      await tester.pump();
      controller.release('app.mobile.shell');
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(mounts, mountsBefore);
    });

    testWidgets('路由内容收缩场景时不触发 build 期 setState 异常', (tester) async {
      final container = ProviderContainer.test(
        overrides: [
          appBackdropControllerProvider.overrideWith(
            _StubBackdropController.new,
          ),
        ],
      );
      addTearDown(container.dispose);
      final router = GoRouter(
        initialLocation: '/portal',
        routes: [
          GoRoute(
            path: '/portal',
            builder: (_, _) => const Scaffold(body: Text('portal')),
          ),
          GoRoute(
            path: '/login',
            builder: (_, _) => const Scaffold(body: Text('login')),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            builder:
                (context, child) =>
                    AppBackdropHost(child: child ?? const SizedBox.shrink()),
          ),
        ),
      );
      await tester.pump();

      final controller = container.read(
        appBackdropSceneControllerProvider.notifier,
      );
      controller.request('app.mobile.shell', AppBackdropPolicy.portalMobile);
      await tester.pump();
      // 模拟导航到 work 类页面并收缩场景：配置变化与前置收缩同帧发生。
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            builder:
                (context, child) =>
                    AppBackdropHost(child: child ?? const SizedBox.shrink()),
          ),
        ),
      );
      router.go('/login');
      controller.release('app.mobile.shell');
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}
