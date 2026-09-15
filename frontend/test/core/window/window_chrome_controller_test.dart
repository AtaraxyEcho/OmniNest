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
    final lease = controller.acquireFullscreen(owner: 'movie');

    lease
      ..release()
      ..release();

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
      final fullscreenEntered = Completer<void>();
      final allowFullscreenEnter = Completer<void>();
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'setWindowFullscreen') {
              final fullscreen =
                  (call.arguments as Map<Object?, Object?>)['fullscreen']
                      as bool;
              calls.add('fullscreen:$fullscreen');
              if (fullscreen) {
                fullscreenEntered.complete();
                await allowFullscreenEnter.future;
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
      await fullscreenEntered.future;
      lease.release();
      await Future<void>.delayed(Duration.zero);
      allowFullscreenEnter.complete();
      await controller.pendingApply;

      expect(
        calls.where((call) => call.startsWith('fullscreen:')).last,
        'fullscreen:false',
      );
      expect(calls, contains('restoreWindowPlacement'));
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
      final resizableCalls = <bool>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(frameChannel, (call) async => null);
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
      await controller.pendingApply;
      // 全屏应用期间禁止写入窗口样式，否则客户区内缩露出白边。
      expect(resizableCalls, isEmpty);

      lease.release();
      await Future<void>.delayed(Duration.zero);
      await controller.pendingApply;
      // 回到窗口态后一次性补上可缩放性恢复，且恰一次。
      expect(resizableCalls, [true]);
    },
  );
}
