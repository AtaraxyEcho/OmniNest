import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
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
    super.key,
  });

  final double volume;
  final bool isMuted;
  final VoidCallback onToggleMute;
  final void Function(double) onVolumeChanged;
  final VoidCallback onMouseActivity;
  final void Function(double) setPlayerVolume;
  final bool showSlider;

  @override
  Widget build(BuildContext context) {
    final colors = context.videoColors;
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
          size: 44,
          iconSize: 22,
        ),
        if (showSlider)
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
                value: volume.clamp(0, 100),
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
      ],
    );
  }
}
