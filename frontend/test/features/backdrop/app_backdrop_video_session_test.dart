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
}
