import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/video_colors.dart';
import 'package:omninest/features/video/domain/movie_models.dart'
    hide SubtitleTrack;
import 'package:omninest/features/video/presentation/widgets/movie_player_controls.dart';
import 'package:omninest/features/video/presentation/widgets/movie_player_progress_bar.dart';
import 'package:omninest/features/video/presentation/widgets/movie_player_volume.dart';

/// 播放器底部控制栏，根据输入方式使用桌面或移动布局。
class MoviePlayerBottomBar extends StatelessWidget {
  const MoviePlayerBottomBar({
    required this.plan,
    required this.polledPosition,
    required this.playerDuration,
    required this.bufferProgress,
    required this.isSeeking,
    required this.seekValue,
    required this.onSeekStart,
    required this.onSeeking,
    required this.onSeekEnd,
    required this.onMouseActivity,
    required this.volume,
    required this.isMuted,
    required this.onToggleMute,
    required this.onVolumeChanged,
    required this.setPlayerVolume,
    required this.playbackSpeed,
    required this.activeSubtitleId,
    required this.onAudioTap,
    required this.onSubtitleTap,
    required this.onSpeedTap,
    required this.onSettingsTap,
    required this.onFullscreenTap,
    required this.isFullscreen,
    required this.formatDuration,
    required this.playing,
    required this.onPlayPause,
    required this.isMobile,
    this.onPreviousEpisode,
    this.onNextEpisode,
    super.key,
  });

  final PlaybackPlan plan;
  final ValueNotifier<Duration> polledPosition;
  final Duration playerDuration;
  final double bufferProgress;
  final bool isSeeking;
  final double seekValue;
  final void Function(double) onSeekStart;
  final void Function(double) onSeeking;
  final void Function(double) onSeekEnd;
  final VoidCallback onMouseActivity;
  final double volume;
  final bool isMuted;
  final VoidCallback onToggleMute;
  final void Function(double) onVolumeChanged;
  final void Function(double) setPlayerVolume;
  final double playbackSpeed;
  final int? activeSubtitleId;
  final VoidCallback? onAudioTap;
  final VoidCallback onSubtitleTap;
  final VoidCallback onSpeedTap;
  final VoidCallback onSettingsTap;
  final VoidCallback onFullscreenTap;
  final bool isFullscreen;
  final String Function(Duration) formatDuration;
  final Stream<bool> playing;
  final VoidCallback onPlayPause;
  final bool isMobile;
  final VoidCallback? onPreviousEpisode;
  final VoidCallback? onNextEpisode;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final viewport = MediaQuery.sizeOf(context);
            final textScale = MediaQuery.textScalerOf(context).scale(1);
            final controlMaxWidth = constraints.maxWidth;
            final density = _resolveDensity(controlMaxWidth, textScale);
            final animationsDisabled = MediaQuery.disableAnimationsOf(context);
            final horizontalPadding = (controlMaxWidth * 0.012).clamp(
              12.0,
              density == _MoviePlayerControlDensity.expanded ? 28.0 : 22.0,
            );
            final proportionalBottomInset =
                viewport.height *
                switch ((isFullscreen, isMobile)) {
                  (true, true) => 0.035,
                  (true, false) => 0.06,
                  (false, true) => 0.012,
                  (false, false) => 0.018,
                };
            final bottomInset = proportionalBottomInset.clamp(
              isMobile ? 8.0 : 12.0,
              isFullscreen
                  ? (isMobile ? 36.0 : 80.0)
                  : (isMobile ? 18.0 : 28.0),
            );
            final topPadding = (viewport.height *
                    (isFullscreen ? 0.032 : 0.024))
                .clamp(24.0, 44.0);

            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, context.videoColors.playerBarBg],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: SizedBox(
                key: const Key('moviePlayerControlViewport'),
                width: double.infinity,
                child: AnimatedPadding(
                  key: const Key('moviePlayerBottomBarContent'),
                  duration:
                      animationsDisabled
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    topPadding,
                    horizontalPadding,
                    _bottomPaddingFor(density) + bottomInset,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MoviePlayerProgressBar(
                        polledPosition: polledPosition,
                        durationSeconds: plan.durationSeconds,
                        playerDuration: playerDuration,
                        bufferProgress: bufferProgress,
                        isSeeking: isSeeking,
                        seekValue: seekValue,
                        onSeekStart: onSeekStart,
                        onSeeking: onSeeking,
                        onSeekEnd: onSeekEnd,
                        onMouseActivity: onMouseActivity,
                        formatDuration: formatDuration,
                      ),
                      const SizedBox(height: 6),
                      AnimatedSwitcher(
                        duration:
                            animationsDisabled
                                ? Duration.zero
                                : const Duration(milliseconds: 160),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        child: switch (density) {
                          _MoviePlayerControlDensity.compact =>
                            _buildCompactControls(context),
                          _MoviePlayerControlDensity.medium =>
                            _buildMediumControls(context),
                          _MoviePlayerControlDensity.expanded =>
                            _buildExpandedControls(context),
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  _MoviePlayerControlDensity _resolveDensity(
    double availableWidth,
    double textScale,
  ) {
    final scale = textScale.clamp(1.0, 1.3);
    final compactRequirement = (isMobile ? 640.0 : 720.0) * scale;
    final expandedRequirement = (isMobile ? 1120.0 : 1260.0) * scale;
    if (availableWidth < compactRequirement) {
      return _MoviePlayerControlDensity.compact;
    }
    if (availableWidth < expandedRequirement) {
      return _MoviePlayerControlDensity.medium;
    }
    return _MoviePlayerControlDensity.expanded;
  }

  double _bottomPaddingFor(_MoviePlayerControlDensity density) {
    return switch (density) {
      _MoviePlayerControlDensity.compact => isMobile ? 8 : 10,
      _MoviePlayerControlDensity.medium => 12,
      _MoviePlayerControlDensity.expanded => 14,
    };
  }

  Widget _buildExpandedControls(BuildContext context) {
    return _buildInlineControls(
      context,
      key: const Key('moviePlayerControlsExpanded'),
      showVolumeSlider: true,
      showSpeed: true,
      compactTime: false,
    );
  }

  Widget _buildMediumControls(BuildContext context) {
    return _buildInlineControls(
      context,
      key: const Key('moviePlayerControlsMedium'),
      showVolumeSlider: false,
      showSpeed: true,
      compactTime: true,
    );
  }

  Widget _buildCompactControls(BuildContext context) {
    if (!isMobile) {
      return _buildInlineControls(
        context,
        key: const Key('moviePlayerControlsCompact'),
        showVolumeSlider: false,
        showSpeed: true,
        compactTime: true,
      );
    }
    final l10n = AppLocalizations.of(context);
    final targetSize = isMobile ? 48.0 : 44.0;
    return Column(
      key: const Key('moviePlayerControlsCompact'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: targetSize,
          child: Row(
            children: [
              Expanded(child: _buildTimeLabel(context, compact: true)),
              if (onAudioTap != null)
                MoviePlayerIconButton(
                  icon: Icons.language_rounded,
                  tooltip: l10n.coreLanguage,
                  onPressed: onAudioTap,
                  size: targetSize,
                ),
              MoviePlayerIconButton(
                icon:
                    activeSubtitleId != null
                        ? Icons.subtitles_rounded
                        : Icons.subtitles_off_rounded,
                tooltip: l10n.videoSubtitle,
                selected: activeSubtitleId != null,
                onPressed: onSubtitleTap,
                size: targetSize,
              ),
              SpeedButton(speed: playbackSpeed, onTap: onSpeedTap),
              MoviePlayerIconButton(
                icon: Icons.settings_rounded,
                tooltip: l10n.videoPlaybackSettings,
                onPressed: onSettingsTap,
                size: targetSize,
              ),
              MoviePlayerIconButton(
                icon:
                    isFullscreen
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                tooltip:
                    isFullscreen
                        ? l10n.videoExitFullscreen
                        : l10n.videoEnterFullscreen,
                onPressed: onFullscreenTap,
                size: targetSize,
              ),
            ],
          ),
        ),
        _buildTransportControls(context, targetSize: targetSize),
      ],
    );
  }

  Widget _buildInlineControls(
    BuildContext context, {
    required Key key,
    required bool showVolumeSlider,
    required bool showSpeed,
    required bool compactTime,
  }) {
    final targetSize = isMobile ? 48.0 : 44.0;
    return SizedBox(
      height: targetSize,
      child: Row(
        key: key,
        children: [
          Expanded(
            child: Row(
              key: const Key('moviePlayerLeftControls'),
              children: [
                _buildTransportControls(context, targetSize: targetSize),
                if (!isMobile) const SizedBox(width: 4),
                if (!isMobile)
                  MoviePlayerVolume(
                    volume: volume,
                    isMuted: isMuted,
                    onToggleMute: onToggleMute,
                    onVolumeChanged: onVolumeChanged,
                    onMouseActivity: onMouseActivity,
                    setPlayerVolume: setPlayerVolume,
                    showSlider: showVolumeSlider,
                  ),
                const SizedBox(width: 8),
                Flexible(child: _buildTimeLabel(context, compact: compactTime)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _buildRightControls(
            context,
            targetSize: targetSize,
            showSpeed: showSpeed,
          ),
        ],
      ),
    );
  }

  Widget _buildTransportControls(
    BuildContext context, {
    required double targetSize,
  }) {
    final l10n = AppLocalizations.of(context);
    return Row(
      key: const Key('moviePlayerTransportControls'),
      mainAxisSize: MainAxisSize.min,
      children: [
        MoviePlayerIconButton(
          icon: Icons.skip_previous_rounded,
          tooltip: l10n.videoPreviousEpisode,
          onPressed: onPreviousEpisode,
          size: targetSize,
        ),
        _PlayPauseButton(
          playing: playing,
          onPressed: onPlayPause,
          size: targetSize,
        ),
        MoviePlayerIconButton(
          icon: Icons.skip_next_rounded,
          tooltip: l10n.videoNextEpisode,
          onPressed: onNextEpisode,
          size: targetSize,
        ),
      ],
    );
  }

  Widget _buildRightControls(
    BuildContext context, {
    required double targetSize,
    required bool showSpeed,
  }) {
    final l10n = AppLocalizations.of(context);
    return Row(
      key: const Key('moviePlayerRightControls'),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onAudioTap != null)
          MoviePlayerIconButton(
            icon: Icons.language_rounded,
            tooltip: l10n.coreLanguage,
            onPressed: onAudioTap,
            size: targetSize,
          ),
        MoviePlayerIconButton(
          icon:
              activeSubtitleId != null
                  ? Icons.subtitles_rounded
                  : Icons.subtitles_off_rounded,
          tooltip: l10n.videoSubtitle,
          selected: activeSubtitleId != null,
          onPressed: onSubtitleTap,
          size: targetSize,
        ),
        if (showSpeed) SpeedButton(speed: playbackSpeed, onTap: onSpeedTap),
        MoviePlayerIconButton(
          icon: Icons.settings_rounded,
          tooltip: l10n.videoPlaybackSettings,
          onPressed: onSettingsTap,
          size: targetSize,
        ),
        MoviePlayerIconButton(
          icon:
              isFullscreen
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded,
          tooltip:
              isFullscreen
                  ? l10n.videoExitFullscreen
                  : l10n.videoEnterFullscreen,
          onPressed: onFullscreenTap,
          size: targetSize,
        ),
      ],
    );
  }

  Widget _buildTimeLabel(BuildContext context, {required bool compact}) {
    final colors = context.videoColors;
    return ValueListenableBuilder<Duration>(
      valueListenable: polledPosition,
      builder: (context, position, _) {
        final duration =
            plan.durationSeconds > 0
                ? Duration(seconds: plan.durationSeconds)
                : playerDuration;
        return Text(
          compact
              ? '${formatDuration(position)} / ${formatDuration(duration)}'
              : '${formatDuration(position)}  /  ${formatDuration(duration)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.playerControlForeground,
            fontSize: AppTypography.bodySmall,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        );
      },
    );
  }
}

enum _MoviePlayerControlDensity { compact, medium, expanded }

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({
    required this.playing,
    required this.onPressed,
    required this.size,
  });

  final Stream<bool> playing;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: playing,
      initialData: false,
      builder: (context, snapshot) {
        final isPlaying = snapshot.data ?? false;
        return MoviePlayerIconButton(
          icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          tooltip:
              isPlaying
                  ? AppLocalizations.of(context).videoPause
                  : AppLocalizations.of(context).videoPlay,
          onPressed: onPressed,
          size: size,
          iconSize: 28,
        );
      },
    );
  }
}
