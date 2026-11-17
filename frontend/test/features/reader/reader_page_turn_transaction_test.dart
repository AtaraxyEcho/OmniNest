import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_loader.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_page_locator.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_page_view.dart';

/// 摘要：PageTurn 事务化回归（方案 Commit 1，验收矩阵 A 组）。
/// A1 连续 20 次右击严格递增；A2 PageLocator 成功/异常/取消/覆盖四路径
/// 都必须退出 locating；混沌场景（翻页中途父级状态变化）不得锁死。
void main() {
  group('A1 连续翻页', () {
    testWidgets('右侧连续点击 20 次pageIndex 严格递增无停滞', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 600);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final harnessKey = GlobalKey<_TransactionHarnessState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TransactionHarness(key: harnessKey, pageCount: 24),
          ),
        ),
      );
      expect(tester.takeException(), isNull);

      for (var expected = 1; expected <= 20; expected++) {
        await tester.tapAt(const Offset(760, 300));
        await tester.pump(const Duration(milliseconds: 120));
        await tester.pump(const Duration(milliseconds: 120));
        expect(
          harnessKey.currentState!.pageIndex,
          expected,
          reason: '第 $expected 次点击后应停留在第 $expected 页',
        );
      }
      expect(
        harnessKey.currentState!.observedPages,
        List.generate(20, (i) => i + 1),
      );
    });

    testWidgets('翻页中途父级状态变化（pageCount 收缩）不锁死输入', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 600);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final harnessKey = GlobalKey<_TransactionHarnessState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TransactionHarness(key: harnessKey, pageCount: 24),
          ),
        ),
      );

      await tester.tapAt(const Offset(760, 300));
      await tester.pump(const Duration(milliseconds: 120));
      // 动画进行中父级收缩页数（模拟窗口变化触发的重排）。
      harnessKey.currentState!.setPageCount(24);
      await tester.pump(const Duration(milliseconds: 120));
      expect(tester.takeException(), isNull);

      // 后续翻页必须照常工作。
      await tester.tapAt(const Offset(760, 300));
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump(const Duration(milliseconds: 120));
      expect(harnessKey.currentState!.pageIndex, 2);
    });
  });

  group('A2 PageLocator 事务安全', () {
    test('定位成功后退出 locating', () async {
      final locator = ReaderPageLocator();
      final navigator = _FakeNavigator(resolve: (charOffset) => 3);
      final page = await locator.locate(navigator, 120);
      expect(page, 3);
      expect(locator.isLocating, isFalse);
    });

    test('定位异常后退出 locating，不残留全局锁', () async {
      final locator = ReaderPageLocator();
      final navigator = _FakeNavigator(throwOnLocate: true);
      await expectLater(
        locator.locate(navigator, 120),
        throwsA(isA<StateError>()),
      );
      expect(
        locator.isLocating,
        isFalse,
        reason: 'await 异常必须经 finally 释放，否则 isPaginating 永真锁死翻页',
      );
    });

    test('取消与新导航覆盖旧导航后退出 locating', () async {
      final locator = ReaderPageLocator();
      final navigator = _FakeNavigator(
        resolve: (charOffset) => 1,
        delay: const Duration(milliseconds: 30),
      );
      final first = locator.locate(navigator, 10);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      locator.cancel();
      expect(await first, isNull);
      expect(locator.isLocating, isFalse);

      final second = locator.locate(navigator, 10);
      final third = locator.locate(navigator, 20);
      expect(await second, isNull, reason: '被新导航覆盖的旧请求返回 null');
      expect(await third, isNotNull);
      expect(locator.isLocating, isFalse);
    });
  });
}

class _FakeNavigator extends PageNavigator {
  _FakeNavigator({this.resolve, this.throwOnLocate = false, this.delay})
    : super(blocks: const <ContentBlock>[], computeFn: (_) => null);

  final int? Function(int charOffset)? resolve;
  final bool throwOnLocate;
  final Duration? delay;

  @override
  Future<int?> findPageByCharOffset(
    int charOffset, {
    int pagesPerBatch = 8,
    bool Function()? isCancelled,
  }) async {
    if (delay != null) {
      await Future<void>.delayed(delay!);
    }
    if (throwOnLocate) {
      throw StateError('locate exploded');
    }
    return resolve?.call(charOffset);
  }
}

class _TransactionHarness extends StatefulWidget {
  const _TransactionHarness({required this.pageCount, super.key});

  final int pageCount;

  @override
  State<_TransactionHarness> createState() => _TransactionHarnessState();
}

class _TransactionHarnessState extends State<_TransactionHarness> {
  final ReaderPageTurnController controller = ReaderPageTurnController();
  final List<int> observedPages = [];
  int pageIndex = 0;
  late int pageCount = widget.pageCount;

  void setPageCount(int value) {
    setState(() => pageCount = value);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return ReaderPageView(
          controller: controller,
          state: PagedState(
            chapterId: 'chapter-1',
            pageIndex: pageIndex,
            pageCount: pageCount,
            hasMore: false,
          ),
          pageBuilder: (index) => Text('page-$index'),
          callbacks: _TransactionCallbacks(
            handlePageChanged: (index) {
              observedPages.add(index);
              setState(() => pageIndex = index);
            },
          ),
          surfaceColor: Colors.white,
        );
      },
    );
  }
}

class _TransactionCallbacks implements PageTurnCallbacks {
  _TransactionCallbacks({required this.handlePageChanged});

  final void Function(int) handlePageChanged;

  @override
  void onPageChanged(int pageIndex) => handlePageChanged(pageIndex);

  @override
  void onNextChapter() {}

  @override
  void onPreviousChapter() {}

  @override
  void onToggleControls() {}
}
