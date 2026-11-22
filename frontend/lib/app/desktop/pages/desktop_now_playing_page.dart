import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_np_style.dart';
import 'package:omninest/app/desktop/desktop_player_bar.dart'
    show formatDesktopClock;
import 'package:omninest/app/desktop/desktop_routes.dart';
import 'package:omninest/app/desktop/desktop_shell_state.dart';
import 'package:omninest/app/desktop/desktop_toast.dart';
import 'package:omninest/app/desktop/pages/desktop_music_metadata_drawer.dart';
import 'package:omninest/app/desktop/pages/desktop_now_playing_lyrics.dart';
import 'package:omninest/app/desktop/pages/desktop_now_playing_spectrum.dart';
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
import 'package:omninest/core/auth/user_capabilities.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/core/utils/file_size_formatter.dart';
import 'package:omninest/core/utils/route_exit.dart';
import 'package:omninest/features/backdrop/backdrop_ui.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart'
    show LocalMusicRef;
import 'package:omninest/features/music/music_portal.dart';

part 'desktop_now_playing_deck.dart';
part 'desktop_now_playing_wallpaper.dart';
part 'desktop_now_playing_deck_parts.dart';
part 'desktop_now_playing_panels.dart';
part 'desktop_now_playing_transport.dart';

/// 桌面「正在播放」覆盖层（样例 `Music.tsx` 的 NowPlaying）。
///
/// 顶栏全宽贴顶 64px（空白区与居中专辑标题支持拖拽窗口与双击最大化，
/// 左右按钮与右上角 `DesktopWindowControls` 同级放置避免手势冲突）；
/// 左半是黑胶唱机，右半是曲名+收藏红心与歌词/队列/关于三页，
/// 右侧全高外观抽屉，底部是波形走带 + 播放模式/队列胶囊 + 实时音量控制。
class DesktopNowPlayingPage extends ConsumerStatefulWidget {
  const DesktopNowPlayingPage({super.key});

  @override
  ConsumerState<DesktopNowPlayingPage> createState() =>
      _DesktopNowPlayingPageState();
}

class _DesktopNowPlayingPageState extends ConsumerState<DesktopNowPlayingPage>
    with SingleTickerProviderStateMixin {
  static const String _bilingualPrefKey = 'omninest.desktop.npShowTranslation';
  static const Duration _seekStep = Duration(seconds: 5);
  static const double _volumeStep = 5;

  /// 真实 33⅓ RPM（60 / 33.333 ≈ 1.8s 一圈，对齐 desktop.css:387）。
  static const Duration _vinylRpmDuration = Duration(milliseconds: 1800);

  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: _vinylRpmDuration,
  );
  int _tab = 0;
  bool _dragging = false;
  double? _dragValue;
  bool _styleOpen = false;
  bool _showTranslation = true;
  double _lastAudibleVolume = 100;

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

  Future<void> _toggleFavorite({
    required MusicPlayableItem? item,
    required MusicTrack track,
    required bool canManageOwnActivity,
    required bool isZh,
  }) async {
    if (!canManageOwnActivity) {
      showDesktopToast(
        context,
        isZh ? '当前账号暂无收藏权限' : 'You do not have permission to manage favorites',
        kind: DesktopToastKind.warn,
        icon: DesktopIcons.info,
      );
      return;
    }
    if (item?.ref is! LocalMusicRef) {
      showDesktopToast(
        context,
        isZh ? '暂仅支持收藏本地曲目' : 'Only local tracks can be favorited',
        kind: DesktopToastKind.info,
        icon: DesktopIcons.info,
      );
      return;
    }
    final wasFavorite = track.favorite;
    try {
      await ref
          .read(musicCenterControllerProvider.notifier)
          .toggleFavorite(track);
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      showDesktopToast(
        context,
        wasFavorite ? l10n.favoriteRemoved : l10n.favoriteAdded,
        kind: DesktopToastKind.success,
        icon: wasFavorite ? DesktopIcons.heart : DesktopIcons.heartFilled,
      );
    } on Object catch (error) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      showDesktopToast(
        context,
        failureToast(l10n, l10n.musicFavoriteToggleFailed, error),
        kind: DesktopToastKind.error,
        icon: DesktopIcons.info,
      );
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
    final isZh = Localizations.localeOf(
      context,
    ).languageCode.toLowerCase().startsWith('zh');
    final outerTheme = Theme.of(context);
    final accent = ref.watch(
      desktopAppearanceProvider.select((appearance) => appearance.accent),
    );
    final canManageOwnActivity = ref.watch(
      userCapabilitiesProvider.select((caps) => caps.canManageOwnActivity),
    );
    final darkSkin = DesktopSkin.resolve(isDark: true, accent: accent);

    final state = ref.watch(musicCenterControllerProvider).asData?.value;
    final playMode = state?.playMode ?? MusicPlayMode.sequential;
    final actions = ref.watch(musicPortalActionsProvider);
    final timeline = ref.watch(musicPortalPlaybackTimelineProvider);
    final item = state?.currentItem;
    final track = item?.track;
    final playing = state?.isPlaying ?? false;
    final queue = state?.playbackItems ?? const <MusicPlayableItem>[];
    final engine = track == null ? null : ref.watch(musicAudioPlaybackProvider);
    final initialVolume = engine?.state.volume ?? _lastAudibleVolume;
    if (initialVolume > 0) {
      _lastAudibleVolume = initialVolume;
    }

    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final npStyle = ref.watch(desktopNpStyleProvider);
    final hueColor = desktopTrackHue(track?.hue, darkSkin.accent);

    if (playing && track != null && !_spin.isAnimating && !reduceMotion) {
      _spin.repeat();
    } else if ((!playing || track == null || reduceMotion) &&
        _spin.isAnimating) {
      _spin.stop();
    }

    final cover = track?.coverUrl;
    final duration = Duration(seconds: track?.durationSeconds ?? 0);
    final audioSpecBadge = _audioSpecBadge(track);
    final queueIndex =
        queue.isEmpty
            ? 0
            : queue.indexWhere(
                  (entry) => entry.playableKey == item?.playableKey,
                ) +
                1;

    void setEngineVolume(double next) {
      if (engine == null) return;
      final clamped = next.clamp(0.0, 100.0).toDouble();
      if (clamped > 0) {
        _lastAudibleVolume = clamped;
      }
      engine.setVolume(clamped);
    }

    void toggleMute() {
      if (engine == null) return;
      final current = engine.state.volume;
      if (current > 0) {
        _lastAudibleVolume = current;
        engine.setVolume(0);
      } else {
        final restore = _lastAudibleVolume > 0 ? _lastAudibleVolume : 100.0;
        engine.setVolume(restore);
      }
    }

    void seekBy(Duration delta) {
      if (track == null || duration <= Duration.zero) return;
      final baseMs =
          _dragging && _dragValue != null
              ? _dragValue!.round()
              : timeline.position.inMilliseconds;
      final targetMs = (baseMs + delta.inMilliseconds).clamp(
        0,
        duration.inMilliseconds,
      );
      unawaited(timeline.seek(Duration(milliseconds: targetMs)));
    }

    // 字面量里混 DesktopSkin 时 kernel 会把元素推成
    // ThemeExtension<ThemeExtension<dynamic>>（analyze 不报），显式构造列表。
    final mergedExtensions = outerTheme.extensions.values
      .where((ext) => ext is! DesktopSkin)
      .toList(growable: true)..add(darkSkin);
    return Theme(
      data: outerTheme.copyWith(
        brightness: Brightness.dark,
        extensions: mergedExtensions,
      ),
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          final isDown = event is KeyDownEvent;
          final isRepeat = event is KeyRepeatEvent;
          if (!isDown && !isRepeat) {
            return KeyEventResult.ignored;
          }
          final key = event.logicalKey;
          if (isDown && key == LogicalKeyboardKey.escape) {
            if (_styleOpen) {
              setState(() => _styleOpen = false);
            } else {
              _close();
            }
            return KeyEventResult.handled;
          }
          if (isDown && key == LogicalKeyboardKey.space) {
            if (track != null) {
              unawaited(actions.togglePlayback());
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          }
          if (key == LogicalKeyboardKey.arrowLeft) {
            if (track != null) {
              seekBy(-_seekStep);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          }
          if (key == LogicalKeyboardKey.arrowRight) {
            if (track != null) {
              seekBy(_seekStep);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          }
          if (key == LogicalKeyboardKey.arrowUp) {
            if (engine != null) {
              setEngineVolume(engine.state.volume + _volumeStep);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          }
          if (key == LogicalKeyboardKey.arrowDown) {
            if (engine != null) {
              setEngineVolume(engine.state.volume - _volumeStep);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          }
          if (isDown && key == LogicalKeyboardKey.keyM) {
            if (engine != null) {
              toggleMute();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          }
          return KeyEventResult.ignored;
        },
        child: ColoredBox(
          color: const Color(0xFF07090B),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _NpBackdrop(
                style: npStyle,
                cover: cover,
                playing: playing && track != null,
                hueColor: hueColor,
                seed: track?.id ?? '',
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _NowPlayingTopBar(
                    eyebrow: l10n.musicNowPlayingEyebrow,
                    albumTitle: track?.albumTitle ?? l10n.desktopDockNowPlaying,
                    audioSpecBadge: audioSpecBadge,
                    accent: darkSkin.accent,
                    styleOpen: _styleOpen,
                    showStyleToggle: track != null,
                    closeTooltip: l10n.photosClose,
                    appearanceTooltip: l10n.desktopNpAppearance,
                    onClose: _close,
                    onToggleStyle:
                        () => setState(() => _styleOpen = !_styleOpen),
                  ),
                  if (track == null)
                    Expanded(
                      child: _NowPlayingEmptyState(
                        title: l10n.desktopNothingPlaying,
                        browseLabel: isZh ? '浏览音乐' : 'Browse music',
                        onBrowse: _browseMusic,
                      ),
                    )
                  else
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(32, 8, 32, 22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
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
                                      index: queueIndex,
                                      total: queue.length,
                                    ),
                                  ),
                                  SizedBox(
                                    width: (MediaQuery.sizeOf(context).width *
                                            0.04)
                                        .clamp(24.0, 72.0),
                                  ),
                                  Expanded(
                                    flex: 100,
                                    child: _SidePanel(
                                      track: track,
                                      title: track.title,
                                      artist: track.artistName,
                                      album: track.albumTitle,
                                      duration: duration,
                                      format: track.format,
                                      bitrate: track.bitrate,
                                      sampleRate: track.sampleRate,
                                      fileSize: track.fileSize,
                                      position: timeline.position,
                                      positionStream: timeline.positionStream,
                                      playing: playing,
                                      hueColor: hueColor,
                                      tab: _tab,
                                      onTab:
                                          (value) =>
                                              setState(() => _tab = value),
                                      showTranslation: _showTranslation,
                                      onToggleTranslation:
                                          () => unawaited(_toggleTranslation()),
                                      onSeek:
                                          (value) =>
                                              unawaited(timeline.seek(value)),
                                      queue: queue,
                                      currentKey: item?.playableKey,
                                      onPickQueue:
                                          (index) => unawaited(
                                            actions.playQueueAt(index),
                                          ),
                                      onToggleFavorite: () {
                                        _toggleFavorite(
                                          item: item,
                                          track: track,
                                          canManageOwnActivity:
                                              canManageOwnActivity,
                                          isZh: isZh,
                                        );
                                      },
                                      onBrowseMusic: _browseMusic,
                                      onEdit:
                                          () => unawaited(_editMetadata(track)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
                            _Transport(
                              trackId: track.id,
                              playing: playing,
                              hueColor: hueColor,
                              playMode: playMode,
                              queueLength: queue.length,
                              queueIndex: queueIndex,
                              queueActive: _tab == 1,
                              position: timeline.position,
                              positionStream: timeline.positionStream,
                              duration: duration,
                              dragging: _dragging,
                              dragValue: _dragValue,
                              volumeStream:
                                  engine?.stream.volume ??
                                  const Stream<double>.empty(),
                              initialVolume: initialVolume,
                              onSeek:
                                  (value) => unawaited(timeline.seek(value)),
                              onDragStart:
                                  () => setState(() => _dragging = true),
                              onDragUpdate:
                                  (value) => setState(() => _dragValue = value),
                              onDragEnd: () {
                                setState(() {
                                  _dragging = false;
                                  _dragValue = null;
                                });
                              },
                              onCyclePlayMode:
                                  () =>
                                      ref
                                          .read(
                                            musicCenterControllerProvider
                                                .notifier,
                                          )
                                          .cyclePlayMode(),
                              onPrevious:
                                  () => unawaited(actions.previousTrack()),
                              onToggle:
                                  () => unawaited(actions.togglePlayback()),
                              onNext: () => unawaited(actions.nextTrack()),
                              onToggleQueue:
                                  () =>
                                      setState(() => _tab = _tab == 1 ? 0 : 1),
                              onToggleMute: toggleMute,
                              onVolumeChanged: setEngineVolume,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              if (_styleOpen && track != null) ...[
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
                        alwaysIncludeSemantics: true,
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

  void _close() {
    if (!mounted) return;
    exitDetailRoute(context, fallbackRoute: DesktopRoutes.music);
  }

  void _browseMusic() {
    if (!mounted) return;
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      router.go(DesktopRoutes.music);
      return;
    }
    exitDetailRoute(context, fallbackRoute: DesktopRoutes.music);
  }

  Future<void> _editMetadata(MusicTrack currentTrack) async {
    final state = ref.read(musicCenterControllerProvider).asData?.value;
    final trackId = currentTrack.id;
    final MusicTrack track =
        state?.tracks.where((item) => item.id == trackId).firstOrNull ??
        state?.playbackItems
            .where((item) => item.track.id == trackId)
            .map((item) => item.track)
            .firstOrNull ??
        state?.selectedPlaylistTracks
            .where((item) => item.id == trackId)
            .firstOrNull ??
        state?.selectedAlbumTracks
            .where((item) => item.id == trackId)
            .firstOrNull ??
        state?.selectedArtistTracks
            .where((item) => item.id == trackId)
            .firstOrNull ??
        (state?.currentItem?.track.id == trackId
            ? state?.currentItem?.track
            : null) ??
        currentTrack;
    await showDesktopMusicMetadataDrawer(context: context, track: track);
  }
}

/// 顶栏全宽贴顶 64px 布局：底层铺满 `DesktopWindowDragRegion`（含顶部与两侧边缘），
/// 居中专辑标题与非交互规格徽章透传手势，左右交互按钮与右上角三键位于同级上方。
class _NowPlayingTopBar extends StatelessWidget {
  const _NowPlayingTopBar({
    required this.eyebrow,
    required this.albumTitle,
    required this.audioSpecBadge,
    required this.accent,
    required this.styleOpen,
    required this.showStyleToggle,
    required this.closeTooltip,
    required this.appearanceTooltip,
    required this.onClose,
    required this.onToggleStyle,
  });

  final String eyebrow;
  final String albumTitle;
  final String? audioSpecBadge;
  final Color accent;
  final bool styleOpen;
  final bool showStyleToggle;
  final String closeTooltip;
  final String appearanceTooltip;
  final VoidCallback onClose;
  final VoidCallback onToggleStyle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DesktopWindowDragRegion(child: SizedBox.expand()),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(width: 24),
              DesktopIconButton(
                key: const ValueKey('desktop-np-close'),
                icon: DesktopIcons.chevDown,
                size: 36,
                iconSize: 20,
                color: Colors.white.withValues(alpha: 0.88),
                tooltip: closeTooltip,
                onPressed: onClose,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: IgnorePointer(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        eyebrow,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DesktopType.eyebrow(
                          Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        albumTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DesktopType.caption(
                          Colors.white.withValues(alpha: 0.78),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              if (showStyleToggle)
                DesktopIconButton(
                  key: const ValueKey('desktop-np-appearance'),
                  icon: DesktopIcons.palette,
                  size: 34,
                  iconSize: 18,
                  active: styleOpen,
                  color:
                      styleOpen ? accent : Colors.white.withValues(alpha: 0.88),
                  tooltip: appearanceTooltip,
                  onPressed: onToggleStyle,
                ),
              if (audioSpecBadge != null) ...[
                const SizedBox(width: 10),
                IgnorePointer(
                  child: Container(
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
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accent,
                            boxShadow: [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.7),
                                blurRadius: 8,
                                spreadRadius: 0.5,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          audioSpecBadge!,
                          style: DesktopType.nano(
                            Colors.white.withValues(alpha: 0.82),
                          ).copyWith(letterSpacing: 0.6),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 12),
              const Align(
                alignment: Alignment.topRight,
                child: DesktopWindowControls(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 无曲目空态：独立渲染，不覆盖唱机与底栏。
class _NowPlayingEmptyState extends StatelessWidget {
  const _NowPlayingEmptyState({
    required this.title,
    required this.browseLabel,
    required this.onBrowse,
  });

  final String title;
  final String browseLabel;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              DesktopIcons.music,
              size: 42,
              color: Colors.white.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: DesktopType.displaySm(
                Colors.white.withValues(alpha: 0.78),
              ),
            ),
            const SizedBox(height: 18),
            DesktopButton(
              key: const ValueKey('desktop-np-empty-browse'),
              label: browseLabel,
              icon: DesktopIcons.music,
              variant: DesktopButtonVariant.glass,
              foregroundOverride: Colors.white,
              onPressed: onBrowse,
            ),
          ],
        ),
      ),
    );
  }
}
