import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/video_colors.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/features/video/presentation/widgets/movie_player_controls.dart';

/// 播放器中央的触控操作区。
class MoviePlayerCenterControls extends StatelessWidget {
  const MoviePlayerCenterControls({
    required this.playing,
    required this.isMobile,
    required this.onPlayPause,
    required this.onSeekBackward,
    required this.onSeekForward,
    super.key,
  });

  final Stream<bool> playing;
  final bool isMobile;
  final VoidCallback onPlayPause;
  final VoidCallback onSeekBackward;
  final VoidCallback onSeekForward;

  @override
  Widget build(BuildContext context) {
    // 仅按钮区接收命中；空白处不拦截，点击落到画面层的播放/暂停手势。
    return Positioned.fill(
      child: Stack(
        children: [
          const Positioned.fill(child: SizedBox.expand()),
          Center(
            child: StreamBuilder<bool>(
              stream: playing,
              initialData: false,
              builder: (context, snapshot) {
                final isPlaying = snapshot.data ?? false;
                if (!isMobile && isPlaying) {
                  return const SizedBox.shrink();
                }
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isMobile) ...[
                      MoviePlayerIconButton(
                        // 样例打磨轮：±10s 用双三角快进/快退字形（主流视频语言），
                        // 秒数只由读屏与 tooltip 承担，不再画进图标里。
                        icon: Icons.fast_rewind_rounded,
                        tooltip: AppLocalizations.of(
                          context,
                        ).videoSeekBackwardSeconds(10),
                        onPressed: onSeekBackward,
                        size: 52,
                        iconSize: 28,
                        filled: true,
                      ),
                      const SizedBox(width: 24),
                    ],
                    MoviePlayerIconButton(
                      icon:
                          isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                      tooltip:
                          isPlaying
                              ? AppLocalizations.of(context).videoPause
                              : AppLocalizations.of(context).videoPlay,
                      onPressed: onPlayPause,
                      size: isMobile ? 68 : 72,
                      iconSize: isMobile ? 40 : 42,
                      filled: true,
                    ),
                    if (isMobile) ...[
                      const SizedBox(width: 24),
                      MoviePlayerIconButton(
                        icon: Icons.fast_forward_rounded,
                        tooltip: AppLocalizations.of(
                          context,
                        ).videoSeekForwardSeconds(10),
                        onPressed: onSeekForward,
                        size: 52,
                        iconSize: 28,
                        filled: true,
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

enum MoviePlayerFeedbackPlacement { center, left, right }

/// 显示快进、快退等短时操作反馈。
class MoviePlayerActionFeedback extends StatelessWidget {
  const MoviePlayerActionFeedback({
    required this.icon,
    required this.label,
    required this.placement,
    super.key,
  });

  final IconData icon;
  final String label;
  final MoviePlayerFeedbackPlacement placement;

  @override
  Widget build(BuildContext context) {
    final alignment = switch (placement) {
      MoviePlayerFeedbackPlacement.center => Alignment.center,
      MoviePlayerFeedbackPlacement.left => const Alignment(-0.55, 0),
      MoviePlayerFeedbackPlacement.right => const Alignment(0.55, 0),
    };
    final colors = context.videoColors;
    return Positioned.fill(
      child: IgnorePointer(
        child: Align(
          alignment: alignment,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.playerPanelSurface.withValues(alpha: 0.86),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: colors.playerControlForeground, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: colors.playerControlForeground,
                      fontSize: AppTypography.bodyMedium,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 样例 `.v-flash`（`desktop.css:324`）：播放/暂停切换的瞬间，画面正中
/// 一枚 92×92 的圆形图标从 `scale(.7)` 放大到 1.5 并在 .7s 内淡出。
///
/// 只在动作发生时挂上去、由外层定时器摘掉，空闲时不留任何层；每帧变化的
/// 圆用 `RepaintBoundary` 与视频帧隔开。样例的 `backdrop-filter: blur(10px)`
/// 也按 1:1 复刻，裁剪在 92×92 的圆内，不影响窗口其它区域。
class MoviePlayerCenterFlash extends StatefulWidget {
  const MoviePlayerCenterFlash({required this.icon, super.key});

  final IconData icon;

  @override
  State<MoviePlayerCenterFlash> createState() => _MoviePlayerCenterFlashState();
}

class _MoviePlayerCenterFlashState extends State<MoviePlayerCenterFlash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: MotionToken.playerFlash,
  );

  @override
  void initState() {
    super.initState();
    // initState 里还不能读 MediaQuery，用平台无障碍标志决定要不要播。
    if (MotionToken.prefersReducedOnPlatform()) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MotionToken.prefersReduced(context)) {
      // 减动效下连 ticker 都不留，避免一个用户看不见的动画空转 700ms。
      _controller.stop();
      return const SizedBox.shrink();
    }
    return Positioned.fill(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = MotionToken.curve.transform(_controller.value);
              return Opacity(
                opacity: 1 - t,
                child: Transform.scale(
                  scale: 0.7 + 0.8 * t,
                  child: Center(
                    // 样例 `desktop.css:324` 的 `backdrop-filter: blur(10px)`：
                    // 先裁成圆再把背后的视频帧模糊 10σ，只作用在 92×92 内。
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(46),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          key: const ValueKey('player-center-flash'),
                          width: 92,
                          height: 92,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.18),
                            ),
                          ),
                          child: Icon(
                            widget.icon,
                            size: 34,
                            color: Colors.white,
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
  }
}
