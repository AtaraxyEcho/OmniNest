import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/widgets.dart' show BuildContext, MediaQuery;

import 'package:omninest/app/theme/mobile_layout_tokens.dart';
import 'package:omninest/core/widgets/responsive_breakpoints.dart';

/// Portal 移动形态在平板三档下的舞台与列数派生值。
///
/// 对应设计基准 index.css：
/// - `(min-width: 600px) and (max-width: 979.9px)`：`.content-scroll` 与
///   `.app-header` 收成 720 居中（sheet 限宽由天气面板自身承担）。
/// - `(min-width: 720px)`：`.app-frame` 限宽 760、`.home-stage` 页边距 40、
///   `.content-scroll` 页边距 34。
/// - `(min-width: 980px)`：Home 转 `.home-stage` 双栏（1.1fr / .9fr，
///   下行跨两列），大时钟 130、最近条 150 高、动作行收 420。
///
/// 窄于 600 时逐项等于既有手机值，手机档渲染不受影响。壳层的
/// `.tablet-rail`/`.bottom-nav` 切换不归本模块，这里只保证内容在
/// 三档内限宽正确、不越界。
@immutable
class PortalMobileTier {
  const PortalMobileTier({
    required this.width,
    required this.stageMaxWidth,
    required this.contentMaxWidth,
    required this.homeHorizontalPadding,
    required this.contentHorizontalPadding,
    required this.twoColumnHome,
    required this.recentTileHeight,
    required this.heroTimeMaxFontSize,
    required this.quickLineMaxWidth,
  });

  /// 判定用的逻辑宽度。
  final double width;

  /// 舞台（原型 `.app-frame`）最大宽度；null 表示铺满。
  final double? stageMaxWidth;

  /// 内容列（原型 `.content-scroll`）最大宽度；null 表示铺满。
  final double? contentMaxWidth;

  /// Home（原型 `.home-stage`）左右页边距。
  final double homeHorizontalPadding;

  /// 内容页（原型 `.content-scroll`）左右页边距。
  final double contentHorizontalPadding;

  /// 是否进入 Home 双栏档。
  final bool twoColumnHome;

  /// 最近动态瓦片高度（136 / 150）。
  final double recentTileHeight;

  /// 大时钟字号上限（108 / 130）。
  final double heroTimeMaxFontSize;

  /// 高频动作行限宽（原型 `.quick-line` ≥980 收 420）；null 表示铺满。
  final double? quickLineMaxWidth;

  /// 按当前视口宽度解析档位。
  static PortalMobileTier resolve(BuildContext context) {
    return resolveWidth(MediaQuery.sizeOf(context).width);
  }

  /// 按给定宽度解析档位；与 Widget 树无关，便于 LayoutBuilder 复用。
  static PortalMobileTier resolveWidth(double width) {
    if (width >= ResponsiveBreakpoints.tabletRail) {
      return PortalMobileTier(
        width: width,
        // ≥980 原型把 `.app-frame` 放开到 none，舞台宽度由壳层侧栏轨
        // 约束；本模块沿用 `.app-frame` 基线 1180 作为上限，避免超宽
        // 平板把双栏拉散。
        stageMaxWidth: ResponsiveBreakpoints.appFrameBaseMaxWidth,
        contentMaxWidth: null,
        homeHorizontalPadding: ResponsiveBreakpoints.homeHorizontalPadding,
        contentHorizontalPadding:
            ResponsiveBreakpoints.contentHorizontalPadding,
        twoColumnHome: true,
        recentTileHeight: 150,
        heroTimeMaxFontSize: 130,
        quickLineMaxWidth: 420,
      );
    }
    if (width >= ResponsiveBreakpoints.stageFrame) {
      return PortalMobileTier(
        width: width,
        stageMaxWidth: ResponsiveBreakpoints.stageFrameMaxWidth,
        contentMaxWidth: ResponsiveBreakpoints.contentRailMaxWidth,
        homeHorizontalPadding: ResponsiveBreakpoints.homeHorizontalPadding,
        contentHorizontalPadding:
            ResponsiveBreakpoints.contentHorizontalPadding,
        twoColumnHome: false,
        recentTileHeight: 136,
        heroTimeMaxFontSize: 108,
        quickLineMaxWidth: null,
      );
    }
    if (width >= ResponsiveBreakpoints.mobile) {
      return PortalMobileTier(
        width: width,
        stageMaxWidth: null,
        contentMaxWidth: ResponsiveBreakpoints.contentRailMaxWidth,
        homeHorizontalPadding: MobileLayoutTokens.tabletHorizontalPadding,
        contentHorizontalPadding: MobileLayoutTokens.tabletHorizontalPadding,
        twoColumnHome: false,
        recentTileHeight: 136,
        heroTimeMaxFontSize: 108,
        quickLineMaxWidth: null,
      );
    }
    return PortalMobileTier(
      width: width,
      stageMaxWidth: null,
      contentMaxWidth: null,
      homeHorizontalPadding: MobileLayoutTokens.horizontalPadding,
      contentHorizontalPadding: MobileLayoutTokens.horizontalPadding,
      twoColumnHome: false,
      recentTileHeight: 136,
      heroTimeMaxFontSize: 108,
      quickLineMaxWidth: null,
    );
  }
}
