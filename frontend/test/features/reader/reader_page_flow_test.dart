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

  group('resolveRebuiltPageIndex 页索引归属解析', () {
    test('显式导航禁止旧页身份重映射（邻章硬切不得回滚到旧章页）', () {
      // 复刻邻章硬切：旧流锚点 c0，当前页 0 = c0#0；切到 c1 后窗口不变，
      // 旧身份 c0#0 仍能被 indexOf 命中，但显式导航必须锚定 c1 起始。
      final oldFlow = build(anchor: 'c0');
      final previousRef = oldFlow.keyAt(0); // c0#0
      final newFlow = build(anchor: 'c1');
      final resolved = newFlow.resolveRebuiltPageIndex(
        anchorChapterId: 'c1',
        currentPage: 0,
        previousRef: previousRef,
        explicitNavigation: true,
      );
      expect(resolved, newFlow.startIndexOf('c1'));
      expect(resolved, isNot(newFlow.indexOf(previousRef!)));
    });

    test('非显式导航允许旧页身份重映射保持视觉位置', () {
      final oldFlow = build(anchor: 'c1');
      final previousRef = oldFlow.keyAt(3); // c1#1
      final newFlow = build(anchor: 'c1');
      final resolved = newFlow.resolveRebuiltPageIndex(
        anchorChapterId: 'c1',
        currentPage: 3,
        previousRef: previousRef,
      );
      expect(resolved, 3);
    });

    test('身份丢失时钳制到锚点章起始', () {
      final oldFlow = build(
        chapters: const ['c0', 'c1'],
        counts: const {'c0': 2, 'c1': 3},
        done: const {'c0': true, 'c1': true},
        anchor: 'c0',
      );
      final previousRef = oldFlow.keyAt(0); // c0#0，已滑出新窗口
      final newFlow = build(
        chapters: const ['c1', 'c2'],
        counts: const {'c1': 3, 'c2': 1},
        done: const {'c1': true, 'c2': true},
        anchor: 'c2',
      );
      final resolved = newFlow.resolveRebuiltPageIndex(
        anchorChapterId: 'c2',
        currentPage: 0,
        previousRef: previousRef,
      );
      expect(resolved, newFlow.startIndexOf('c2'));
    });

    test('待映射章内页优先锚定到锚点章起始加局部页', () {
      final flow = build(anchor: 'c1');
      final resolved = flow.resolveRebuiltPageIndex(
        anchorChapterId: 'c1',
        currentPage: 0,
        pendingLocalIndex: 2,
        explicitNavigation: true,
      );
      expect(resolved, flow.startIndexOf('c1')! + 2);
    });

    test('锚点章尚无页时保持当前索引等待重试', () {
      final flow = build(
        counts: const {'c0': 2, 'c1': 0, 'c2': 1},
        done: const {'c0': true, 'c1': false, 'c2': true},
        anchor: 'c1',
      );
      expect(flow.startIndexOf('c1'), isNull);
      expect(
        flow.resolveRebuiltPageIndex(
          anchorChapterId: 'c1',
          currentPage: 1,
          pendingLocalIndex: 0,
          explicitNavigation: true,
        ),
        1,
      );
    });
  });
}
