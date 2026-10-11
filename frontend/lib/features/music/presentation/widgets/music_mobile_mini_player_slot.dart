import 'package:omninest/core/widgets/omni_icons.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/feature/music_backdrop_theme.dart';
import 'package:omninest/app/theme/feature/music_colors.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/app/theme/mobile_layout_tokens.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_controller.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_scene_controller.dart';
import 'package:omninest/features/music/application/music_audio_playback.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_playback_session.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_primitives.dart';
import 'package:omninest/core/feedback/omni_feedback.dart';

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
    // 浮起卡片配方：壁纸激活（玻璃模块）保持烟熏半透；实底模块上近实底，
    // 读作一张浮起的卡而不是第二根贴边栏。
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
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: context.env.elevShadow,
                        blurRadius: 28,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: MobileEnvBlur(
                      sigma: 24,
                      child: DecoratedBox(
                        // 浮起卡片：两态都带模糊，浅态是与底栏同源的半透明白。
                        decoration: BoxDecoration(
                          color: context.env.miniPlayer,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: context.env.line13),
                        ),
                        child: SizedBox(
                          height: 58,
                          child: Column(
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    const SizedBox(width: 6),
                                    SizedBox.square(
                                      dimension: 46,
                                      child: InkWell(
                                        onTap: widget.onOpenPlayer,
                                        borderRadius: BorderRadius.circular(12),
                                        child: MusicDeckArtwork(
                                          title: track.title,
                                          imageUrl: track.listCoverUrl,
                                          borderRadius: 12,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
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
                                                  // ignore: font_size_whitelist
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                track.artistName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                // ignore: font_size_whitelist
                                                style: TextStyle(
                                                  color:
                                                      colors.onSurfaceVariant,
                                                  // ignore: font_size_whitelist
                                                  fontSize: 9,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    _MiniStrokeButton(
                                      tooltip:
                                          center?.isPlaying == true
                                              ? l10n.musicPause
                                              : l10n.musicPlay,
                                      icon:
                                          center?.isPlaying == true
                                              ? OmniIcons.pause
                                              : OmniIcons.play,
                                      onTap:
                                          () => unawaited(
                                            _runCommand(
                                              _controller.togglePlayback,
                                            ),
                                          ),
                                    ),
                                    _MiniStrokeButton(
                                      tooltip: l10n.coreNext,
                                      icon: OmniIcons.next,
                                      onTap:
                                          () => unawaited(
                                            _runCommand(_controller.nextTrack),
                                          ),
                                    ),
                                    const SizedBox(width: 4),
                                  ],
                                ),
                              ),
                              // 2px 进度：强调色走到当前进度，其余轨道取最浅发丝档。
                              ClipRRect(
                                borderRadius: BorderRadius.circular(1),
                                child: SizedBox(
                                  height: 2,
                                  child: LinearGradientProgress(
                                    value: progress.clamp(0, 1),
                                    barColor: context.env.accent,
                                    trackColor: context.env.line07,
                                  ),
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

  Future<void> _runCommand(Future<void> Function() command) async {
    try {
      await command();
    } on Exception {
      if (!mounted) {
        return;
      }
      showOmniFeedback(
        context,
        AppLocalizations.of(context).musicPlaybackError,
        severity: OmniFeedbackSeverity.error,
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

/// 迷你条描边钮（样例 41×43 命中盒）。
class _MiniStrokeButton extends StatelessWidget {
  const _MiniStrokeButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final OmniIconsData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 41,
          height: 43,
          child: Center(
            child: OmniIcon(icon: icon, size: 19, color: context.env.ink),
          ),
        ),
      ),
    );
  }
}

/// 迷你条的渐变进度：强调色走到 value 比例，其余为轨道色。
class LinearGradientProgress extends StatelessWidget {
  const LinearGradientProgress({
    required this.value,
    required this.barColor,
    required this.trackColor,
    super.key,
  });

  final double value;
  final Color barColor;
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: trackColor),
        FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: value <= 0 ? 0.0 : value.clamp(0, 1),
          child: ColoredBox(color: barColor),
        ),
      ],
    );
  }
}
