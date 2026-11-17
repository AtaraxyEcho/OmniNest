import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_page_view.dart';

class _RecordingCallbacks implements PageTurnCallbacks {
  int pageChanged = 0;
  int previousChapter = 0;
  int nextChapter = 0;
  int toggleControls = 0;

  @override
  void onPageChanged(int pageIndex) => pageChanged++;

  @override
  void onPreviousChapter() => previousChapter++;

  @override
  void onNextChapter() => nextChapter++;

  @override
  void onToggleControls() => toggleControls++;
}

void main() {
  testWidgets('翻页模式点击中央只触发一次控制栏切换', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final callbacks = _RecordingCallbacks();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderPageView(
            state: PagedState(
              chapterId: 'chapter_0',
              pageIndex: 0,
              pageCount: 3,
              hasMore: false,
            ),
            pageBuilder: (index) => const SizedBox.expand(),
            callbacks: callbacks,
            surfaceColor: Colors.white,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(ReaderPageView));
    await tester.pump();

    expect(callbacks.toggleControls, 1, reason: '中央点击必须恰好触发一次');
    expect(callbacks.nextChapter, 0);
    expect(callbacks.previousChapter, 0);
  });

  testWidgets('翻页模式点击右侧热区翻下一页而非切换控制栏', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final callbacks = _RecordingCallbacks();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderPageView(
            state: PagedState(
              chapterId: 'chapter_0',
              pageIndex: 0,
              pageCount: 3,
              hasMore: false,
            ),
            pageBuilder: (index) => const SizedBox.expand(),
            callbacks: callbacks,
            surfaceColor: Colors.white,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tapAt(const Offset(760, 300));
    await tester.pump();

    expect(callbacks.toggleControls, 0);
    expect(callbacks.nextChapter, 0, reason: '翻页由 PageView 内部处理，不触发换章');
  });
}
