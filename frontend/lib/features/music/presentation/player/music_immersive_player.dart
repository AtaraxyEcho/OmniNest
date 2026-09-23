import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/feature/music_colors.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/log/dev_log.dart';
import 'package:omninest/features/music/application/music_audio_playback.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_playback_session.dart';
import 'package:omninest/features/music/application/music_visualizer_preset_controller.dart';
import 'package:omninest/features/music/application/music_cover_artwork.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:omninest/features/music/domain/music_visualizer_preset.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_layout_spec.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_lyrics.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_queue_sheet.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_preset_editor.dart';
import 'package:omninest/features/music/presentation/player/music_playback_settings_dialog.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_style.dart';
import 'package:omninest/features/music/presentation/widgets/music_playback_controls.dart';
import 'package:omninest/features/music/presentation/widgets/music_volume_button.dart';
import 'package:omninest/features/music/application/music_local_preferences_controller.dart';

part 'music_immersive_cover_deck.dart';
part 'music_immersive_cover_deck_widgets.dart';
part 'music_immersive_controls.dart';
part 'music_immersive_deck_spec.dart';
part 'music_immersive_player_stage.dart';
part 'music_immersive_track_header.dart';

/// Music 模块拥有的桌面数字沉浸播放器。
class MusicImmersivePlayer extends StatelessWidget {
  const MusicImmersivePlayer({
    this.palette = MusicImmersivePalette.digital,
    this.reservedTopInset = 0,
    super.key,
  });

  final MusicImmersivePalette palette;
  final double reservedTopInset;

  @override
  Widget build(BuildContext context) {
    // 沉浸层全屏遮盖了 beneath 的门户内容：用 BlockSemantics 把被遮盖内容
    // 排除出辅助功能树。否则隐藏的门户语义树（数百节点）仍随每次语义更新
    // 重新序列化，触发 Windows 辅助功能桥 "Nodes left pending by the
    // update" 失败；本层的可交互语义（顶栏、Dock、视觉编辑）全部保留。
    return BlockSemantics(
      child: _MusicImmersivePlayerStage(
        palette: palette,
        reservedTopInset: reservedTopInset,
      ),
    );
  }
}

class _ImmersiveLyrics extends StatelessWidget {
  const _ImmersiveLyrics({
    required this.palette,
    required this.player,
    required this.track,
    required this.lyrics,
    required this.scale,
    required this.blockAnchor,
    required this.textAlign,
    required this.onTogglePlayback,
    required this.onPrevious,
    required this.onNext,
    required this.onSeek,
    this.lyricSettings,
    this.lyricSpec,
    this.lyricScrollMode = true,
    this.trackOffsetMs,
    this.onAdjustLyricOffset,
  });

  final MusicImmersivePalette palette;
  final MusicAudioPlayback player;
  final MusicTrack? track;
  final List<MusicLyricLine> lyrics;
  final double scale;

  /// 文字块锚点：两侧布局贴左基线，居中布局居中。
  final Alignment blockAnchor;

  /// 居中锚点下的文本排列：两侧布局左对齐，居中布局居中。
  final TextAlign textAlign;
  final PortalLyricVisualSettings? lyricSettings;

  /// 复刻参数（由舞台按布局解析）：字号、行距与上下渐隐按样例取值。
  final MusicLyricSpec? lyricSpec;
  final VoidCallback onTogglePlayback;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  /// 进度跳转：由舞台转发到播放会话的受控 seek。
  final Future<void> Function(Duration position) onSeek;

  /// 桌面端歌词形态由布局唯一决定：两侧滚动、居中固定窗口。
  final bool lyricScrollMode;

  /// 曲目级歌词延迟覆盖（设备本地）与菜单微调回调，透传给歌词组件。
  final int? trackOffsetMs;
  final void Function(int deltaMs)? onAdjustLyricOffset;

  @override
  Widget build(BuildContext context) {
    return MusicImmersiveLyrics(
      palette: palette,
      player: player,
      track: track,
      lyrics: lyrics,
      scale: scale,
      lyricSettings: lyricSettings,
      lyricSpec: lyricSpec,
      scrollMode: lyricScrollMode,
      trackOffsetMs: trackOffsetMs,
      onAdjustLyricOffset: onAdjustLyricOffset,
      textAlign: textAlign,
      blockAnchor: blockAnchor,
      onTogglePlayback: onTogglePlayback,
      onPrevious: onPrevious,
      onNext: onNext,
      onSeek: onSeek,
    );
  }
}

class _MusicImmersiveArtwork extends ConsumerWidget {
  const _MusicImmersiveArtwork({
    required this.imageUrl,
    required this.fallback,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.cacheWidth,
    this.cacheHeight,
  });

  final String? imageUrl;
  final Widget fallback;
  final BoxFit fit;
  final double? width;
  final double? height;
  final int? cacheWidth;
  final int? cacheHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = imageUrl?.trim();
    // 本地封面稳定 API 路径走专域缓存管理器；CDN 地址保持默认路径。
    // Web 端默认 HtmlImage 渲染绕过 cacheManager 且按页面 origin 解析
    // 相对 URL，跨源部署必须切 HttpGet 走管理器下载。
    final manager =
        url == null ? null : ref.watch(musicCoverCacheManagerProvider(url));
    final child =
        url == null || url.isEmpty
            ? fallback
            : CachedNetworkImage(
              imageUrl: url,
              fit: fit,
              width: width,
              height: height,
              memCacheWidth: cacheWidth,
              memCacheHeight: cacheHeight,
              cacheManager: manager,
              imageRenderMethodForWeb:
                  manager == null
                      ? ImageRenderMethodForWeb.HtmlImage
                      : ImageRenderMethodForWeb.HttpGet,
              filterQuality: FilterQuality.medium,
              placeholder: (context, url) => fallback,
              errorWidget: (context, url, error) => fallback,
            );
    return child;
  }
}
