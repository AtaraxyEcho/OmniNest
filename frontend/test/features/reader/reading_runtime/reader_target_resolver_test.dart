import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_position_target.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_target_resolver.dart';

import 'geometry_fixtures.dart';

void main() {
  group('ReaderTargetResolver（方案 §19-§20）', () {
    test('目标章不在布局内返回 null', () {
      final entry = textEntry(id: 'c1', heights: const [100, 200, 300]);
      final layout = layoutFor(snapshotFor([entry]));
      const resolver = ReaderTargetResolver();
      expect(
        resolver.resolveScrollOffset(
          target: const ReaderPositionTarget(
            chapterId: 'missing',
            charOffset: 0,
          ),
          layout: layout,
        ),
        isNull,
      );
    });

    test('章首目标 = 章头顶部贴锚线（prefix − anchorY，含前缀章）', () {
      final first = textEntry(id: 'c1', heights: const [100, 200, 300]);
      final second = textEntry(id: 'c2', heights: const [100, 200, 300]);
      final layout = layoutFor(snapshotFor([first, second]));
      const resolver = ReaderTargetResolver();

      // 第二章前缀 = 36 + 300 + 48 = 384。
      final offset =
          resolver.resolveScrollOffset(
            target: const ReaderPositionTarget(chapterId: 'c2', charOffset: 0),
            layout: layout,
          )!;
      expect(offset, closeTo(384 - 50, 0.001));

      // 单章窗口章首 offset 为 0（prefix=0，钳制到 0）。
      final single = layoutFor(snapshotFor([first]));
      expect(
        resolver.resolveScrollOffset(
          target: const ReaderPositionTarget(chapterId: 'c1', charOffset: 0),
          layout: single,
        ),
        0.0,
      );
    });

    test('章内 charOffset 按块字符前缀映射到窗口坐标', () {
      final first = textEntry(id: 'c1', heights: const [100, 200, 300]);
      final second = textEntry(id: 'c2', heights: const [100, 200, 300]);
      final layout = layoutFor(snapshotFor([first, second]));
      const resolver = ReaderTargetResolver();

      // c2 block0（100 字符 / 100px）的 charOffset=50 → 章体局部 Y=50。
      final offset =
          resolver.resolveScrollOffset(
            target: const ReaderPositionTarget(chapterId: 'c2', charOffset: 50),
            layout: layout,
          )!;
      expect(offset, closeTo(384 + 36 + 50 - 50, 0.001));
    });

    test('charOffset 恰为图片块起点时映射图片顶部（方案 §45）', () {
      final entry = entryWithImage(id: 'c1');
      final layout = layoutFor(snapshotFor([entry]));
      const resolver = ReaderTargetResolver();

      final offset =
          resolver.resolveScrollOffset(
            target: const ReaderPositionTarget(
              chapterId: 'c1',
              charOffset: 100,
            ),
            layout: layout,
          )!;
      expect(offset, closeTo(36 + 100 - 50, 0.001));
    });
  });
}
