import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 漫画内容区域的响应式布局结果。
class ComicReaderLayout {
  const ComicReaderLayout({
    required this.contentWidth,
    required this.horizontalPadding,
    required this.pagedPadding,
  });

  final double contentWidth;
  final double horizontalPadding;
  final EdgeInsets pagedPadding;

  /// 根据窗口宽度和用户偏好计算实际页面宽度。
  static ComicReaderLayout resolve({
    required Size viewport,
    required double preferredContentWidth,
    required bool fullWidth,
  }) {
    final width = math.max(1.0, viewport.width);
    final horizontalPadding = switch (width) {
      < 600 => 0.0,
      < 1000 => 20.0,
      _ => 40.0,
    };
    final availableWidth = math.max(1.0, width - horizontalPadding * 2);
    final contentWidth =
        fullWidth
            ? availableWidth
            : math.min(availableWidth, preferredContentWidth);
    final pagedInset = switch (width) {
      < 600 => 8.0,
      < 1000 => 20.0,
      _ => 32.0,
    };
    return ComicReaderLayout(
      contentWidth: contentWidth,
      horizontalPadding: horizontalPadding,
      pagedPadding: EdgeInsets.all(pagedInset),
    );
  }
}
