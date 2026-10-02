import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/auth/user_capabilities.dart';
import 'package:omninest/core/widgets/animated_switcher_semantics.dart';
import 'package:omninest/core/widgets/omni_icons.dart';
import 'package:omninest/features/music/application/music_audio_playback.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_local_preferences_controller.dart';
import 'package:omninest/features/music/application/music_playback_session.dart';
import 'package:omninest/features/music/application/music_visualizer_preset_controller.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:omninest/features/music/domain/music_visualizer_preset.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_primitives.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_queue_sheet.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_lyrics.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_preset_editor.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_style.dart';
import 'package:omninest/features/music/presentation/player/music_playback_settings_dialog.dart';
import 'package:omninest/features/music/presentation/widgets/music_playback_controls.dart';
import 'package:omninest/app/theme/feature/music_chrome_colors.dart';
import 'package:omninest/core/feedback/omni_feedback.dart';

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

  /// 默认展示滚动歌词页（索引 1）；封面页为用户可切换的次视图。
  int _selectedView = 1;

  /// 歌词样式面板的即时预览（未保存前只作用于当前播放页）。
  PortalMusicVisualizerSettings? _previewVisual;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedView);
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
    final preferences =
        ref.watch(musicVisualizerPreferencesProvider).asData?.value ??
        const PortalMusicVisualizerPreferences();
    final visual = _previewVisual ?? preferences.visual;
    // 歌词形态是设备级偏好：移动端同样可切换（两种形态都文本居中）。
    final lyricScrollMode =
        ref.watch(musicLyricScrollModeProvider).asData?.value ??
        kMusicLyricScrollModeDefault;
    final item = center?.currentItem;
    final track = item?.track ?? center?.activeTrack;
    // 曲目级歌词延迟覆盖（设备本地）：仅在解析完成后生效，未设置时退回全局校准。
    final trackOffsetMs =
        track == null
            ? null
            : ref.watch(musicTrackLyricOffsetProvider(track.id)).asData?.value;
    final lyrics = track?.lyricLines ?? const <MusicLyricLine>[];
    // 下滑关闭：与 mini player 收起手势同阈值；页面内歌词区有自己的手势
    // 竞争，垂直拖拽仅在未被内层消费时触发。
    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > 240) {
          widget.onClose();
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          const _MobileCoverBackdrop(),
          const _MobileAuroraLayer(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: Column(
                children: [
                  SizedBox(
                    height: 44,
                    child: Row(
                      children: [
                        _MobileHeaderButton(
                          tooltip:
                              MaterialLocalizations.of(
                                context,
                              ).backButtonTooltip,
                          icon: Icons.keyboard_arrow_down_rounded,
                          onPressed: widget.onClose,
                        ),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                l10n.musicImmersiveEyebrow.toUpperCase(),
                                // ignore: font_size_whitelist
                                style: TextStyle(
                                  color: const Color(0x9EF6F6F2),
                                  // ignore: font_size_whitelist
                                  fontSize: 8,
                                  letterSpacing: 1.2,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                track?.albumTitle.isNotEmpty == true
                                    ? track!.albumTitle
                                    : (track?.title ??
                                        l10n.musicDeckNowPlaying),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: AppTypography.labelSmall,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _MobileHeaderButton(
                          tooltip: l10n.musicNowPlayingMoreActions,
                          icon: Icons.more_horiz_rounded,
                          onPressed:
                              () => _openActionsSheet(
                                visual: preferences.visual,
                                lyricScrollMode: lyricScrollMode,
                              ),
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
                          lyrics: lyrics,
                          position: session.player.state.position,
                          onShowLyrics: () => _selectView(1),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
                          child: MusicImmersiveLyrics(
                            palette: MusicImmersivePalette.digital,
                            player: session.player,
                            track: track,
                            lyrics: lyrics,
                            lyricsLoadFailed: item?.lyricsLoadFailed ?? false,
                            scale:
                                MediaQuery.sizeOf(context).width < 390
                                    ? 0.86
                                    : 0.94,
                            // 移动端两种形态都文本居中：窄屏长句折行后居中
                            // 更贴近主流移动播放器排版。
                            textAlign: TextAlign.center,
                            blockAnchor: Alignment.center,
                            lyricSettings: visual.lyrics,
                            scrollMode: lyricScrollMode,
                            trackOffsetMs: trackOffsetMs,
                            onAdjustLyricOffset: _adjustTrackLyricOffset,
                            onTogglePlayback:
                                () =>
                                    ref
                                        .read(
                                          musicCenterControllerProvider
                                              .notifier,
                                        )
                                        .togglePlayback(),
                            onPrevious:
                                () =>
                                    ref
                                        .read(
                                          musicCenterControllerProvider
                                              .notifier,
                                        )
                                        .previousTrack(),
                            onNext:
                                () =>
                                    ref
                                        .read(
                                          musicCenterControllerProvider
                                              .notifier,
                                        )
                                        .nextTrack(),
                            onSeek:
                                (position) => ref
                                    .read(musicPlaybackSessionProvider.notifier)
                                    .seekTo(position),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _MobileTrackHeader(
                    item: item,
                    track: track,
                    onToggleFavorite:
                        track == null ||
                                item?.ref is! LocalMusicRef ||
                                !ref
                                    .watch(userCapabilitiesProvider)
                                    .canManageOwnActivity
                            ? null
                            : () => _toggleFavorite(context, track),
                  ),
                  const SizedBox(height: 6),
                  _MobilePlaybackControls(
                    player: session.player,
                    enabled: track != null,
                    isPlaying: center?.isPlaying == true,
                    playMode: center?.playMode ?? MusicPlayMode.sequential,
                    onCyclePlayMode:
                        () =>
                            ref
                                .read(musicCenterControllerProvider.notifier)
                                .cyclePlayMode(),
                    onSeek:
                        (position) => ref
                            .read(musicPlaybackSessionProvider.notifier)
                            .seekTo(position),
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
                  ),
                  _MobileUtilityRow(
                    onOpenSettings:
                        () => showMusicPlaybackSettingsDialog(context, ref),
                    onOpenQueue: () => showMusicDeckQueue(context),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 头部 ⋯ 动作面板：歌词样式与播放设置的收纳入口（队列在底部工具行）。
  Future<void> _openActionsSheet({
    required PortalMusicVisualizerSettings visual,
    required bool lyricScrollMode,
  }) async {
    final l10n = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                child: Material(
                  color: MusicChromeColors.panelBackground,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 10),
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.tune_rounded, size: 20),
                        title: Text(l10n.musicVisualizerLyricStyle),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          _openLyricStyle(
                            visual: visual,
                            lyricScrollMode: lyricScrollMode,
                          );
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.equalizer_rounded, size: 20),
                        title: Text(l10n.musicPlaybackSettings),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          showMusicPlaybackSettingsDialog(context, ref);
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 打开歌词样式面板：移动端只展示歌词分区，形态开关写回设备级偏好，
  /// 改动即时预览，确认后写入跨端视觉设置。
  Future<void> _openLyricStyle({
    required PortalMusicVisualizerSettings visual,
    required bool lyricScrollMode,
  }) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (sheetContext) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: FractionallySizedBox(
              heightFactor: 0.78,
              child: MusicVisualEditorPanel(
                key: const ValueKey('music-mobile-lyric-style'),
                palette: MusicImmersivePalette.digital,
                source: visual,
                sections: const <MusicVisualEditorSection>{
                  MusicVisualEditorSection.mobileLyrics,
                },
                lyricScrollMode: lyricScrollMode,
                onLyricScrollModeChanged:
                    (enabled) => ref
                        .read(musicLyricScrollModeProvider.notifier)
                        .setScrollMode(enabled),
                onChanged: (next) => setState(() => _previewVisual = next),
                onSave: (next) async {
                  await ref
                      .read(musicVisualizerPreferencesProvider.notifier)
                      .saveVisual(next);
                  if (sheetContext.mounted) {
                    Navigator.of(sheetContext).pop(true);
                  }
                },
                onClose: () => Navigator.of(sheetContext).pop(false),
              ),
            ),
          ),
    );
    if (!mounted || saved != true) {
      setState(() => _previewVisual = null);
    }
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

  /// 调整当前曲目的歌词延迟（行菜单触发）：写入曲目级设备本地覆盖。
  void _adjustTrackLyricOffset(int deltaMs) {
    if (!mounted) {
      return;
    }
    final track =
        ref.read(musicCenterControllerProvider).asData?.value.currentTrack;
    if (track == null) {
      return;
    }
    unawaited(
      ref
          .read(musicTrackLyricOffsetProvider(track.id).notifier)
          .adjust(deltaMs),
    );
  }

  Future<void> _toggleFavorite(BuildContext context, MusicTrack track) async {
    final wasFavorite = track.favorite;
    try {
      await ref
          .read(musicCenterControllerProvider.notifier)
          .toggleFavorite(track);
      if (context.mounted) {
        showOmniFeedback(
          context,
          wasFavorite
              ? AppLocalizations.of(context).favoriteRemoved
              : AppLocalizations.of(context).favoriteAdded,
          severity: OmniFeedbackSeverity.success,
        );
      }
    } on Exception {
      if (!context.mounted) {
        return;
      }
      showOmniFeedback(
        context,
        AppLocalizations.of(context).musicFavoriteToggleFailed,
        severity: OmniFeedbackSeverity.error,
      );
    }
  }
}

class _MobileCoverBackdrop extends StatelessWidget {
  const _MobileCoverBackdrop();

  @override
  Widget build(BuildContext context) {
    // 桌面同语言：动态壁纸由应用背景宿主透出，播放页不再叠专辑图模糊
    // 底图与重遮罩，只保留纵向可读性渐变——回切 Music 页时两侧同底，
    // 过渡快照淡出不再产生亮度跳变（黑闪）。
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [MusicChromeColors.scrimStart, MusicChromeColors.scrimEnd],
          stops: [0.35, 1],
        ),
      ),
    );
  }
}

class _MobileArtworkView extends StatelessWidget {
  const _MobileArtworkView({
    required this.track,
    required this.lyrics,
    required this.position,
    required this.onShowLyrics,
  });

  final MusicTrack? track;
  final List<MusicLyricLine> lyrics;
  final Duration position;
  final VoidCallback onShowLyrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final hasPreview = lyrics.isNotEmpty;
        final available = math.min(
          math.max(1, constraints.maxWidth - 32),
          math.max(1, constraints.maxHeight - (hasPreview ? 190 : 28)),
        );
        final coverSize = available.clamp(1.0, 340.0).toDouble();
        // 样例 main 为可滚动区：短横屏时封面+歌词预览整体可滚。
        return SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Center(
                child: Semantics(
                  button: true,
                  label: AppLocalizations.of(context).musicNowPlayingLyrics,
                  child: GestureDetector(
                    onTap: onShowLyrics,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      switchInCurve: Curves.easeOutCubic,
                      // 退场子树排除语义，避免与入场子树同批更新触发桥失败。
                      layoutBuilder: excludeExitingSemanticsStack,
                      child: SizedBox.square(
                        key: ValueKey<String?>('mobile-cover-${track?.id}'),
                        dimension: coverSize,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(26),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.5),
                                    blurRadius: 65,
                                    spreadRadius: -12,
                                    offset: const Offset(0, 25),
                                  ),
                                ],
                              ),
                              child: MusicDeckArtwork(
                                title: track?.title ?? '',
                                imageUrl: track?.coverUrl,
                                borderRadius: 26,
                              ),
                            ),
                            if (_isLossless(track?.format))
                              const Positioned(
                                top: 13,
                                right: 13,
                                child: _LosslessBadge(),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (hasPreview)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _LiveLyricsPreview(
                    lyrics: lyrics,
                    position: position,
                    onOpenFullLyrics: onShowLyrics,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 底部工具行（样例 player-utility）：左=播放设置，右=队列，
/// 沉在控制行下方两端，替代原头部双钮。
class _MobileUtilityRow extends StatelessWidget {
  const _MobileUtilityRow({
    required this.onOpenSettings,
    required this.onOpenQueue,
  });

  final VoidCallback onOpenSettings;
  final VoidCallback onOpenQueue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 4,
        right: 4,
        bottom: math.max(10, MediaQuery.paddingOf(context).bottom),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            tooltip: l10n.musicPlaybackSettings,
            onPressed: onOpenSettings,
            icon: const Icon(Icons.equalizer_rounded, size: 20),
            style: IconButton.styleFrom(
              foregroundColor: const Color(0x75F6F6F2),
              minimumSize: const Size.square(44),
            ),
          ),
          IconButton(
            tooltip: l10n.musicQueueTitle,
            onPressed: onOpenQueue,
            icon: const Icon(Icons.queue_music_rounded, size: 21),
            style: IconButton.styleFrom(
              foregroundColor: const Color(0x75F6F6F2),
              minimumSize: const Size.square(44),
            ),
          ),
        ],
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
                l10n.musicNowPlayingEyebrow.toUpperCase(),
                // ignore: font_size_whitelist
                style: TextStyle(
                  color: const Color(0xFFD5F17D),
                  // ignore: font_size_whitelist
                  fontSize: 8,
                  letterSpacing: 1.3,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                track?.title ?? l10n.musicNotPlaying,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'InstrumentSerif',
                  // ignore: font_size_whitelist
                  fontSize: 35,
                  height: 1,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                track == null
                    ? l10n.musicDeckSelectTrack
                    : '${track!.artistName} · ${track!.albumTitle}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // ignore: font_size_whitelist
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.62),
                  // ignore: font_size_whitelist
                  fontSize: 10,
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
            icon: OmniIcon(
              icon: OmniIcons.heart,
              size: 22,
              color:
                  track?.favorite == true
                      ? const Color(0xFFD5F17D)
                      : Colors.white.withValues(alpha: 0.84),
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
    required this.playMode,
    required this.onCyclePlayMode,
    required this.onSeek,
    required this.onPrevious,
    required this.onTogglePlayback,
    required this.onNext,
  });

  final MusicAudioPlayback player;
  final bool enabled;
  final bool isPlaying;
  final MusicPlayMode playMode;
  final VoidCallback onCyclePlayMode;

  /// 进度跳转经播放会话，避免与切歌加载竞争。
  final Future<void> Function(Duration position) onSeek;
  final VoidCallback onPrevious;
  final VoidCallback onTogglePlayback;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return StreamBuilder<Duration>(
      stream: player.stream.duration,
      initialData: player.state.duration,
      builder: (context, durationSnapshot) {
        final duration = durationSnapshot.data ?? Duration.zero;
        final totalMs = duration.inMilliseconds;
        return Column(
          children: [
            MusicThrottledPositionBuilder(
              player: player,
              builder: (context, position) {
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
                      activeColor: MusicChromeColors.tealAccent,
                      inactiveColor: Colors.white.withValues(alpha: 0.14),
                      thumbColor: Colors.white,
                      onChanged:
                          enabled && totalMs > 0
                              ? (value) => unawaited(
                                onSeek(
                                  Duration(
                                    milliseconds: (totalMs * value).round(),
                                  ),
                                ),
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
                  ],
                );
              },
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                // 播放模式单按钮轮换：与桌面 Dock 同一交互（只换图标，不留底色）。
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: MusicPlayModeButton(
                      playMode: playMode,
                      onTap: enabled ? onCyclePlayMode : null,
                      iconSize: 20,
                      padding: 10,
                      idleColor: Colors.white.withValues(alpha: 0.62),
                      activeColor: MusicChromeColors.tealAccent,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: l10n.musicDeckPrevious,
                  onPressed: enabled ? onPrevious : null,
                  icon: Icon(Icons.skip_previous_rounded, size: 30),
                  color: Colors.white,
                ),
                const SizedBox(width: 10),
                MusicPlaybackButton(
                  isPlaying: isPlaying,
                  tooltip: isPlaying ? l10n.musicPause : l10n.musicPlay,
                  onPressed: enabled ? onTogglePlayback : null,
                  buttonSize: MusicPlaybackButtonSize.regular,
                  backgroundColor: MusicChromeColors.tealPanel,
                  accentColor: MusicChromeColors.tealAccent,
                  foregroundColor: Colors.white,
                ),
                const SizedBox(width: 10),
                IconButton(
                  tooltip: l10n.musicDeckNext,
                  onPressed: enabled ? onNext : null,
                  icon: Icon(Icons.skip_next_rounded, size: 30),
                  color: Colors.white,
                ),
                const Expanded(child: SizedBox.shrink()),
              ],
            ),
          ],
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
}

/// 播放页 aurora 光晕（原型 player-aurora 的双径向紫青光，45px 模糊）。
class _MobileAuroraLayer extends StatelessWidget {
  const _MobileAuroraLayer();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      bottom: -60,
      child: IgnorePointer(
        child: SizedBox(
          height: 420,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 45, sigmaY: 45),
            child: Stack(
              children: [
                Positioned(
                  left: -80,
                  right: 80,
                  top: 60,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.center,
                        radius: 0.55,
                        colors: [Color(0x597E4880), Colors.transparent],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 80,
                  right: -80,
                  top: 100,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.center,
                        radius: 0.5,
                        colors: [Color(0x57396469), Colors.transparent],
                      ),
                    ),
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

/// 无损格式判定（大小写不敏感的常见无损容器）。
bool _isLossless(String? format) {
  if (format == null || format.isEmpty) {
    return false;
  }
  const lossless = {'FLAC', 'ALAC', 'WAV', 'APE', 'WV', 'DSF', 'AIFF'};
  return lossless.contains(format.toUpperCase());
}

/// LOSSLESS 徽标（原型 player-art > b：玻璃底白字 7px）。
class _LosslessBadge extends StatelessWidget {
  const _LosslessBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0x7A090D0C),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0x29FFFFFF)),
      ),
      child: const Text(
        'LOSSLESS',
        // ignore: font_size_whitelist
        style: TextStyle(
          color: Colors.white,
          // ignore: font_size_whitelist
          fontSize: 7,
          letterSpacing: 1,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// LIVE LYRICS 预览块（样例 lyric-preview）：眉标 + Full lyrics 按钮 +
/// 三行衬线歌词逐行淡出。
class _LiveLyricsPreview extends StatelessWidget {
  const _LiveLyricsPreview({
    required this.lyrics,
    required this.position,
    required this.onOpenFullLyrics,
  });

  final List<MusicLyricLine> lyrics;
  final Duration position;
  final VoidCallback onOpenFullLyrics;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 当前时间轴附近的 1 行 + 后 2 行作为预览。
    var currentIndex = -1;
    for (var i = 0; i < lyrics.length; i++) {
      if (lyrics[i].position <= position + const Duration(milliseconds: 300)) {
        currentIndex = i;
      } else {
        break;
      }
    }
    if (currentIndex < 0) {
      currentIndex = 0;
    }
    final preview = <MusicLyricLine>[
      for (var i = currentIndex; i < lyrics.length && i < currentIndex + 3; i++)
        lyrics[i],
    ];
    return Container(
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0x21FFFFFF))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.musicLiveLyrics.toUpperCase(),
                  // ignore: font_size_whitelist
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.62),
                    // ignore: font_size_whitelist
                    fontSize: 8,
                    letterSpacing: 1.3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onOpenFullLyrics,
                icon: const OmniIcon(
                  icon: OmniIcons.chevron,
                  size: 15,
                  color: Colors.white54,
                ),
                label: Text(l10n.musicFullLyrics),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white54,
                  minimumSize: const Size(48, 38),
                  padding: EdgeInsets.zero,
                  // ignore: font_size_whitelist
                  textStyle: TextStyle(fontSize: 8),
                ),
              ),
            ],
          ),
          for (var i = 0; i < preview.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                preview[i].text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.70 - i * 0.26),
                  fontFamily: 'InstrumentSerif',
                  // ignore: font_size_whitelist
                  fontSize: 24,
                  height: 1.2,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
