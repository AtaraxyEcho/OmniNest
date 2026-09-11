import 'dart:math' as math;

import 'package:flutter/material.dart';

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

  /// 连续滚动阅读位置换算的视口锚点 Y（窗口 contentY = 滚动 offset + 此值）。
  ///
  /// 页面与滚动视图必须共用本实现；两处公式漂移会造成读写位置天然错位。
  static double anchorViewportY({
    required Size viewportSize,
    required bool immersiveMode,
    required double topInset,
  }) {
    final chrome = resolve(immersiveMode: immersiveMode, isPageMode: false);
    return (viewportSize.height - topInset - chrome.viewportVerticalReserve) *
        0.25;
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
    final horizontalPadding = switch (density) {
      ReaderControlDensity.compact => 18.0,
      ReaderControlDensity.medium => 32.0,
      ReaderControlDensity.expanded => 44.0,
    };
    final scaledFont = fontSize * textScale.clamp(1.0, 1.6);
    final preferredTextWidth = (scaledFont * 40).clamp(560.0, 820.0);
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
