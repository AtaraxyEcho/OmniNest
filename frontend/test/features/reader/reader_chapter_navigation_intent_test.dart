import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_chapter_navigation.dart';

/// 路由进入语义 → 初始导航意图（目录显式选章不得被续读 defer 劫持）。
void main() {
  test('entry=chapter 映射为 start 意图（目录显式选章）', () {
    final intent = ReaderChapterNavigationIntent.intentForRouteEntry('chapter');
    expect(intent.entryPoint, ReaderChapterEntryPoint.start);
    expect(intent.charOffset, isNull);
    expect(intent.offerReturn, isFalse);
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
