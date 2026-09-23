import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/music_backdrop_theme.dart';
import 'package:omninest/app/theme/feature/music_colors.dart';
import 'package:omninest/app/theme/mobile_layout_tokens.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_controller.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_scene_controller.dart';
import 'package:omninest/features/music/application/music_audio_playback.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_playback_session.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_primitives.dart';

/// 应用级移动端壳层使用的音乐播放插槽。
class MusicMobileMiniPlayerSlot extends ConsumerStatefulWidget {
  const MusicMobileMiniPlayerSlot({required this.onOpenPlayer, super.key});

  final VoidCallback onOpenPlayer;

  @override
  ConsumerState<MusicMobileMiniPlayerSlot> createState() =>
      _MusicMobileMiniPlayerSlotState();
}

class _MusicMobileMiniPlayerSlotState
    extends ConsumerState<MusicMobileMiniPlayerSlot> {
  /// 已被下滑收起的曲目：切歌后自动回归。
  String? _dismissedForTrackId;

  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  DateTime _lastPaint = DateTime.fromMillisecondsSinceEpoch(0);
  bool _syncScheduled = false;

  @override
  void initState() {
    super.initState();
    _bindPlayer(ref.read(musicPlaybackSessionProvider).player);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scheduleSync();
      }
    });
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(musicCenterControllerProvider, (_, _) => _scheduleSync());
    final center = ref.watch(musicCenterControllerProvider).asData?.value;
    final item = center?.currentItem;
    final track = item?.track ?? center?.activeTrack;
    if (track == null) {
      return const SizedBox.shrink();
    }
    final progress =
        _duration.inMilliseconds <= 0
            ? 0.0
            : (_position.inMilliseconds / _duration.inMilliseconds).clamp(
              0.0,
              1.0,
            );
    final canFavorite = item?.ref is LocalMusicRef;
    final l10n = AppLocalizations.of(context);
    final backdrop = ref.watch(appBackdropControllerProvider).asData?.value;
    final backdropVisible = ref.watch(
      appBackdropSceneControllerProvider.select(
        (state) => state.policy.visible,
      ),
    );
    final backdropActive =
        backdropVisible && backdrop?.hasActiveBackdrop == true;
    final theme = MusicBackdropTheme.resolve(
      Theme.of(context),
      backdropActive: backdropActive,
    );
    final colors = theme.extension<MusicColors>() ?? context.musicColors;
    final light = theme.brightness == Brightness.light;
    final surface =
        Color.lerp(
          colors.surfaceContainer,
          light ? colors.primary : colors.surfaceContainerHigh,
          light ? 0.06 : 0.04,
        )!;
    // 浮起卡片配方：壁纸激活（玻璃模块）保持烟熏半透；实底模块上近实底，
    // 读作一张浮起的卡而不是第二根贴边栏。
    final requestedSurfaceAlpha =
        backdropActive ? (light ? 0.55 : 0.80) : (light ? 0.96 : 0.94);
    final surfaceAlpha =
        requestedSurfaceAlpha < surface.a ? requestedSurfaceAlpha : surface.a;
    final requestedOutlineAlpha = light ? 0.35 : 0.50;
    final outlineAlpha =
        requestedOutlineAlpha < colors.outline.a
            ? requestedOutlineAlpha
            : colors.outline.a;
    final progressTrackAlpha =
        0.30 < colors.outline.a ? 0.30 : colors.outline.a;
    if (track.id == _dismissedForTrackId) {
      return const SizedBox.shrink();
    }
    return Theme(
      data: theme,
      child: Semantics(
        container: true,
        label: '${track.title}, ${track.artistName}',
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
          // 平板宽度下浮卡限宽居中，与底栏 tab 组同宽，避免整屏拉伸。
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: MobileLayoutTokens.chromeMaxWidth,
              ),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragEnd: (details) {
                  final velocity = details.primaryVelocity ?? 0;
                  if (velocity.abs() < 180) {
                    return;
                  }
                  if (velocity < 0) {
                    unawaited(_runCommand(() => _controller.nextTrack()));
                  } else {
                    unawaited(_runCommand(() => _controller.previousTrack()));
                  }
                },
                // 下滑收起：读作浮层卡片的可关闭性；切歌后自动回归。
                onVerticalDragEnd: (details) {
                  if ((details.primaryVelocity ?? 0) > 240) {
                    setState(() => _dismissedForTrackId = track.id);
                  }
                },
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: surface.withValues(alpha: surfaceAlpha),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: colors.outline.withValues(
                              alpha: outlineAlpha,
                            ),
                          ),
                        ),
                        child: SizedBox(
                          height: 52,
                          child: Column(
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    const SizedBox(width: 6),
                                    SizedBox.square(
                                      dimension: 38,
                                      child: InkWell(
                                        onTap: widget.onOpenPlayer,
                                        borderRadius: BorderRadius.circular(6),
                                        child: MusicDeckArtwork(
                                          title: track.title,
                                          imageUrl: track.listCoverUrl,
                                          borderRadius: 6,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: InkWell(
                                        onTap: widget.onOpenPlayer,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 2,
                                          ),
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                track.title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: colors.onSurface,
                                                  fontSize:
                                                      AppTypography.bodyMedium,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                track.artistName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color:
                                                      colors.onSurfaceVariant,
                                                  fontSize:
                                                      AppTypography.labelSmall,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip:
                                          track.favorite
                                              ? l10n.musicUnfavorite
                                              : l10n.musicFavorite,
                                      onPressed:
                                          canFavorite
                                              ? () => unawaited(
                                                _toggleFavorite(track),
                                              )
                                              : null,
                                      icon: AnimatedSwitcher(
                                        duration: const Duration(
                                          milliseconds: 160,
                                        ),
                                        child: Icon(
                                          track.favorite
                                              ? Icons.favorite_rounded
                                              : Icons.favorite_border_rounded,
                                          key: ValueKey<bool>(track.favorite),
                                          color:
                                              track.favorite
                                                  ? colors.star
                                                  : colors.onSurfaceVariant,
                                          size: 21,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip:
                                          center?.isPlaying == true
                                              ? l10n.musicPause
                                              : l10n.musicPlay,
                                      onPressed:
                                          () => unawaited(
                                            _runCommand(
                                              _controller.togglePlayback,
                                            ),
                                          ),
                                      icon: Icon(
                                        center?.isPlaying == true
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded,
                                        color: colors.primary,
                                        size: 28,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                  ],
                                ),
                              ),
                              LinearProgressIndicator(
                                minHeight: 2,
                                value: progress,
                                color: colors.primary,
                                backgroundColor: colors.outline.withValues(
                                  alpha: progressTrackAlpha,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  MusicCenterController get _controller {
    return ref.read(musicCenterControllerProvider.notifier);
  }

  void _bindPlayer(MusicAudioPlayback player) {
    _position = player.state.position;
    _duration = player.state.duration;
    _positionSubscription = player.stream.position.listen((position) {
      final now = DateTime.now();
      if (now.difference(_lastPaint) < const Duration(milliseconds: 120)) {
        return;
      }
      _lastPaint = now;
      if (mounted) {
        setState(() => _position = position);
      }
    });
    _durationSubscription = player.stream.duration.listen((duration) {
      if (mounted && duration != _duration) {
        setState(() => _duration = duration);
      }
    });
  }

  Future<void> _toggleFavorite(MusicTrack track) async {
    await _runCommand(() => _controller.toggleFavorite(track));
  }

  Future<void> _runCommand(Future<void> Function() command) async {
    try {
      await command();
    } on Exception {
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

  void _scheduleSync() {
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
}
