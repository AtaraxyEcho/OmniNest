import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/video_colors.dart';
import 'package:omninest/features/video/presentation/widgets/movie_player_controls.dart';

/// 播放器顶部导航和影片上下文。
class MoviePlayerTopBar extends StatelessWidget {
  const MoviePlayerTopBar({
    required this.title,
    required this.onBack,
    required this.onInfoTap,
    required this.isMobile,
    this.subtitle,
    super.key,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onBack;
  final VoidCallback onInfoTap;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    final colors = context.videoColors;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xC7000000), // black 0.78
              Colors.transparent,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(
              children: [
                MoviePlayerIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: AppLocalizations.of(context).videoBackToDetail,
                  onPressed: onBack,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.playerControlForeground,
                          fontSize: isMobile ? 15 : 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (!isMobile && subtitle?.isNotEmpty == true) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.playerControlMuted,
                            fontSize: AppTypography.bodySmall,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                MoviePlayerIconButton(
                  icon: isMobile ? Icons.more_vert_rounded : Icons.info_outline,
                  tooltip:
                      isMobile
                          ? AppLocalizations.of(context).videoPlaybackSettings
                          : AppLocalizations.of(context).videoPlaybackInfo,
                  onPressed: onInfoTap,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
