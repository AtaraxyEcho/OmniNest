import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/core/window/window_chrome_controller.dart';
import 'package:omninest/core/widgets/app_fullscreen_control.dart';
import 'package:omninest/features/notifications/notification_ui.dart';
import 'package:omninest/core/widgets/font_scale_control.dart';
import 'package:omninest/core/widgets/user_avatar_menu.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_controller.dart';
import 'package:omninest/features/backdrop/backdrop_ui.dart';
import 'package:omninest/features/admin/domain/admin_console_summary.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';
import 'package:omninest/features/music/music_portal.dart';
import 'package:omninest/features/music/music_shell_ui.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/portal/application/portal_dashboard_providers.dart';
import 'package:omninest/features/portal/application/portal_preferences_controller.dart';
import 'package:omninest/features/portal/application/weather_provider.dart';
import 'package:omninest/features/portal/domain/portal_focus_models.dart';
import 'package:omninest/features/portal/domain/portal_preferences.dart';
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
  bool _immersivePlaybackEnabled = false;
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
      final immersive =
          ref
              .read(portalPreferencesProvider)
              .asData
              ?.value
              .immersiveModeEnabled ??
          false;
      _scheduleWindowChromeIntent(immersive);
      _scheduleImmersiveFocus(immersive || _immersivePlaybackEnabled);
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
    ref.listen(portalPreferencesProvider, (_, next) {
      final immersive = next.asData?.value.immersiveModeEnabled ?? false;
      _scheduleWindowChromeIntent(immersive);
      _scheduleImmersiveFocus(immersive || _immersivePlaybackEnabled);
    });
    final preferences = ref.watch(portalPreferencesProvider);
    final resolved = preferences.asData?.value ?? const PortalPreferences();
    final immersivePlaybackVisible =
        resolved.immersiveModeEnabled || _immersivePlaybackEnabled;
    final weather = ref.watch(realtimeWeatherProvider).asData?.value;
    final localBackdropState =
        isDesktopPlatform
            ? ref.watch(appBackdropControllerProvider).asData?.value
            : null;
    final localBackdropActive =
        localBackdropState?.settings.enabled == true &&
        localBackdropState?.selectedBackdrop != null &&
        localBackdropState?.selectedBackdrop?.missing == false;
    final palette = PortalVisualPalette.of(
      context,
      backdropActive: localBackdropActive,
    );
    return AppFullscreenShortcutScope(
      onToggle:
          () => ref
              .read(portalPreferencesProvider.notifier)
              .updateImmersiveMode(!resolved.immersiveModeEnabled),
      child: Focus(
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
          if (_immersivePlaybackEnabled) {
            setState(() => _immersivePlaybackEnabled = false);
          } else {
            ref
                .read(portalPreferencesProvider.notifier)
                .updateImmersiveMode(false);
          }
          return KeyEventResult.handled;
        },
        child: Stack(
          children: [
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 28),
                child: Column(
                  children: [
                    if (!resolved.immersiveModeEnabled)
                      _buildTopBar(palette: palette, resolved: resolved),
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
                          child: AnimatedSlide(
                            offset:
                                immersivePlaybackVisible
                                    ? const Offset(0, 0.035)
                                    : Offset.zero,
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
            if (immersivePlaybackVisible)
              Positioned.fill(
                top:
                    resolved.immersiveModeEnabled
                        ? 0
                        : MediaQuery.paddingOf(context).top + 58,
                child: MusicImmersivePlayer(
                  palette: _musicImmersivePalette(palette),
                  reservedTopInset:
                      resolved.immersiveModeEnabled
                          ? MediaQuery.paddingOf(context).top + 58
                          : 0,
                ),
              ),
            if (resolved.immersiveModeEnabled)
              Positioned(
                left: 32,
                right: 32,
                top: 0,
                child: SafeArea(
                  bottom: false,
                  child: _buildTopBar(palette: palette, resolved: resolved),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar({
    required PortalVisualPalette palette,
    required PortalPreferences resolved,
  }) {
    final immersive = resolved.immersiveModeEnabled;
    return PortalImmersiveTopBarReveal(
      immersive: immersive,
      child: PortalVisualTopBar(
        palette: palette,
        onSearch: () => context.go('/search'),
        trailing: [
          _PortalLocalBackdropButton(palette: palette),
          const SizedBox(width: 10),
          AppFullscreenButton(
            isFullscreen: resolved.immersiveModeEnabled,
            foregroundColor: palette.text,
            accentColor: palette.accent,
            onPressed:
                () => ref
                    .read(portalPreferencesProvider.notifier)
                    .updateImmersiveMode(!resolved.immersiveModeEnabled),
          ),
          const SizedBox(width: 10),
          FontScaleControl(size: 20, color: palette.text),
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
          await ref
              .read(portalPreferencesProvider.notifier)
              .updateImmersiveMode(false);
        },
      );
      return;
    }
    _windowChromeLease?.release();
    _windowChromeLease = null;
  }

  void _openImmersivePlayback() {
    if (_immersivePlaybackEnabled) {
      return;
    }
    setState(() => _immersivePlaybackEnabled = true);
    _scheduleImmersiveFocus(true);
  }

  bool _isImmersivePlaybackActive() {
    final immersive =
        ref
            .read(portalPreferencesProvider)
            .asData
            ?.value
            .immersiveModeEnabled ??
        false;
    return immersive || _immersivePlaybackEnabled;
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
