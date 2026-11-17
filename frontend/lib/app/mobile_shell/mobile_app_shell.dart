import 'dart:ui' show ImageFilter;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/mobile_shell/mobile_account_sheet.dart';
import 'package:omninest/app/mobile_shell/mobile_environment_scope.dart';
import 'package:omninest/app/mobile_shell/mobile_navigation_config.dart';
import 'package:omninest/app/mobile_shell/mobile_shell_feature_bindings.dart';
import 'package:omninest/app/mobile_shell/mobile_shell_form.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/app/theme/mobile_app_theme.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/app/theme/mobile_layout_tokens.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/mobile_status_kit.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/widgets/module_switch_transition.dart';
import 'package:omninest/core/widgets/omni_icons.dart';
import 'package:omninest/features/backdrop/backdrop_ui.dart';
import 'package:omninest/features/music/music_shell_ui.dart';

/// 移动平台及紧凑视口使用的应用级导航壳层。
///
/// 一级信息架构为四个空间：Home、Library、Reader、Files；音乐、照片、
/// 影视由 Library 直达并以全屏模块页承载。壳层 chrome 直接呈现在全局
/// 环境上：顶栏无背景，底栏为浮动玻璃胶囊，配色固定取自设计原型。
class MobileAppShell extends ConsumerStatefulWidget {
  const MobileAppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<MobileAppShell> createState() => _MobileAppShellState();
}

class _MobileAppShellState extends ConsumerState<MobileAppShell> {
  late int _previousBranch;
  bool _transitionForward = true;

  @override
  void initState() {
    super.initState();
    _previousBranch = widget.navigationShell.currentIndex;
  }

  @override
  void didUpdateWidget(covariant MobileAppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final branch = widget.navigationShell.currentIndex;
    if (branch == _previousBranch) {
      return;
    }
    _transitionForward = branch > _previousBranch;
    _previousBranch = branch;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (!shouldUseResponsiveMobileShell(
      mobilePlatform: isMobilePlatform,
      width: width,
    )) {
      return MobileShellScope(hosted: false, child: _moduleContent());
    }
    final branch = widget.navigationShell.currentIndex;
    final selectionActive = ref.watch(
      mobileShellSelectionActiveProvider(branch),
    );
    // 子页态（如 Files 的最近使用/我的收藏/与我共享）由页面自带
    // 90 高页头，壳层顶栏与底部 tab 让位；离线横幅不在此列，它只在壳层出一次。
    final subpageActive = ref.watch(mobileShellSubpageActiveProvider(branch));
    final offline = ref.watch(appOnlineStatusProvider).asData?.value == false;
    final backdropActive = ref.watch(mobileShellLocalBackdropActiveProvider);
    // 极性在这里决定并注册：外观设置就是极性源，壁纸不参与判定。
    // 壳层之下的所有面都已接进极性表，未注册时 MobileEnvPalette.of 仍取暗基准。
    final baseTheme = Theme.of(context);
    final envPalette = mobileEnvPaletteFor(baseTheme);
    final shellTheme = (envPalette.brightness == Brightness.light
            ? MobileAppTheme.resolve(baseTheme)
            : baseTheme)
        .withEnvPalette(envPalette);
    final content = Theme(
      data: shellTheme,
      child: MobileShellScope(
        hosted: true,
        child: Scaffold(
          backgroundColor:
              backdropActive ? Colors.transparent : envPalette.stage,
          // 平板与手机统一底部导航（浮动胶囊 tab 组限宽居中），不再切换
          // 左侧 rail：触屏可达性与三端一致性优先于 M3 导航规范。
          body: _buildBottomNavigationLayout(
            context,
            selectionActive: selectionActive,
            subpageActive: subpageActive,
            offline: offline,
          ),
        ),
      ),
    );
    return AppBackdropSceneScope(
      owner: 'app.mobile.shell',
      policy: MobileNavigationConfig.backdropPolicyForBranch(branch),
      child: content,
    );
  }

  Widget _buildBottomNavigationLayout(
    BuildContext context, {
    required bool selectionActive,
    required bool subpageActive,
    required bool offline,
  }) {
    return Column(
      children: [
        if (!subpageActive)
          _MobileTopBar(branch: widget.navigationShell.currentIndex),
        if (offline)
          _MobileSystemBanner(branch: widget.navigationShell.currentIndex),
        Expanded(child: _moduleContent()),
        if (!selectionActive && !subpageActive) ...[
          MusicMobileMiniPlayerSlot(onOpenPlayer: _openNowPlaying),
          _MobileBottomNavigation(
            branch: widget.navigationShell.currentIndex,
            selectedIndex: _destinationIndex,
            onSelected: _selectDestination,
          ),
        ],
      ],
    );
  }

  int get _destinationIndex {
    return MobileNavigationConfig.destinationIndexForBranch(
      widget.navigationShell.currentIndex,
    );
  }

  Widget _moduleContent() {
    return ModuleSwitchTransition(
      transitionKey: widget.navigationShell.currentIndex,
      forward: _transitionForward,
      child: widget.navigationShell,
    );
  }

  void _selectDestination(int index) {
    final branch = MobileNavigationConfig.branchForDestination(index);
    widget.navigationShell.goBranch(
      branch,
      initialLocation: branch == widget.navigationShell.currentIndex,
    );
  }

  void _openNowPlaying() {
    context.push('/music/now-playing');
  }
}

/// 顶栏：无背景，直接呈现在环境上；首页仅品牌标记，其余空间标题+副题。
class _MobileTopBar extends ConsumerWidget {
  const _MobileTopBar({required this.branch});

  final int branch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isHome = branch == MobileNavigationConfig.portalBranch;
    final title = _title(l10n);
    final subtitle = _subtitle(l10n);
    return SafeArea(
      bottom: false,
      child: SizedBox(
        // 原型 .app-header 总高 84（含上内衬 max(20, safe-area)）；SafeArea
        // 已给出状态栏避让，基准内容带高度取 64。微型字号是设计签名不随
        // 无障碍字号放大，容器自撑：1.6x 下标题 35.2 + 副题 24.6 + 底内衬
        // 8 超过 64，按字号倍率同步抬高内容带。
        height: MobileLayoutTokens.scaleHeight(context, 64),
        child: Center(
          // 壳层 chrome 统一按 720 限宽居中：样例在 600 以上收拢 .app-header，
          // 而本应用宽档不切换左侧 rail，顶栏、tab 组与托管内容列必须同宽，
          // 否则宽屏顶行会坐到内容列之外。窄屏时该上限不产生约束。
          child: ConstrainedBox(
            key: const ValueKey('omninest.mobile.top-bar'),
            constraints: const BoxConstraints(
              maxWidth: MobileLayoutTokens.chromeMaxWidth,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  // 移动端顶栏不设品牌位：品牌标记是 512px 插画，缩到 48 后细节
                  // 糊成色带，且与右侧账户头像构成「两个人像」的语义撞车。桌面
                  // 顶栏保留标记（那里有更大字号档与更长的横向空间），移动端
                  // 退为纯 chrome，让首页的居中大时钟成为唯一视觉中心。
                  if (!isHome) ...[
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.env.ink,
                              // ignore: font_size_whitelist
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.4,
                              height: 1.1,
                            ),
                          ),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.env.inkMuted,
                              fontSize: 11,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else
                    const Spacer(),
                  _GlassCircleButton(
                    tooltip: l10n.searchTitle,
                    icon: OmniIcons.search,
                    iconSize: 20,
                    onTap:
                        // 所有空间的搜索统一进全局覆盖层：覆盖层按内容档过滤，
                        // 并在页内自持查询状态，模块不再各自维护页内搜索条。
                        () => unawaited(context.push('/search')),
                  ),
                  const SizedBox(width: 4),
                  const MobileAccountAvatar(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _title(AppLocalizations l10n) {
    return switch (branch) {
      MobileNavigationConfig.libraryBranch => l10n.mobileNavLibrary,
      MobileNavigationConfig.readerBranch => l10n.mobileNavReader,
      _ => l10n.mobileNavFiles,
    };
  }

  String _subtitle(AppLocalizations l10n) {
    return switch (branch) {
      MobileNavigationConfig.libraryBranch => l10n.mobileSpaceLibrarySubtitle,
      MobileNavigationConfig.readerBranch => l10n.mobileSpaceReaderSubtitle,
      _ => l10n.mobileSpaceFilesSubtitle,
    };
  }
}

class _MobileSystemBanner extends StatelessWidget {
  const _MobileSystemBanner({required this.branch});

  final int branch;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 原型 .offline-banner 是内容流内的琥珀条件条，全壳层仅此一条，
    // 模块页不再重复渲染离线提示。宽度随内容列上限，不铺满整个视口。
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: MobileLayoutTokens.chromeMaxWidth,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: MobileLayoutTokens.horizontalPadding,
          ),
          child: MobileOfflineBanner(message: l10n.mobileOfflineBanner),
        ),
      ),
    );
  }
}

/// 浮动胶囊底栏：环境玻璃面板 + 选中胶囊高亮（几何取自原型）。
class _MobileBottomNavigation extends ConsumerWidget {
  const _MobileBottomNavigation({
    required this.branch,
    required this.selectedIndex,
    required this.onSelected,
  });

  final int branch;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final destinations = _destinations(AppLocalizations.of(context));
    // 原型底边距为 max(12, safe-area inset)：不叠加 SafeArea，直接取
    // 较大值，保证带手势条设备与无插图设备一致。
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final bottomPadding = bottomInset > 12 ? bottomInset : 12.0;
    // 分档取布局宽度：限宽只作用于本层实际可用宽度，测试与真机都在同一
    // 坐标系判定，避免 MediaQuery 与渲染宽度在多视图缩放下分叉。
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // 原型 600-979 档：.bottom-nav 收为 min(460px, 100%-24px) 居中（外层
        // 12 留边已实现 100%-24px，这里再限宽 460）；其余档保持壳层 720 限宽。
        final tabGroupMaxWidth =
            width >= 600 && width < 980
                ? 460.0
                : MobileLayoutTokens.chromeMaxWidth;
        return Padding(
          padding: EdgeInsets.fromLTRB(12, 0, 12, bottomPadding),
          child: Center(
            child: ConstrainedBox(
              key: const ValueKey('omninest.mobile.bottom-nav'),
              constraints: BoxConstraints(maxWidth: tabGroupMaxWidth),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // 滑块层要按"整条带"算槽位，Positioned 又必须是 Stack 的
                  // 直接子级，因此带宽在这里量一次再传进去。
                  final bandWidth =
                      constraints.maxWidth - _navHorizontalPadding * 2;
                  return DecoratedBox(
                    // 投影留在裁切之外，模糊与描边在裁切之内；样例 `.bottom-nav`
                    // 两态都带 backdrop-filter，浅态只是把底色换成半透明白。
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(23),
                      boxShadow: [
                        BoxShadow(
                          color: context.env.elevShadow,
                          blurRadius: 35,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(23),
                      child: MobileEnvBlur(
                        sigma: 28,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: context.env.navGlass,
                            border: Border.all(color: context.env.line12),
                          ),
                          child: SizedBox(
                            height: _navBarHeight,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: _navHorizontalPadding,
                                vertical: _navVerticalPadding,
                              ),
                              child: Stack(
                                children: [
                                  // 选中胶囊是单层滑块：横向按等宽槽位居中，竖向
                                  // 复刻目的地列的整组居中（图标带 + 间隙 + 单行
                                  // 标签），因此滑块与图标带同心且槽位几何不变。
                                  AnimatedPositioned(
                                    key: const ValueKey(
                                      'omninest.mobile.bottom-nav-pill',
                                    ),
                                    duration: MotionToken.reduced(
                                      context,
                                      MobileLayoutTokens.stateDuration,
                                    ),
                                    curve: MobileLayoutTokens.motionCurve,
                                    left: _navPillLeft(
                                      bandWidth: bandWidth,
                                      selectedIndex: selectedIndex,
                                      slotCount: destinations.length,
                                    ),
                                    top: _navPillTop(context),
                                    width: _navPillWidth,
                                    height: _navPillHeight,
                                    child: const IgnorePointer(
                                      child: _MobileBottomPill(),
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      for (
                                        var index = 0;
                                        index < destinations.length;
                                        index++
                                      )
                                        Expanded(
                                          child: _MobileBottomDestination(
                                            destination: destinations[index],
                                            selected: selectedIndex == index,
                                            onTap: () => onSelected(index),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MobileBottomDestination extends StatelessWidget {
  const _MobileBottomDestination({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _MobileDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: destination.label,
      child: MobilePressable(
        semanticLabel: destination.label,
        onTap: onTap,
        child: SizedBox.expand(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 原型 `.bottom-nav button > span` 是 min-width:48 + height:30。
              // 选中底色与投影归底栏的单层滑块，这里只保留同尺寸的图标带，
              // 使槽位几何与改造前逐字节一致。
              SizedBox(
                width: _navPillWidth,
                height: _navPillHeight,
                child: Center(
                  child: OmniIcon(
                    icon: destination.icon,
                    size: 20,
                    color:
                        selected ? context.env.onAccent : context.env.white46,
                  ),
                ),
              ),
              const SizedBox(height: _navItemGap),
              Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _navLabelStyle(
                  ink: selected ? context.env.ink : context.env.white46,
                  bold: selected,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 底栏几何：目的地列与滑块层共用同一组常量，避免两处各算一遍居中。
const double _navBarHeight = 70;
const double _navHorizontalPadding = 6;
const double _navVerticalPadding = 5;
const double _navPillWidth = 48;
const double _navPillHeight = 30;
const double _navItemGap = 3;
const double _navLabelSize = 9;
const double _navLabelHeightFactor = 1.2;

/// 图标带所在的高度：底栏高减去上下内衬。
const double _navBandHeight = _navBarHeight - _navVerticalPadding * 2;

/// 滑块横向位置：等宽槽位的中心减去胶囊半宽。
double _navPillLeft({
  required double bandWidth,
  required int selectedIndex,
  required int slotCount,
}) {
  final slotWidth = bandWidth / slotCount;
  return slotWidth * (selectedIndex + 0.5) - _navPillWidth / 2;
}

/// 滑块竖向位置。
///
/// 目的地列是"图标带 + 间隙 + 单行标签"整组居中，图标带顶边因此落在
/// (带高 − 整组高) / 2；标签行高用同一份样式实测，而不是按字号乘行高系数
/// 手算——手算会留下亚像素差，滑块与图标带就不同心了。
double _navPillTop(BuildContext context) {
  final painter = TextPainter(
    text: TextSpan(
      text: '甲',
      style: _navLabelStyle(ink: Colors.transparent, bold: false),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final labelExtent = painter.height;
  painter.dispose();
  final groupHeight = _navPillHeight + _navItemGap + labelExtent;
  return ((_navBandHeight - groupHeight) / 2)
      .clamp(0.0, _navBandHeight)
      .toDouble();
}

/// 底栏标签样式。目的地列与滑块的竖向定位测量共用它——两处行高必须一致，
/// 胶囊才谈得上与图标带同心。
TextStyle _navLabelStyle({required Color ink, required bool bold}) {
  return TextStyle(
    color: ink,
    // ignore: font_size_whitelist
    fontSize: _navLabelSize,
    fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
    height: _navLabelHeightFactor,
  );
}

/// 底栏选中胶囊：样例 `.bottom-nav button.active > span` 的酸绿底与投影。
class _MobileBottomPill extends StatelessWidget {
  const _MobileBottomPill();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.env.accent,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: context.env.pillGlow,
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: const SizedBox(width: _navPillWidth, height: _navPillHeight),
    );
  }
}

List<_MobileDestination> _destinations(AppLocalizations l10n) {
  return [
    _MobileDestination(icon: OmniIcons.home, label: l10n.mobileNavHome),
    _MobileDestination(icon: OmniIcons.library, label: l10n.mobileNavLibrary),
    _MobileDestination(icon: OmniIcons.book, label: l10n.mobileNavReader),
    _MobileDestination(icon: OmniIcons.folder, label: l10n.mobileNavFiles),
  ];
}

class _MobileDestination {
  const _MobileDestination({required this.icon, required this.label});

  final OmniIconsData icon;
  final String label;
}

/// 样例 icon-button：48 圆形玻璃钮（烟熏底 + 白 10% 描边 + blur）。
class _GlassCircleButton extends StatelessWidget {
  const _GlassCircleButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.iconSize = 20,
  });

  final String tooltip;
  final OmniIconsData icon;
  final VoidCallback onTap;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: MobilePressable(
        semanticLabel: tooltip,
        onTap: onTap,
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: context.env.iconButtonGlass,
                shape: BoxShape.circle,
                border: Border.all(color: context.env.line10),
              ),
              child: Center(
                child: OmniIcon(
                  icon: icon,
                  size: iconSize,
                  color: context.env.ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
