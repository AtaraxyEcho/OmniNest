import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:omninest/app/appearance/application/composed_scaler.dart';

/// 阅读器控制层的响应式密度。
enum ReaderControlDensity { compact, medium, expanded }

/// 阅读器正文区域在普通模式和沉浸模式下的界面约束。
@immutable
class ReaderChromeLayout {
  const ReaderChromeLayout({
    required this.contentPadding,
    required this.viewportVerticalReserve,
    required this.chapterHeaderReserve,
    required this.showPersistentProgress,
  });

  final EdgeInsets contentPadding;
  final double viewportVerticalReserve;
  final double chapterHeaderReserve;
  final bool showPersistentProgress;

  static ReaderChromeLayout resolve({
    required bool immersiveMode,
    required bool isPageMode,
    EdgeInsets safePadding = EdgeInsets.zero,
  }) {
    if (immersiveMode) {
      return const ReaderChromeLayout(
        contentPadding: EdgeInsets.zero,
        viewportVerticalReserve: 0,
        chapterHeaderReserve: 0,
        showPersistentProgress: false,
      );
    }
    // 阅读页为独立 Scaffold，正文 padding 自行兜底状态栏与手势条 inset。
    return ReaderChromeLayout(
      contentPadding: EdgeInsets.only(
        top: math.max(35, safePadding.top),
        bottom: 16 + safePadding.bottom,
      ),
      viewportVerticalReserve: 51,
      chapterHeaderReserve: 54,
      showPersistentProgress: true,
    );
  }

  /// 滚动模式下正文列表自身的首尾呼吸区。
  ///
  /// 净空取稿子 `.article-column` 的上下 padding：常规态
  /// `clamp(118px, 15vh, 154px)` 与 `164px`（index.css:211），沉浸态
  /// `max(68px, safe-top + 36px)` 与 `max(62px, safe-bottom + 28px)`
  /// （index.css:441-442）。必须放在滚动子项里：外层 [contentPadding] 是
  /// 裁切框，加满 118/164 会让正文可视高度长期少掉 282px，而稿子的留白只
  /// 出现在滚到顶/底的静止位置，中间是内容从玻璃 chrome 下面穿过去。
  /// 外层框架已占掉一部分高度，这里只补差额。
  static EdgeInsets scrollContentInsets({
    required double viewportHeight,
    required EdgeInsets frame,
    required bool immersiveMode,
    EdgeInsets safePadding = EdgeInsets.zero,
  }) {
    final leading =
        immersiveMode
            ? math.max(68.0, safePadding.top + 36)
            : (viewportHeight * 0.15).clamp(118.0, 154.0);
    final trailing =
        immersiveMode ? math.max(62.0, safePadding.bottom + 28) : 164.0;
    return EdgeInsets.only(
      top: math.max(20.0, leading - frame.top),
      bottom: math.max(20.0, trailing - frame.bottom),
    );
  }
}

/// 阅读器根据实际视口计算的布局约束。
@immutable
class ReaderControlLayout {
  static const double returnControlMaxWidth = 360;

  const ReaderControlLayout({
    required this.density,
    required this.isShort,
    required this.horizontalPadding,
    required this.textColumnWidth,
    required this.panelMaxHeight,
  });

  final ReaderControlDensity density;
  final bool isShort;
  final double horizontalPadding;
  final double textColumnWidth;
  final double panelMaxHeight;

  bool get usesSidePanel =>
      density == ReaderControlDensity.expanded && !isShort;

  double get panelWidth => density == ReaderControlDensity.expanded ? 400 : 360;

  double get contentFrameWidth => textColumnWidth + horizontalPadding * 2;

  /// 按视口、字体大小和系统文字缩放计算稳定阅读列。
  static ReaderControlLayout resolve({
    required Size viewport,
    required double fontSize,
    double textScale = 1,
  }) {
    final density = switch (viewport.width) {
      < 600 => ReaderControlDensity.compact,
      < 1000 => ReaderControlDensity.medium,
      _ => ReaderControlDensity.expanded,
    };
    // 左右边距按稿子的 `.article-column` padding 连续取值：
    // clamp(24px, 7.2vw, 54px)（index.css:211，全局 box-sizing: border-box）。
    // 原来是 18/32/44 三档密度表，手机宽度上比稿子窄 10px 左右。
    final horizontalPadding = (viewport.width * 0.072).clamp(24.0, 54.0);
    final scaledFont = fontSize * textScale.clamp(1.0, ComposedScaler.maxScale);
    // 正文列宽按行长定标，不是按视口比例：CJK 正文的最优行长是 22-37 字
    // （对应拉丁 45-75 字符），30 字是稿子 `.article-column` 的收敛值：
    // width min(100%, 680px) 减 padding clamp(24px, 7.2vw, 54px) 两侧 = 572px
    // （index.css:208/211）。30em 在 19px 下即 570px；上下界让字号推到 26-28px
    // 时行长仍留在带内。视口 ≤680 时 available 是瓶颈，手机侧与稿子逐像素相等。
    final preferredTextWidth = (scaledFont * 30).clamp(480.0, 660.0);
    final availableTextWidth = math.max(
      80.0,
      viewport.width - horizontalPadding * 2,
    );
    final textColumnWidth = math.min(preferredTextWidth, availableTextWidth);
    final isShort = viewport.height < 480;
    final panelRatio = isShort ? 0.92 : 0.82;

    return ReaderControlLayout(
      density: density,
      isShort: isShort,
      horizontalPadding: horizontalPadding,
      textColumnWidth: textColumnWidth,
      panelMaxHeight: math.min(viewport.height * panelRatio, 680),
    );
  }
}
