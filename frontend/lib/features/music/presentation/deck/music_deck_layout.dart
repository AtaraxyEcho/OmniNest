import 'package:flutter/foundation.dart';
import 'package:omninest/app/theme/control_tokens.dart';

/// Music Deck 桌面端在不同窗口宽度下使用的布局参数。
@immutable
class MusicDeckDesktopLayout {
  /// 宽屏左右两张侧卡（导航/正在播放）的统一宽度与卡片间间距。
  static const double sideCardWidth = 264;
  static const double cardGap = 20;

  /// 播放岛在超宽屏上的收束上限；常态下岛与中内容列同宽，不再按比例收缩。
  static const double islandMaxWidth = 1480;

  const MusicDeckDesktopLayout({
    required this.viewportWidth,
    required this.compactNavigation,
    required this.showWidePanel,
    required this.horizontalPadding,
    required this.navigationWidth,
    required this.widePanelWidth,
    required this.playerMaxWidth,
    required this.searchMaxWidth,
  });

  factory MusicDeckDesktopLayout.resolve(double viewportWidth) {
    final compactNavigation = viewportWidth < 1050;
    // 阈值须覆盖 Windows 高 DPI 缩放下的最大化逻辑宽度（如 4K@250% = 1536），
    // 与 Web 端 1920 视口行为保持一致；此前 1780 会漏掉该档导致两端不一致。
    final showWidePanel = viewportWidth >= 1500;
    final horizontalPadding =
        viewportWidth >= 2560
            ? 44.0
            : viewportWidth >= 1600
            ? 30.0
            : 20.0;
    final availableWidth = viewportWidth - horizontalPadding * 2;
    return MusicDeckDesktopLayout(
      viewportWidth: viewportWidth,
      compactNavigation: compactNavigation,
      showWidePanel: showWidePanel,
      horizontalPadding: horizontalPadding,
      navigationWidth: compactNavigation ? 76 : sideCardWidth,
      widePanelWidth: showWidePanel ? sideCardWidth : 0,
      playerMaxWidth: islandMaxWidth,
      // 搜索框与其他模块顶栏搜索对齐:上限取统一搜索框令牌宽,不再随视口放大。
      searchMaxWidth: (availableWidth * 0.14).clamp(
        AppControlTokens.searchFieldWidth * 0.8,
        AppControlTokens.searchFieldWidth,
      ),
    );
  }

  final double viewportWidth;
  final bool compactNavigation;
  final bool showWidePanel;
  final double horizontalPadding;
  final double navigationWidth;
  final double widePanelWidth;
  final double playerMaxWidth;
  final double searchMaxWidth;

  double get trailingPanelSpace => showWidePanel ? widePanelWidth + cardGap : 0;

  double get mainContentWidth =>
      viewportWidth -
      horizontalPadding * 2 -
      navigationWidth -
      14 -
      trailingPanelSpace;
}
