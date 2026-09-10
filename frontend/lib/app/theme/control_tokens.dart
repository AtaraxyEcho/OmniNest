import 'package:flutter/foundation.dart';

/// 桌面/Web 与移动端共用的控件尺寸令牌。
///
/// 业务侧禁止散落硬编码控件高度；按钮、输入框、下拉、菜单项、图标按钮
/// 统一从这里取值，保证筛选栏中下拉与相邻按钮视觉等高。
abstract final class AppControlTokens {
  static bool get isDesktopDensity =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;

  /// 主按钮 / 描边按钮最小高度。
  static double get buttonHeight => isDesktopDensity ? 36 : 44;

  /// 输入框、下拉闭合态目标高度（不含浮动标签额外空间）。
  static double get fieldHeight => isDesktopDensity ? 36 : 44;

  /// 下拉菜单项高度。
  static double get menuItemHeight => isDesktopDensity ? 34 : 44;

  /// 图标按钮方形最小边长。
  static double get iconButtonSize => isDesktopDensity ? 36 : 40;

  /// 输入框水平内边距。
  static double get fieldHorizontalPadding => isDesktopDensity ? 12 : 14;

  /// 输入框垂直内边距。
  static double get fieldVerticalPadding => isDesktopDensity ? 8 : 12;

  /// 紧凑筛选下拉内边距（与按钮内容区对齐）。
  static double get denseFieldHorizontalPadding => isDesktopDensity ? 10 : 12;

  /// 紧凑筛选下拉垂直内边距。
  static double get denseFieldVerticalPadding => isDesktopDensity ? 8 : 12;

  /// 筛选栏带标签下拉默认宽度。
  static double get filterFieldWidth => isDesktopDensity ? 200 : 220;

  /// 筛选栏无标签短下拉默认宽度。
  static double get filterFieldCompactWidth => isDesktopDensity ? 148 : 168;

  /// 筛选栏搜索框默认宽度。
  static double get searchFieldWidth => isDesktopDensity ? 220 : 240;

  /// 输入框前缀图标占位宽度（搜索等）。
  static double get fieldPrefixIconWidth => isDesktopDensity ? 32 : 36;

  /// 下拉箭头占位宽度。
  static double get fieldSuffixIconWidth => isDesktopDensity ? 28 : 32;

  /// 菜单 / 字段圆角。
  static const double controlRadius = 8;

  /// 菜单面板圆角。
  static const double menuRadius = 12;
}
