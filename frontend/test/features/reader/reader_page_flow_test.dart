import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_page_flow.dart';

void main() {
  ReaderPageFlow build({
    List<String> chapters = const ['c0', 'c1', 'c2'],
    Map<String, int> counts = const {'c0': 2, 'c1': 3, 'c2': 1},
    Map<String, bool> done = const {'c0': true, 'c1': true, 'c2': true},
    String anchor = 'c1',
    bool hasNextAfter = false,
    bool hasPrevBefore = false,
  }) {
    return ReaderPageFlow(
      chapterIds: chapters,
      readableCounts: counts,
      fullyPaginated: done,
      hasNextChapterAfterWindow: hasNextAfter,
      hasPrevChapterBeforeWindow: hasPrevBefore,
      anchorChapterId: anchor,
    );
  }

  test('展开页序列并映射全局索引', () {
    final flow = build();
    expect(flow.readablePageCount, 6);
    expect(
      flow.keyAt(0),
      const BookPageRef(chapterId: 'c0', localPageIndex: 0),
    );
    expect(
      flow.keyAt(2),
      const BookPageRef(chapterId: 'c1', localPageIndex: 0),
    );
    expect(
      flow.keyAt(5),
      const BookPageRef(chapterId: 'c2', localPageIndex: 0),
    );
    expect(flow.startIndexOf('c1'), 2);
    expect(flow.chapterIdAt(4), 'c1');
  });

  test('未分页完时需要探测页', () {
    final flow = build(
      counts: const {'c0': 2, 'c1': 3, 'c2': 0},
      done: const {'c0': true, 'c1': false, 'c2': false},
    );
    expect(flow.needsProbe, isTrue);
    expect(flow.itemCount, flow.readablePageCount + 1);
  });

  test('全书分页完且无后继章时不需要探测页', () {
    final flow = build();
    expect(flow.needsProbe, isFalse);
    expect(flow.itemCount, flow.readablePageCount);
  });

  test('窗口后还有章时需要探测页', () {
    final flow = build(hasNextAfter: true);
    expect(flow.needsProbe, isTrue);
  });

  test('前向扩窗并入下一章', () {
    final flow = build(
      chapters: const ['c0', 'c1'],
      counts: const {'c0': 1, 'c1': 2},
      done: const {'c0': true, 'c1': true},
      anchor: 'c1',
      hasNextAfter: true,
    ).expandForward(const ['c0', 'c1', 'c2']);
    expect(flow.chapterIds, const ['c0', 'c1', 'c2']);
    expect(flow.readableCounts['c2'], 0);
    expect(flow.hasNextChapterAfterWindow, isFalse);
  });

  test('锚点起始索引为前缀页数之和', () {
    final flow = build(
      chapters: const ['c0', 'c1', 'c2'],
      counts: const {'c0': 4, 'c1': 5, 'c2': 3},
      anchor: 'c2',
    );
    expect(flow.anchorStartIndex, 9);
  });

  test('indexOf 反向查找页身份，前缀页数变化后仍可定位', () {
    final before = build(
      chapters: const ['c0', 'c1'],
      counts: const {'c0': 2, 'c1': 3},
      done: const {'c0': true, 'c1': true},
      anchor: 'c1',
    );
    final ref = before.keyAt(4); // c1#2
    expect(ref, const BookPageRef(chapterId: 'c1', localPageIndex: 2));

    final after = build(
      chapters: const ['c0', 'c1'],
      counts: const {'c0': 5, 'c1': 3},
      done: const {'c0': true, 'c1': true},
      anchor: 'c1',
    );
    final remapped = after.indexOf(ref!);
    expect(remapped, after.startIndexOf('c1')! + 2);
  });
}
