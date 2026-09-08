part of 'music_immersive_player.dart';

class _DigitalImmersiveGlassPlayerControls extends StatelessWidget {
  const _DigitalImmersiveGlassPlayerControls({
    required this.palette,
    required this.player,
    required this.track,
    required this.isPlaying,
    required this.settings,
    required this.scale,
    required this.onPrevious,
    required this.onTogglePlayback,
    required this.onNext,
  });

  final MusicImmersivePalette palette;
  final MusicAudioPlayback player;
  final MusicTrack? track;
  final bool isPlaying;
  final PortalGlassPlayerSettings settings;
  final double scale;
  final VoidCallback onPrevious;
  final VoidCallback onTogglePlayback;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 660;
        final dense = constraints.maxWidth < 520;
        final controlHeight = (dense ? 54.0 : 64.0) * scale;
        final radius = BorderRadius.circular(10);
        return ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.24),
                borderRadius: radius,
                border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              ),
              child: SizedBox(
                height: controlHeight,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: dense ? 8 : 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      if (!dense) _buildTrackThumb(),
                      if (!dense) SizedBox(width: 10 * scale),
                      _GlassIconButton(
                        palette: palette,
                        tooltip: l10n.videoPreviousEpisode,
                        icon: Icons.skip_previous_rounded,
                        onTap: onPrevious,
                      ),
                      SizedBox(width: 6 * scale),
                      MusicPlaybackButton(
                        tooltip: isPlaying ? l10n.musicPause : l10n.musicPlay,
                        isPlaying: isPlaying,
                        onPressed: onTogglePlayback,
                        buttonSize: MusicPlaybackButtonSize.regular,
                        backgroundColor: const Color(0xFF28676B),
                        accentColor: palette.accent,
                        foregroundColor: palette.text,
                      ),
                      SizedBox(width: 6 * scale),
                      _GlassIconButton(
                        palette: palette,
                        tooltip: l10n.videoNextEpisode,
                        icon: Icons.skip_next_rounded,
                        onTap: onNext,
                      ),
                      if (settings.progressEnabled) ...[
                        SizedBox(width: compact ? 10 : 16),
                        Expanded(
                          child: _GlassMusicProgress(
                            palette: palette,
                            player: player,
                            enabled: track != null,
                          ),
                        ),
                      ] else
                        const Spacer(),
                      if (settings.volumeEnabled && !compact) ...[
                        SizedBox(width: 14 * scale),
                        _GlassVolumeControl(
                          palette: palette,
                          player: player,
                          tooltip: l10n.portalMusicVisualizerVolume,
                        ),
                      ],
                      if (!compact) ...[
                        SizedBox(width: 8 * scale),
                        _GlassIconButton(
                          palette: palette,
                          tooltip: l10n.portalMusicVisualizerOpenSystem,
                          icon: Icons.open_in_new_rounded,
                          onTap: () => context.go('/music'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTrackThumb() {
    final size = (42 * scale).clamp(34.0, 46.0).toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: _MusicImmersiveArtwork(
        imageUrl: track?.coverUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: 180,
        cacheHeight: 180,
        fallback: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          color: palette.surfaceStrong.withValues(alpha: 0.72),
          child: Icon(
            Icons.music_note_rounded,
            size: size * 0.42,
            color: palette.text.withValues(alpha: 0.78),
          ),
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.palette,
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final MusicImmersivePalette palette;
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const size = 36.0;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: SizedBox.square(
          dimension: size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.08),
            ),
            child: Icon(icon, color: palette.text, size: 21),
          ),
        ),
      ),
    );
  }
}

class _GlassMusicProgress extends StatelessWidget {
  const _GlassMusicProgress({
    required this.palette,
    required this.player,
    required this.enabled,
  });

  final MusicImmersivePalette palette;
  final MusicAudioPlayback player;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return StreamBuilder<Duration>(
      stream: player.stream.duration,
      initialData: player.state.duration,
      builder: (context, durationSnapshot) {
        final duration = durationSnapshot.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: player.stream.position,
          initialData: player.state.position,
          builder: (context, positionSnapshot) {
            final position = positionSnapshot.data ?? Duration.zero;
            final totalMs = duration.inMilliseconds;
            final value =
                totalMs <= 0
                    ? 0.0
                    : (position.inMilliseconds / totalMs)
                        .clamp(0.0, 1.0)
                        .toDouble();
            return Row(
              children: [
                Text(_formatDuration(position), style: _timeStyle()),
                const SizedBox(width: 8),
                Expanded(
                  child: MusicPlaybackProgressBar(
                    value: value,
                    semanticLabel: l10n.portalMusicVisualizerSeek,
                    activeColor: palette.accent,
                    thumbColor: palette.text,
                    onChanged:
                        enabled && totalMs > 0
                            ? (next) => player.seek(
                              Duration(milliseconds: (totalMs * next).round()),
                            )
                            : null,
                  ),
                ),
                const SizedBox(width: 8),
                Text(_formatDuration(duration), style: _timeStyle()),
              ],
            );
          },
        );
      },
    );
  }

  TextStyle _timeStyle() {
    return TextStyle(
      color: palette.text.withValues(alpha: 0.70),
      fontSize: AppTypography.labelSmall,
      fontFeatures: const [ui.FontFeature.tabularFigures()],
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _GlassVolumeControl extends StatelessWidget {
  const _GlassVolumeControl({
    required this.palette,
    required this.player,
    required this.tooltip,
  });

  final MusicImmersivePalette palette;
  final MusicAudioPlayback player;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 116,
        child: StreamBuilder<double>(
          stream: player.stream.volume,
          initialData: player.state.volume,
          builder: (context, snapshot) {
            final volume = (snapshot.data ?? 100).clamp(0.0, 100.0).toDouble();
            return Row(
              children: [
                Icon(
                  volume <= 0
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                  size: 17,
                  color: palette.text.withValues(alpha: 0.78),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 4,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 10,
                      ),
                      activeTrackColor: palette.text.withValues(alpha: 0.68),
                      inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
                      thumbColor: palette.text,
                      overlayColor: palette.text.withValues(alpha: 0.10),
                    ),
                    child: AppSlider(
                      value: volume / 100,
                      onChanged: (next) => player.setVolume(next * 100),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
