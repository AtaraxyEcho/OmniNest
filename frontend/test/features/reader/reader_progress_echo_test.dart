import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/application/reader_progress_echo.dart';

void main() {
  group('ReaderProgressEchoDetector', () {
    test('较旧保存的回声在更新保存之后到达仍被识别（实机 67 字符场景）', () {
      final detector = ReaderProgressEchoDetector();
      final t0 = DateTime(2026, 9, 12, 10, 0, 0);
      // 保存 A（1285），随后保存 B（1352）——差 67 字符，旧实现 64 容差漏判。
      detector.note(
        chapterId: 'chapter_5',
        charOffset: 1285,
        progress: 0.4371,
        at: t0,
      );
      detector.note(
        chapterId: 'chapter_5',
        charOffset: 1352,
        progress: 0.4374,
        at: t0.add(const Duration(seconds: 20)),
      );
      // 保存 A 的服务端回声（时间戳略新、位置=A）在 B 之后到达。
      expect(
        detector.isEcho(
          chapterId: 'chapter_5',
          charOffset: 1285,
          progress: 0.4371,
          at: t0.add(const Duration(seconds: 25)),
        ),
        isTrue,
      );
    });

    test('跨设备新进度（位置显著不同）不被误判为回声', () {
      final detector = ReaderProgressEchoDetector();
      final t0 = DateTime(2026, 9, 12, 10, 0, 0);
      detector.note(
        chapterId: 'chapter_5',
        charOffset: 1285,
        progress: 0.4371,
        at: t0,
      );
      // 位置推进 800 字符：超出容差，是真新进度。
      expect(
        detector.isEcho(
          chapterId: 'chapter_5',
          charOffset: 2085,
          progress: 0.44,
          at: t0.add(const Duration(seconds: 10)),
        ),
        isFalse,
      );
      // 别章更新也不是回声。
      expect(
        detector.isEcho(
          chapterId: 'chapter_9',
          charOffset: 1285,
          progress: 0.4371,
          at: t0.add(const Duration(seconds: 10)),
        ),
        isFalse,
      );
    });

    test('回声窗口外（>30s）的相同位置不视为回声', () {
      final detector = ReaderProgressEchoDetector();
      final t0 = DateTime(2026, 9, 12, 10, 0, 0);
      detector.note(
        chapterId: 'chapter_5',
        charOffset: 1285,
        progress: 0.4371,
        at: t0,
      );
      expect(
        detector.isEcho(
          chapterId: 'chapter_5',
          charOffset: 1285,
          progress: 0.4371,
          at: t0.add(const Duration(seconds: 31)),
        ),
        isFalse,
      );
    });

    test('环形记录超出上限时淘汰最旧条目', () {
      final detector = ReaderProgressEchoDetector();
      final t0 = DateTime(2026, 9, 12, 10, 0, 0);
      for (var i = 0; i < 10; i++) {
        detector.note(
          chapterId: 'chapter_5',
          charOffset: 1000 + i * 200,
          progress: 0.4,
          at: t0.add(Duration(seconds: i)),
        );
      }
      // 最旧两条（1000/1200）被淘汰；1400 仍在环内但其回声窗口已过。
      final late = t0.add(const Duration(seconds: 60));
      expect(
        detector.isEcho(
          chapterId: 'chapter_5',
          charOffset: 1000,
          progress: 0.4,
          at: t0.add(const Duration(seconds: 5)),
        ),
        isFalse,
      );
      expect(
        detector.isEcho(
          chapterId: 'chapter_5',
          charOffset: 1400,
          progress: 0.4,
          at: late,
        ),
        isFalse,
      );
    });
  });
}
