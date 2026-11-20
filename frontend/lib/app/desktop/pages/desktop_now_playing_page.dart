import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_np_style.dart';
import 'package:omninest/app/desktop/pages/desktop_music_metadata_drawer.dart';
import 'package:omninest/app/desktop/desktop_toast.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_surfaces.dart';
import 'package:omninest/app/desktop/widgets/desktop_track_hue.dart';
import 'package:omninest/app/desktop/widgets/desktop_visualizer.dart';
import 'package:omninest/app/desktop/widgets/desktop_glass.dart';
import 'package:omninest/app/desktop/widgets/desktop_np_style_panel.dart';
import 'package:omninest/app/desktop/widgets/desktop_window_controls.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/core/utils/route_exit.dart';
import 'package:omninest/core/utils/file_size_formatter.dart';
import 'package:omninest/features/backdrop/backdrop_ui.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/music_portal.dart';

part 'desktop_now_playing_deck.dart';

/// 桌面「正在播放」覆盖层（样例 `Music.tsx` 的 NowPlaying）。
///
/// 左半是黑胶 + 衬线曲名，右半是歌词/队列两页，底部是走带。
/// 数据全部来自音乐门面：当前曲目、队列、播放进度与命令各走各的 provider，
/// 不复制一份播放状态。
class DesktopNowPlayingPage extends ConsumerStatefulWidget {
  const DesktopNowPlayingPage({super.key});

  @override
  ConsumerState<DesktopNowPlayingPage> createState() =>
      _DesktopNowPlayingPageState();
}

class _DesktopNowPlayingPageState extends ConsumerState<DesktopNowPlayingPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: DesktopMotion.vinylSpin,
  );
  int _tab = 0;
  bool _dragging = false;
  double? _dragValue;
  bool _styleOpen = false;

  /// 退场动画进行中：先播 400ms 收束再真正退出路由。
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _spin.repeat();
    unawaited(ref.read(desktopNpStyleProvider.notifier).load());
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(musicCenterControllerProvider).asData?.value;
    final actions = ref.watch(musicPortalActionsProvider);
    final timeline = ref.watch(musicPortalPlaybackTimelineProvider);
    final item = state?.currentItem;
    final track = item?.track;
    final playing = state?.isPlaying ?? false;
    final queue = state?.playbackItems ?? const <MusicPlayableItem>[];
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final npStyle = ref.watch(desktopNpStyleProvider);

    if (playing && !_spin.isAnimating && !reduceMotion) {
      _spin.repeat();
    } else if ((!playing || reduceMotion) && _spin.isAnimating) {
      _spin.stop();
    }

    final cover = track?.coverUrl;
    final duration = Duration(seconds: track?.durationSeconds ?? 0);

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          if (_styleOpen) {
            setState(() => _styleOpen = false);
          } else {
            _close();
          }
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.space) {
          unawaited(actions.togglePlayback());
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      // 样例 `npin .7s` / `npout .4s`：淡入 + 上移 8% + 从 .97 放大，
      // 入场还带 30px 圆角收束（`npin from { border-radius: 30px }`）。
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: _closing ? 0 : 1),
        duration: MotionToken.reduced(
          context,
          _closing ? DesktopMotion.fade : DesktopMotion.rise,
        ),
        curve: _closing ? DesktopMotion.ease : DesktopMotion.easeOut,
        builder: (context, t, child) {
          final viewport = MediaQuery.sizeOf(context);
          return Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, viewport.height * 0.08 * (1 - t)),
              child: Transform.scale(
                scale: 0.97 + 0.03 * t,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30 * (1 - t)),
                  child: child,
                ),
              ),
            ),
          );
        },
        child: ColoredBox(
          color: const Color(0xFF07090B),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _NpBackdrop(style: npStyle, cover: cover),
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DesktopWindowDragRegion(
                      child: Row(
                        children: [
                          DesktopIconButton(
                            icon: DesktopIcons.chevDown,
                            size: 36,
                            iconSize: 20,
                            tooltip: l10n.photosClose,
                            onPressed: _close,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.musicNowPlayingEyebrow,
                                  style: DesktopType.eyebrow(
                                    Colors.white.withValues(alpha: 0.6),
                                  ),
                                ),
                                Text(
                                  track?.albumTitle ??
                                      l10n.desktopDockNowPlaying,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: DesktopType.caption(
                                    Colors.white.withValues(alpha: 0.72),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          DesktopIconButton(
                            icon: DesktopIcons.sparkle,
                            size: 34,
                            iconSize: 18,
                            active: _styleOpen,
                            tooltip: l10n.desktopNpAppearance,
                            onPressed:
                                () => setState(() => _styleOpen = !_styleOpen),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 样例 `.np-main`：`minmax(0,1.05fr) minmax(0,1fr)`。
                          Expanded(
                            flex: 105,
                            child: _Deck(
                              spin: _spin,
                              cover: cover,
                              playing: playing,
                              hueColor: desktopTrackHue(
                                track?.hue,
                                DesktopSkin.of(context).accent,
                              ),
                              index:
                                  queue.indexWhere(
                                    (entry) =>
                                        entry.playableKey == item?.playableKey,
                                  ) +
                                  1,
                              total: queue.length,
                            ),
                          ),
                          SizedBox(
                            width: (MediaQuery.sizeOf(context).width * 0.04)
                                .clamp(30.0, 72.0),
                          ),
                          Expanded(
                            flex: 100,
                            child: _SidePanel(
                              title: track?.title ?? l10n.desktopNothingPlaying,
                              artist: track?.artistName ?? '',
                              album: track?.albumTitle ?? '',
                              duration: duration,
                              format: track?.format,
                              bitrate: track?.bitrate,
                              sampleRate: track?.sampleRate,
                              fileSize: track?.fileSize,
                              position: timeline.position,
                              playing: playing,
                              tab: _tab,
                              onTab: (value) => setState(() => _tab = value),
                              lyrics: track?.lyricsRaw,
                              queue: queue,
                              currentKey: item?.playableKey,
                              onPickQueue:
                                  (index) =>
                                      unawaited(actions.playQueueAt(index)),
                              onEdit:
                                  track == null
                                      ? null
                                      : () =>
                                          unawaited(_editMetadata(track.id)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    _Transport(
                      playing: playing,
                      position: timeline.position,
                      positionStream: timeline.positionStream,
                      duration: duration,
                      dragging: _dragging,
                      dragValue: _dragValue,
                      onSeek: (value) => unawaited(timeline.seek(value)),
                      onDragStart: () => setState(() => _dragging = true),
                      onDragUpdate:
                          (value) => setState(() => _dragValue = value),
                      onDragEnd: () {
                        setState(() => _dragging = false);
                        _dragValue = null;
                      },
                      onPrevious: () => unawaited(actions.previousTrack()),
                      onToggle: () => unawaited(actions.togglePlayback()),
                      onNext: () => unawaited(actions.nextTrack()),
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
              if (_styleOpen) ...[
                // 样例 NpStyle 在面板外点击即收起，避免设置面板长期挡住歌词/队列。
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => setState(() => _styleOpen = false),
                    child: const SizedBox.expand(),
                  ),
                ),
                Positioned(
                  top: 62,
                  right: 24,
                  child: DesktopNpStylePanel(
                    onClose: () => setState(() => _styleOpen = false),
                  ),
                ),
              ],
              if (track == null)
                Center(
                  child: Text(
                    l10n.desktopNothingPlaying,
                    style: DesktopType.displaySm(
                      Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _close() async {
    if (_closing) {
      return;
    }
    // 样例 `.np.closing { animation: npout .4s }`：先收束再退路由，
    // 直接 pop 会硬切。
    setState(() => _closing = true);
    await Future<void>.delayed(
      MotionToken.reduced(context, DesktopMotion.fade),
    );
    if (!mounted) {
      return;
    }
    exitDetailRoute(context, fallbackRoute: '/music');
  }

  Future<void> _editMetadata(String trackId) async {
    final track =
        ref
            .read(musicCenterControllerProvider)
            .asData
            ?.value
            .tracks
            .where((item) => item.id == trackId)
            .firstOrNull;
    if (track == null) return;
    final saved = await showDesktopMusicMetadataDrawer(
      context: context,
      track: track,
    );
    if (!mounted || saved != true) return;
    showDesktopToast(
      context,
      AppLocalizations.of(context).musicMetadataSaved,
      kind: DesktopToastKind.success,
      icon: DesktopIcons.check,
    );
  }
}

class _SidePanel extends ConsumerWidget {
  const _SidePanel({
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.format,
    required this.bitrate,
    required this.sampleRate,
    required this.fileSize,
    required this.position,
    required this.playing,
    required this.tab,
    required this.onTab,
    required this.lyrics,
    required this.queue,
    required this.currentKey,
    required this.onPickQueue,
    required this.onEdit,
  });

  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final String? format;
  final int? bitrate;
  final int? sampleRate;
  final int? fileSize;
  final Duration position;
  final bool playing;
  final int tab;
  final ValueChanged<int> onTab;
  final String? lyrics;
  final List<MusicPlayableItem> queue;
  final String? currentKey;
  final ValueChanged<int> onPickQueue;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final style = ref.watch(desktopNpStyleProvider);
    final lines = _lyricLines(lyrics);
    // 样例歌词：衬线 clamp(24, 2.4vw, 36)，非当前行 28% 白，当前行纯白 + 光晕。
    final lyricSize =
        (MediaQuery.sizeOf(context).width * 0.024).clamp(24.0, 36.0) *
        style.lyricScale;
    // 逐字填充：按播放进度把歌词总时长切成行，行内再按比例点亮。
    final totalMs = duration.inMilliseconds;
    final progress =
        totalMs <= 0
            ? 0.0
            : (position.inMilliseconds / totalMs).clamp(0.0, 0.999);
    final lineIndex =
        lines.isEmpty
            ? -1
            : (progress * lines.length).floor().clamp(0, lines.length - 1);
    final lineFill =
        lines.isEmpty ? 0.0 : (progress * lines.length) - lineIndex;
    final brushColor = DesktopNpBrush.values[style.brush.clamp(0, 4)].color;
    // 样例 `Paint.split`：当前行上半区 / 下半区各用一套颜料，分界按 pos%。
    final lowerColor =
        DesktopNpBrush.values[style.lowerBrush.clamp(0, 4)].color;
    final splitAt = style.splitPos.clamp(5, 95) / 100;
    // 样例 `.np-right`：标题块在歌词/队列之上，本身不再套一层玻璃卡。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          artist.isEmpty ? l10n.musicNowPlayingEyebrow : artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DesktopType.eyebrow(
            Colors.white.withValues(alpha: 0.6),
          ).copyWith(letterSpacing: 1.6),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: DesktopType.displayXl(
            Colors.white,
            MediaQuery.sizeOf(context).width,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          [
            if (album.isNotEmpty) album,
            _Transport._format(duration),
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DesktopType.medium(Colors.white.withValues(alpha: 0.65)),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            DesktopSeg<int>(
              options: const [0, 1, 2],
              value: tab,
              labelOf:
                  (value) => switch (value) {
                    0 => l10n.musicNowPlayingLyrics,
                    1 => l10n.musicQueueTitle,
                    _ => l10n.musicNowPlayingAbout,
                  },
              small: true,
              onChanged: onTab,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child:
              tab == 0
                  ? (lines.isEmpty
                      ? Center(
                        child: Text(
                          l10n.musicNoLyrics,
                          style: DesktopType.dense(
                            Colors.white.withValues(alpha: 0.55),
                          ),
                        ),
                      )
                      : ListView.builder(
                        itemCount: lines.length,
                        itemBuilder: (context, index) {
                          final current = index == lineIndex;
                          final lyric = Text(
                            lines[index],
                            style: DesktopType.sectionTitle(
                              current
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.28),
                            ).copyWith(
                              fontSize: lyricSize,
                              height: 1.25,
                              shadows:
                                  current && style.glow
                                      ? [
                                        Shadow(
                                          color: brushColor.withValues(
                                            alpha: 0.55,
                                          ),
                                          blurRadius: 34,
                                        ),
                                      ]
                                      : null,
                            ),
                          );
                          final filled =
                              current && style.splitPaint
                                  ? ShaderMask(
                                    blendMode: BlendMode.srcIn,
                                    shaderCallback:
                                        (rect) => LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            brushColor,
                                            brushColor,
                                            lowerColor,
                                            lowerColor,
                                          ],
                                          stops: [0, splitAt, splitAt, 1],
                                        ).createShader(rect),
                                    child: lyric,
                                  )
                                  : current && style.wordFill
                                  ? ShaderMask(
                                    blendMode: BlendMode.srcIn,
                                    shaderCallback:
                                        (rect) => LinearGradient(
                                          colors: [
                                            brushColor,
                                            brushColor,
                                            Colors.white.withValues(
                                              alpha: 0.28,
                                            ),
                                            Colors.white.withValues(
                                              alpha: 0.28,
                                            ),
                                          ],
                                          stops: [
                                            0,
                                            lineFill.clamp(0.0, 1.0),
                                            lineFill.clamp(0.0, 1.0),
                                            1,
                                          ],
                                        ).createShader(rect),
                                    child: lyric,
                                  )
                                  : lyric;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            child: filled,
                          );
                        },
                      ))
                  : tab == 1
                  ? (queue.isEmpty
                      ? Center(
                        child: Text(
                          l10n.musicQueueEmpty,
                          style: DesktopType.dense(
                            Colors.white.withValues(alpha: 0.55),
                          ),
                        ),
                      )
                      : ListView.builder(
                        itemCount: queue.length,
                        itemBuilder: (context, index) {
                          final item = queue[index];
                          final active = item.playableKey == currentKey;
                          return GestureDetector(
                            onTap: () => onPickQueue(index),
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 9,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    active
                                        ? Colors.white.withValues(alpha: 0.1)
                                        : Colors.transparent,
                                borderRadius: BorderRadius.circular(
                                  DesktopMetrics.radiusSmall,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    active
                                        ? DesktopIcons.play
                                        : DesktopIcons.music,
                                    size: 13,
                                    color:
                                        active
                                            ? skin.accent
                                            : Colors.white.withValues(
                                              alpha: 0.45,
                                            ),
                                  ),
                                  const SizedBox(width: 8),
                                  // 样例 `.np-queue .q-row`：22 序号 + 44 封面列。
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(7),
                                    child: SizedBox(
                                      width: 44,
                                      height: 44,
                                      child: DesktopImage(
                                        url: item.track.coverUrl,
                                        borderRadius: BorderRadius.circular(7),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.track.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: DesktopType.dense(
                                            active
                                                ? Colors.white
                                                : Colors.white.withValues(
                                                  alpha: 0.82,
                                                ),
                                          ),
                                        ),
                                        Text(
                                          item.track.artistName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: DesktopType.nano(
                                            Colors.white.withValues(alpha: 0.5),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    _queueDuration(item.track.durationSeconds),
                                    style: DesktopType.numeric(
                                      Colors.white.withValues(alpha: 0.45),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ))
                  : _NowPlayingAbout(
                    playing: playing,
                    color: brushColor,
                    artist: artist,
                    album: album,
                    duration: duration,
                    format: format,
                    bitrate: bitrate,
                    sampleRate: sampleRate,
                    fileSize: fileSize,
                    onEdit: onEdit,
                  ),
        ),
      ],
    );
  }
}

class _NowPlayingAbout extends StatelessWidget {
  const _NowPlayingAbout({
    required this.playing,
    required this.color,
    required this.artist,
    required this.album,
    required this.duration,
    required this.format,
    required this.bitrate,
    required this.sampleRate,
    required this.fileSize,
    required this.onEdit,
  });

  final bool playing;
  final Color color;
  final String artist;
  final String album;
  final Duration duration;
  final String? format;
  final int? bitrate;
  final int? sampleRate;
  final int? fileSize;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rows = <MapEntry<String, String>>[
      MapEntry(l10n.musicFieldArtist, artist),
      MapEntry(l10n.musicFieldAlbum, album),
      MapEntry(l10n.musicFieldDuration, _Transport._format(duration)),
      MapEntry(l10n.musicFieldFormat, format?.toUpperCase() ?? '—'),
      MapEntry(l10n.musicFieldBitrate, bitrate == null ? '—' : '$bitrate kbps'),
      MapEntry(
        l10n.musicFieldSampleRate,
        sampleRate == null
            ? '—'
            : '${(sampleRate! / 1000).toStringAsFixed(1)} kHz',
      ),
      MapEntry(
        l10n.musicFieldFileSize,
        fileSize == null ? '—' : formatFileSize(fileSize!),
      ),
    ];
    final skin = DesktopSkin.of(context);
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: DesktopButton(
            label: l10n.musicEditDetailsLyrics,
            icon: DesktopIcons.edit,
            variant: DesktopButtonVariant.soft,
            onPressed: onEdit,
          ),
        ),
        const SizedBox(height: 18),
        for (var index = 0; index < rows.length; index++) ...[
          if (index > 0)
            Container(height: 1, color: Colors.white.withValues(alpha: 0.10)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 4,
                  child: Text(
                    rows[index].key,
                    style: DesktopType.caption(
                      Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  flex: 6,
                  child: Text(
                    rows[index].value.isEmpty ? '—' : rows[index].value,
                    textAlign: TextAlign.right,
                    style: DesktopType.dense(skin.onStage),
                  ),
                ),
              ],
            ),
          ),
        ],
        // 样例 `Music.tsx:248` 的 `.np-viz-sm`：About 页元数据下方一条
        // 64 柱、90px、85% 不透明度的动态频谱，颜色跟随当前外观笔刷。
        const SizedBox(height: 18),
        SizedBox(
          height: 90,
          child: Opacity(
            opacity: 0.85,
            child: DesktopVisualizer(
              playing: playing,
              color: color,
              bars: 64,
              seed: 5,
            ),
          ),
        ),
      ],
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport({
    required this.playing,
    required this.position,
    required this.positionStream,
    required this.duration,
    required this.dragging,
    required this.dragValue,
    required this.onSeek,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onPrevious,
    required this.onToggle,
    required this.onNext,
  });

  final bool playing;
  final Duration position;
  final Stream<Duration> positionStream;
  final Duration duration;
  final bool dragging;
  final double? dragValue;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onPrevious;
  final VoidCallback onToggle;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final max =
        duration.inMilliseconds <= 0 ? 1.0 : duration.inMilliseconds.toDouble();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StreamBuilder<Duration>(
              stream: positionStream,
              initialData: position,
              builder: (context, snapshot) {
                final value = (snapshot.data ?? position).inMilliseconds
                    .toDouble()
                    .clamp(0.0, max);
                final shown =
                    dragging && dragValue != null ? dragValue! : value;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _WaveSeek(
                      position: Duration(milliseconds: shown.round()),
                      duration: duration,
                      onSeek: (value) {
                        onDragStart();
                        onDragUpdate(value.inMilliseconds.toDouble());
                        onSeek(value);
                        onDragEnd();
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        children: [
                          Text(
                            _format(Duration(milliseconds: shown.round())),
                            style: DesktopType.numeric(
                              Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _format(duration),
                            style: DesktopType.numeric(
                              Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                DesktopIconButton(
                  icon: DesktopIcons.previous,
                  size: 44,
                  iconSize: 22,
                  tooltip: l10n.coreBack,
                  onPressed: onPrevious,
                ),
                const SizedBox(width: 14),
                GestureDetector(
                  onTap: onToggle,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        playing ? DesktopIcons.pause : DesktopIcons.play,
                        size: 30,
                        color: const Color(0xFF07090B),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                DesktopIconButton(
                  icon: DesktopIcons.next,
                  size: 44,
                  iconSize: 22,
                  tooltip: l10n.desktopActionNextTrack,
                  onPressed: onNext,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _format(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

/// 歌词：LRC 去时间戳后逐行保留；没有时间轴就按纯文本滚动。
List<String> _lyricLines(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return const <String>[];
  }
  final parsed = parseMusicLyrics(raw);
  if (parsed.isNotEmpty) {
    return parsed.map((line) => line.text).toList(growable: false);
  }
  final tag = RegExp(r'\[\d{1,2}:\d{2}(?:[.:]\d{1,3})?\]');
  return raw
      .split('\n')
      .map((line) => line.replaceAll(tag, '').trim())
      .where(
        (line) =>
            line.isNotEmpty &&
            !line.startsWith('[') &&
            !line.startsWith('{"t"') &&
            !line.startsWith('{"c"'),
      )
      .toList(growable: false);
}

/// 队列行的时长（样例 `.q-row time`）：秒数缺失时留空而不是显示 00:00。
String _queueDuration(int? seconds) {
  if (seconds == null || seconds <= 0) {
    return '';
  }
  final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
  final rest = (seconds % 60).toString().padLeft(2, '0');
  return '$minutes:$rest';
}
