import 'package:flutter/painting.dart' show TextScaler;
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_chapter_end_card.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_pagination_models.dart';

/// 章末收页的页数与位置记账。
///
/// 收页是翻页模式里"本章最后一页"：它没有正文切片，因此不进字符域，
/// 但必须被页数算进去、并把位置记在本章末尾——否则读者在章末合上书再开会回到章首。
void main() {
  group('收页何时挂上', () {
    test('分页完成后正文页数 +1', () {
      expect(readerDisplayPageCount(contentPages: 5, fullyPaginated: true), 6);
      expect(
        isReaderChapterEndPage(
          pageIndex: 5,
          contentPages: 5,
          fullyPaginated: true,
        ),
        isTrue,
      );
      expect(
        isReaderChapterEndPage(
          pageIndex: 4,
          contentPages: 5,
          fullyPaginated: true,
        ),
        isFalse,
      );
    });

    test('正文还没分页完时不挂收页', () {
      // 懒分页的页数是"已确认"的，此时算进收页会让边界判定以为到了章末，
      // 翻页手势会把读者提前送进下一章。
      expect(readerDisplayPageCount(contentPages: 2, fullyPaginated: false), 2);
      expect(
        isReaderChapterEndPage(
          pageIndex: 2,
          contentPages: 2,
          fullyPaginated: false,
        ),
        isFalse,
      );
    });

    test('空章不挂只有卡片的死页', () {
      expect(readerDisplayPageCount(contentPages: 0, fullyPaginated: true), 0);
      expect(
        isReaderChapterEndPage(
          pageIndex: 0,
          contentPages: 0,
          fullyPaginated: true,
        ),
        isFalse,
      );
    });
  });

  group('收页的位置记账', () {
    PageSlice slice(int start, int end) => PageSlice(
      startIndex: 0,
      endIndex: 1,
      startCharOffset: start,
      endCharOffset: end,
    );

    test('正文页仍取页首偏移', () {
      expect(
        readerPageCharOffset(
          slice: slice(120, 200),
          pageIndex: 3,
          contentPages: 5,
          fullyPaginated: true,
          totalChars: 900,
        ),
        120,
      );
    });

    test('收页记本章末尾，不是 0', () {
      expect(
        readerPageCharOffset(
          slice: null,
          pageIndex: 5,
          contentPages: 5,
          fullyPaginated: true,
          totalChars: 900,
        ),
        900,
      );
    });

    test('分页未完成时的空洞页不冒充章末', () {
      expect(
        readerPageCharOffset(
          slice: null,
          pageIndex: 5,
          contentPages: 5,
          fullyPaginated: false,
          totalChars: 900,
        ),
        0,
      );
    });

    test('越界页仍是 0', () {
      expect(
        readerPageCharOffset(
          slice: null,
          pageIndex: 7,
          contentPages: 5,
          fullyPaginated: true,
          totalChars: 900,
        ),
        0,
      );
    });
  });

  test('卡片在最坏文字缩放下仍低于最小可用页高', () {
    // 收页是一整页只有卡片：卡片比页还高就会被翻页内容层裁掉，而翻页不可滚。
    // 最小可用页高按阅读器实际下限取（手机横屏/小窗 320），文字缩放按面板上限 3。
    expect(
      ReaderChapterEndCard.heightFor(
        hasNextChapter: true,
        scaler: TextScaler.linear(3),
      ),
      lessThan(320),
    );
  });
}
