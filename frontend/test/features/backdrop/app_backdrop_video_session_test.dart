import 'dart:io';
import 'dart:ui' show AppLifecycleState;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_video_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppBackdropVideoSession.configure', () {
    late ProviderContainer container;
    late AppBackdropVideoSession session;

    setUp(() {
      container = ProviderContainer();
      session = container.read(appBackdropVideoSessionProvider);
    });

    tearDown(() {
      container.dispose();
    });

    test('签名查询串轮换不递增 generation', () {
      const base = 'http://localhost:9000/obj/original.mp4';
      const signedA = '$base?X-Amz-Signature=aaa';
      const signedB = '$base?X-Amz-Signature=bbb';

      session.configure(path: signedA, muted: true, active: true);
      final generationAfterFirst = session.generation;
      expect(session.sourceIdentity, base);

      session.configure(path: signedB, muted: true, active: true);

      expect(session.generation, generationAfterFirst);
      expect(session.sourceIdentity, base);
    });

    test('资源身份变化会递增 generation', () {
      session.configure(
        path: 'http://localhost:9000/a/original.mp4?sig=1',
        muted: true,
        active: true,
      );
      final first = session.generation;

      session.configure(
        path: 'http://localhost:9000/b/original.mp4?sig=1',
        muted: true,
        active: true,
      );

      expect(session.generation, greaterThan(first));
      expect(session.sourceIdentity, 'http://localhost:9000/b/original.mp4');
    });
  });

  group('AppBackdropVideoSession.renderable', () {
    late ProviderContainer container;
    late AppBackdropVideoSession session;

    setUp(() {
      container = ProviderContainer();
      session = container.read(appBackdropVideoSessionProvider);
    });

    tearDown(() {
      container.dispose();
    });

    test('后台隐藏后回落海报，恢复后等待首个解码帧', () {
      expect(session.renderable, isTrue, reason: '初始纹理有效');

      session.updateLifecycleState(AppLifecycleState.hidden);
      expect(session.renderable, isFalse, reason: '后台期间纹理内容失效');

      session.updateLifecycleState(AppLifecycleState.resumed);
      expect(
        session.renderable,
        isFalse,
        reason: '恢复后等待 position 流推进（首个解码帧）再显示视频',
      );
    });

    test('IO 视图按 renderable 门控回落海报（源断言）', () {
      final source =
          File(
            'lib/features/backdrop/presentation/app_backdrop_video_view_io.dart',
          ).readAsStringSync();
      expect(source, contains('!session.renderable'));
      expect(source, contains('SizedBox.shrink'));
    });
  });
}
