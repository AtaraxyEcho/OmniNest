import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/core/window/window_chrome_controller.dart';
import 'package:omninest/core/widgets/app_fullscreen_control.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop_policy.dart';
import 'package:omninest/features/backdrop/backdrop_ui.dart';
import 'package:omninest/features/music/presentation/player/music_mobile_now_playing.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_player.dart';
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
  late final WindowChromeController _windowChromeController;
  WindowChromeLease? _fullscreenLease;

  @override
  void initState() {
    super.initState();
    _windowChromeController = ref.read(windowChromeControllerProvider.notifier);
  }

  @override
  void dispose() {
    _fullscreenLease?.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final fullVisual = isDesktopPlatform && !kIsWeb && width >= 900;
    final safeTop = MediaQuery.paddingOf(context).top;
    final windowChrome = ref.watch(windowChromeControllerProvider);
    return AppBackdropSceneScope(
      owner: 'music.immersive',
      policy: AppBackdropPolicy.musicImmersive,
      child: Material(
        type: MaterialType.transparency,
        child: AppFullscreenShortcutScope(
          onToggle: _toggleFullscreen,
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
                    top: safeTop,
                    left: 12,
                    right: 12,
                    child: _buildDesktopTopBar(
                      context,
                      isFullscreen: windowChrome.isFullscreen,
                    ),
                  ),
              ],
            ),
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
    final lease = _fullscreenLease;
    if (lease == null) {
      _fullscreenLease = _windowChromeController.acquireFullscreen(
        owner: 'music.immersive.overlay',
      );
      return;
    }
    lease.release();
    _fullscreenLease = null;
  }

  void _setTopBarHovered(bool hovered) {
    if (_topBarHovered == hovered) {
      return;
    }
    setState(() => _topBarHovered = hovered);
  }
}
