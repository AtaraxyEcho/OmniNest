import 'package:flutter/foundation.dart';
import 'package:omninest/app/theme/control_tokens.dart';

/// Music Deck 桌面端在不同窗口宽度下使用的布局参数。
@immutable
class MusicDeckDesktopLayout {
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
    final showWidePanel = viewportWidth >= 1780;
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
      navigationWidth: compactNavigation ? 76 : 216,
      widePanelWidth:
          showWidePanel ? (viewportWidth * 0.145).clamp(270.0, 380.0) : 0,
      playerMaxWidth: (viewportWidth * 0.52).clamp(920.0, 1480.0),
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

  double get trailingPanelSpace => showWidePanel ? widePanelWidth + 14 : 0;

  double get mainContentWidth =>
      viewportWidth -
      horizontalPadding * 2 -
      navigationWidth -
      14 -
      trailingPanelSpace;
}
