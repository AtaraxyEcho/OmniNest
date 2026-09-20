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
import 'package:omninest/app/widgets/app_dropdown.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/log/dev_log.dart';
import 'package:omninest/core/widgets/app_slider.dart';
import 'package:omninest/features/music/application/music_audio_playback.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_playback_session.dart';
import 'package:omninest/features/music/application/music_spectrum_analyzer.dart';
import 'package:omninest/features/music/application/music_visualizer_preset_controller.dart';
import 'package:omninest/features/music/data/music_cover_cache.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_visualizer_preset.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_lyrics.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_queue_sheet.dart';
import 'package:omninest/features/music/presentation/player/music_playback_settings_dialog.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_style.dart';
import 'package:omninest/features/music/presentation/player/music_visual_color_picker.dart';
import 'package:omninest/features/music/presentation/widgets/music_playback_controls.dart';
import 'package:omninest/features/music/presentation/widgets/music_volume_button.dart';

part 'music_immersive_cover_deck.dart';
part 'music_immersive_cover_plane.dart';
part 'music_immersive_audio_bar.dart';
part 'music_immersive_controls.dart';
part 'music_immersive_player_stage.dart';
part 'music_immersive_preset_editor.dart';
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
    return _MusicImmersivePlayerStage(
      palette: palette,
      reservedTopInset: reservedTopInset,
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
    required this.onTogglePlayback,
    required this.onPrevious,
    required this.onNext,
    this.lyricSettings,
  });

  final MusicImmersivePalette palette;
  final MusicAudioPlayback player;
  final MusicTrack? track;
  final List<MusicLyricLine> lyrics;
  final double scale;
  final PortalLyricVisualSettings? lyricSettings;
  final VoidCallback onTogglePlayback;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return MusicImmersiveLyrics(
      palette: palette,
      player: player,
      track: track,
      lyrics: lyrics,
      scale: scale,
      lyricSettings: lyricSettings,
      onTogglePlayback: onTogglePlayback,
      onPrevious: onPrevious,
      onNext: onNext,
    );
  }
}

class _MusicImmersiveArtwork extends StatelessWidget {
  const _MusicImmersiveArtwork({
    required this.imageUrl,
    required this.fallback,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.borderRadius,
    this.cacheWidth,
    this.cacheHeight,
  });

  final String? imageUrl;
  final Widget fallback;
  final BoxFit fit;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final int? cacheWidth;
  final int? cacheHeight;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim();
    // 本地封面稳定 API 路径走专域缓存管理器；CDN 地址保持默认路径。
    // Web 端默认 HtmlImage 渲染绕过 cacheManager 且按页面 origin 解析
    // 相对 URL，跨源部署必须切 HttpGet 走管理器下载。
    final manager =
        url == null || !isMusicCoverApiPath(url)
            ? null
            : MusicCoverCache.maybeInstance;
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
    if (borderRadius == null) {
      return child;
    }
    return ClipRRect(borderRadius: borderRadius!, child: child);
  }
}
