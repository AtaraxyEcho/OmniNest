import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

/// 视口快照（方案 §8）：一次事务期间冻结的完整布局上下文。
///
/// pageWidth / textScale / viewport / safeArea / settings 都可能改变
/// Geometry 语义，因此不能只冻结 anchorY；contentY = scrollOffset +
/// anchorY 在整个事务期间使用同一基准，窗口尺寸、沉浸式与 SafeArea
/// 变化不得在中途改变该换算。
@immutable
class ReaderViewportSnapshot {
  const ReaderViewportSnapshot({
    required this.viewportSize,
    required this.anchorY,
    required this.contentWidth,
    required this.textScale,
    required this.safeAreaTop,
    required this.safeAreaBottom,
  });

  final Size viewportSize;

  /// 视口锚线在窗口内的 Y：contentY = scrollOffset + anchorY。
  final double anchorY;

  /// 正文排版宽度（列宽），排版几何的横向基准。
  final double contentWidth;

  /// 生效的文字缩放。
  final double textScale;

  final double safeAreaTop;

  final double safeAreaBottom;

  @override
  bool operator ==(Object other) =>
      other is ReaderViewportSnapshot &&
      other.viewportSize == viewportSize &&
      other.anchorY == anchorY &&
      other.contentWidth == contentWidth &&
      other.textScale == textScale &&
      other.safeAreaTop == safeAreaTop &&
      other.safeAreaBottom == safeAreaBottom;

  @override
  int get hashCode => Object.hash(
    viewportSize,
    anchorY,
    contentWidth,
    textScale,
    safeAreaTop,
    safeAreaBottom,
  );

  @override
  String toString() =>
      'ReaderViewportSnapshot(${viewportSize.width.toStringAsFixed(0)}x'
      '${viewportSize.height.toStringAsFixed(0)}, anchorY='
      '${anchorY.toStringAsFixed(1)})';
}
