import 'package:flutter/foundation.dart';
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
import 'package:omninest/core/widgets/brand_logo.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/widgets/module_switch_transition.dart';
import 'package:omninest/core/widgets/responsive_breakpoints.dart';
import 'package:omninest/core/widgets/user_avatar_menu.dart';
import 'package:omninest/features/backdrop/backdrop_ui.dart';
import 'package:omninest/features/music/music_shell_ui.dart';
import 'package:omninest/features/notifications/notification_ui.dart';

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
          // 平板与手机统一底部导航（tab 组限宽居中），不再切换左侧 rail：
          // 触屏可达性与三端一致性优先于 M3 的 medium/expanded 导航规范。
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
///
/// 宽度自适应仅作用于手机浏览器（Web 且浏览器宿主 OS 为 Android/iOS）
/// 与桌面应用窄窗；桌面浏览器收缩窗口不切换移动壳层。
bool shouldUseResponsiveMobileShell({
  required bool mobilePlatform,
  required double width,
}) {
  return resolveMobileShell(
    mobilePlatform: mobilePlatform,
    web: kIsWeb,
    hostPlatform: defaultTargetPlatform,
    width: width,
  );
}

/// [shouldUseResponsiveMobileShell] 的纯函数形态，便于按宿主场景测试。
@visibleForTesting
bool resolveMobileShell({
  required bool mobilePlatform,
  required bool web,
  required TargetPlatform hostPlatform,
  required double width,
}) {
  if (mobilePlatform) {
    return true;
  }
  final compact = ResponsiveBreakpoints.isCompact(width);
  if (web) {
    final mobileBrowser =
        hostPlatform == TargetPlatform.android ||
        hostPlatform == TargetPlatform.iOS;
    return mobileBrowser && compact;
  }
  return compact;
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
    final titleStyle = TextStyle(
      color: foreground,
      fontSize: 22,
      fontWeight: FontWeight.w700,
    );
    // Files/Photos 分支搜索改为模块页内搜索条（按宿主隔离），
    // 其余分支跳全局搜索；搜索框与图标共用同一目标。
    final VoidCallback onSearch;
    if (_searchHostForBranch(branch) case final searchHost?) {
      onSearch =
          () =>
              ref
                  .read(mobileModuleSearchActiveProvider(searchHost).notifier)
                  .toggle();
    } else {
      onSearch =
          () => context.push(
            '/search?scope=${MobileNavigationConfig.searchScopeForBranch(branch)}',
          );
    }
    final titleText = Text(
      _title(l10n),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: titleStyle,
    );
    // 平板及以上顶栏把搜索图标升级为展开搜索框，宽度被有效利用；
    // 以布局约束而非 MediaQuery 判定宽度，测试视口与真机行为一致。
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth >= MobileLayoutTokens.topBarSearchMinWidth;
        Widget searchIconButton(Color foreground) => IconButton(
          tooltip: l10n.searchTitle,
          onPressed: onSearch,
          icon: Icon(Icons.search_rounded, size: 22),
          style: IconButton.styleFrom(
            foregroundColor: foreground,
            minimumSize: const Size.square(MobileLayoutTokens.minimumTarget),
          ),
        );
        // 表面画满含状态栏区域（与底栏同法）：SafeArea 放在装饰盒内
        // 只避让内容，玻璃/实底色延伸到屏幕顶端，消除状态栏透明断层。
        return DecoratedBox(
          decoration: BoxDecoration(
            color: surface,
            border: Border(bottom: BorderSide(color: outline)),
          ),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: 56,
              child: Padding(
                padding: const EdgeInsets.only(left: 16, right: 8),
                child: Row(
                  children: [
                    // 三端统一品牌入口：顶栏以 logo 领起，Portal 首页
                    // 紧随品牌字标，其余分支保持分支名提供上下文。
                    BrandLogo(size: wide ? 28 : 24, radius: wide ? 8 : 7),
                    SizedBox(width: wide ? 12 : 10),
                    if (wide && portalStyle) ...[
                      titleText,
                      // 全局搜索框只在 Portal 首页展示，限宽并紧随品牌，
                      // 不再横向拉满整条顶栏。
                      const SizedBox(width: 16),
                      SizedBox(
                        width: MobileLayoutTokens.topBarSearchMaxWidth,
                        child: _TopBarSearchField(
                          foreground: foreground,
                          hint: l10n.searchTitle,
                          onTap: onSearch,
                        ),
                      ),
                      const Spacer(),
                    ] else if (wide) ...[
                      titleText,
                      const Spacer(),
                    ] else
                      Expanded(child: titleText),
                    if (branch == MobileNavigationConfig.musicBranch)
                      const MusicMobileTopBarActions(),
                    // 搜索图标仅保留在手机宽度与 Files/Photos（页内搜索条
                    // 的唯一触发）；Music/Video/Reader 平板宽度走模块自带
                    // 搜索，不再重复展示全局搜索入口。
                    if (!wide || _searchHostForBranch(branch) != null)
                      searchIconButton(foreground),
                    // 平板 hosted 桌面视觉不再绘制自身顶栏，背景库入口
                    // 由壳层顶栏接管；窄幅手机仍走移动 Portal 自身入口。
                    if (wide && branch == MobileNavigationConfig.portalBranch)
                      IconButton(
                        tooltip: l10n.portalLocalBackdropTitle,
                        onPressed: () => showAppBackdropSettings(context),
                        icon: Icon(Icons.wallpaper_rounded, size: 22),
                        style: IconButton.styleFrom(
                          foregroundColor: foreground,
                          minimumSize: const Size.square(
                            MobileLayoutTokens.minimumTarget,
                          ),
                        ),
                      ),
                    // 与桌面/Web 同一铃铛组件：三端一致的未读徽标与跳转目标。
                    NotificationIcon(size: 22, color: foreground),
                    const SizedBox(width: 4),
                    const UserAvatarMenu(size: 32, directToProfile: true),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _title(AppLocalizations l10n) {
    return switch (branch) {
      // Portal 首页顶栏展示品牌字标（与桌面 Portal 顶栏同语言）。
      MobileNavigationConfig.portalBranch => 'OmniNest',
      MobileNavigationConfig.musicBranch => l10n.mobileNavMusic,
      MobileNavigationConfig.photosBranch => l10n.portalDockPhotos,
      MobileNavigationConfig.videoBranch => l10n.portalDockMovies,
      MobileNavigationConfig.readerBranch => l10n.mobileNavReader,
      _ => l10n.mobileNavFiles,
    };
  }
}

/// 顶栏展开搜索框（平板及以上替代搜索图标）。
/// 非输入态的引导控件：点击后进入与图标一致的模块搜索或全局搜索。
class _TopBarSearchField extends StatelessWidget {
  const _TopBarSearchField({
    required this.foreground,
    required this.hint,
    required this.onTap,
  });

  final Color foreground;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = foreground.withValues(alpha: 0.62);
    // 顶栏行高 56，把命中盒抬到 48 不改变可见胶囊的 38 高度与位置。
    return SizedBox(
      height: MobileLayoutTokens.minimumTarget,
      child: Center(
        child: SizedBox(
          height: 38,
          child: Material(
            key: const ValueKey('omninest.mobile.top-bar-search'),
            color: foreground.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(19),
            child: InkWell(
              borderRadius: BorderRadius.circular(19),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Icon(Icons.search_rounded, size: 19, color: muted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        hint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: muted, fontSize: 15),
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 平板宽度收紧栏高：横屏竖向空间宝贵，图标+文字纵向堆叠
            // 在 56 内仍有充分呼吸；手机保持拇指友好的 68。
            final compactHeight =
                constraints.maxWidth >= MobileLayoutTokens.topBarSearchMinWidth;
            return SizedBox(
              height: compactHeight ? 56 : 68,
              // 平板宽度下 tab 组限宽居中：间距不被整屏拉伸，
              // 两侧留给玻璃/壁纸自然过渡。
              child: Center(
                child: ConstrainedBox(
                  key: const ValueKey('omninest.mobile.bottom-nav'),
                  constraints: const BoxConstraints(
                    maxWidth: MobileLayoutTokens.chromeMaxWidth,
                  ),
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
          },
        ),
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
/// 的 68%，底栏再高一档）；无壁纸时上下栏同档近实底——半透明烟熏在近黑
/// 内容上会拼出明暗/冷暖断裂的色带，深色与浅色 0.90 对称取 0.92。
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
  return base.withValues(alpha: light ? 0.90 : 0.92);
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
