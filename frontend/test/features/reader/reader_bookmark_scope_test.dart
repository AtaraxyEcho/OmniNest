import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';

/// 书签按章节归属判存：整书判存会让全书只能存在一条书签。
void main() {
  ReaderBookmark bookmark({String? chapterId, int charOffset = 0}) {
    return ReaderBookmark(
      id: 'bm-$chapterId-$charOffset',
      readerItemId: 'item-1',
      chapterId: chapterId,
      charOffset: charOffset,
      progressPercent: 0.2,
      createdAt: null,
    );
  }

  test('同章命中，别章的书签不算当前章已加书签', () {
    expect(
      bookmarkAtChapter(
        bookmark(chapterId: 'c2'),
        chapterId: 'c2',
        charOffset: 0,
      ),
      isTrue,
    );
    expect(
      bookmarkAtChapter(
        bookmark(chapterId: 'c2'),
        chapterId: 'c9',
        charOffset: 0,
      ),
      isFalse,
    );
  });

  test('章内偏移不同不影响同章判存', () {
    expect(
      bookmarkAtChapter(
        bookmark(chapterId: 'c2', charOffset: 800),
        chapterId: 'c2',
        charOffset: 12,
      ),
      isTrue,
    );
  });

  test('章节归属缺失时退回章内偏移比较', () {
    expect(
      bookmarkAtChapter(
        bookmark(charOffset: 500),
        chapterId: null,
        charOffset: 500,
      ),
      isTrue,
    );
    expect(
      bookmarkAtChapter(
        bookmark(charOffset: 500),
        chapterId: '',
        charOffset: 1,
      ),
      isFalse,
    );
  });

  test('空白章节标识按缺失处理', () {
    // 章节空白 → 退回偏移比较：书签在第 500 字，位置不同就不算命中。
    expect(
      bookmarkAtChapter(
        bookmark(chapterId: 'c2', charOffset: 500),
        chapterId: '   ',
        charOffset: 0,
      ),
      isFalse,
    );
    expect(
      bookmarkAtChapter(
        bookmark(chapterId: 'c2'),
        chapterId: '  c2 ',
        charOffset: 0,
      ),
      isTrue,
    );
  });
}
