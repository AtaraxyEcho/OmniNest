import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/music_chrome_colors.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/core/auth/user_capabilities.dart';
import 'package:omninest/core/widgets/mobile_sheet_semantics.dart';
import 'package:omninest/core/feedback/omni_feedback.dart';
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

part 'music_mobile_now_playing_pages.dart';

/// 沉浸播放器背景的两团环境光晕：玫瑰与青。
const Color _ambienceRose = Color(0x597E4880);
const Color _ambienceTeal = Color(0x57396469);

/// 样例播放页的第一页索引（封面页）。
const int _musicCoverPage = 0;

/// 样例播放页的第二页索引（整屏歌词页）。
const int _musicLyricPage = 1;

/// 移动端音乐播放详情页。
///
/// 主区是两页横滑 pager：第一页封面 + 曲名 + 进度 + 五控制行 + 底部工具行，
/// 第二页整屏歌词。头部只有返回 / 标题 / ⋯，翻页只靠横滑（原型已删除
/// 头部歌词钮、队列钮与页码点）。
class MusicMobileNowPlaying extends ConsumerStatefulWidget {
  const MusicMobileNowPlaying({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  ConsumerState<MusicMobileNowPlaying> createState() =>
      _MusicMobileNowPlayingState();
}

class _MusicMobileNowPlayingState extends ConsumerState<MusicMobileNowPlaying> {
  late final PageController _pageController;

  /// 当前 pager 页：只用于 `_selectView` 的幂等判断（封面点按跳歌词）。
  int _selectedView = _musicCoverPage;

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
    // 收藏只对"本地曲目 + 有自有活动写权限"开放；先收敛成可空曲目，
    // 让回调里的非空使用只依赖一处判据。
    final favoriteTarget =
        track != null &&
                item?.ref is LocalMusicRef &&
                ref.watch(userCapabilitiesProvider).canManageOwnActivity
            ? track
            : null;
    // 下滑关闭与 mini player 收起手势同阈值；横向翻页由 PageView 承担，
    // 歌词页自身的纵向滚动与关闭手势按主速度方向各自赢下手势竞技场。
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
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Column(
                children: [
                  SizedBox(
                    height: 48,
                    child: Row(
                      children: [
                        _MobileHeaderButton(
                          tooltip:
                              MaterialLocalizations.of(
                                context,
                              ).backButtonTooltip,
                          vector: OmniIcons.chevronLeft,
                          onPressed: widget.onClose,
                        ),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                l10n.musicImmersiveEyebrow.toUpperCase(),
                                style: TextStyle(
                                  color: context.env.inkFaint,
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
                                  color: context.env.ink,
                                  fontSize: AppTypography.labelSmall,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _MobileHeaderButton(
                          tooltip: l10n.musicNowPlayingMoreActions,
                          vector: OmniIcons.more,
                          onPressed:
                              () => _openActionsSheet(
                                visual: visual,
                                lyricScrollMode: lyricScrollMode,
                              ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: PageView(
                      controller: _pageController,
                      onPageChanged:
                          (index) => setState(() => _selectedView = index),
                      children: [
                        _MobileCoverPage(
                          item: item,
                          track: track,
                          lyrics: lyrics,
                          player: session.player,
                          enabled: track != null,
                          isPlaying: center?.isPlaying == true,
                          playMode:
                              center?.playMode ?? MusicPlayMode.sequential,
                          onShowLyrics: () => _selectView(_musicLyricPage),
                          onToggleFavorite:
                              favoriteTarget == null
                                  ? null
                                  : () =>
                                      _toggleFavorite(context, favoriteTarget),
                          onRequestPlayMode:
                              (mode) => ref
                                  .read(musicCenterControllerProvider.notifier)
                                  .setPlayMode(mode),
                          onSeek:
                              (position) => ref
                                  .read(musicPlaybackSessionProvider.notifier)
                                  .seekTo(position),
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
                          onTogglePlayback:
                              () =>
                                  ref
                                      .read(
                                        musicCenterControllerProvider.notifier,
                                      )
                                      .togglePlayback(),
                          onOpenSettings:
                              () =>
                                  showMusicPlaybackSettingsDialog(context, ref),
                          onOpenQueue: () => showMusicDeckQueue(context),
                        ),
                        _MobileLyricsPage(
                          player: session.player,
                          track: track,
                          lyrics: lyrics,
                          lyricsLoadFailed: item?.lyricsLoadFailed ?? false,
                          lyricSettings: _mobileLyricSettings(
                            visual.lyrics,
                            context.env,
                          ),
                          scrollMode: lyricScrollMode,
                          trackOffsetMs: trackOffsetMs,
                          onAdjustLyricOffset: _adjustTrackLyricOffset,
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
                          onSeek:
                              (position) => ref
                                  .read(musicPlaybackSessionProvider.notifier)
                                  .seekTo(position),
                        ),
                      ],
                    ),
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
      barrierColor: context.env.modalScrim,
      builder: (sheetContext) {
        return MobileSheetSemantics(
          child: SafeArea(
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
                              color: context.env.line25,
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
                          leading: const Icon(
                            Icons.equalizer_rounded,
                            size: 20,
                          ),
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
          (sheetContext) => MobileSheetSemantics(
            child: Padding(
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
          ),
    );
    if (!mounted || saved != true) {
      setState(() => _previewVisual = null);
    }
  }

  /// 翻到指定 pager 页：已在目标页时不重复动画（歌词页只此一个入口之一）。
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
                        colors: [_ambienceRose, Colors.transparent],
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
                        colors: [_ambienceTeal, Colors.transparent],
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
