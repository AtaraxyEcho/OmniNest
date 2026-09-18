import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/core/utils/fullscreen_helper.dart' as fs;
import 'package:omninest/core/window/window_chrome_controller.dart';
import 'package:omninest/core/widgets/app_fullscreen_control.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop_policy.dart';
import 'package:omninest/features/backdrop/backdrop_ui.dart';
import 'package:omninest/features/music/presentation/player/music_mobile_now_playing.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_player.dart';
import 'package:omninest/features/music/application/music_sleep_timer_controller.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_style.dart';

/// Music Deck 使用的全平台沉浸播放覆盖层。
class MusicImmersiveOverlay extends ConsumerStatefulWidget {
  const MusicImmersiveOverlay({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  ConsumerState<MusicImmersiveOverlay> createState() =>
      _MusicImmersiveOverlayState();
}

class _MusicImmersiveOverlayState extends ConsumerState<MusicImmersiveOverlay> {
  bool _topBarHovered = false;
  bool _webFullscreen = false;
  late final WindowChromeController _windowChromeController;

  @override
  void initState() {
    super.initState();
    _windowChromeController = ref.read(windowChromeControllerProvider.notifier);
    if (kIsWeb) {
      _webFullscreen = fs.isFullscreen;
      fs.addFullscreenChangeListener(_handleWebFullscreenChange);
    }
  }

  void _handleWebFullscreenChange(bool active) {
    if (mounted) {
      setState(() => _webFullscreen = active);
    } else {
      _webFullscreen = active;
    }
  }

  @override
  void dispose() {
    if (kIsWeb) {
      fs.removeFullscreenChangeListener(_handleWebFullscreenChange);
      if (fs.isFullscreen) {
        fs.toggleFullscreen();
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final fullVisual = (isDesktopPlatform || kIsWeb) && width >= 900;
    final safeTop = MediaQuery.paddingOf(context).top;
    final windowChrome = ref.watch(windowChromeControllerProvider);
    return AppBackdropSceneScope(
      owner: 'music.immersive',
      policy: AppBackdropPolicy.musicImmersive,
      child: Material(
        type: MaterialType.transparency,
        // F11 由 app.dart 全局按键处理器分发，本层不得再绑 F11
        //（硬件层与焦点树双重派发）；全屏走手动全屏，不设页面租约。
        child: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              widget.onClose();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          // 移动端与桌面同语言：不叠自有色层，动态壁纸由应用背景宿主
          // 透出，可读性由宿主 immersive 渐变与播放页自身轻量渐变承担，
          // 回切 Music 页时两侧同底无缝衔接。
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (fullVisual)
                MusicImmersivePlayer(reservedTopInset: safeTop + 58)
              else
                MusicMobileNowPlaying(onClose: widget.onClose),
              if (fullVisual)
                Positioned(
                  top: safeTop + 14,
                  left: 12,
                  right: 12,
                  child: _buildDesktopTopBar(
                    context,
                    isFullscreen:
                        kIsWeb ? _webFullscreen : windowChrome.isFullscreen,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopTopBar(
    BuildContext context, {
    required bool isFullscreen,
  }) {
    final visible = !isFullscreen || _topBarHovered;
    return SizedBox(
      height: 58,
      child: MouseRegion(
        onEnter: (_) => _setTopBarHovered(true),
        onExit: (_) => _setTopBarHovered(false),
        child: IgnorePointer(
          ignoring: !visible,
          child: AnimatedSlide(
            offset: visible ? Offset.zero : const Offset(0, -0.78),
            duration: MusicImmersiveMotion.duration(
              context,
              const Duration(milliseconds: 220),
            ),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: MusicImmersiveMotion.duration(
                context,
                const Duration(milliseconds: 180),
              ),
              curve: Curves.easeOutCubic,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBackButton(context),
                  const SleepTimerBadge(),
                  const Spacer(),
                  AppFullscreenButton(
                    isFullscreen: isFullscreen,
                    foregroundColor: MusicImmersivePalette.digital.text,
                    accentColor: MusicImmersivePalette.digital.accent,
                    onPressed: _toggleFullscreen,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackButton(BuildContext context) {
    return IconButton(
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      onPressed: widget.onClose,
      style: IconButton.styleFrom(
        backgroundColor: const Color(0xB812222A),
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
      ),
      icon: const Icon(Icons.arrow_back_rounded, size: 21),
    );
  }

  void _toggleFullscreen() {
    if (kIsWeb) {
      fs.toggleFullscreen();
      return;
    }
    // 手动全屏统一入口：无沉浸租约时切换全屏，有则先退出沉浸页。
    unawaited(_windowChromeController.toggleFullscreen());
  }

  void _setTopBarHovered(bool hovered) {
    if (_topBarHovered == hovered) {
      return;
    }
    setState(() => _topBarHovered = hovered);
  }
}

/// 定时关闭倒计时徽标：未开启时不占位。
class SleepTimerBadge extends ConsumerWidget {
  const SleepTimerBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timer = ref.watch(musicSleepTimerControllerProvider);
    final remaining = timer.remaining;
    if (remaining == null) {
      return const SizedBox.shrink();
    }
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.nightlight_round, size: 14, color: Colors.white70),
            const SizedBox(width: 5),
            Text(
              '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
