import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_navigation_token.dart';

void main() {
  group('ReaderNavigationTokenHolder', () {
    test('begin 创建令牌并使旧令牌失效', () {
      final holder = ReaderNavigationTokenHolder();
      final first = holder.begin(
        source: ReaderNavigationSource.tableOfContents,
        targetChapterId: 'chapter_1',
      );
      expect(holder.isActive(first), isTrue);
      expect(holder.current, same(first));

      final second = holder.begin(
        source: ReaderNavigationSource.progressSeek,
        targetChapterId: 'chapter_5',
      );
      expect(holder.isActive(first), isFalse, reason: '旧令牌必须失效');
      expect(holder.isActive(second), isTrue);
      expect(second.id, greaterThan(first.id));
    });

    test('isActive 对 null 恒为无效', () {
      final holder = ReaderNavigationTokenHolder();
      expect(holder.isActive(null), isFalse);
    });

    test('isUnchangedSince 允许 null 对 null（尚无显式导航）', () {
      final holder = ReaderNavigationTokenHolder();
      expect(holder.isUnchangedSince(null), isTrue);
      holder.begin(
        source: ReaderNavigationSource.chapterStep,
        targetChapterId: 'chapter_2',
      );
      expect(holder.isUnchangedSince(null), isFalse);
    });

    test('isUnchangedSince 捕获令牌后新导航介入则失效', () {
      final holder = ReaderNavigationTokenHolder();
      final captured = holder.current;
      holder.begin(
        source: ReaderNavigationSource.returnToProgress,
        targetChapterId: 'chapter_3',
      );
      expect(holder.isUnchangedSince(captured), isFalse);

      final sameToken = holder.current;
      expect(holder.isUnchangedSince(sameToken), isTrue);
    });
  });
}
