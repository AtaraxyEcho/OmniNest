import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_control_layout.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_return_to_progress_control.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

void main() {
  test('沉浸模式释放正文空间并隐藏常驻阅读界面', () {
    final normal = ReaderChromeLayout.resolve(
      immersiveMode: false,
      isPageMode: false,
    );
    final immersive = ReaderChromeLayout.resolve(
      immersiveMode: true,
      isPageMode: false,
    );
    final paginated = ReaderChromeLayout.resolve(
      immersiveMode: false,
      isPageMode: true,
    );

    expect(normal.contentPadding, const EdgeInsets.only(top: 35, bottom: 16));
    expect(normal.viewportVerticalReserve, 51);
    expect(normal.chapterHeaderReserve, 54);
    expect(normal.showPersistentProgress, isTrue);
    expect(immersive.contentPadding, EdgeInsets.zero);
    expect(immersive.viewportVerticalReserve, 0);
    expect(immersive.chapterHeaderReserve, 0);
    expect(immersive.showPersistentProgress, isFalse);
    expect(
      paginated.contentPadding,
      const EdgeInsets.only(top: 35, bottom: 16),
    );
    expect(paginated.viewportVerticalReserve, 51);
    expect(paginated.showPersistentProgress, isTrue);
  });

  test('侧边热区与翻页模式同档，且不被桌面居中列撑满', () {
    expect(ReaderControlLayout.sideTapZoneWidth(390), 97.5);
    expect(ReaderControlLayout.sideTapZoneWidth(320), 80);
    // 窄到 1/4 不足 64 时按拇指下限取。
    expect(ReaderControlLayout.sideTapZoneWidth(200), 64);
    expect(ReaderControlLayout.sideTapZoneWidth(1440), 120);
  });

  test('滚动正文首尾净空取稿子的上下 padding', () {
    final frame =
        ReaderChromeLayout.resolve(
          immersiveMode: false,
          isPageMode: false,
        ).contentPadding;
    final insets = ReaderChromeLayout.scrollContentInsets(
      viewportHeight: 844,
      frame: frame,
      immersiveMode: false,
    );
    // 外层是裁切框，净空只补到稿子 `.article-column` 的取值：
    // padding-top clamp(118px, 15vh, 154px)、padding-bottom 164px。
    expect(frame.top + insets.top, closeTo(126.6, 0.01));
    expect(frame.bottom + insets.bottom, 164);

    final short = ReaderChromeLayout.scrollContentInsets(
      viewportHeight: 300,
      frame: frame,
      immersiveMode: false,
    );
    expect(short.top, 83, reason: '15vh 低于下限时取 clamp 下限 118');

    const safe = EdgeInsets.only(top: 44, bottom: 34);
    final immersiveInsets = ReaderChromeLayout.scrollContentInsets(
      viewportHeight: 844,
      frame:
          ReaderChromeLayout.resolve(
            immersiveMode: true,
            isPageMode: false,
            safePadding: safe,
          ).contentPadding,
      immersiveMode: true,
      safePadding: safe,
    );
    expect(immersiveInsets.top, 80, reason: '稿子 max(68px, safe-top + 36px)');
    expect(immersiveInsets.bottom, 62, reason: 'max(62px, 34 + 28) 取上限');
  });

  test('layout resolves compact medium and expanded viewports', () {
    final compact = ReaderControlLayout.resolve(
      viewport: const Size(320, 568),
      fontSize: 18,
    );
    final medium = ReaderControlLayout.resolve(
      viewport: const Size(800, 600),
      fontSize: 18,
    );
    final expanded = ReaderControlLayout.resolve(
      viewport: const Size(1280, 720),
      fontSize: 18,
    );

    expect(compact.density, ReaderControlDensity.compact);
    expect(medium.density, ReaderControlDensity.medium);
    expect(expanded.density, ReaderControlDensity.expanded);
    expect(expanded.usesSidePanel, isTrue);
    expect(compact.textColumnWidth, lessThanOrEqualTo(284));
    // 列宽按行长定标（30 字），宽窗不再随视口长到 40 字以上。
    expect(medium.textColumnWidth, 540, reason: '18px × 30 字');
    expect(expanded.textColumnWidth, 540);
    final phone = ReaderControlLayout.resolve(
      viewport: const Size(390, 844),
      fontSize: 19,
    );
    expect(phone.textColumnWidth, closeTo(333.8, 0.1), reason: '手机侧仍受视口约束');
    expect(
      ReaderControlLayout.resolve(
        viewport: const Size(1280, 720),
        fontSize: 28,
      ).textColumnWidth,
      660,
      reason: '大字号被上界收到 23.6 字',
    );
  });

  test('short landscape uses a scrollable bottom panel', () {
    final layout = ReaderControlLayout.resolve(
      viewport: const Size(740, 360),
      fontSize: 22,
      textScale: 2,
    );

    expect(layout.isShort, isTrue);
    expect(layout.usesSidePanel, isFalse);
    expect(layout.panelMaxHeight, lessThanOrEqualTo(360));
  });

  test('return progress control remains bounded on desktop', () {
    expect(ReaderControlLayout.returnControlMaxWidth, 360);
  });

  testWidgets('return progress control does not stretch across desktop', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderReturnToProgressControl(
            settings: ReaderViewSettings(),
            label: 'Return to last reading position',
            onPressed: () {},
          ),
        ),
      ),
    );

    final size = tester.getSize(
      find.byKey(const ValueKey('reader-return-progress-control')),
    );
    expect(size.width, lessThanOrEqualTo(360));
    expect(size.width, lessThan(1280));
  });
}
