import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_router_scope.dart';
import 'package:omninest/app/desktop/desktop_routes.dart';
import 'package:omninest/app/desktop/desktop_shell_state.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_cover.dart';
import 'package:omninest/app/desktop/widgets/desktop_glass.dart';
import 'package:omninest/app/desktop/widgets/desktop_visualizer.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/features/music/music_portal.dart';

/// 格式化播放时间：超过一小时补时位，秒始终两位。
String formatDesktopClock(Duration value) {
  final total = value.inSeconds < 0 ? 0 : value.inSeconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  final mm = hours > 0 ? minutes.toString().padLeft(2, '0') : '$minutes';
  final ss = seconds.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}

/// 常驻播放条（样例 `.playerbar`）。
///
/// 它挂在壳层而不是音乐页里：切模块音乐不停、控件不消失，这正是「一个
/// 产品一套壳」相对「每模块一个子系统」的关键差别。
class DesktopPlayerBar extends ConsumerStatefulWidget {
  const DesktopPlayerBar({super.key});

  @override
  ConsumerState<DesktopPlayerBar> createState() => _DesktopPlayerBarState();
}

class _DesktopPlayerBarState extends ConsumerState<DesktopPlayerBar> {
  double? _scrubSeconds;
  double _lastAudibleVolume = 100;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final compact = viewportWidth <= DesktopMetrics.playerBarCompactBreakpoint;
    final narrow = viewportWidth <= DesktopMetrics.playerBarNarrowBreakpoint;
    final trackCellWidth =
        narrow
            ? DesktopMetrics.playerBarNarrowTrackWidth
            : compact
            ? DesktopMetrics.playerBarCompactTrackWidth
            : DesktopMetrics.playerBarWideTrackWidth;
    final sectionGap =
        narrow
            ? DesktopMetrics.playerBarNarrowSectionGap
            : DesktopMetrics.playerBarWideSectionGap;
    final showVolume = !compact;
    final showVisualizer =
        viewportWidth >= DesktopMetrics.playerBarVisualizerBreakpoint;
    final snapshot = ref.watch(musicPortalSnapshotProvider).asData?.value;
    final track = snapshot?.activeTrack;
    final playing = snapshot?.isPlaying ?? false;
    // 只订阅播放条真正渲染的三个字段：中心控制器每次重建都会带上整份
    // 曲库快照（专辑/艺人/歌单/分页），直接 watch 整份 AsyncValue 会让
    // 后台次级回填把这条 36σ 毛玻璃底栏一起重建。
    final centerTrack = ref.watch(
      musicCenterControllerProvider.select(
        (state) => state.asData?.value.currentItem?.track,
      ),
    );
    final mode = ref.watch(
      musicCenterControllerProvider.select(
        (state) => state.asData?.value.playMode ?? MusicPlayMode.sequential,
      ),
    );
    final current = centerTrack;
    final durationSeconds = current?.durationSeconds ?? 0;
    final favorite = current?.favorite ?? false;
    // 时间轴与音量都要读播放引擎，而引擎是 autoDispose 的：空闲态一律
    // 不订阅，否则壳层一启动就会初始化音频设备与系统媒体会话——用户
    // 可能整场都不碰音乐。有曲目时才接上真实播放状态。
    final timeline =
        track == null ? null : ref.watch(musicPortalPlaybackTimelineProvider);
    final actions = ref.watch(musicPortalActionsProvider);
    final shellController = ref.read(desktopShellProvider.notifier);
    final engine = track == null ? null : ref.watch(musicAudioPlaybackProvider);
    final volume = engine?.state.volume ?? _lastAudibleVolume;
    if (volume > 0) {
      _lastAudibleVolume = volume;
    }

    return Center(
      child: DesktopGlassSurface(
        borderRadius: BorderRadius.circular(DesktopMetrics.radiusPlayerBar),
        blur: 36,
        saturation: 1.7,
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(
            maxWidth:
                compact
                    ? DesktopMetrics.playerBarCompactMaxWidth
                    : DesktopMetrics.playerBarMaxWidth,
          ),
          height: DesktopMetrics.playerBarHeight,
          margin: EdgeInsets.symmetric(
            horizontal:
                compact
                    ? DesktopMetrics.playerBarCompactMargin
                    : DesktopMetrics.playerBarWideMargin,
          ),
          padding: const EdgeInsets.fromLTRB(8, 0, 14, 0),
          decoration: BoxDecoration(
            color: skin.panel,
            borderRadius: BorderRadius.circular(DesktopMetrics.radiusPlayerBar),
            border: Border.all(color: skin.line2),
            boxShadow: skin.shadow,
          ),
          child:
              track == null
                  ? _IdleBar(
                    onOpenMusic: () => desktopGo(context, DesktopRoutes.music),
                  )
                  : Builder(
                    builder: (context) {
                      return Row(
                        children: [
                          SizedBox(
                            width: trackCellWidth,
                            child: _TrackCell(
                              track: track,
                              playing: playing,
                              showArtist: !narrow,
                              onOpen:
                                  () => desktopPush(
                                    context,
                                    DesktopRoutes.nowPlaying,
                                  ),
                            ),
                          ),
                          SizedBox(width: sectionGap),
                          DesktopIconButton(
                            icon:
                                favorite
                                    ? DesktopIcons.heartFilled
                                    : DesktopIcons.heart,
                            tooltip: l10n.desktopFavorite,
                            color: favorite ? skin.liked : null,
                            onPressed:
                                current == null
                                    ? null
                                    : () => ref
                                        .read(
                                          musicCenterControllerProvider
                                              .notifier,
                                        )
                                        .toggleFavorite(current),
                          ),
                          SizedBox(width: sectionGap),
                          Expanded(
                            child: Center(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minWidth:
                                      narrow
                                          ? DesktopMetrics
                                              .playerBarNarrowCenterMinWidth
                                          : compact
                                          ? DesktopMetrics
                                              .playerBarCompactCenterMinWidth
                                          : DesktopMetrics
                                              .playerBarWideCenterMinWidth,
                                  maxWidth:
                                      DesktopMetrics.playerBarCenterMaxWidth,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      height: 34,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          DesktopIconButton(
                                            icon: switch (mode) {
                                              MusicPlayMode.sequential =>
                                                DesktopIcons.listOrder,
                                              MusicPlayMode.shuffle =>
                                                DesktopIcons.shuffle,
                                              MusicPlayMode.repeatOne =>
                                                DesktopIcons.repeatOne,
                                            },
                                            size: 28,
                                            iconSize: 15,
                                            active:
                                                mode !=
                                                MusicPlayMode.sequential,
                                            tooltip:
                                                '${switch (mode) {
                                                  MusicPlayMode.sequential => l10n.desktopPlayInOrder,
                                                  MusicPlayMode.shuffle => l10n.desktopShuffle,
                                                  MusicPlayMode.repeatOne => l10n.desktopRepeatOne,
                                                }} — ${l10n.desktopClickToSwitch}',
                                            onPressed:
                                                () =>
                                                    ref
                                                        .read(
                                                          musicCenterControllerProvider
                                                              .notifier,
                                                        )
                                                        .cyclePlayMode(),
                                          ),
                                          const SizedBox(width: 4),
                                          DesktopIconButton(
                                            icon: DesktopIcons.previous,
                                            size: 28,
                                            iconSize: 18,
                                            tooltip: l10n.desktopPrevious,
                                            onPressed:
                                                () => actions.previousTrack(),
                                          ),
                                          const SizedBox(width: 4),
                                          _PlayButton(
                                            playing: playing,
                                            onPressed:
                                                () => actions.togglePlayback(),
                                          ),
                                          const SizedBox(width: 4),
                                          DesktopIconButton(
                                            icon: DesktopIcons.next,
                                            size: 28,
                                            iconSize: 18,
                                            tooltip: l10n.desktopNext,
                                            onPressed:
                                                () => actions.nextTrack(),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // 关键：只有这一行随 16ms 播放位置流重建。此前 StreamBuilder 包住
                                    // 整个 Row（封面、按钮、频谱），音乐播放时每帧重建几十个 widget，
                                    // 连带玻璃面板的 child 每帧换新，backdrop 层也跟着重录。
                                    Transform.translate(
                                      offset: const Offset(0, -2),
                                      child: _PlayerSeekBar(
                                        timeline: timeline!,
                                        scrubSeconds: _scrubSeconds,
                                        durationSeconds: durationSeconds,
                                        onScrub:
                                            (value) => setState(
                                              () => _scrubSeconds = value,
                                            ),
                                        onCommit: (value) {
                                          setState(() => _scrubSeconds = null);
                                          timeline.seek(
                                            Duration(
                                              milliseconds:
                                                  (value * 1000).round(),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: sectionGap),
                          // 样例 `.pb-viz`：extra.css 默认 `display:none`，
                          // 只有 ≥1360 宽才显示 64×26、85% 不透明度。
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (showVisualizer) ...[
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: SizedBox(
                                    width: 64,
                                    height: 26,
                                    child: Opacity(
                                      opacity: 0.85,
                                      child: DesktopVisualizer(
                                        playing: playing,
                                        color: skin.accent,
                                        bars: 14,
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: DesktopMetrics.playerBarControlGap,
                                ),
                              ],
                              DesktopIconButton(
                                icon: DesktopIcons.queue,
                                tooltip: l10n.desktopDockQueue,
                                active:
                                    ref.watch(desktopShellProvider).dockOpen,
                                onPressed:
                                    () => shellController.setDockTab(
                                      DesktopDockTab.queue,
                                    ),
                              ),
                              SizedBox(
                                width: DesktopMetrics.playerBarControlGap,
                              ),
                              DesktopIconButton(
                                icon:
                                    volume <= 0
                                        ? DesktopIcons.mute
                                        : DesktopIcons.volume,
                                tooltip: l10n.desktopMute,
                                onPressed:
                                    engine == null
                                        ? null
                                        : () => engine.setVolume(
                                          volume <= 0 ? _lastAudibleVolume : 0,
                                        ),
                              ),
                              if (showVolume) ...[
                                SizedBox(
                                  width: DesktopMetrics.playerBarControlGap,
                                ),
                                DesktopSlider(
                                  width: 92,
                                  value: volume,
                                  max: 100,
                                  onChanged:
                                      (value) => engine?.setVolume(value),
                                ),
                              ],
                              SizedBox(
                                width: DesktopMetrics.playerBarControlGap,
                              ),
                              DesktopIconButton(
                                icon: DesktopIcons.expand,
                                tooltip: l10n.desktopOpenNowPlaying,
                                onPressed:
                                    () => desktopPush(
                                      context,
                                      DesktopRoutes.nowPlaying,
                                    ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
        ),
      ),
    );
  }
}

class _IdleBar extends StatelessWidget {
  const _IdleBar({required this.onOpenMusic});

  final VoidCallback onOpenMusic;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        const SizedBox(width: 6),
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: skin.raise2,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(DesktopIcons.music, size: 20, color: skin.text3),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.desktopNothingPlaying,
                style: DesktopType.denseStrong(skin.text),
              ),
              Text(
                l10n.desktopNothingPlayingHint,
                style: DesktopType.micro(skin.text3),
              ),
            ],
          ),
        ),
        DesktopButton(
          label: l10n.desktopOpenMusic,
          icon: DesktopIcons.chevron,
          variant: DesktopButtonVariant.soft,
          onPressed: onOpenMusic,
        ),
      ],
    );
  }
}

class _TrackCell extends StatelessWidget {
  const _TrackCell({
    required this.track,
    required this.playing,
    required this.showArtist,
    required this.onOpen,
  });

  final MusicPortalTrack track;
  final bool playing;
  final bool showArtist;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    return DesktopHover(
      builder:
          (context, hovered) => GestureDetector(
            onTap: onOpen,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: hovered ? skin.raise : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  _SpinningArt(track: track, playing: playing),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DesktopType.denseStrong(skin.text),
                        ),
                        if (showArtist) ...[
                          const SizedBox(height: 1),
                          Text(
                            track.artistName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DesktopType.micro(skin.text3),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Tooltip(
                    message: l10n.desktopOpenNowPlaying,
                    child: const SizedBox(width: 4),
                  ),
                ],
              ),
            ),
          ),
    );
  }
}

/// 播放条封面（样例 `.pb-art`）：暂停时是 11 圆角方块，播放时变成唱片——
/// 圆角收成 50%、中心打一个孔、9s 一圈匀速转。圆角与旋转分开跑：
/// 圆角跟 `.8s var(--ease)` 收束，旋转与播放态同生共死。
class _SpinningArt extends StatefulWidget {
  const _SpinningArt({required this.track, required this.playing});

  final MusicPortalTrack track;
  final bool playing;

  @override
  State<_SpinningArt> createState() => _SpinningArtState();
}

class _SpinningArtState extends State<_SpinningArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: DesktopMotion.vinylSpin,
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_SpinningArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final animate =
        widget.playing &&
        !(WidgetsBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .disableAnimations);
    if (animate) {
      if (!_spin.isAnimating) {
        _spin.repeat();
      }
    } else {
      _spin.stop();
      _spin.value = 0;
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return AnimatedContainer(
      duration: DesktopMotion.of(context, DesktopMotion.slow),
      curve: DesktopMotion.ease,
      width: 46,
      height: 46,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.playing ? 23 : 11),
        boxShadow: [
          BoxShadow(
            color: skin.shadow.first.color.withValues(alpha: 0.4),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          RotationTransition(
            turns: _spin,
            child: DesktopCover(
              url: widget.track.listCoverUrl ?? widget.track.coverUrl,
              kind: DesktopCoverKind.music,
              fallbackIcon: DesktopIcons.music,
              cacheKey: 'desktop-player-${widget.track.id}',
              iconSize: 18,
            ),
          ),
          if (widget.playing)
            Center(
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: skin.bg,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.20),
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, required this.onPressed});

  final bool playing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final label = playing ? l10n.desktopPause : l10n.desktopPlay;
    return Semantics(
      button: true,
      label: label,
      child: DesktopHover(
        builder:
            (context, hovered) => GestureDetector(
              onTap: onPressed,
              behavior: HitTestBehavior.opaque,
              child: Tooltip(
                message: label,
                child: AnimatedScale(
                  duration: MotionToken.reduced(context, MotionToken.fast),
                  curve: MotionToken.curve,
                  scale: hovered ? 1.1 : 1,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: skin.text,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: skin.accentWash(0.35),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                          spreadRadius: -6,
                        ),
                      ],
                    ),
                    child: Icon(
                      playing ? DesktopIcons.pause : DesktopIcons.play,
                      size: 18,
                      color: skin.bg,
                    ),
                  ),
                ),
              ),
            ),
      ),
    );
  }
}

/// 播放条的时间轴与进度条：自行订阅 16ms 位置流。
///
/// 抽出来是为了把重建范围压到这一行：外层 Row 的封面、控制按钮与频谱
/// 不再随播放位置每帧重建。玻璃面板的 child 保持同一实例，backdrop 层
/// 才不会跟着每帧重录。
class _PlayerSeekBar extends StatelessWidget {
  const _PlayerSeekBar({
    required this.timeline,
    required this.scrubSeconds,
    required this.durationSeconds,
    required this.onScrub,
    required this.onCommit,
  });

  final MusicPortalPlaybackTimeline timeline;
  final double? scrubSeconds;
  final int durationSeconds;
  final ValueChanged<double> onScrub;
  final ValueChanged<double> onCommit;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return SizedBox(
      height: DesktopMetrics.playerBarSeekHeight,
      child: StreamBuilder<Duration>(
        stream: timeline.positionStream,
        initialData: timeline.position,
        builder: (context, snapshot) {
          final positionSeconds =
              scrubSeconds ??
              (snapshot.data ?? Duration.zero).inMilliseconds / 1000;
          return Row(
            children: [
              SizedBox(
                width: DesktopMetrics.playerBarSeekTimeWidth,
                child: Text(
                  formatDesktopClock(
                    Duration(milliseconds: (positionSeconds * 1000).round()),
                  ),
                  textAlign: TextAlign.center,
                  style: DesktopType.numeric(skin.text3).copyWith(height: 1),
                ),
              ),
              SizedBox(width: DesktopMetrics.playerBarSeekGap),
              Expanded(
                child: DesktopSlider(
                  height: DesktopMetrics.playerBarSeekHeight,
                  value: positionSeconds,
                  max: durationSeconds <= 0 ? 1 : durationSeconds.toDouble(),
                  onChanged: durationSeconds <= 0 ? (_) {} : onScrub,
                  onCommit: durationSeconds <= 0 ? null : onCommit,
                ),
              ),
              SizedBox(width: DesktopMetrics.playerBarSeekGap),
              SizedBox(
                width: DesktopMetrics.playerBarSeekTimeWidth,
                child: Text(
                  formatDesktopClock(Duration(seconds: durationSeconds)),
                  textAlign: TextAlign.center,
                  style: DesktopType.numeric(skin.text3).copyWith(height: 1),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
