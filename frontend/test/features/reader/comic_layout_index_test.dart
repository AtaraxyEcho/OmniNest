import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/domain/comic_layout_index.dart';
import 'package:omninest/features/reader/domain/comic_models.dart';

ComicPage _page(String id, {int? width, int? height}) {
  return ComicPage(
    id: id,
    sourceId: 'src1',
    pageIndex: 0,
    sourcePath: '$id.jpg',
    width: width,
    height: height,
  );
}

void main() {
  group('ComicLayoutIndex', () {
    late ComicLayoutIndex index;
    const viewportHeight = 800.0;

    setUp(() {
      // 3 页，带已知宽高比 (2:1 → 高度 = 800 * (1/2) = 400)
      index = ComicLayoutIndex([
        _page('p1', width: 800, height: 400),
        _page('p2', width: 800, height: 400),
        _page('p3', width: 800, height: 400),
      ], contentWidth: 800.0);
    });

    group('hitTest with known heights', () {
      test('scrollOffset 0 returns page 0 at intraOffset 0', () {
        // 不更新真实高度，使用宽高比估算: 每页高度 = 800 * (400/800) = 400
        final (page, intra) = index.hitTest(0, viewportHeight);
        expect(page, 0);
        expect(intra, 0.0);
      });

      test('scrollOffset at page boundary returns correct page', () {
        // 使用 updateHeight 设置真实高度
        index.updateHeight(0, 300);
        index.updateHeight(1, 500);
        index.updateHeight(2, 200);

        // 在第 2 页中间 (offset = 300 + 250 = 550)
        final (page, intra) = index.hitTest(550, viewportHeight);
        expect(page, 1);
        expect(intra, closeTo(0.5, 0.01));
      });

      test('scrollOffset past last page returns last page', () {
        index.updateHeight(0, 300);
        index.updateHeight(1, 300);
        index.updateHeight(2, 300);

        final (page, intra) = index.hitTest(1000, viewportHeight);
        expect(page, 2);
        expect(intra, 1.0);
      });
    });

    group('hitTest with estimated heights', () {
      test('uses aspect ratio when no real heights set', () {
        // 宽高比 2:1 → 每页估算高度 = 800 * (400/800) = 400
        // 在第 2 页中间 (offset = 400 + 200 = 600)
        final (page, intra) = index.hitTest(600, viewportHeight);
        expect(page, 1);
        expect(intra, closeTo(0.5, 0.01));
      });

      test('uses default 3:4 ratio when no dimensions', () {
        final noDimIndex = ComicLayoutIndex([
          _page('a'),
          _page('b'),
        ], contentWidth: 900.0);
        // 默认高度 = 900 * (4/3) = 1200
        // 总高度 = 2400, 在第 2 页顶部
        final (page, _) = noDimIndex.hitTest(1200, viewportHeight);
        expect(page, 1);
      });
    });

    group('scrollTo', () {
      test('returns offset for given pageIndex and intraOffset 0', () {
        index.updateHeight(0, 300);
        index.updateHeight(1, 400);

        final offset = index.scrollTo(1, 0.0, viewportHeight);
        expect(offset, 300.0);
      });

      test('returns offset for intraOffset 0.5 within page', () {
        index.updateHeight(0, 300);
        index.updateHeight(1, 400);

        final offset = index.scrollTo(1, 0.5, viewportHeight);
        expect(offset, 500.0); // 300 + 400 * 0.5
      });

      test('clamps pageIndex to valid range', () {
        final offset = index.scrollTo(-1, 0.0, viewportHeight);
        expect(offset, 0.0);
      });

      test('clamps result to totalHeight', () {
        index.updateHeight(0, 300);
        index.updateHeight(1, 300);
        index.updateHeight(2, 300);

        final offset = index.scrollTo(2, 1.0, viewportHeight);
        expect(offset, lessThanOrEqualTo(index.totalHeight));
      });
    });

    group('updateContentWidth', () {
      test('returns true on significant change', () {
        final result = index.updateContentWidth(1000.0);
        expect(result, isTrue);
      });

      test('returns false when change is less than 1px', () {
        final result = index.updateContentWidth(800.5);
        expect(result, isFalse);
      });

      test('invalidates offsets on significant change', () {
        final before = index.totalHeight;
        index.updateContentWidth(1600.0);
        // 宽度加倍 → 估算高度加倍 → totalHeight 应增大
        final after = index.totalHeight;
        expect(after, greaterThan(before));
      });
    });

    group('totalHeight', () {
      test('sums estimated page heights', () {
        // 3 页，每页估算 400 → 总高 1200
        expect(index.totalHeight, closeTo(1200.0, 1.0));
      });

      test('uses real heights after updateHeight', () {
        index.updateHeight(0, 500);
        index.updateHeight(1, 600);
        index.updateHeight(2, 700);
        expect(index.totalHeight, closeTo(1800.0, 1.0));
      });
    });

    group('length', () {
      test('returns number of pages', () {
        expect(index.length, 3);
      });
    });
  });
}
