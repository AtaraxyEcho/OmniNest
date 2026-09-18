import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/music_colors.dart';
import 'package:omninest/features/music/application/music_audio_playback.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_playback_session.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_primitives.dart';
import 'package:omninest/features/music/presentation/player/music_playback_settings_dialog.dart';
import 'package:omninest/features/music/presentation/widgets/music_playback_controls.dart';
import 'package:omninest/features/music/presentation/widgets/music_volume_button.dart';
import 'package:omninest/core/log/dev_log.dart';

/// Mini Player 可注入配色。
class MusicMiniPlayerPalette {
  const MusicMiniPlayerPalette({
    required this.text,
    required this.muted,
    required this.accent,
    required this.onAccent,
  });

  final Color text;
  final Color muted;
  final Color accent;
  final Color onAccent;
}

/// 全平台共用的紧凑 Music Deck 播放控制岛。
class MusicDeckMiniPlayer extends ConsumerStatefulWidget {
  const MusicDeckMiniPlayer({
    required this.compact,
    required this.onOpenQueue,
    this.onOpenPlayer,
    this.onOpenImmersive,
    this.palette,
    this.managePlaybackSession = false,
    this.embedded = false,
    super.key,
  });

  final bool compact;
  final VoidCallback onOpenQueue;
  final VoidCallback? onOpenPlayer;
  final VoidCallback? onOpenImmersive;
  final MusicMiniPlayerPalette? palette;
  final bool managePlaybackSession;
  final bool embedded;

  @override
  ConsumerState<MusicDeckMiniPlayer> createState() =>
      _MusicDeckMiniPlayerState();
}

class _MusicDeckMiniPlayerState extends ConsumerState<MusicDeckMiniPlayer> {
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  DateTime _lastPositionPaint = DateTime.fromMillisecondsSinceEpoch(0);
  bool _syncScheduled = false;

  MusicMiniPlayerPalette _palette(BuildContext context) {
    final colors = context.musicColors;
    return widget.palette ??
        MusicMiniPlayerPalette(
          text: colors.onSurface,
          muted: colors.onSurfaceVariant,
          accent: colors.primary,
          onAccent: Theme.of(context).colorScheme.onPrimary,
        );
  }

  @override
  void initState() {
    super.initState();
    _bindPlayer(ref.read(musicPlaybackSessionProvider).player);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.managePlaybackSession) {
        _schedulePlaybackSync();
      }
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.managePlaybackSession) {
      ref.listen(musicCenterControllerProvider, (previous, next) {
        _schedulePlaybackSync();
      });
    }
    final session = ref.watch(musicPlaybackSessionProvider);
    final music = ref.watch(musicCenterControllerProvider).asData?.value;
    final item = music?.currentItem;
    final track = _resolveDisplayTrack(music);
    final playing =
        session.player.state.playing &&
        track != null &&
        item?.track.id == track.id;
    final progress =
        _duration.inMilliseconds <= 0
            ? 0.0
            : (_position.inMilliseconds / _duration.inMilliseconds).clamp(
              0.0,
              1.0,
            );
    if (widget.compact) {
      final compactContent = _buildCompactContent(
        context,
        track: track,
        item: item,
        playing: playing,
        progress: progress,
      );
      if (widget.embedded) {
        return Align(alignment: Alignment.topLeft, child: compactContent);
      }
      return MusicDeckGlass(opacity: 0.30, blur: 18, child: compactContent);
    }
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(14, 7, 12, 7),
      child: SizedBox(
        height: 66,
        child: Row(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: widget.onOpenPlayer,
              child: SizedBox.square(
                dimension: 52,
                child: MusicDeckArtwork(
                  title: track?.title ?? '',
                  imageUrl: track?.coverUrl,
                  borderRadius: 5,
                ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              flex: 3,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track?.title ??
                          AppLocalizations.of(context).musicNotPlaying,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _palette(context).text,
                        fontSize: AppTypography.bodyMedium,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      track?.artistName ??
                          AppLocalizations.of(context).musicDeckSelectTrack,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _palette(context).muted,
                        fontSize: AppTypography.labelSmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            IconButton(
              tooltip: AppLocalizations.of(context).musicDeckPrevious,
              onPressed:
                  item == null
                      ? null
                      : () => _runPlaybackCommand(
                        () =>
                            ref
                                .read(musicCenterControllerProvider.notifier)
                                .previousTrack(),
                      ),
              icon: Icon(
                Icons.skip_previous_rounded,
                color: _palette(context).text,
              ),
            ),
            MusicPlaybackButton(
              buttonSize: MusicPlaybackButtonSize.regular,
              isPlaying: playing,
              tooltip:
                  playing
                      ? AppLocalizations.of(context).musicPause
                      : AppLocalizations.of(context).musicPlay,
              onPressed:
                  track == null ? null : () => _togglePlayback(track, item),
              backgroundColor:
                  Color.lerp(
                    const Color(0xFF153C43),
                    _palette(context).accent,
                    0.18,
                  )!,
              accentColor: _palette(context).accent,
              foregroundColor: _palette(context).onAccent,
            ),
            IconButton(
              tooltip: AppLocalizations.of(context).musicDeckNext,
              onPressed:
                  item == null
                      ? null
                      : () => _runPlaybackCommand(
                        () =>
                            ref
                                .read(musicCenterControllerProvider.notifier)
                                .nextTrack(),
                      ),
              icon: Icon(
                Icons.skip_next_rounded,
                color: _palette(context).text,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  Text(_formatDuration(_position), style: _timeStyle),
                  Expanded(
                    child: MusicPlaybackProgressBar(
                      value: progress,
                      semanticLabel:
                          AppLocalizations.of(
                            context,
                          ).portalMusicVisualizerSeek,
                      activeColor: _palette(context).accent,
                      thumbColor: _palette(context).text,
                      onChanged:
                          item == null
                              ? null
                              : (value) {
                                final target = Duration(
                                  milliseconds:
                                      (_duration.inMilliseconds * value)
                                          .round(),
                                );
                                session.player.seek(target);
                                setState(() => _position = target);
                              },
                    ),
                  ),
                  Text(_formatDuration(_duration), style: _timeStyle),
                ],
              ),
            ),
            // 次要操作聚拢：音量 / 均衡 / 队列，减少中部按钮的横向跨度。
            MusicVolumeButton(
              player: session.player,
              tooltip: AppLocalizations.of(context).portalMusicVisualizerVolume,
              style: MusicVolumeButtonStyle.flat,
              iconColor: _palette(context).text,
              mutedIconColor: _palette(context).muted.withValues(alpha: 0.7),
              activeColor: _palette(context).accent,
              panelTextColor: _palette(context).text,
              panelBackground: const Color(0xF00E151B),
              iconSize: 22,
            ),
            IconButton(
              tooltip: AppLocalizations.of(context).musicPlaybackSettings,
              onPressed: () => showMusicPlaybackSettingsDialog(context, ref),
              icon: Icon(
                Icons.equalizer_rounded,
                size: 20,
                color: _palette(context).text,
              ),
            ),
            IconButton(
              tooltip: AppLocalizations.of(context).musicQueueTitle,
              onPressed: widget.onOpenQueue,
              icon: Icon(
                Icons.queue_music_rounded,
                size: 20,
                color: _palette(context).text,
              ),
            ),
            if (widget.onOpenImmersive != null)
              IconButton(
                tooltip: AppLocalizations.of(context).portalImmersivePlayback,
                onPressed: widget.onOpenImmersive,
                icon: Icon(
                  Icons.graphic_eq_rounded,
                  size: 20,
                  color: _palette(context).text,
                ),
              ),
          ],
        ),
      ),
    );
    if (widget.embedded) {
      return Align(alignment: Alignment.topLeft, child: content);
    }
    return MusicDeckGlass(opacity: 0.24, blur: 15, child: content);
  }

  MusicTrack? _resolveDisplayTrack(MusicCenterState? music) {
    if (music == null) {
      return null;
    }
    final current = music.currentTrack;
    if (current != null) {
      return current;
    }
    final index = music.playbackIndex;
    if (index >= 0 && index < music.playbackItems.length) {
      return music.playbackItems[index].track;
    }
    if (music.playbackItems.isNotEmpty) {
      return music.playbackItems.first.track;
    }
    if (music.recentItems.isNotEmpty) {
      return music.recentItems.first.track;
    }
    if (music.dashboard.recentTracks.isNotEmpty) {
      return music.dashboard.recentTracks.first;
    }
    return null;
  }

  Widget _buildCompactContent(
    BuildContext context, {
    required MusicTrack? track,
    required MusicPlayableItem? item,
    required bool playing,
    required double progress,
  }) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 64,
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 4, 4),
              child: Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: widget.onOpenPlayer,
                    child: SizedBox.square(
                      dimension: 46,
                      child: MusicDeckArtwork(
                        title: track?.title ?? '',
                        imageUrl: track?.coverUrl,
                        borderRadius: 5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: widget.onOpenPlayer,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                track?.title ?? l10n.musicNotPlaying,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _palette(context).text,
                                  fontSize: AppTypography.bodyMedium,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                track?.artistName ?? l10n.musicDeckSelectTrack,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _palette(context).muted,
                                  fontSize: AppTypography.labelSmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  MusicPlaybackButton(
                    buttonSize: MusicPlaybackButtonSize.compact,
                    isPlaying: playing,
                    tooltip: playing ? l10n.musicPause : l10n.musicPlay,
                    onPressed:
                        track == null
                            ? null
                            : () => _togglePlayback(track, item),
                    backgroundColor: const Color(0xFF153C43),
                    accentColor: _palette(context).accent,
                    foregroundColor: _palette(context).onAccent,
                  ),
                  _compactIconButton(
                    tooltip: l10n.musicDeckNext,
                    icon: Icons.skip_next_rounded,
                    onPressed:
                        item == null
                            ? null
                            : () => _runPlaybackCommand(
                              () =>
                                  ref
                                      .read(
                                        musicCenterControllerProvider.notifier,
                                      )
                                      .nextTrack(),
                            ),
                  ),
                  _compactIconButton(
                    tooltip: l10n.musicQueueTitle,
                    icon: Icons.queue_music_rounded,
                    onPressed: widget.onOpenQueue,
                  ),
                ],
              ),
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 2.5,
              value: progress,
              color: _palette(context).accent,
              backgroundColor: context.musicColors.surfaceContainerHigh,
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactIconButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, size: 20, color: _palette(context).text),
    );
  }

  TextStyle get _timeStyle => TextStyle(
    color: _palette(context).muted,
    fontSize: AppTypography.labelSmall,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );

  void _bindPlayer(MusicAudioPlayback player) {
    _position = player.state.position;
    _duration = player.state.duration;
    _positionSub = player.stream.position.listen((position) {
      final now = DateTime.now();
      if (now.difference(_lastPositionPaint) <
          const Duration(milliseconds: 120)) {
        return;
      }
      _lastPositionPaint = now;
      if (mounted) {
        setState(() => _position = position);
      }
    });
    _durationSub = player.stream.duration.listen((duration) {
      if (mounted && duration != _duration) {
        setState(() => _duration = duration);
      }
    });
  }

  Future<void> _togglePlayback(
    MusicTrack track,
    MusicPlayableItem? currentItem,
  ) async {
    final controller = ref.read(musicCenterControllerProvider.notifier);
    if (currentItem == null || currentItem.track.id != track.id) {
      await _runPlaybackCommand(() => controller.playTrack(track));
      return;
    }
    await _runPlaybackCommand(controller.togglePlayback);
  }

  Future<void> _runPlaybackCommand(Future<void> Function() command) async {
    try {
      await command();
      if (widget.managePlaybackSession) {
        _schedulePlaybackSync();
      }
    } on Exception catch (error) {
      if (kDebugMode) {
        devLog('Music Mini Player 播放命令失败: $error');
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).musicPlaybackError),
        ),
      );
    }
  }

  void _schedulePlaybackSync() {
    if (_syncScheduled) {
      return;
    }
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted) {
        return;
      }
      unawaited(
        ref.read(musicPlaybackSessionProvider.notifier).syncFromCenterState(),
      );
    });
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds.clamp(0, 359999);
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
