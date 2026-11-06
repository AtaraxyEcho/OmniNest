import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

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

  /// 主按钮 / 描边按钮统一内容内边距。
  ///
  /// Filled 与 Outlined 必须共用同一组水平/垂直内边距，避免同类操作按钮
  /// 因样式分支出现高度与视觉密度漂移。
  static const EdgeInsets buttonPadding = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 10,
  );

  /// 带图标操作按钮的图标边长。
  static const double buttonIconSize = 18;

  /// 纯图标按钮内图标边长。
  static const double iconButtonIconSize = 20;

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

  /// 卡片 / 面板圆角：比控件大一档，形成「控件 < 卡片 < 对话框」的层级。
  static const double cardRadius = 12;

  /// 对话框 / 抽屉面板圆角。
  static const double dialogRadius = 14;

  /// 胶囊圆角：只用于开关轨道、标签与头像，容器不使用。
  static const double pillRadius = 999;

  /// 复选框圆角：比控件小一档，避免小尺寸控件被圆角吃掉轮廓。
  static const double checkboxRadius = 4;

  /// 工具栏 / 表单最小间距（图标与文字之间）。
  static const double gapXs = 4;

  /// 同组紧凑控件间距（相邻按钮）。
  static const double gapSm = 8;

  /// 同组工具栏控件标准间距（搜索框与筛选器）。
  static const double gapMd = 12;

  /// 分组之间间距（筛选区与列表之间）。
  static const double gapLg = 16;

  /// 区块之间间距（面板与面板之间）。
  static const double gapXl = 24;

  /// 桌面模块侧栏展开宽度。
  static const double sidebarWidth = 256;

  /// 桌面模块侧栏折叠宽度（仅图标）。
  static const double sidebarCollapsedWidth = 56;

  /// 侧栏品牌 Logo 边长。
  static const double sidebarLogoSize = 36;

  /// 侧栏品牌 Logo 圆角。
  static const double sidebarLogoRadius = 10;
}
