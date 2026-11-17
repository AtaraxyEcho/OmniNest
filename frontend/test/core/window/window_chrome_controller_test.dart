import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/window/window_chrome_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('toggleFullscreen toggles manual fullscreen state', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(windowChromeControllerProvider.notifier);

    await controller.toggleFullscreen();
    expect(container.read(windowChromeControllerProvider).isFullscreen, isTrue);

    await controller.toggleFullscreen();
    expect(
      container.read(windowChromeControllerProvider).isFullscreen,
      isFalse,
    );
  });

  test('toggleFullscreen exits an active immersive owner', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(windowChromeControllerProvider.notifier);
    var exited = false;
    await controller.requestImmersive(
      owner: 'movie-player',
      onExit: () => exited = true,
    );

    await controller.toggleFullscreen();

    expect(exited, isTrue);
    expect(
      container.read(windowChromeControllerProvider).immersiveOwner,
      isNull,
    );
    expect(
      container.read(windowChromeControllerProvider).isFullscreen,
      isFalse,
    );
  });

  test('releasing an older lease keeps the newer owner active', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(windowChromeControllerProvider.notifier);

    final older = controller.acquireImmersive(owner: 'reader');
    final newer = controller.acquireImmersive(owner: 'photos');
    older.release();
    // 释放经微任务延迟，冲刷后再断言状态。
    await Future<void>.delayed(Duration.zero);

    final active = container.read(windowChromeControllerProvider);
    expect(active.immersiveOwner, 'photos');
    expect(active.isFullscreen, isTrue);

    newer.release();
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(windowChromeControllerProvider).isFullscreen,
      isFalse,
    );
  });

  test('lease release is idempotent and preserves manual fullscreen', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(windowChromeControllerProvider.notifier);
    await controller.setFullscreen(true);
    final lease = controller.acquireImmersive(owner: 'movie');

    lease
      ..release()
      ..release();
    await Future<void>.delayed(Duration.zero);

    expect(container.read(windowChromeControllerProvider).isFullscreen, isTrue);
    await controller.setFullscreen(false);
    expect(
      container.read(windowChromeControllerProvider).isFullscreen,
      isFalse,
    );
  });

  test(
    'rapid immersive enter and exit leaves native window restored',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const channel = MethodChannel('omninest/window_frame');
      final chromeEntered = Completer<void>();
      final allowChromeEnter = Completer<void>();
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'applyWindowChrome') {
              final args = call.arguments as Map<Object?, Object?>;
              final hidden = args['hidden'] as bool;
              final fullscreen = args['fullscreen'] as bool;
              calls.add('chrome:$hidden:$fullscreen');
              if (hidden && fullscreen) {
                chromeEntered.complete();
                await allowChromeEnter.future;
              }
            } else {
              calls.add(call.method);
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(
        windowChromeControllerProvider.notifier,
      );

      final lease = controller.acquireImmersive(owner: 'reader');
      await chromeEntered.future;
      lease.release();
      await Future<void>.delayed(Duration.zero);
      allowChromeEnter.complete();
      await controller.applied;

      expect(calls.last, 'chrome:false:false');
      // 退出窗口态由原生 applyWindowChrome 内部恢复 placement，Dart 不再二次下发。
      expect(calls, isNot(contains('restoreWindowPlacement')));
      expect(
        container.read(windowChromeControllerProvider).chromeHidden,
        isFalse,
      );
    },
  );

  test(
    'one-shot resizable restore defers until chrome leaves hidden state',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const frameChannel = MethodChannel('omninest/window_frame');
      const windowManagerChannel = MethodChannel('window_manager');
      final frameCalls = <String>[];
      final resizableCalls = <bool>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(frameChannel, (call) async {
        frameCalls.add(call.method);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(frameChannel, null));
      messenger.setMockMethodCallHandler(windowManagerChannel, (call) async {
        if (call.method == 'setResizable') {
          resizableCalls.add(
            (call.arguments as Map<Object?, Object?>)['isResizable'] as bool,
          );
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(windowManagerChannel, null),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(
        windowChromeControllerProvider.notifier,
      );

      final lease = controller.acquireImmersive(owner: 'photos.slideshow');
      await controller.applied;
      // 全屏应用期间禁止写入窗口样式，否则客户区内缩露出白边。
      expect(resizableCalls, isEmpty);
      // Windows 走原子 applyWindowChrome，全屏后做一次几何断言。
      expect(frameCalls, contains('applyWindowChrome'));
      expect(frameCalls, contains('verifyWindowFrame'));

      lease.release();
      await Future<void>.delayed(Duration.zero);
      await controller.applied;
      // 回到窗口态后一次性补上可缩放性恢复，且恰一次。
      expect(resizableCalls, [true]);
    },
  );
}
