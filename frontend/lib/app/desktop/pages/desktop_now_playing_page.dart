import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_np_style.dart';
import 'package:omninest/app/desktop/desktop_toast.dart';
import 'package:omninest/app/desktop/pages/desktop_music_metadata_drawer.dart';
import 'package:omninest/app/desktop/pages/desktop_now_playing_lyrics.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_glass.dart';
import 'package:omninest/app/desktop/widgets/desktop_np_style_panel.dart';
import 'package:omninest/app/desktop/widgets/desktop_surfaces.dart';
import 'package:omninest/app/desktop/widgets/desktop_track_hue.dart';
import 'package:omninest/app/desktop/widgets/desktop_visualizer.dart';
import 'package:omninest/app/desktop/widgets/desktop_window_controls.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/core/utils/file_size_formatter.dart';
import 'package:omninest/core/utils/route_exit.dart';
import 'package:omninest/features/backdrop/backdrop_ui.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/music_portal.dart';

part 'desktop_now_playing_deck.dart';

/// 桌面「正在播放」覆盖层（样例 `Music.tsx` 的 NowPlaying）。
///
/// 左半是黑胶 + 衬线曲名，右半是歌词/队列/关于三页，右侧全高外观抽屉，底部是走带。
class DesktopNowPlayingPage extends ConsumerStatefulWidget {
  const DesktopNowPlayingPage({super.key});

  @override
  ConsumerState<DesktopNowPlayingPage> createState() =>
      _DesktopNowPlayingPageState();
}

class _DesktopNowPlayingPageState extends ConsumerState<DesktopNowPlayingPage>
    with SingleTickerProviderStateMixin {
  static const String _bilingualPrefKey = 'omninest.desktop.npShowTranslation';

  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: DesktopMotion.vinylSpin,
  );
  int _tab = 0;
  bool _dragging = false;
  double? _dragValue;
  bool _styleOpen = false;
  bool _showTranslation = true;

  /// 退场动画进行中：先播 400ms 收束再真正退出路由。
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _spin.repeat();
    unawaited(ref.read(desktopNpStyleProvider.notifier).load());
    unawaited(_loadBilingualPref());
  }

  Future<void> _loadBilingualPref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(_bilingualPrefKey);
      if (saved != null && mounted) {
        setState(() => _showTranslation = saved);
      }
    } on Object {
      // 忽略偏好读取异常，默认开启双语。
    }
  }

  Future<void> _toggleTranslation() async {
    final next = !_showTranslation;
    setState(() => _showTranslation = next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_bilingualPrefKey, next);
    } on Object {
      // 忽略偏好写入异常。
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final state = ref.watch(musicCenterControllerProvider).asData?.value;
    final actions = ref.watch(musicPortalActionsProvider);
    final timeline = ref.watch(musicPortalPlaybackTimelineProvider);
    final item = state?.currentItem;
    final track = item?.track;
    final playing = state?.isPlaying ?? false;
    final queue = state?.playbackItems ?? const <MusicPlayableItem>[];
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final npStyle = ref.watch(desktopNpStyleProvider);
    final hueColor = desktopTrackHue(track?.hue, skin.accent);

    if (playing && !_spin.isAnimating && !reduceMotion) {
      _spin.repeat();
    } else if ((!playing || reduceMotion) && _spin.isAnimating) {
      _spin.stop();
    }

    final cover = track?.coverUrl;
    final duration = Duration(seconds: track?.durationSeconds ?? 0);
    final audioSpecBadge = _audioSpecBadge(track);

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
              _NpBackdrop(
                style: npStyle,
                cover: cover,
                playing: playing,
                hueColor: hueColor,
              ),
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
                          if (audioSpecBadge != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.14),
                                ),
                              ),
                              child: Text(
                                audioSpecBadge,
                                style: DesktopType.nano(
                                  Colors.white.withValues(alpha: 0.78),
                                ).copyWith(letterSpacing: 0.6),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          DesktopIconButton(
                            icon: DesktopIcons.palette,
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
                          Expanded(
                            flex: 105,
                            child: _Deck(
                              spin: _spin,
                              cover: cover,
                              playing: playing,
                              hueColor: hueColor,
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
                              track: track,
                              title: track?.title ?? l10n.desktopNothingPlaying,
                              artist: track?.artistName ?? '',
                              album: track?.albumTitle ?? '',
                              duration: duration,
                              format: track?.format,
                              bitrate: track?.bitrate,
                              sampleRate: track?.sampleRate,
                              fileSize: track?.fileSize,
                              position: timeline.position,
                              positionStream: timeline.positionStream,
                              playing: playing,
                              hueColor: hueColor,
                              tab: _tab,
                              onTab: (value) => setState(() => _tab = value),
                              showTranslation: _showTranslation,
                              onToggleTranslation:
                                  () => unawaited(_toggleTranslation()),
                              onSeek:
                                  (value) => unawaited(timeline.seek(value)),
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
                // 点击抽屉外透明区域即收起。
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => setState(() => _styleOpen = false),
                    child: const SizedBox.expand(),
                  ),
                ),
                // 全高右侧抽屉（top/right/bottom: 0，400ms 右侧滑入）。
                Positioned(
                  top: 0,
                  right: 0,
                  bottom: 0,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: 1),
                    duration: MotionToken.reduced(
                      context,
                      const Duration(milliseconds: 400),
                    ),
                    curve: DesktopMotion.ease,
                    builder: (context, t, child) {
                      return Opacity(
                        opacity: t.clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(24 * (1 - t), 0),
                          child: child,
                        ),
                      );
                    },
                    child: DesktopNpStylePanel(
                      hueColor: hueColor,
                      onClose: () => setState(() => _styleOpen = false),
                    ),
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

  String? _audioSpecBadge(MusicTrack? track) {
    if (track == null) return null;
    final parts = <String>[];
    final fmt = track.format.trim().toUpperCase();
    if (fmt.isNotEmpty && fmt != 'AUDIO') {
      parts.add(fmt);
    }
    final sr = track.sampleRate;
    if (sr != null && sr > 0) {
      final khz = sr / 1000.0;
      parts.add(
        '${khz.toStringAsFixed(khz.truncateToDouble() == khz ? 0 : 1)} kHz',
      );
    }
    final br = track.bitrate;
    if (br != null && br > 0) {
      parts.add('$br kbps');
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Future<void> _close() async {
    if (_closing) {
      return;
    }
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
    required this.track,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.format,
    required this.bitrate,
    required this.sampleRate,
    required this.fileSize,
    required this.position,
    required this.positionStream,
    required this.playing,
    required this.hueColor,
    required this.tab,
    required this.onTab,
    required this.showTranslation,
    required this.onToggleTranslation,
    required this.onSeek,
    required this.queue,
    required this.currentKey,
    required this.onPickQueue,
    required this.onEdit,
  });

  final MusicTrack? track;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final String? format;
  final int? bitrate;
  final int? sampleRate;
  final int? fileSize;
  final Duration position;
  final Stream<Duration> positionStream;
  final bool playing;
  final Color hueColor;
  final int tab;
  final ValueChanged<int> onTab;
  final bool showTranslation;
  final VoidCallback onToggleTranslation;
  final ValueChanged<Duration> onSeek;
  final List<MusicPlayableItem> queue;
  final String? currentKey;
  final ValueChanged<int> onPickQueue;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final style = ref.watch(desktopNpStyleProvider);
    final timedLyrics = track?.lyricLines ?? const <MusicLyricLine>[];
    final plainLyrics =
        timedLyrics.isEmpty
            ? _plainLyricLines(track?.lyricsRaw)
            : const <String>[];
    final hasTranslation = timedLyrics.any((line) => line.hasTranslation);
    final activeColor = style.effectiveFillPaint(hueColor).primaryColor;

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
            if (tab == 0 && hasTranslation) ...[
              const SizedBox(width: 10),
              GestureDetector(
                onTap: onToggleTranslation,
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: DesktopMotion.of(context, DesktopMotion.fast),
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color:
                        showTranslation
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color:
                          showTranslation
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Text(
                    '译',
                    style: DesktopType.chip(
                      showTranslation
                          ? const Color(0xFF0A0C0E)
                          : Colors.white.withValues(alpha: 0.8),
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child:
              tab == 0
                  ? DesktopNowPlayingLyrics(
                    lines: timedLyrics,
                    plainLines: plainLyrics,
                    position: position,
                    positionStream: positionStream,
                    duration: duration,
                    playing: playing,
                    style: style,
                    hueColor: hueColor,
                    showTranslation: showTranslation,
                    onSeek: onSeek,
                  )
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
                    color: activeColor,
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

/// 纯文本歌词回退：仅在无任何时间轴时按行展示。
List<String> _plainLyricLines(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return const <String>[];
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
