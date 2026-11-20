import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_control_layout.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 阅读器唯一几何事实源：测量、分页、恢复、渲染四处统一从此处取值。
///
/// 由 [_ReaderViewPageState] 在 `LayoutBuilder` 中缓存为 `lastViewportMetrics`，
/// `computePageWidth()` 与 `computePageHeight()` 优先读缓存，杜绝在 `dispose()`
/// 期间访问 defunct Element 的 `MediaQuery` 引发断言崩溃。
@immutable
class ReaderViewportMetrics {
  const ReaderViewportMetrics({
    required this.viewportSize,
    required this.isSpread,
    required this.frameSize,
    required this.halfWidth,
    required this.pageInsets,
    required this.pageWidth,
    required this.pageHeight,
    required this.folioBottom,
    required this.scrollColumnMaxWidth,
    required this.scrollHorizontalPadding,
    required this.textScale,
  });

  final Size viewportSize;
  final bool isSpread;
  final Size frameSize;
  final double halfWidth;
  final EdgeInsets? pageInsets;
  final double pageWidth;
  final double pageHeight;
  final double folioBottom;
  final double scrollColumnMaxWidth;
  final double scrollHorizontalPadding;
  final double textScale;

  /// 双页模式强制偶数页对齐（偶左奇右，对齐样例 `ReaderView.tsx:100`）。
  int alignPageIndex(int index) {
    if (index <= 0) return 0;
    return isSpread ? index - (index % 2) : index;
  }

  static ReaderViewportMetrics resolve({
    required Size viewportSize,
    required ReaderViewSettings settings,
    required double textScale,
    EdgeInsets safePadding = EdgeInsets.zero,
  }) {
    final isPageMode = settings.readingMode == 'page';
    // 对齐样例 `.bookview.mode-flip`：仅 Book (cover) 模式在宽屏 >= 960px 启用双页。
    final isSpread =
        isPageMode &&
        settings.pageTurnMode == 'cover' &&
        viewportSize.width >= 960;

    final frameSize =
        isSpread ? _resolveSpreadFrame(viewportSize) : viewportSize;
    // 中缝为悬浮叠加层，不占用纸页宽度；左右半页各占严格 50%。
    final halfWidth = isSpread ? frameSize.width / 2.0 : frameSize.width;

    final controlLayout = ReaderControlLayout.resolve(
      viewport: viewportSize,
      fontSize: settings.fontSize,
      textScale: textScale,
    );

    final marginScale = switch (settings.marginPreset) {
      'narrow' => 0.80,
      'wide' => 1.25,
      _ => 1.0,
    };
    final scrollMaxW = switch (settings.marginPreset) {
      'narrow' => 820.0,
      'wide' => 620.0,
      _ => 720.0,
    };
    // 窄宽屏统一水平内距：测量 pageWidth 与 Scroll itemBuilder 渲染共用同一字段。
    final scrollHPad =
        viewportSize.width < scrollMaxW
            ? controlLayout.horizontalPadding * marginScale
            : 32.0;

    EdgeInsets? pageInsets;
    if (isSpread) {
      // 样例 `.pg { padding: 7% 9% 8% }`（百分比按包含块宽度 halfWidth 计算）。
      pageInsets = EdgeInsets.only(
        left: halfWidth * 0.09 * marginScale,
        right: halfWidth * 0.09 * marginScale,
        top: halfWidth * 0.07,
        bottom: halfWidth * 0.08,
      );
    } else if (isPageMode && frameSize.width >= 900) {
      final targetCol = scrollMaxW - 40.0;
      final hPad = math.max(24.0, (frameSize.width - targetCol) / 2.0);
      pageInsets = EdgeInsets.only(
        left: hPad,
        right: hPad,
        top: math.max(64.0, frameSize.height * 0.09),
        bottom: math.max(56.0, frameSize.height * 0.09),
      );
    } else if (isPageMode) {
      pageInsets = EdgeInsets.fromLTRB(
        controlLayout.horizontalPadding * marginScale,
        math.max(24.0, safePadding.top + 16),
        controlLayout.horizontalPadding * marginScale,
        math.max(36.0, safePadding.bottom + 24),
      );
    }

    final scrollContentOuterW = math.min(scrollMaxW, viewportSize.width);
    final pageWidth =
        isPageMode
            ? math.max(80.0, halfWidth - (pageInsets?.horizontal ?? 0.0))
            : math.max(80.0, scrollContentOuterW - scrollHPad * 2);

    // 预留 24px 给页脚页码 .folio；buildPageContent 已移除外部 Column 章头，
    // 章节标题统一作为正文首块 HeadingBlock 参与分页测高，杜绝首页裁字。
    final pageHeight = math.max(
      1.0,
      frameSize.height - (pageInsets?.vertical ?? 0.0) - 24.0,
    );

    return ReaderViewportMetrics(
      viewportSize: viewportSize,
      isSpread: isSpread,
      frameSize: frameSize,
      halfWidth: halfWidth,
      pageInsets: pageInsets,
      pageWidth: pageWidth,
      pageHeight: pageHeight,
      folioBottom: isSpread ? frameSize.height * 0.045 : 22.0,
      scrollColumnMaxWidth: scrollMaxW,
      scrollHorizontalPadding: scrollHPad,
      textScale: textScale,
    );
  }

  static Size _resolveSpreadFrame(Size viewport) {
    final maxW = math.max(320.0, viewport.width - 140.0);
    final maxH = math.max(320.0, viewport.height - 128.0);
    final h = math.min(780.0, math.min(maxH, maxW / 1.42));
    return Size(h * 1.42, h);
  }
}
