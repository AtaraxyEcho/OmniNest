import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_scene_controller.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_video_session.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop_policy.dart';
import 'package:omninest/features/backdrop/presentation/app_backdrop_scene_scope.dart';

void main() {
  group('AppBackdropSceneController', () {
    test('工作页面策略隐藏背景并启用工作可读性', () {
      expect(AppBackdropPolicy.work.scene, AppBackdropScene.work);
      expect(AppBackdropPolicy.work.visible, isFalse);
      expect(
        AppBackdropPolicy.work.playbackMode,
        AppBackdropPlaybackMode.paused,
      );
      expect(
        AppBackdropPolicy.work.readabilityMode,
        AppBackdropReadabilityMode.work,
      );
      expect(AppBackdropPolicy.work.motionAllowed, isFalse);
    });

    test('媒体内容页面使用静态背景快照', () {
      expect(AppBackdropPolicy.staticContent.visible, isTrue);
      expect(
        AppBackdropPolicy.staticContent.playbackMode,
        AppBackdropPlaybackMode.paused,
      );
      expect(AppBackdropPolicy.staticContent.motionAllowed, isFalse);
    });

    test('最近激活场景释放后回退到上一场景', () {
      final container = ProviderContainer.test();
      addTearDown(container.dispose);
      final controller = container.read(
        appBackdropSceneControllerProvider.notifier,
      );

      controller.request('portal', AppBackdropPolicy.portal);
      controller.request('music', AppBackdropPolicy.musicDeck);

      expect(
        container.read(appBackdropSceneControllerProvider).policy.scene,
        AppBackdropScene.musicDeck,
      );

      controller.release('music');

      final state = container.read(appBackdropSceneControllerProvider);
      expect(state.owner, 'portal');
      expect(state.policy.scene, AppBackdropScene.portal);
    });

    test('过期租约不能释放同一所有者的新场景', () {
      final container = ProviderContainer.test();
      addTearDown(container.dispose);
      final controller = container.read(
        appBackdropSceneControllerProvider.notifier,
      );

      final oldLease = controller.request('music', AppBackdropPolicy.portal);
      controller.request('music', AppBackdropPolicy.musicDeck);
      controller.release('music', lease: oldLease);

      final state = container.read(appBackdropSceneControllerProvider);
      expect(state.owner, 'music');
      expect(state.policy.scene, AppBackdropScene.musicDeck);
    });

    testWidgets('场景作用域卸载时在当前帧结束后释放场景', (tester) async {
      final container = ProviderContainer.test();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: AppBackdropSceneScope(
              owner: 'music',
              policy: AppBackdropPolicy.musicDeck,
              child: SizedBox(),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(container.read(appBackdropSceneControllerProvider).owner, 'music');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SizedBox()),
        ),
      );
      await tester.pump();
      // 空策略宽限在 post-frame release 之后再经微任务落到 hidden。
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(container.read(appBackdropSceneControllerProvider).owner, isNull);
    });

    test('视频会话 Provider 在同一容器内保持单实例', () {
      final container = ProviderContainer.test();
      addTearDown(container.dispose);

      final first = container.read(appBackdropVideoSessionProvider);
      final second = container.read(appBackdropVideoSessionProvider);

      expect(identical(first, second), isTrue);
      expect(first.diagnostics?.textureCount, 0);
      expect(first.diagnostics?.successfulOpenCount, 0);
    });
  });
}
