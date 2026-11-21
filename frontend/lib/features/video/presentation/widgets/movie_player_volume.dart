import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/video_colors.dart';
import 'package:omninest/core/widgets/app_slider.dart';
import 'package:omninest/features/video/presentation/widgets/movie_player_controls.dart';

class MoviePlayerVolume extends StatelessWidget {
  const MoviePlayerVolume({
    required this.volume,
    required this.isMuted,
    required this.onToggleMute,
    required this.onVolumeChanged,
    required this.onMouseActivity,
    required this.setPlayerVolume,
    this.showSlider = true,
    this.buttonSize = 32,
    super.key,
  });

  final double volume;
  final bool isMuted;
  final VoidCallback onToggleMute;
  final void Function(double) onVolumeChanged;
  final VoidCallback onMouseActivity;
  final void Function(double) setPlayerVolume;
  final bool showSlider;
  final double buttonSize;

  @override
  Widget build(BuildContext context) {
    final colors = context.videoColors;
    final effectiveVolume = isMuted ? 0 : volume.clamp(0, 100).round();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        MoviePlayerIconButton(
          icon:
              isMuted || volume <= 0
                  ? Icons.volume_off_rounded
                  : volume < 50
                  ? Icons.volume_down_rounded
                  : Icons.volume_up_rounded,
          tooltip:
              isMuted || volume <= 0
                  ? AppLocalizations.of(context).videoUnmute
                  : AppLocalizations.of(context).videoMute,
          onPressed: onToggleMute,
          size: buttonSize,
          iconSize: buttonSize <= 34 ? 19 : 22,
        ),
        if (showSlider) ...[
          SizedBox(
            width: 80,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                activeTrackColor: colors.playerTimelinePlayed,
                inactiveTrackColor: colors.playerTimelineInactive,
                thumbColor: colors.playerControlForeground,
                overlayColor: colors.playerControlForeground.withValues(
                  alpha: 0.14,
                ),
              ),
              child: AppSlider(
                value: isMuted ? 0 : volume.clamp(0, 100),
                min: 0,
                max: 100,
                onChanged: (v) {
                  onVolumeChanged(v);
                  setPlayerVolume(v);
                  onMouseActivity();
                },
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 34,
            child: Text(
              '$effectiveVolume%',
              textAlign: TextAlign.right,
              maxLines: 1,
              style: TextStyle(
                color: colors.playerControlMuted,
                fontSize: AppTypography.labelSmall,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
