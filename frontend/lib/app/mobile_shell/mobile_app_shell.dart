import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/mobile_shell/mobile_navigation_config.dart';
import 'package:omninest/app/mobile_shell/mobile_shell_feature_bindings.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/app/theme/feature/music_backdrop_theme.dart';
import 'package:omninest/app/theme/feature/portal_mobile_theme.dart';
import 'package:omninest/app/theme/feature/reader_colors.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_palette.dart';
import 'package:omninest/app/theme/mobile_app_theme.dart';
import 'package:omninest/app/theme/mobile_layout_tokens.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/widgets/module_switch_transition.dart';
import 'package:omninest/core/widgets/responsive_breakpoints.dart';
import 'package:omninest/core/widgets/user_avatar_menu.dart';
import 'package:omninest/features/backdrop/backdrop_ui.dart';
import 'package:omninest/features/music/music_shell_ui.dart';

/// 移动平台及紧凑视口使用的应用级导航壳层。
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
    final useRail = width >= 840;
    final selectionActive = ref.watch(
      mobileShellSelectionActiveProvider(branch),
    );
    final offline = ref.watch(appOnlineStatusProvider).asData?.value == false;
    final content = Theme(
      data: MobileAppTheme.resolve(Theme.of(context)),
      child: MobileShellScope(
        hosted: true,
        child: Scaffold(
          backgroundColor: _shellBackground(context, branch: branch),
          body:
              useRail
                  ? _buildRailLayout(
                    context,
                    selectionActive: selectionActive,
                    offline: offline,
                  )
                  : _buildBottomNavigationLayout(
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
            portalStyle:
                widget.navigationShell.currentIndex ==
                MobileNavigationConfig.portalBranch,
            musicStyle:
                widget.navigationShell.currentIndex ==
                MobileNavigationConfig.musicBranch,
          ),
        ],
      ],
    );
  }

  Widget _buildRailLayout(
    BuildContext context, {
    required bool selectionActive,
    required bool offline,
  }) {
    return SafeArea(
      child: Row(
        children: [
          if (!selectionActive)
            _MobileNavigationRail(
              branch: widget.navigationShell.currentIndex,
              selectedIndex: _destinationIndex,
              onSelected: _selectDestination,
              portalStyle:
                  widget.navigationShell.currentIndex ==
                  MobileNavigationConfig.portalBranch,
              musicStyle:
                  widget.navigationShell.currentIndex ==
                  MobileNavigationConfig.musicBranch,
            ),
          Expanded(
            child: Column(
              children: [
                _MobileTopBar(branch: widget.navigationShell.currentIndex),
                if (offline)
                  _MobileSystemBanner(
                    branch: widget.navigationShell.currentIndex,
                  ),
                Expanded(child: _moduleContent()),
                if (!selectionActive)
                  MusicMobileMiniPlayerSlot(onOpenPlayer: _openNowPlaying),
              ],
            ),
          ),
        ],
      ),
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

/// 判断当前平台和视口是否应启用统一移动端壳层。
bool shouldUseResponsiveMobileShell({
  required bool mobilePlatform,
  required double width,
}) {
  return mobilePlatform || ResponsiveBreakpoints.isCompact(width);
}

class _MobileTopBar extends ConsumerWidget {
  const _MobileTopBar({required this.branch});

  final int branch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final portalStyle = branch == MobileNavigationConfig.portalBranch;
    final musicStyle = branch == MobileNavigationConfig.musicBranch;
    final backdropActive = _localBackdropActive(ref);
    if (portalStyle) {
      return Theme(
        data: PortalMobileTheme.resolve(
          context,
          backdropActive: backdropActive,
        ),
        child: Builder(
          builder:
              (context) => _buildTopBar(
                context,
                ref: ref,
                l10n: l10n,
                backdropActive: backdropActive,
              ),
        ),
      );
    }
    if (musicStyle) {
      return Theme(
        data: MusicBackdropTheme.resolve(
          Theme.of(context),
          backdropActive: backdropActive,
        ),
        child: Builder(
          builder:
              (context) => _buildTopBar(
                context,
                ref: ref,
                l10n: l10n,
                backdropActive: backdropActive,
              ),
        ),
      );
    }
    return _buildTopBar(context, ref: ref, l10n: l10n, backdropActive: false);
  }

  Widget _buildTopBar(
    BuildContext context, {
    required WidgetRef ref,
    required AppLocalizations l10n,
    required bool backdropActive,
  }) {
    final portalStyle = branch == MobileNavigationConfig.portalBranch;
    final musicStyle = branch == MobileNavigationConfig.musicBranch;
    final glassStyle = portalStyle || musicStyle;
    final surface =
        glassStyle
            ? _glassChromeSurface(
              context,
              backdropActive: backdropActive,
              bottom: false,
            )
            : _solidChromeSurface(context, branch: branch);
    // 玻璃分支不画描边（浅色下白线显突兀），层次由玻璃面本身承担。
    final outline =
        glassStyle
            ? Colors.transparent
            : _solidChromeOutline(context, branch: branch);
    final foreground = _chromeForeground(context, branch: branch);
    return SafeArea(
      bottom: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: surface,
          border: Border(bottom: BorderSide(color: outline)),
        ),
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _title(l10n),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (branch == MobileNavigationConfig.musicBranch)
                  const MusicMobileTopBarActions(),
                // Files/Photos 分支搜索改为模块页内搜索条（按宿主隔离），
                // 其余分支跳全局搜索。
                if (_searchHostForBranch(branch) case final searchHost?)
                  IconButton(
                    tooltip: l10n.searchTitle,
                    onPressed:
                        () =>
                            ref
                                .read(
                                  mobileModuleSearchActiveProvider(
                                    searchHost,
                                  ).notifier,
                                )
                                .toggle(),
                    icon: Icon(Icons.search_rounded, size: 22),
                    style: IconButton.styleFrom(
                      foregroundColor: foreground,
                      minimumSize: const Size.square(
                        MobileLayoutTokens.minimumTarget,
                      ),
                    ),
                  )
                else
                  IconButton(
                    tooltip: l10n.searchTitle,
                    onPressed:
                        () => context.push(
                          '/search?scope=${MobileNavigationConfig.searchScopeForBranch(branch)}',
                        ),
                    icon: Icon(Icons.search_rounded, size: 22),
                    style: IconButton.styleFrom(
                      foregroundColor: foreground,
                      minimumSize: const Size.square(
                        MobileLayoutTokens.minimumTarget,
                      ),
                    ),
                  ),
                _MobileActivityButton(
                  foregroundColor: foreground,
                  borderColor: surface,
                ),
                const SizedBox(width: 4),
                const UserAvatarMenu(size: 32, directToProfile: true),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _title(AppLocalizations l10n) {
    return switch (branch) {
      MobileNavigationConfig.portalBranch => l10n.mobileNavHome,
      MobileNavigationConfig.musicBranch => l10n.mobileNavMusic,
      MobileNavigationConfig.photosBranch => l10n.portalDockPhotos,
      MobileNavigationConfig.videoBranch => l10n.portalDockMovies,
      MobileNavigationConfig.readerBranch => l10n.mobileNavReader,
      _ => l10n.mobileNavFiles,
    };
  }
}

class _MobileActivityButton extends ConsumerWidget {
  const _MobileActivityButton({
    required this.foregroundColor,
    required this.borderColor,
  });

  final Color foregroundColor;

  /// 活动点外圈描边色，取当前 chrome 表面避免浮点错位。
  final Color borderColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(mobileShellActivityProvider);
    final failed = activity.failedTaskCount > 0;
    final active = activity.activeTaskCount > 0;
    final indicatorColor =
        failed
            ? context.mobileColors.danger
            : active
            ? context.mobileColors.musicAccent
            : context.mobileColors.warmAccent;
    final visible = activity.isVisible;
    return IconButton(
      tooltip: AppLocalizations.of(context).mobileActivityCenter,
      onPressed: () => context.push('/activity'),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            Icons.notifications_none_rounded,
            size: 22,
            color: foregroundColor,
          ),
          if (visible)
            Positioned(
              top: -2,
              right: -3,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: indicatorColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: borderColor, width: 2),
                ),
                child: const SizedBox.square(dimension: 9),
              ),
            ),
        ],
      ),
    );
  }
}

class _MobileSystemBanner extends StatelessWidget {
  const _MobileSystemBanner({required this.branch});

  final int branch;

  @override
  Widget build(BuildContext context) {
    final readerStyle = branch == MobileNavigationConfig.readerBranch;
    final frameStyle = branch == MobileNavigationConfig.photosBranch;
    final background =
        readerStyle
            ? context.readerColors.primaryContainer
            : frameStyle
            ? context.frameColors.activeBg
            : context.mobileColors.surfaceSelected;
    final foreground =
        readerStyle
            ? context.readerColors.onSurface
            : frameStyle
            ? context.frameColors.ink
            : context.mobileColors.textPrimary;
    return ColoredBox(
      color: background,
      child: SizedBox(
        height: 42,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(
                Icons.wifi_off_rounded,
                size: 18,
                color:
                    readerStyle
                        ? context.readerColors.warning
                        : frameStyle
                        ? context.frameColors.accent
                        : context.mobileColors.warmAccent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  AppLocalizations.of(context).mobileOfflineBanner,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileBottomNavigation extends ConsumerWidget {
  const _MobileBottomNavigation({
    required this.branch,
    required this.selectedIndex,
    required this.onSelected,
    required this.portalStyle,
    required this.musicStyle,
  });

  final int branch;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool portalStyle;
  final bool musicStyle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backdropActive = _localBackdropActive(ref);
    if (portalStyle) {
      return Theme(
        data: PortalMobileTheme.resolve(
          context,
          backdropActive: backdropActive,
        ),
        child: Builder(
          builder:
              (context) =>
                  _buildNavigation(context, backdropActive: backdropActive),
        ),
      );
    }
    if (musicStyle) {
      return Theme(
        data: MusicBackdropTheme.resolve(
          Theme.of(context),
          backdropActive: backdropActive,
        ),
        child: Builder(
          builder:
              (context) =>
                  _buildNavigation(context, backdropActive: backdropActive),
        ),
      );
    }
    return _buildNavigation(context, backdropActive: false);
  }

  Widget _buildNavigation(
    BuildContext context, {
    required bool backdropActive,
  }) {
    final destinations = _destinations(AppLocalizations.of(context));
    final surface =
        portalStyle || musicStyle
            ? _glassChromeSurface(
              context,
              backdropActive: backdropActive,
              bottom: true,
            )
            : _solidChromeSurface(context, branch: branch);
    // 玻璃分支不画描边（浅色下白线显突兀）。
    final outline =
        portalStyle || musicStyle
            ? Colors.transparent
            : _solidChromeOutline(context, branch: branch);
    final selectedColor = _chromeForeground(context, branch: branch);
    final unselectedColor = _chromeUnselectedColor(context, branch: branch);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: surface,
        border: Border(top: BorderSide(color: outline)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            children: [
              for (var index = 0; index < destinations.length; index++)
                Expanded(
                  child: _MobileBottomDestination(
                    destination: destinations[index],
                    selected: selectedIndex == index,
                    selectedColor: selectedColor,
                    unselectedColor: unselectedColor,
                    onTap: () => onSelected(index),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileNavigationRail extends ConsumerWidget {
  const _MobileNavigationRail({
    required this.branch,
    required this.selectedIndex,
    required this.onSelected,
    required this.portalStyle,
    required this.musicStyle,
  });

  final int branch;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool portalStyle;
  final bool musicStyle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backdropActive = _localBackdropActive(ref);
    if (portalStyle) {
      return Theme(
        data: PortalMobileTheme.resolve(
          context,
          backdropActive: backdropActive,
        ),
        child: Builder(
          builder:
              (context) => _buildRail(context, backdropActive: backdropActive),
        ),
      );
    }
    if (musicStyle) {
      return Theme(
        data: MusicBackdropTheme.resolve(
          Theme.of(context),
          backdropActive: backdropActive,
        ),
        child: Builder(
          builder:
              (context) => _buildRail(context, backdropActive: backdropActive),
        ),
      );
    }
    return _buildRail(context, backdropActive: false);
  }

  Widget _buildRail(BuildContext context, {required bool backdropActive}) {
    final destinations = _destinations(AppLocalizations.of(context));
    final surface =
        portalStyle || musicStyle
            ? _glassChromeSurface(
              context,
              backdropActive: backdropActive,
              bottom: false,
            )
            : _solidChromeSurface(context, branch: branch);
    // 玻璃分支不画描边（浅色下白线显突兀）。
    final outline =
        portalStyle || musicStyle
            ? Colors.transparent
            : _solidChromeOutline(context, branch: branch);
    final selectedColor = _chromeForeground(context, branch: branch);
    final unselectedColor = _chromeUnselectedColor(context, branch: branch);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: surface,
        border: Border(right: BorderSide(color: outline)),
      ),
      child: NavigationRail(
        minWidth: 80,
        selectedIndex: selectedIndex,
        onDestinationSelected: onSelected,
        indicatorColor: Colors.transparent,
        selectedIconTheme: IconThemeData(color: selectedColor),
        unselectedIconTheme: IconThemeData(color: unselectedColor),
        labelType: NavigationRailLabelType.all,
        destinations: [
          for (final destination in destinations)
            NavigationRailDestination(
              icon: Icon(destination.icon),
              selectedIcon: Icon(destination.selectedIcon),
              label: Text(destination.label),
            ),
        ],
      ),
    );
  }
}

bool _localBackdropActive(WidgetRef ref) {
  return ref.watch(mobileShellLocalBackdropActiveProvider);
}

/// 返回分支对应的页内搜索宿主标识；无宿主的分支返回 null（走全局搜索）。
String? _searchHostForBranch(int branch) {
  return switch (branch) {
    MobileNavigationConfig.filesBranch => MobileModuleSearchHosts.files,
    MobileNavigationConfig.photosBranch => MobileModuleSearchHosts.photos,
    _ => null,
  };
}

/// 玻璃分支（首页/音乐）统一 chrome 表面配方。
///
/// 两分支主题在「浅色 + 动态壁纸」时都已把 scheme 换为烟熏组，此处直接
/// 取 scheme 表面即可同语言：壁纸激活 = 烟熏玻璃（α 不低于 Portal 内容卡
/// 的 68%，底栏再高一档）；无壁纸浅色 = 近实底浅玻璃；深色 = 深玻璃。
Color _glassChromeSurface(
  BuildContext context, {
  required bool backdropActive,
  required bool bottom,
}) {
  final scheme = Theme.of(context).colorScheme;
  final light = scheme.brightness == Brightness.light;
  if (backdropActive) {
    // withValues 为替换 alpha：烟熏基色自带的透明度被目标档位覆盖。
    return scheme.surfaceContainerLow.withValues(
      alpha: light ? (bottom ? 0.80 : 0.72) : (bottom ? 0.82 : 0.78),
    );
  }
  final base = light ? scheme.surfaceContainerHigh : scheme.surfaceContainerLow;
  return base.withValues(alpha: light ? 0.90 : (bottom ? 0.82 : 0.78));
}

/// 壳层底色：玻璃分支保持透明（壁纸绘制底）；实底分支自绘面板底色——
/// hosted 页面按透明设计（壁纸时代遗留），壁纸隐藏后不绘制会在窗口露出黑底。
Color _shellBackground(BuildContext context, {required int branch}) {
  final glassStyle =
      branch == MobileNavigationConfig.portalBranch ||
      branch == MobileNavigationConfig.musicBranch;
  if (glassStyle) {
    return Colors.transparent;
  }
  if (branch == MobileNavigationConfig.readerBranch) {
    return context.readerColors.surface;
  }
  if (branch == MobileNavigationConfig.photosBranch) {
    return context.frameColors.bg;
  }
  return Theme.of(context).colorScheme.surface;
}

/// 实底分支的 chrome 表面：与页面同源——阅读取纸感表面、照片取 Frame
/// 暖纸表面（浅色扁平化下与全局面仅细微差、深色下避免冷暖拼接连条），
/// 其余取全局 surface。
Color _solidChromeSurface(BuildContext context, {required int branch}) {
  if (branch == MobileNavigationConfig.readerBranch) {
    return context.readerColors.surface;
  }
  if (branch == MobileNavigationConfig.photosBranch) {
    return context.frameColors.navBg;
  }
  return context.mobileColors.pageMask;
}

Color _solidChromeOutline(BuildContext context, {required int branch}) {
  if (branch == MobileNavigationConfig.readerBranch) {
    return context.readerColors.outlineVariant;
  }
  if (branch == MobileNavigationConfig.photosBranch) {
    return context.frameColors.border;
  }
  return context.mobileColors.outline;
}

/// chrome 前景色；选中态一律取该前景色（墨色单色），不使用模块 accent。
/// 玻璃分支跟随分支主题 scheme（浅色+壁纸即烟熏浅字）。
Color _chromeForeground(BuildContext context, {required int branch}) {
  final glassStyle =
      branch == MobileNavigationConfig.portalBranch ||
      branch == MobileNavigationConfig.musicBranch;
  if (glassStyle) {
    return Theme.of(context).colorScheme.onSurface;
  }
  if (branch == MobileNavigationConfig.readerBranch) {
    return context.readerColors.onSurface;
  }
  if (branch == MobileNavigationConfig.photosBranch) {
    return context.frameColors.ink;
  }
  return context.mobileColors.textPrimary;
}

/// chrome 未选中前景：随分支面板的弱化色。
Color _chromeUnselectedColor(BuildContext context, {required int branch}) {
  if (branch == MobileNavigationConfig.readerBranch) {
    return context.readerColors.onSurfaceVariant;
  }
  if (branch == MobileNavigationConfig.photosBranch) {
    return context.frameColors.muted;
  }
  return context.mobileColors.textSecondary;
}

class _MobileBottomDestination extends StatelessWidget {
  const _MobileBottomDestination({
    required this.destination,
    required this.selected,
    required this.selectedColor,
    required this.unselectedColor,
    required this.onTap,
  });

  final _MobileDestination destination;
  final bool selected;

  /// 选中态统一墨色前景（亮墨/暗米白/玻璃烟熏随分支主题解析）。
  final Color selectedColor;
  final Color unselectedColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: destination.label,
      child: MobilePressable(
        semanticLabel: destination.label,
        onTap: onTap,
        child: SizedBox.expand(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                top: 0,
                child: AnimatedContainer(
                  duration: MobileLayoutTokens.stateDuration,
                  curve: MobileLayoutTokens.motionCurve,
                  width: selected ? 28 : 0,
                  height: 3,
                  decoration: BoxDecoration(
                    color: selectedColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    selected ? destination.selectedIcon : destination.icon,
                    size: 22,
                    color: selected ? selectedColor : unselectedColor,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    destination.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? selectedColor : unselectedColor,
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
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
    _MobileDestination(
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      label: l10n.mobileNavHome,
    ),
    _MobileDestination(
      icon: Icons.music_note_outlined,
      selectedIcon: Icons.music_note_rounded,
      label: l10n.mobileNavMusic,
    ),
    _MobileDestination(
      icon: Icons.photo_library_outlined,
      selectedIcon: Icons.photo_library_rounded,
      label: l10n.portalDockPhotos,
    ),
    _MobileDestination(
      icon: Icons.movie_outlined,
      selectedIcon: Icons.movie_rounded,
      label: l10n.portalDockMovies,
    ),
    _MobileDestination(
      icon: Icons.menu_book_outlined,
      selectedIcon: Icons.menu_book_rounded,
      label: l10n.mobileNavReader,
    ),
    _MobileDestination(
      icon: Icons.folder_outlined,
      selectedIcon: Icons.folder_rounded,
      label: l10n.mobileNavFiles,
    ),
  ];
}

class _MobileDestination {
  const _MobileDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}
