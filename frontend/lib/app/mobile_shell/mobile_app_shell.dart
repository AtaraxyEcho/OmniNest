import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/mobile_shell/mobile_account_sheet.dart';
import 'package:omninest/app/mobile_shell/mobile_navigation_config.dart';
import 'package:omninest/app/mobile_shell/mobile_shell_feature_bindings.dart';
import 'package:omninest/app/mobile_shell/mobile_shell_form.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/mobile_env_colors.dart';
import 'package:omninest/app/theme/mobile_layout_tokens.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/core/widgets/brand_logo.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
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
    // 环境设计为固定暗色族：浅色根主题下强制暗色基底，保证环境配色
    // 与文字对比不随系统明暗翻转。
    final baseTheme = Theme.of(context);
    final shellTheme =
        baseTheme.brightness == Brightness.dark
            ? baseTheme
            : OmniNestTheme.dark();
    final content = Theme(
      data: shellTheme,
      child: MobileShellScope(
        hosted: true,
        child: Scaffold(
          backgroundColor:
              backdropActive ? Colors.transparent : MobileEnvColors.stage,
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
    // Files 空间搜索为模块页内搜索条（按宿主隔离）；其余空间进入全局
    // 搜索覆盖层；搜索框与图标共用同一目标。
    final VoidCallback onSearch;
    if (_searchHostForBranch(branch) case final searchHost?) {
      onSearch =
          () =>
              ref
                  .read(mobileModuleSearchActiveProvider(searchHost).notifier)
                  .toggle();
    } else {
      onSearch = () => context.push('/search');
    }
    final title = _title(l10n);
    final subtitle = _subtitle(l10n);
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 12, 0),
          child: Row(
            children: [
              BrandLogo(size: 28, radius: 9),
              if (!isHome) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: MobileEnvColors.ink,
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
                        style: const TextStyle(
                          color: MobileEnvColors.inkMuted,
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
                onTap: onSearch,
              ),
              const SizedBox(width: 4),
              const MobileAccountAvatar(),
            ],
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
    return ColoredBox(
      color: MobileEnvColors.surfaceGlass,
      child: SizedBox(
        height: 40,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const OmniIcon(
                icon: OmniIcons.cloud,
                size: 17,
                color: MobileEnvColors.inkMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.mobileOfflineBanner,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MobileEnvColors.ink,
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
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, bottomPadding),
      child: Center(
        child: ConstrainedBox(
          key: const ValueKey('omninest.mobile.bottom-nav'),
          constraints: const BoxConstraints(
            maxWidth: MobileLayoutTokens.chromeMaxWidth,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: MobileEnvColors.navGlass,
              borderRadius: BorderRadius.circular(23),
              border: Border.all(color: MobileEnvColors.line12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 35,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: SizedBox(
              height: 70,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                child: Row(
                  children: [
                    for (var index = 0; index < destinations.length; index++)
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
    );
  }
}

/// 返回分支对应的页内搜索宿主标识；无宿主的分支返回 null（走全局搜索）。
String? _searchHostForBranch(int branch) {
  return switch (branch) {
    MobileNavigationConfig.filesBranch => MobileModuleSearchHosts.files,
    _ => null,
  };
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
                duration: MobileLayoutTokens.stateDuration,
                curve: MobileLayoutTokens.motionCurve,
                width: selected ? 48 : 34,
                height: 30,
                decoration: BoxDecoration(
                  color: selected ? MobileEnvColors.accent : Colors.transparent,
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
                        selected
                            ? MobileEnvColors.onAccent
                            : MobileEnvColors.white46,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color:
                      selected ? MobileEnvColors.ink : MobileEnvColors.white46,
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
                color: const Color(0x520D1817),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x1AFFFFFF)),
              ),
              child: Center(
                child: OmniIcon(
                  icon: icon,
                  size: iconSize,
                  color: MobileEnvColors.ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
