import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/widgets.dart' show BuildContext, MediaQuery;

import 'package:omninest/app/theme/mobile_layout_tokens.dart';
import 'package:omninest/core/widgets/responsive_breakpoints.dart';

/// Library 媒体空间在平板三档下的几何派生值。
///
/// 逐值取自设计基准 index.css：`(min-width: 600px)` 只切换目录列数与
/// sheet 限宽（不改变本空间的卡片尺寸），`(min-width: 720px)` 收紧舞台
/// 限宽并放大 `.library-feature`/`.poster`/`.album`/`.photo-mosaic`，
/// `(min-width: 980px)` 再抬一档横幅与马赛克行高，并把内容主栏从
/// `.module-overlay > main` 的 650 放到 760。
///
/// 窄于 600 时逐项等于既有手机值，手机档渲染不受影响。
@immutable
class LibrarySpaceTier {
  const LibrarySpaceTier({
    required this.width,
    required this.contentMaxWidth,
    required this.horizontalPadding,
    required this.featureHeight,
    required this.mosaicRowHeight,
    required this.posterWidth,
    required this.posterHeight,
    required this.albumSize,
  });

  /// 判定用的逻辑宽度（不含设备像素比）。
  final double width;

  /// 内容主栏限宽：650 基线，≥980 抬到 760。
  final double contentMaxWidth;

  /// 内容左右页边距：手机 16、平板 24。
  ///
  /// Library 空间对应原型 `.module-overlay > main`（基线内衬 20，随壳层
  /// 令牌取 16/24），三档只改限宽与轨道尺寸，页边距不参与放大；
  /// 内容页 34/40 页边距是 Portal 的 `.content-scroll`/`.home-stage`。
  final double horizontalPadding;

  /// 原型 `.library-feature` 高度（300 / 370 / 420）。
  final double featureHeight;

  /// 原型 `.photo-mosaic` 单行高度（88 / 120 / 140）；总高为两倍行高加 5 间隙。
  final double mosaicRowHeight;

  /// 原型 `.poster` 基准宽（136 / 165）。
  final double posterWidth;

  /// 原型 `.poster > div` 高度（187 / 220）。
  final double posterHeight;

  /// 原型 `.album` 方形封面边长（145 / 168）。
  final double albumSize;

  /// 马赛克总高：两行加 5px 间隙（原型 grid gap）。
  double get mosaicHeight => mosaicRowHeight * 2 + 5;

  /// 海报轨的媒体高度。
  double get posterMediaHeight => posterHeight;

  /// 专辑轨的媒体高度（方形封面）。
  double get albumMediaHeight => albumSize;

  /// 按当前视口宽度解析档位。
  static LibrarySpaceTier resolve(BuildContext context) {
    return resolveWidth(MediaQuery.sizeOf(context).width);
  }

  /// 按给定宽度解析档位；与 Widget 树无关，便于测试与 LayoutBuilder 复用。
  static LibrarySpaceTier resolveWidth(double width) {
    if (width >= ResponsiveBreakpoints.tabletRail) {
      return LibrarySpaceTier(
        width: width,
        contentMaxWidth: ResponsiveBreakpoints.moduleMainWideMaxWidth,
        horizontalPadding: MobileLayoutTokens.tabletHorizontalPadding,
        featureHeight: 420,
        mosaicRowHeight: 140,
        posterWidth: 165,
        posterHeight: 220,
        albumSize: 168,
      );
    }
    if (width >= ResponsiveBreakpoints.stageFrame) {
      // 720-979 档：轨道已放大，但内容主栏沿用 650 基线——该档的
      // `.app-frame` 限宽 760 大于内容栏，不构成额外约束。
      return LibrarySpaceTier(
        width: width,
        contentMaxWidth: ResponsiveBreakpoints.moduleMainMaxWidth,
        horizontalPadding: MobileLayoutTokens.tabletHorizontalPadding,
        featureHeight: 370,
        mosaicRowHeight: 120,
        posterWidth: 165,
        posterHeight: 220,
        albumSize: 168,
      );
    }
    if (width >= ResponsiveBreakpoints.mobile) {
      return LibrarySpaceTier(
        width: width,
        contentMaxWidth: ResponsiveBreakpoints.moduleMainMaxWidth,
        horizontalPadding: MobileLayoutTokens.tabletHorizontalPadding,
        featureHeight: 300,
        mosaicRowHeight: 88,
        posterWidth: 136,
        posterHeight: 187,
        albumSize: 145,
      );
    }
    return LibrarySpaceTier(
      width: width,
      contentMaxWidth: ResponsiveBreakpoints.moduleMainMaxWidth,
      horizontalPadding: MobileLayoutTokens.horizontalPadding,
      featureHeight: 300,
      mosaicRowHeight: 88,
      posterWidth: 136,
      posterHeight: 187,
      albumSize: 145,
    );
  }
}

/// 轨道行高：图块固定高 + 文案块随无障碍字号放大（文案基准 45）。
///
/// 稿子的微型字号不放大（签名密度），因此大字号下由容器自撑，
/// 1.0x 时与稿子原值一致（145+45=190、187+45=232）。
double libraryRailHeightFor(BuildContext context, double mediaHeight) {
  return mediaHeight + MobileLayoutTokens.scaleHeight(context, 45);
}

/// 海报轨总高（`.poster > div` 随档位 187/220）。
double libraryPosterRailHeight(BuildContext context) {
  return libraryRailHeightFor(
    context,
    LibrarySpaceTier.resolve(context).posterMediaHeight,
  );
}

/// 专辑轨总高（`.album > span` 随档位 145/168）。
double libraryAlbumRailHeight(BuildContext context) {
  return libraryRailHeightFor(
    context,
    LibrarySpaceTier.resolve(context).albumMediaHeight,
  );
}
