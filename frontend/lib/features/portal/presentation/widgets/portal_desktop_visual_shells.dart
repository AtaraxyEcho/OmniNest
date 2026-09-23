import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/core/widgets/responsive_breakpoints.dart';
import 'package:omninest/core/window/window_chrome_controller.dart';
import 'package:omninest/core/widgets/app_fullscreen_control.dart';
import 'package:omninest/features/tasks/task_ui.dart';
import 'package:omninest/features/notifications/notification_ui.dart';
import 'package:omninest/core/widgets/font_scale_control.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/user_avatar_menu.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_controller.dart';
import 'package:omninest/features/backdrop/backdrop_ui.dart';
import 'package:omninest/features/admin/application/admin_console_access_provider.dart';
import 'package:omninest/features/admin/domain/admin_console_summary.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';
import 'package:omninest/features/music/music_portal.dart';
import 'package:omninest/features/music/music_shell_ui.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/portal/application/portal_dashboard_providers.dart';
import 'package:omninest/features/portal/application/portal_paged_cards.dart';
import 'package:omninest/features/portal/application/portal_immersive_session.dart';
import 'package:omninest/features/portal/application/weather_provider.dart';
import 'package:omninest/features/portal/domain/portal_focus_models.dart';
import 'package:omninest/features/portal/presentation/portal_focus_icon.dart';
import 'package:omninest/features/portal/presentation/widgets/portal_media_thumbnail.dart';
import 'package:omninest/features/portal/presentation/widgets/portal_visual_widgets.dart';
import 'package:omninest/features/portal/presentation/widgets/portal_weather_profile.dart';
import 'package:omninest/features/portal/presentation/widgets/portal_hero_ellipsized_title.dart';
import 'package:omninest/features/portal/presentation/widgets/weather_detail_dialog.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/reader_cover_ui.dart';
import 'package:omninest/features/video/domain/movie_models.dart';

part 'portal_desktop_companions.dart';
part 'portal_desktop_dock_weather_effects.dart';
part 'portal_desktop_data.dart';
part 'portal_desktop_gallery_styles.dart';
part 'portal_desktop_quick_actions.dart';

void _openWeatherDetails(BuildContext context, _PortalDesktopData data) {
  final weather = data.weatherData ?? WeatherData.empty();
  showWeatherDetailDialog(context, weather: weather);
}

int _resolveCarouselIndex({
  required List<PortalFocusItem> items,
  required PortalFocusItem preferred,
  required int? selectedIndex,
}) {
  if (items.isEmpty) {
    return 0;
  }
  final selected = selectedIndex;
  if (selected != null && selected >= 0 && selected < items.length) {
    return selected;
  }
  final preferredIndex = items.indexWhere((item) {
    return item.route == preferred.route &&
        item.title == preferred.title &&
        item.subtitle == preferred.subtitle;
  });
  return preferredIndex < 0 ? 0 : preferredIndex;
}

double _resolvePortalViewportHeight(
  BuildContext context,
  BoxConstraints constraints,
) {
  if (constraints.maxHeight.isFinite && constraints.maxHeight > 0) {
    return constraints.maxHeight;
  }
  final screenHeight = MediaQuery.sizeOf(context).height;
  if (screenHeight.isFinite && screenHeight > 0) {
    return screenHeight.clamp(640.0, 980.0).toDouble();
  }
  return 760.0;
}

/// 桌面 Portal 内容最大宽度：超宽窗口下三栏内容封顶居中，两侧留给壁纸。
/// 取 1560 而非更大值，保证 1920 全屏下两侧也有可感知的留白。
const double kPortalDesktopContentMaxWidth = 1560;

/// 桌面 Portal 布局档位：按内容区可用宽度决定栏式。
enum PortalDesktopLayoutTier {
  /// 单栏堆叠，仅作极窄兜底（桌面护栏下常规不可达）。
  singleColumn,

  /// 两栏：中央 hero（文案+封面并排）与合并右栏，覆盖最小桌面宽度。
  twoColumn,

  /// 三栏：状态栏 + 中央 hero + 关注面板。平板与桌面共用此形态；
  /// 1120 为三栏几何下限（文案+封面并排不局促）。
  wide,
}

@visibleForTesting
PortalDesktopLayoutTier resolvePortalDesktopLayoutTier(double maxWidth) {
  if (maxWidth >= 1120) {
    return PortalDesktopLayoutTier.wide;
  }
  if (maxWidth >= ResponsiveBreakpoints.desktop) {
    return PortalDesktopLayoutTier.twoColumn;
  }
  return PortalDesktopLayoutTier.singleColumn;
}

class _PortalLocalBackdropButton extends StatelessWidget {
  const _PortalLocalBackdropButton({required this.palette});

  final PortalVisualPalette palette;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Tooltip(
      message: l10n.portalLocalBackdropTitle,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => showAppBackdropSettings(context),
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: palette.structuralStrongSurface(alpha: 0.64),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: palette.muted.withValues(alpha: 0.22)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.photo_library_rounded,
                  size: 18,
                  color: palette.text,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.portalLocalBackdropShort,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: AppTypography.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PortalDesktopVisualHost extends ConsumerStatefulWidget {
  const PortalDesktopVisualHost({super.key});

  @override
  ConsumerState<PortalDesktopVisualHost> createState() =>
      _PortalDesktopVisualHostState();
}

class _PortalDesktopVisualHostState
    extends ConsumerState<PortalDesktopVisualHost> {
  static const _windowChromeOwner = 'portalMusic';

  late final FocusNode _immersiveFocusNode;
  late final WindowChromeController _windowChromeController;
  WindowChromeLease? _windowChromeLease;
  bool _windowChromeRequested = false;
  bool _windowChromeSyncScheduled = false;
  bool _focusSyncScheduled = false;
  bool? _pendingWindowChromeIntent;

  @override
  void initState() {
    super.initState();
    _immersiveFocusNode = FocusNode(debugLabel: 'Portal 全屏');
    _windowChromeController = ref.read(windowChromeControllerProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      // 沉浸会话是本机瞬态：应用启动/进入门户时不继承任何持久化状态，
      // 窗口不会被历史会话自动无边框全屏。
      final immersive = ref.read(portalImmersiveSessionProvider);
      _scheduleWindowChromeIntent(immersive);
      _scheduleImmersiveFocus(immersive);
    });
  }

  @override
  void dispose() {
    _windowChromeLease?.release();
    _immersiveFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 统一沉浸事实源：本机会话（内容区域与顶栏按钮共用）+ 音乐甲板
    // 覆盖层形态。任一激活即呈现门户沉浸视觉。
    final musicImmersive = ref.watch(musicImmersiveControllerProvider);
    final immersiveActive = ref.watch(portalImmersiveSessionProvider);
    ref.listen(portalImmersiveSessionProvider, (_, next) {
      _scheduleWindowChromeIntent(next);
      _scheduleImmersiveFocus(next);
    });
    // 平板等宽幅触屏设备在移动壳层内复用桌面视觉：壳层顶栏已提供标题、
    // 搜索、通知与头像，且壳层各自消费了状态栏与导航栏内边距，这里不再
    // 重复绘制顶栏，避免搜索/铃铛/头像三重堆叠与双重 SafeArea。
    final hosted = MobileShellScope.isHosted(context);
    final immersivePlaybackVisible = immersiveActive || musicImmersive;
    final weather = ref.watch(realtimeWeatherProvider).asData?.value;
    final localBackdropState =
        ref.watch(appBackdropControllerProvider).asData?.value;
    final localBackdropActive =
        localBackdropState?.settings.enabled == true &&
        localBackdropState?.selectedBackdrop != null &&
        localBackdropState?.selectedBackdrop?.missing == false;
    final palette = PortalVisualPalette.of(
      context,
      backdropActive: localBackdropActive,
    );
    // F11 由 app.dart 全局按键处理器统一分发为无边框全屏；此处不得再绑定
    // F11 切换沉浸模式，否则同一按键会双重触发（硬件层 handler 与焦点树
    // CallbackShortcuts 无条件先后执行），表现为全屏与音乐沉浸模式同时翻转。
    return Focus(
      focusNode: _immersiveFocusNode,
      autofocus: true,
      canRequestFocus: true,
      onKeyEvent: (node, event) {
        if (!immersivePlaybackVisible || event is! KeyDownEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey != LogicalKeyboardKey.escape) {
          return KeyEventResult.ignored;
        }
        if (immersiveActive) {
          ref.read(portalImmersiveSessionProvider.notifier).deactivate();
        } else if (musicImmersive) {
          ref.read(musicImmersiveControllerProvider.notifier).requestExit();
        }
        return KeyEventResult.handled;
      },
      child: Stack(
        children: [
          SafeArea(
            top: !hosted,
            bottom: !hosted,
            child: Padding(
              padding: EdgeInsets.fromLTRB(32, hosted ? 12 : 0, 32, 28),
              child: Column(
                children: [
                  if (!hosted && !immersiveActive)
                    _buildTopBar(palette: palette, immersive: immersiveActive),
                  Expanded(
                    child: IgnorePointer(
                      ignoring: immersivePlaybackVisible,
                      child: AnimatedOpacity(
                        opacity: immersivePlaybackVisible ? 0 : 1,
                        duration: PortalMotion.duration(
                          context,
                          const Duration(milliseconds: 240),
                        ),
                        curve: Curves.easeOutCubic,
                        child: AnimatedScale(
                          // 背景"收远"而不是下移：与前景的推近形成对向运动，
                          // 位移读起来像页面被挤走。不叠压暗遮罩，壁纸可见度
                          // 本身就是沉浸页要展示的内容。
                          scale: immersivePlaybackVisible ? 0.985 : 1,
                          duration: PortalMotion.duration(
                            context,
                            const Duration(milliseconds: 240),
                          ),
                          curve: Curves.easeOutCubic,
                          child: _BackdropLibraryPortal(
                            palette: palette,
                            weatherOverride: weather,
                            localBackdropActive: localBackdropActive,
                            onOpenImmersivePlayback: _openImmersivePlayback,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 沉浸播放层自带进出场过渡：此前它被直接插入/移除，背景已经淡出而
          // 前景「啪」地出现（退出同理），观感上就是缺少过渡。让位规则仍由
          // Positioned.fill 的 top 决定，动画只负责淡入与轻微收放。
          Positioned.fill(
            top:
                hosted
                    ? 0
                    : immersiveActive
                    ? 0
                    : MediaQuery.paddingOf(context).top + 58,
            child: IgnorePointer(
              ignoring: !immersivePlaybackVisible,
              child: AnimatedSwitcher(
                duration: PortalMotion.duration(
                  context,
                  const Duration(milliseconds: 240),
                ),
                reverseDuration: PortalMotion.duration(
                  context,
                  const Duration(milliseconds: 200),
                ),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                // 默认 layoutBuilder 以非定位子节点排版，会让沉浸层丢掉
                // Positioned.fill 的铺满约束（塌陷且过渡看不出来）。这里显式
                // 让每一帧都撑满父级。
                layoutBuilder:
                    (current, previousChildren) => Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        ...previousChildren,
                        if (current != null) current,
                      ],
                    ),
                transitionBuilder: (child, animation) {
                  final curved = CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  );
                  // 减少动效偏好下只保留淡入，几何量塌成常量。
                  final settled = MediaQuery.disableAnimationsOf(context);
                  return FadeTransition(
                    opacity: curved,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: settled ? Offset.zero : const Offset(0, 0.02),
                        end: Offset.zero,
                      ).animate(curved),
                      child: ScaleTransition(
                        // 0.985 → 1 的推近：幅度再大就会在视口边缘露出背景。
                        scale: Tween<double>(
                          begin: settled ? 1 : 0.985,
                          end: 1,
                        ).animate(curved),
                        child: child,
                      ),
                    ),
                  );
                },
                child:
                    immersivePlaybackVisible
                        ? KeyedSubtree(
                          key: const ValueKey('portal-immersive-playback'),
                          child: MusicImmersivePlayer(
                            palette: _musicImmersivePalette(palette),
                            reservedTopInset:
                                !hosted && immersiveActive
                                    ? MediaQuery.paddingOf(context).top + 58
                                    : 0,
                          ),
                        )
                        : const SizedBox.shrink(
                          key: ValueKey('portal-immersive-hidden'),
                        ),
              ),
            ),
          ),
          if (!hosted && immersiveActive)
            Positioned(
              left: 32,
              right: 32,
              top: 0,
              child: SafeArea(
                bottom: false,
                child: _buildTopBar(
                  palette: palette,
                  immersive: immersiveActive,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopBar({
    required PortalVisualPalette palette,
    required bool immersive,
  }) {
    // 两个沉浸入口共用同一会话事实源：沉浸中顶栏按钮即退出（含甲板
    // 覆盖层形态的语境退出），非沉浸时即进入，取反基准不再分叉。
    final musicImmersive = ref.watch(musicImmersiveControllerProvider);
    final l10n = AppLocalizations.of(context);
    return PortalImmersiveTopBarReveal(
      immersive: immersive,
      child: PortalVisualTopBar(
        palette: palette,
        onSearch: () => context.go('/search'),
        trailing: [
          _PortalLocalBackdropButton(palette: palette),
          const SizedBox(width: 10),
          AppFullscreenButton(
            isFullscreen: musicImmersive || immersive,
            foregroundColor: palette.text,
            accentColor: palette.accent,
            // 此按钮切换的是门户音乐沉浸会话（整屏音乐沉浸视觉），
            // 不是 F11 无边框全屏，提示文案不得借用全屏快捷键。
            enterTooltip: l10n.portalImmersiveModeEnter,
            exitTooltip:
                musicImmersive
                    ? l10n.portalExitImmersivePlayback
                    : l10n.portalImmersiveModeExit,
            onPressed: () {
              if (musicImmersive) {
                final exited =
                    ref
                        .read(musicImmersiveControllerProvider.notifier)
                        .requestExit();
                if (!exited) {
                  context.go('/music');
                }
                return;
              }
              if (immersive) {
                ref.read(portalImmersiveSessionProvider.notifier).deactivate();
                return;
              }
              ref.read(portalImmersiveSessionProvider.notifier).activate();
            },
          ),
          const SizedBox(width: 10),
          FontScaleControl(size: 20, color: palette.text),
          TaskActivityButton(size: 20, color: palette.text),
          NotificationIcon(size: 20, color: palette.text),
          const SizedBox(width: 8),
          const UserAvatarMenu(),
        ],
      ),
    );
  }

  void _scheduleWindowChromeIntent(bool immersive) {
    if (!isDesktopPlatform) {
      return;
    }
    if (_windowChromeRequested == immersive) {
      _pendingWindowChromeIntent = null;
      return;
    }
    _pendingWindowChromeIntent = immersive;
    if (_windowChromeSyncScheduled) {
      return;
    }
    _windowChromeSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _windowChromeSyncScheduled = false;
      if (!mounted) {
        return;
      }
      final pending = _pendingWindowChromeIntent;
      _pendingWindowChromeIntent = null;
      if (pending == null) {
        return;
      }
      _syncWindowChromeIntent(pending);
    });
  }

  void _syncWindowChromeIntent(bool immersive) {
    if (!isDesktopPlatform || _windowChromeRequested == immersive) {
      return;
    }
    _windowChromeRequested = immersive;
    if (immersive) {
      _windowChromeLease ??= _windowChromeController.acquireImmersive(
        owner: _windowChromeOwner,
        onExit: () async {
          if (!mounted) {
            return;
          }
          // 窗口租约被外部终结（如 F11 退出全屏）时仅回收本机会话，
          // 不产生任何跨端广播。
          ref.read(portalImmersiveSessionProvider.notifier).deactivate();
        },
      );
      return;
    }
    _windowChromeLease?.release();
    _windowChromeLease = null;
  }

  void _openImmersivePlayback() {
    if (ref.read(portalImmersiveSessionProvider)) {
      return;
    }
    ref.read(portalImmersiveSessionProvider.notifier).activate();
    _scheduleImmersiveFocus(true);
  }

  bool _isImmersivePlaybackActive() {
    return ref.read(portalImmersiveSessionProvider);
  }

  void _scheduleImmersiveFocus(bool enabled) {
    if (!enabled || _immersiveFocusNode.hasFocus || _focusSyncScheduled) {
      return;
    }
    _focusSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusSyncScheduled = false;
      if (!mounted || !_isImmersivePlaybackActive()) {
        return;
      }
      _immersiveFocusNode.requestFocus();
    });
  }
}

MusicImmersivePalette _musicImmersivePalette(PortalVisualPalette palette) {
  return MusicImmersivePalette(
    background: palette.background,
    surface: palette.surface,
    surfaceStrong: palette.surfaceStrong,
    text: palette.text,
    muted: palette.muted,
    accent: palette.accent,
    accentAlt: palette.accentAlt,
    glow: palette.glow,
  );
}
