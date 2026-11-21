import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_router_scope.dart';
import 'package:omninest/app/desktop/desktop_routes.dart';
import 'package:omninest/app/desktop/desktop_shell_state.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_cover.dart';
import 'package:omninest/app/desktop/widgets/desktop_glass.dart';
import 'package:omninest/app/desktop/widgets/desktop_press.dart';
import 'package:omninest/app/desktop/widgets/desktop_visualizer.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/features/music/music_portal.dart';

part 'desktop_player_bar_parts.dart';

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
    final shellState = ref.watch(desktopShellProvider);
    final shellController = ref.read(desktopShellProvider.notifier);
    final engine = track == null ? null : ref.watch(musicAudioPlaybackProvider);
    final volume = engine?.state.volume ?? _lastAudibleVolume;
    if (volume > 0) {
      _lastAudibleVolume = volume;
    }

    return LayoutBuilder(
      builder: (context, viewport) {
        // 样例叠加顺序：desktop.css 给 left/right 16；extra.css 改成
        // left/right 0 + margin auto；more.css 覆盖成 width:min(1080,100%-40)。
        // 所以终值是「居中、面板宽 1080、两侧至少留 20px」，不是贴左。
        final margin =
            compact
                ? DesktopMetrics.playerBarCompactMargin
                : DesktopMetrics.playerBarWideMargin;
        final maxPanelWidth =
            compact
                ? DesktopMetrics.playerBarCompactMaxWidth
                : DesktopMetrics.playerBarMaxWidth;
        final available = viewport.maxWidth - 2 * margin;
        final panelWidth =
            available <= 0 ? 0.0 : math.min(maxPanelWidth, available);

        return Center(
          child: SizedBox(
            key: const ValueKey('desktop-player-bar'),
            width: panelWidth,
            height: DesktopMetrics.playerBarHeight,
            // 阴影画在玻璃盒外：CSS 的 box-shadow 在 playerbar 外面，Flutter
            // 的 ClipRRect 会裁掉子内容的阴影，所以由这层非裁剪盒单独负责。
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(
                  DesktopMetrics.radiusPlayerBar,
                ),
                boxShadow: skin.shadow,
              ),
              child: DesktopGlassSurface(
                key: const ValueKey('desktop-player-bar-glass'),
                borderRadius: BorderRadius.circular(
                  DesktopMetrics.radiusPlayerBar,
                ),
                blur: 36,
                saturation: 1.7,
                // 面板、描边、玻璃三者同一个盒子：这里不能再出现 margin，
                // 否则模糊背板比可见面板宽一圈，就是截图里的第二层。
                child: Container(
                  key: const ValueKey('desktop-player-bar-panel'),
                  padding: const EdgeInsets.fromLTRB(8, 0, 14, 0),
                  decoration: BoxDecoration(
                    color: skin.panel,
                    borderRadius: BorderRadius.circular(
                      DesktopMetrics.radiusPlayerBar,
                    ),
                    border: Border.all(color: skin.line2),
                  ),
                  child:
                      track == null
                          ? _IdleBar(
                            onOpenMusic:
                                () => desktopGo(context, DesktopRoutes.music),
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
                                    key: const ValueKey(
                                      'desktop-player-favorite',
                                    ),
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
                                              DesktopMetrics
                                                  .playerBarCenterMaxWidth,
                                        ),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(
                                              height: 34,
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  DesktopIconButton(
                                                    key: const ValueKey(
                                                      'desktop-player-mode',
                                                    ),
                                                    icon: switch (mode) {
                                                      MusicPlayMode
                                                          .sequential =>
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
                                                        MusicPlayMode
                                                            .sequential,
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
                                                    key: const ValueKey(
                                                      'desktop-player-previous',
                                                    ),
                                                    icon: DesktopIcons.previous,
                                                    size: 28,
                                                    iconSize: 18,
                                                    tooltip:
                                                        l10n.desktopPrevious,
                                                    onPressed:
                                                        () =>
                                                            actions
                                                                .previousTrack(),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  _PlayButton(
                                                    key: const ValueKey(
                                                      'desktop-player-play',
                                                    ),
                                                    playing: playing,
                                                    onPressed:
                                                        () =>
                                                            actions
                                                                .togglePlayback(),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  DesktopIconButton(
                                                    key: const ValueKey(
                                                      'desktop-player-next',
                                                    ),
                                                    icon: DesktopIcons.next,
                                                    size: 28,
                                                    iconSize: 18,
                                                    tooltip: l10n.desktopNext,
                                                    onPressed:
                                                        () =>
                                                            actions.nextTrack(),
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
                                                durationSeconds:
                                                    durationSeconds,
                                                onScrub:
                                                    (value) => setState(
                                                      () =>
                                                          _scrubSeconds = value,
                                                    ),
                                                onCommit: (value) {
                                                  setState(
                                                    () => _scrubSeconds = null,
                                                  );
                                                  timeline.seek(
                                                    Duration(
                                                      milliseconds:
                                                          (value * 1000)
                                                              .round(),
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
                                          padding: const EdgeInsets.only(
                                            right: 8,
                                          ),
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
                                          width:
                                              DesktopMetrics
                                                  .playerBarControlGap,
                                        ),
                                      ],
                                      DesktopIconButton(
                                        key: const ValueKey(
                                          'desktop-player-queue',
                                        ),
                                        icon: DesktopIcons.queue,
                                        tooltip: l10n.desktopDockQueue,
                                        active: shellState.dockOpen,
                                        onPressed: () {
                                          // 样例 Shell.tsx:280 是 setDock(!a.dock)：
                                          // 再点一次收起，而不是无条件打开队列。
                                          if (shellState.dockOpen &&
                                              shellState.dockTab ==
                                                  DesktopDockTab.queue) {
                                            shellController.setDock(false);
                                          } else {
                                            shellController.setDockTab(
                                              DesktopDockTab.queue,
                                            );
                                          }
                                        },
                                      ),
                                      SizedBox(
                                        width:
                                            DesktopMetrics.playerBarControlGap,
                                      ),
                                      DesktopIconButton(
                                        key: const ValueKey(
                                          'desktop-player-mute',
                                        ),
                                        icon:
                                            volume <= 0
                                                ? DesktopIcons.mute
                                                : DesktopIcons.volume,
                                        tooltip: l10n.desktopMute,
                                        onPressed:
                                            engine == null
                                                ? null
                                                : () => engine.setVolume(
                                                  volume <= 0
                                                      ? _lastAudibleVolume
                                                      : 0,
                                                ),
                                      ),
                                      if (showVolume) ...[
                                        SizedBox(
                                          width:
                                              DesktopMetrics
                                                  .playerBarControlGap,
                                        ),
                                        DesktopSlider(
                                          key: const ValueKey(
                                            'desktop-player-volume',
                                          ),
                                          width: 92,
                                          value: volume,
                                          max: 100,
                                          trackColor: skin.raise3,
                                          fillColor: skin.accent,
                                          thumbAlwaysVisible: true,
                                          onChanged:
                                              (value) =>
                                                  engine?.setVolume(value),
                                        ),
                                      ],
                                      SizedBox(
                                        width:
                                            DesktopMetrics.playerBarControlGap,
                                      ),
                                      DesktopIconButton(
                                        key: const ValueKey(
                                          'desktop-player-expand',
                                        ),
                                        icon: DesktopIcons.expand,
                                        tooltip: l10n.desktopExpand,
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
            ),
          ),
        );
      },
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
          (context, hovered) => Tooltip(
            // 样例 `.pb-track` 的 title 挂在整个按钮上，不是塞一个 0×4 的
            // Tooltip 到行尾——那样鼠标移到封面上没有任何提示。
            message: l10n.desktopOpenNowPlaying,
            child: GestureDetector(
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
                  ],
                ),
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
                width: 10,
                height: 10,
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
