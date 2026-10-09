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
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/mobile_app_theme.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/app/theme/mobile_layout_tokens.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/core/widgets/brand_logo.dart';
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
    final offline = ref.watch(appOnlineStatusProvider).asData?.value == false;
    final backdropActive = ref.watch(mobileShellLocalBackdropActiveProvider);
    // 极性在这里决定并注册：壁纸在场取采样亮度，无壁纸的实底壳随根主题明暗。
    // 壳层之下的所有面都已接进极性表，未注册时 MobileEnvPalette.of 仍取暗基准。
    final baseTheme = Theme.of(context);
    final envPalette = watchMobileEnvPalette(ref, baseTheme);
    final shellTheme = (envPalette.brightness == Brightness.dark
            ? (baseTheme.brightness == Brightness.dark
                ? baseTheme
                : OmniNestTheme.dark())
            : MobileAppTheme.resolve(baseTheme))
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
    required bool offline,
  }) {
    return Column(
      children: [
        _MobileTopBar(branch: widget.navigationShell.currentIndex),
        if (offline)
          _MobileSystemBanner(branch: widget.navigationShell.currentIndex),
        Expanded(child: _moduleContent()),
        if (!selectionActive) ...[
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
                  BrandLogo(size: 28, radius: 9),
                  if (!isHome) ...[
                    const SizedBox(width: 12),
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
              child: DecoratedBox(
                // 投影留在裁切之外，模糊与描边在裁切之内（对齐原型
                // .bottom-nav：r23 + blur(28) + 白 12% 描边 + 0 12 35 投影）。
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(23),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 35,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(23),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: context.env.navGlass,
                        border: Border.all(color: context.env.line12),
                      ),
                      child: SizedBox(
                        height: 70,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 5,
                          ),
                          child: Row(
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
                        ),
                      ),
                    ),
                  ),
                ),
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
              AnimatedContainer(
                // 原型 `.bottom-nav button > span` 是 min-width:48 + height:30，
                // 选中只换底色与投影，舱体宽度不随状态跳变；减弱动效时
                // 连配色补间一起跳过，直接落终态。
                duration: MotionToken.reduced(
                  context,
                  MobileLayoutTokens.stateDuration,
                ),
                curve: MobileLayoutTokens.motionCurve,
                width: 48,
                height: 30,
                decoration: BoxDecoration(
                  color: selected ? context.env.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow:
                      selected
                          ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.18),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ]
                          : null,
                ),
                child: Center(
                  child: OmniIcon(
                    icon: destination.icon,
                    size: 20,
                    color:
                        selected ? context.env.onAccent : context.env.white46,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? context.env.ink : context.env.white46,
                  // ignore: font_size_whitelist
                  fontSize: 9,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
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
