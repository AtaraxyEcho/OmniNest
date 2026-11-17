import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_chapter_navigation.dart';

/// 路由进入语义 → 初始导航意图（目录显式选章不得被续读 defer 劫持）。
void main() {
  test('proportion 意图携带章内比例，不提前换算偏移', () {
    const intent = ReaderChapterNavigationIntent.proportion(0.25);
    expect(intent.entryPoint, ReaderChapterEntryPoint.proportion);
    expect(intent.chapterRatio, 0.25);
    expect(intent.charOffset, isNull);
  });

  test('entry=chapter 映射为 start 意图（目录显式选章）', () {
    final intent = ReaderChapterNavigationIntent.intentForRouteEntry('chapter');
    expect(intent.entryPoint, ReaderChapterEntryPoint.start);
    expect(intent.charOffset, isNull);
    expect(intent.offerReturn, isFalse);
  });

  test('entry=offset 带偏移时映射为 offset 意图（书签精确定位）', () {
    final intent = ReaderChapterNavigationIntent.intentForRouteEntry(
      'offset',
      charOffset: 640,
    );
    expect(intent.entryPoint, ReaderChapterEntryPoint.offset);
    expect(intent.charOffset, 640);
  });

  test('entry=offset 缺偏移时退回续读，不落到章首', () {
    expect(
      ReaderChapterNavigationIntent.intentForRouteEntry('offset').entryPoint,
      ReaderChapterEntryPoint.resume,
    );
    expect(
      ReaderChapterNavigationIntent.intentForRouteEntry(
        'offset',
        charOffset: 0,
      ).entryPoint,
      ReaderChapterEntryPoint.resume,
    );
  });

  test('null/未知值映射为 resume 意图（续读默认）', () {
    expect(
      ReaderChapterNavigationIntent.intentForRouteEntry(null).entryPoint,
      ReaderChapterEntryPoint.resume,
    );
    expect(
      ReaderChapterNavigationIntent.intentForRouteEntry('resume').entryPoint,
      ReaderChapterEntryPoint.resume,
    );
    expect(
      ReaderChapterNavigationIntent.intentForRouteEntry('unknown').entryPoint,
      ReaderChapterEntryPoint.resume,
    );
  });
}
