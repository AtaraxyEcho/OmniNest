import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/video_colors.dart';
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
                        icon: Icons.replay_10_rounded,
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
                        icon: Icons.forward_10_rounded,
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
