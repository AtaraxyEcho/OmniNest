import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/video_colors.dart';

/// 片尾自动连播提示卡：倒计时结束前可改成立即播放或取消。
class MoviePlayerAutoplayNotice extends StatelessWidget {
  const MoviePlayerAutoplayNotice({
    required this.episodeTitle,
    required this.secondsLeft,
    required this.onPlayNow,
    required this.onCancel,
    super.key,
  });

  final String episodeTitle;
  final int secondsLeft;
  final VoidCallback onPlayNow;
  final VoidCallback onCancel;

  static const Duration countdown = Duration(seconds: 5);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Positioned(
      right: 24,
      bottom: 96,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.42,
        ),
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: context.videoColors.playerPanelSurface.withValues(
                alpha: 0.94,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.videoAutoplayCountdown(secondsLeft),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: AppTypography.labelMedium,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  episodeTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: AppTypography.bodyMedium,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton(
                      onPressed: onPlayNow,
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                      ),
                      child: Text(l10n.videoHeroWatchNow),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: onCancel,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Text(l10n.coreCancel),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
