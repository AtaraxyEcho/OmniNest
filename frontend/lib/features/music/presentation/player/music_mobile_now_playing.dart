import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/mobile_layout_tokens.dart';
import 'package:omninest/features/music/application/music_audio_playback.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_playback_session.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_primitives.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_queue_sheet.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_lyrics.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_style.dart';
import 'package:omninest/features/music/presentation/widgets/music_playback_controls.dart';

/// 移动端音乐播放详情页。
class MusicMobileNowPlaying extends ConsumerStatefulWidget {
  const MusicMobileNowPlaying({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  ConsumerState<MusicMobileNowPlaying> createState() =>
      _MusicMobileNowPlayingState();
}

class _MusicMobileNowPlayingState extends ConsumerState<MusicMobileNowPlaying> {
  late final PageController _pageController;
  int _selectedView = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final center = ref.watch(musicCenterControllerProvider).asData?.value;
    final session = ref.watch(musicPlaybackSessionProvider);
    final item = center?.currentItem;
    final track = item?.track ?? center?.activeTrack;
    final lyrics = track?.lyricLines ?? const <MusicLyricLine>[];
    return SafeArea(
      child: Stack(
        fit: StackFit.expand,
        children: [
          _MobileCoverBackdrop(track: track),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: Column(
              children: [
                SizedBox(
                  height: 44,
                  child: Row(
                    children: [
                      _MobileHeaderButton(
                        tooltip:
                            MaterialLocalizations.of(context).backButtonTooltip,
                        icon: Icons.keyboard_arrow_down_rounded,
                        onPressed: widget.onClose,
                      ),
                      Expanded(
                        child: Text(
                          track?.title ?? l10n.musicDeckNowPlaying,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: AppTypography.titleMedium,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      _MobileHeaderButton(
                        tooltip: l10n.musicQueueTitle,
                        icon: Icons.queue_music_rounded,
                        onPressed: () => showMusicDeckQueue(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    onPageChanged:
                        (index) => setState(() => _selectedView = index),
                    children: [
                      _MobileArtworkView(
                        track: track,
                        onShowLyrics: () => _selectView(1),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
                        child: MusicImmersiveLyrics(
                          palette: MusicImmersivePalette.digital,
                          player: session.player,
                          track: track,
                          lyrics: lyrics,
                          scale:
                              MediaQuery.sizeOf(context).width < 390
                                  ? 0.86
                                  : 0.94,
                          onTogglePlayback:
                              () =>
                                  ref
                                      .read(
                                        musicCenterControllerProvider.notifier,
                                      )
                                      .togglePlayback(),
                          onPrevious:
                              () =>
                                  ref
                                      .read(
                                        musicCenterControllerProvider.notifier,
                                      )
                                      .previousTrack(),
                          onNext:
                              () =>
                                  ref
                                      .read(
                                        musicCenterControllerProvider.notifier,
                                      )
                                      .nextTrack(),
                        ),
                      ),
                    ],
                  ),
                ),
                _MobileViewSwitcher(
                  selectedIndex: _selectedView,
                  artworkLabel: l10n.musicNowPlayingArtwork,
                  lyricsLabel: l10n.musicNowPlayingLyrics,
                  onSelected: _selectView,
                ),
                const SizedBox(height: 8),
                _MobileTrackHeader(
                  item: item,
                  track: track,
                  onToggleFavorite:
                      track == null || item?.ref is! LocalMusicRef
                          ? null
                          : () => _toggleFavorite(context, track),
                ),
                const SizedBox(height: 6),
                _MobilePlaybackControls(
                  player: session.player,
                  enabled: track != null,
                  isPlaying: center?.isPlaying == true,
                  shuffleEnabled: center?.shuffleEnabled == true,
                  repeatMode: center?.repeatMode ?? MusicRepeatMode.off,
                  onToggleShuffle:
                      () =>
                          ref
                              .read(musicCenterControllerProvider.notifier)
                              .toggleShuffle(),
                  onPrevious:
                      () =>
                          ref
                              .read(musicCenterControllerProvider.notifier)
                              .previousTrack(),
                  onTogglePlayback:
                      () =>
                          ref
                              .read(musicCenterControllerProvider.notifier)
                              .togglePlayback(),
                  onNext:
                      () =>
                          ref
                              .read(musicCenterControllerProvider.notifier)
                              .nextTrack(),
                  onToggleRepeat:
                      () =>
                          ref
                              .read(musicCenterControllerProvider.notifier)
                              .toggleRepeatMode(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _selectView(int index) {
    if (_selectedView == index) {
      return;
    }
    setState(() => _selectedView = index);
    unawaited(
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  Future<void> _toggleFavorite(BuildContext context, MusicTrack track) async {
    try {
      await ref
          .read(musicCenterControllerProvider.notifier)
          .toggleFavorite(track);
    } on Exception {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).musicPlaybackError),
        ),
      );
    }
  }
}

class _MobileCoverBackdrop extends StatelessWidget {
  const _MobileCoverBackdrop({required this.track});

  final MusicTrack? track;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 360),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: SizedBox.expand(
            key: ValueKey<String?>('mobile-backdrop-${track?.id}'),
            child: Transform.scale(
              scale: 1.18,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
                child: MusicDeckArtwork(
                  title: track?.title ?? '',
                  imageUrl: track?.coverUrl,
                  borderRadius: 0,
                ),
              ),
            ),
          ),
        ),
        ColoredBox(color: const Color(0xB8050B0F)),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x24000000), Color(0xA6080C0F)],
              stops: [0.35, 1],
            ),
          ),
        ),
      ],
    );
  }
}

class _MobileArtworkView extends StatelessWidget {
  const _MobileArtworkView({required this.track, required this.onShowLyrics});

  final MusicTrack? track;
  final VoidCallback onShowLyrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = math.min(
          math.max(1, constraints.maxWidth - 32),
          math.max(1, constraints.maxHeight - 28),
        );
        final coverSize = available.clamp(1.0, 340.0).toDouble();
        return Center(
          child: Semantics(
            button: true,
            label: AppLocalizations.of(context).musicNowPlayingLyrics,
            child: GestureDetector(
              onTap: onShowLyrics,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                child: SizedBox.square(
                  key: ValueKey<String?>('mobile-cover-${track?.id}'),
                  dimension: coverSize,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.40),
                          blurRadius: 8,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: MusicDeckArtwork(
                      title: track?.title ?? '',
                      imageUrl: track?.coverUrl,
                      borderRadius: 8,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MobileViewSwitcher extends StatelessWidget {
  const _MobileViewSwitcher({
    required this.selectedIndex,
    required this.artworkLabel,
    required this.lyricsLabel,
    required this.onSelected,
  });

  final int selectedIndex;
  final String artworkLabel;
  final String lyricsLabel;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _MobileViewButton(
            tooltip: artworkLabel,
            icon: Icons.album_outlined,
            selected: selectedIndex == 0,
            onPressed: () => onSelected(0),
          ),
          const SizedBox(width: 18),
          _MobileViewButton(
            tooltip: lyricsLabel,
            icon: Icons.lyrics_outlined,
            selected: selectedIndex == 1,
            onPressed: () => onSelected(1),
          ),
        ],
      ),
    );
  }
}

class _MobileViewButton extends StatelessWidget {
  const _MobileViewButton({
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color =
        selected
            ? const Color(0xFF72D6C9)
            : Colors.white.withValues(alpha: 0.58);
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        selected: selected,
        label: tooltip,
        child: InkResponse(
          onTap: onPressed,
          radius: 24,
          child: SizedBox(
            width: 42,
            height: 34,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(icon, size: 19, color: color),
                const SizedBox(height: 4),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: selected ? 22 : 0,
                  height: 2,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileHeaderButton extends StatelessWidget {
  const _MobileHeaderButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: Colors.black.withValues(alpha: 0.22),
        minimumSize: const Size(40, 40),
        maximumSize: const Size(40, 40),
      ),
      icon: Icon(icon, size: 22),
    );
  }
}

class _MobileTrackHeader extends StatelessWidget {
  const _MobileTrackHeader({
    required this.item,
    required this.track,
    required this.onToggleFavorite,
  });

  final MusicPlayableItem? item;
  final MusicTrack? track;
  final VoidCallback? onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                track?.title ?? l10n.musicNotPlaying,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.mobileColors.textPrimary,
                  fontSize: AppTypography.headlineSmall,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                track == null
                    ? l10n.musicDeckSelectTrack
                    : '${track!.artistName} / ${track!.albumTitle}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.64),
                  fontSize: AppTypography.bodySmall,
                ),
              ),
            ],
          ),
        ),
        if (item?.ref is LocalMusicRef)
          IconButton(
            tooltip:
                track?.favorite == true
                    ? l10n.musicUnfavorite
                    : l10n.musicFavorite,
            onPressed: onToggleFavorite,
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Icon(
                track?.favorite == true
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                key: ValueKey<bool>(track?.favorite == true),
                color:
                    track?.favorite == true
                        ? const Color(0xFFF2D986)
                        : Colors.white.withValues(alpha: 0.84),
              ),
            ),
          ),
      ],
    );
  }
}

class _MobilePlaybackControls extends StatelessWidget {
  const _MobilePlaybackControls({
    required this.player,
    required this.enabled,
    required this.isPlaying,
    required this.shuffleEnabled,
    required this.repeatMode,
    required this.onToggleShuffle,
    required this.onPrevious,
    required this.onTogglePlayback,
    required this.onNext,
    required this.onToggleRepeat,
  });

  final MusicAudioPlayback player;
  final bool enabled;
  final bool isPlaying;
  final bool shuffleEnabled;
  final MusicRepeatMode repeatMode;
  final VoidCallback onToggleShuffle;
  final VoidCallback onPrevious;
  final VoidCallback onTogglePlayback;
  final VoidCallback onNext;
  final VoidCallback onToggleRepeat;

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
            final progress =
                totalMs <= 0
                    ? 0.0
                    : (position.inMilliseconds / totalMs)
                        .clamp(0.0, 1.0)
                        .toDouble();
            return Column(
              children: [
                MusicPlaybackProgressBar(
                  value: progress,
                  semanticLabel: l10n.portalMusicVisualizerSeek,
                  activeColor: const Color(0xFF72D6C9),
                  inactiveColor: Colors.white.withValues(alpha: 0.14),
                  thumbColor: Colors.white,
                  onChanged:
                      enabled && totalMs > 0
                          ? (value) => player.seek(
                            Duration(milliseconds: (totalMs * value).round()),
                          )
                          : null,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Text(_formatDuration(position), style: _timeStyle),
                      const Spacer(),
                      Text(_formatDuration(duration), style: _timeStyle),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      tooltip: l10n.musicShuffle,
                      onPressed: enabled ? onToggleShuffle : null,
                      icon: Icon(Icons.shuffle_rounded, size: 20),
                      color:
                          shuffleEnabled
                              ? const Color(0xFF72D6C9)
                              : Colors.white.withValues(alpha: 0.62),
                    ),
                    IconButton(
                      tooltip: l10n.musicDeckPrevious,
                      onPressed: enabled ? onPrevious : null,
                      icon: Icon(Icons.skip_previous_rounded, size: 30),
                      color: Colors.white,
                    ),
                    MusicPlaybackButton(
                      isPlaying: isPlaying,
                      tooltip: isPlaying ? l10n.musicPause : l10n.musicPlay,
                      onPressed: enabled ? onTogglePlayback : null,
                      buttonSize: MusicPlaybackButtonSize.regular,
                      backgroundColor: const Color(0xFF153C43),
                      accentColor: const Color(0xFF72D6C9),
                      foregroundColor: Colors.white,
                    ),
                    IconButton(
                      tooltip: l10n.musicDeckNext,
                      onPressed: enabled ? onNext : null,
                      icon: Icon(Icons.skip_next_rounded, size: 30),
                      color: Colors.white,
                    ),
                    IconButton(
                      tooltip: _repeatTooltip(l10n),
                      onPressed: enabled ? onToggleRepeat : null,
                      icon: Icon(
                        repeatMode == MusicRepeatMode.one
                            ? Icons.repeat_one_rounded
                            : Icons.repeat_rounded,
                        size: 20,
                      ),
                      color:
                          repeatMode == MusicRepeatMode.off
                              ? Colors.white.withValues(alpha: 0.62)
                              : const Color(0xFF72D6C9),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  TextStyle get _timeStyle => TextStyle(
    color: Colors.white.withValues(alpha: 0.58),
    fontSize: AppTypography.labelSmall,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _repeatTooltip(AppLocalizations l10n) {
    return switch (repeatMode) {
      MusicRepeatMode.off => l10n.musicRepeatOff,
      MusicRepeatMode.all => l10n.musicRepeatAll,
      MusicRepeatMode.one => l10n.musicRepeatOne,
    };
  }
}
