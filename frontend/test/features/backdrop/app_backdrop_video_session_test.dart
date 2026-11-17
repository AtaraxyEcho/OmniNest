import 'dart:io';
import 'dart:ui' show AppLifecycleState;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_video_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppBackdropVideoSession.configure', () {
    late ProviderContainer container;
    late AppBackdropVideoSessionNotifier notifier;

    setUp(() {
      container = ProviderContainer();
      notifier = container.read(appBackdropVideoSessionProvider.notifier);
    });

    tearDown(() {
      container.dispose();
    });

    test('签名查询串轮换不递增 generation', () {
      const base = 'http://localhost:9000/obj/original.mp4';
      const signedA = '$base?X-Amz-Signature=aaa';
      const signedB = '$base?X-Amz-Signature=bbb';

      notifier.configure(path: signedA, muted: true, active: true);
      final generationAfterFirst =
          container.read(appBackdropVideoSessionProvider).generation;
      expect(
        container.read(appBackdropVideoSessionProvider).sourceIdentity,
        base,
      );

      notifier.configure(path: signedB, muted: true, active: true);

      expect(
        container.read(appBackdropVideoSessionProvider).generation,
        generationAfterFirst,
      );
      expect(
        container.read(appBackdropVideoSessionProvider).sourceIdentity,
        base,
      );
    });

    test('资源身份变化会递增 generation', () {
      notifier.configure(
        path: 'http://localhost:9000/a/original.mp4?sig=1',
        muted: true,
        active: true,
      );
      final first = container.read(appBackdropVideoSessionProvider).generation;

      notifier.configure(
        path: 'http://localhost:9000/b/original.mp4?sig=1',
        muted: true,
        active: true,
      );

      expect(
        container.read(appBackdropVideoSessionProvider).generation,
        greaterThan(first),
      );
      expect(
        container.read(appBackdropVideoSessionProvider).sourceIdentity,
        'http://localhost:9000/b/original.mp4',
      );
    });
  });

  group('AppBackdropVideoSession.renderable', () {
    late ProviderContainer container;
    late AppBackdropVideoSessionNotifier notifier;

    setUp(() {
      container = ProviderContainer();
      notifier = container.read(appBackdropVideoSessionProvider.notifier);
    });

    tearDown(() {
      container.dispose();
    });

    test('后台恢复宽限期内保持纹理，位置未推进再回落海报', () async {
      expect(
        container.read(appBackdropVideoSessionProvider).renderable,
        isTrue,
        reason: '初始纹理有效',
      );

      notifier.updateLifecycleState(AppLifecycleState.hidden);
      expect(
        container.read(appBackdropVideoSessionProvider).renderable,
        isTrue,
        reason: '后台不可见，保留 renderable，避免恢复瞬间先闪海报',
      );

      notifier.updateLifecycleState(AppLifecycleState.resumed);
      expect(
        container.read(appBackdropVideoSessionProvider).renderable,
        isTrue,
        reason: '恢复宽限期内保持当前纹理可见',
      );

      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(
        container.read(appBackdropVideoSessionProvider).renderable,
        isFalse,
        reason: '宽限期结束且无播放位置推进时回落海报，等待解码帧或重开',
      );
    });

    test('IO 视图保持 Video 挂载并用透明度门控（源断言）', () {
      final source =
          File(
            'lib/features/backdrop/presentation/app_backdrop_video_view_io.dart',
          ).readAsStringSync();
      expect(source, contains('AnimatedOpacity'));
      expect(source, contains('session.renderable'));
      expect(source, contains('SizedBox.shrink'));
      // controller 已就绪时不得因短暂 !renderable 整层拆掉 Video;
      // keepMountedOpacity 在 ready 时保持 1,避免全屏闪垫底/默认壁纸。
      expect(source, contains('opacity: keepMountedOpacity ? 1 : 0'));
      expect(source, contains('session.ready'));
    });
  });
}
