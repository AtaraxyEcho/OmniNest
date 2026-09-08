import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/video_colors.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/features/video/domain/movie_models.dart'
    hide SubtitleTrack;
import 'package:omninest/features/video/presentation/widgets/movie_player_controls.dart';

/// 显示字幕选择面板。
void showSubtitleSheet({
  required BuildContext context,
  required PlaybackPlan plan,
  required int? activeSubtitleId,
  required List<SubtitleTrack> embeddedSubtitles,
  required SubtitleTrack? importedSubtitle,
  required void Function(PlaybackSubtitle) onSelect,
  required void Function(SubtitleTrack) onSelectEmbedded,
  required Future<void> Function() onImport,
  required VoidCallback onDisable,
  required VoidCallback onClosed,
}) {
  final l10n = AppLocalizations.of(context);
  final items = <Widget>[
    _PlayerChoiceTile(
      icon: Icons.subtitles_off_rounded,
      title: l10n.videoDisableSubtitles,
      selected: activeSubtitleId == null,
      onTap: (panelContext) {
        onDisable();
        Navigator.pop(panelContext);
      },
    ),
  ];
  if (importedSubtitle case final imported?) {
    items.add(
      _PlayerChoiceTile(
        icon: Icons.closed_caption_rounded,
        title: imported.title ?? l10n.videoImportedSubtitle,
        metadata: _TrackMetadata(
          language: imported.language ?? l10n.videoUnknown,
          source: l10n.videoLocalSubtitle,
        ),
        selected: activeSubtitleId == imported.id.hashCode,
        onTap: (panelContext) {
          onSelectEmbedded(imported);
          Navigator.pop(panelContext);
        },
      ),
    );
  }
  for (var index = 0; index < embeddedSubtitles.length; index++) {
    final subtitle = embeddedSubtitles[index];
    items.add(
      _PlayerChoiceTile(
        icon: Icons.subtitles_rounded,
        title: subtitle.title ?? l10n.videoSubtitleTrackNumber(index + 1),
        metadata: _TrackMetadata(
          language: subtitle.language ?? l10n.videoUnknown,
          source: subtitle.codec ?? l10n.videoUnknown,
        ),
        selected: activeSubtitleId == subtitle.id.hashCode,
        onTap: (panelContext) {
          onSelectEmbedded(subtitle);
          Navigator.pop(panelContext);
        },
      ),
    );
  }
  for (final subtitle in plan.subtitles) {
    items.add(
      _PlayerChoiceTile(
        icon: Icons.subtitles_rounded,
        title: subtitle.label,
        metadata: _TrackMetadata(
          language: subtitle.language,
          source: subtitle.isExternal ? l10n.videoExternal : l10n.videoEmbedded,
        ),
        selected: activeSubtitleId == subtitle.id.hashCode,
        onTap: (panelContext) {
          onSelect(subtitle);
          Navigator.pop(panelContext);
        },
      ),
    );
  }

  unawaited(
    _showPlayerPanel(
      context: context,
      title: l10n.videoSubtitleTrack,
      emptyMessage: items.length == 1 ? l10n.videoNoSubtitlesAvailable : null,
      headerAction: Builder(
        builder:
            (panelContext) => IconButton(
              tooltip: l10n.videoImportSubtitle,
              onPressed: () {
                Navigator.pop(panelContext);
                unawaited(onImport());
              },
              icon: const Icon(Icons.file_open_rounded),
            ),
      ),
      items: items,
    ).whenComplete(onClosed),
  );
}

/// 显示音轨和 Web 兼容音频模式面板。
void showAudioSheet({
  required BuildContext context,
  required String audioMode,
  required String? audioCodec,
  required bool showStreamModes,
  required List<AudioTrack> audioTracks,
  required String? activeAudioTrackId,
  required void Function(String) onSwitch,
  required void Function(AudioTrack) onSelectTrack,
  required VoidCallback onClosed,
}) {
  final l10n = AppLocalizations.of(context);
  final items = <Widget>[];
  for (var index = 0; index < audioTracks.length; index++) {
    final track = audioTracks[index];
    items.add(
      _PlayerChoiceTile(
        icon: Icons.language_rounded,
        title: track.title ?? l10n.videoLanguageTrackNumber(index + 1),
        metadata: _TrackMetadata(
          language: track.language ?? l10n.videoUnknown,
          source: track.codec ?? l10n.videoUnknown,
        ),
        selected: activeAudioTrackId == track.id,
        onTap: (panelContext) {
          onSelectTrack(track);
          Navigator.pop(panelContext);
        },
      ),
    );
  }
  if (showStreamModes) {
    items.addAll([
      _PlayerChoiceTile(
        icon: Icons.cached_rounded,
        title: l10n.videoCompatibleAudioAac,
        description: l10n.videoCompatibleAudioDesc,
        selected: audioMode == 'cached',
        onTap: (panelContext) {
          onSwitch('cached');
          Navigator.pop(panelContext);
        },
      ),
      _PlayerChoiceTile(
        icon: Icons.high_quality_rounded,
        title: l10n.videoOriginalAudioLabel(audioCodec ?? l10n.videoUnknown),
        description: l10n.videoOriginalAudioDesc,
        selected: audioMode == 'original',
        onTap: (panelContext) {
          onSwitch('original');
          Navigator.pop(panelContext);
        },
      ),
    ]);
  }
  unawaited(
    _showPlayerPanel(
      context: context,
      title: l10n.coreLanguage,
      emptyMessage: items.isEmpty ? l10n.videoNoLanguages : null,
      items: items,
    ).whenComplete(onClosed),
  );
}

/// 显示播放速度面板。
void showSpeedSheet({
  required BuildContext context,
  required double currentSpeed,
  required List<double> speedOptions,
  required void Function(double) onSelect,
  required VoidCallback onClosed,
}) {
  final l10n = AppLocalizations.of(context);
  final items = [
    for (final speed in speedOptions)
      _PlayerChoiceTile(
        icon: Icons.speed_rounded,
        title: '${_formatSpeed(speed)}x',
        selected: speed == currentSpeed,
        onTap: (panelContext) {
          onSelect(speed);
          Navigator.pop(panelContext);
        },
      ),
  ];
  unawaited(
    _showPlayerPanel(
      context: context,
      title: l10n.videoPlaybackSpeed,
      items: items,
    ).whenComplete(onClosed),
  );
}

/// 显示画面比例面板。
void showAspectRatioSheet({
  required BuildContext context,
  required double? currentRatio,
  required bool isFill,
  required void Function(AspectRatioOption) onSelect,
  required VoidCallback onClosed,
}) {
  bool isSelected(AspectRatioOption option) {
    if (option.isFill) {
      return isFill;
    }
    if (isFill) {
      return false;
    }
    return option.ratio == null
        ? currentRatio == null
        : currentRatio == option.ratio;
  }

  final options = AspectRatioOption.options(context);
  final items = [
    for (final option in options)
      _PlayerChoiceTile(
        icon: option.icon,
        title: option.label,
        selected: isSelected(option),
        onTap: (panelContext) {
          onSelect(option);
          Navigator.pop(panelContext);
        },
      ),
  ];
  unawaited(
    _showPlayerPanel(
      context: context,
      title: AppLocalizations.of(context).videoAspectRatio,
      items: items,
    ).whenComplete(onClosed),
  );
}

/// 显示播放器设置入口。
void showSettingsSheet({
  required BuildContext context,
  required PlaybackPlan plan,
  required double playbackSpeed,
  required String currentRatioLabel,
  required String audioMode,
  required int? activeSubtitleId,
  required VoidCallback onSpeedTap,
  required VoidCallback onAspectRatioTap,
  required VoidCallback? onAudioTap,
  required VoidCallback onSubtitleTap,
  required VoidCallback onInfoTap,
  required VoidCallback onClosed,
}) {
  final l10n = AppLocalizations.of(context);
  final items = <Widget>[
    _PlayerNavigationTile(
      icon: Icons.speed_rounded,
      title: l10n.videoPlaybackSpeed,
      value: '${_formatSpeed(playbackSpeed)}x',
      onTap: (panelContext) {
        _closePanelThen(panelContext, onSpeedTap);
      },
    ),
    _PlayerNavigationTile(
      icon: Icons.aspect_ratio_rounded,
      title: l10n.videoAspectRatio,
      value: currentRatioLabel,
      onTap: (panelContext) {
        _closePanelThen(panelContext, onAspectRatioTap);
      },
    ),
  ];
  if (onAudioTap != null) {
    items.add(
      _PlayerNavigationTile(
        icon: Icons.language_rounded,
        title: l10n.coreLanguage,
        value:
            isWebPlatform && plan.hasAudioCache
                ? audioMode == 'cached'
                    ? l10n.videoCompatible
                    : l10n.videoOriginalAudio
                : l10n.videoSelectLanguage,
        onTap: (panelContext) {
          _closePanelThen(panelContext, onAudioTap);
        },
      ),
    );
  }
  items.addAll([
    _PlayerNavigationTile(
      icon: Icons.subtitles_rounded,
      title: l10n.videoSubtitleTrack,
      value:
          activeSubtitleId == null
              ? l10n.videoSubtitlesOff
              : l10n.videoSubtitlesOn,
      onTap: (panelContext) {
        _closePanelThen(panelContext, onSubtitleTap);
      },
    ),
    _PlayerNavigationTile(
      icon: Icons.info_outline_rounded,
      title: l10n.videoPlaybackInfo,
      onTap: (panelContext) {
        _closePanelThen(panelContext, onInfoTap);
      },
    ),
  ]);
  unawaited(
    _showPlayerPanel(
      context: context,
      title: l10n.videoPlaybackSettings,
      items: items,
    ).whenComplete(onClosed),
  );
}

/// 显示播放技术信息。
void showPlaybackInfo({
  required BuildContext context,
  required PlaybackPlan plan,
  required String audioMode,
  required String currentRatioLabel,
  required double volume,
  required bool isMuted,
  required VoidCallback onClosed,
}) {
  final l10n = AppLocalizations.of(context);
  final items = <Widget>[
    InfoRow(label: l10n.videoInfoMode, value: plan.mode),
    InfoRow(label: l10n.videoInfoContainer, value: plan.container ?? '-'),
    InfoRow(label: l10n.videoInfoVideoCodec, value: plan.videoCodec ?? '-'),
    InfoRow(label: l10n.videoInfoAudioCodec, value: plan.audioCodec ?? '-'),
    if (isWebPlatform && plan.hasAudioCache)
      InfoRow(
        label: l10n.videoInfoAudioSource,
        value:
            audioMode == 'cached'
                ? l10n.videoCompatibleAudioAac
                : l10n.videoOriginalAudioLabel(l10n.videoUnknown),
      ),
    InfoRow(
      label: l10n.videoSubtitleTrack,
      value: l10n.videoInfoSubtitleCount(plan.subtitles.length),
    ),
    InfoRow(label: l10n.videoAspectRatio, value: currentRatioLabel),
    InfoRow(
      label: l10n.videoInfoVolume,
      value:
          isMuted
              ? l10n.videoVolumeMutedValue(volume.round())
              : l10n.videoVolumeValue(volume.round()),
    ),
  ];
  unawaited(
    _showPlayerPanel(
      context: context,
      title: l10n.videoPlaybackInfo,
      items: items,
    ).whenComplete(onClosed),
  );
}

Future<void> _showPlayerPanel({
  required BuildContext context,
  required String title,
  required List<Widget> items,
  Widget? headerAction,
  String? emptyMessage,
}) async {
  final useBottomSheet =
      isMobilePlatform || MediaQuery.sizeOf(context).width < 700;
  final reducedMotion = MediaQuery.disableAnimationsOf(context);
  Widget builder(BuildContext panelContext) => _PlayerPanelFrame(
    title: title,
    items: items,
    headerAction: headerAction,
    emptyMessage: emptyMessage,
    bottomSheet: useBottomSheet,
  );

  if (useBottomSheet) {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: builder,
    );
    return;
  }
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black38,
    transitionDuration:
        reducedMotion ? Duration.zero : const Duration(milliseconds: 180),
    pageBuilder:
        (context, animation, secondaryAnimation) => SafeArea(
          child: Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 16, bottom: 84),
              child: builder(context),
            ),
          ),
        ),
    transitionBuilder:
        (context, animation, secondaryAnimation, child) => FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.04),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        ),
  );
}

class _PlayerPanelFrame extends StatelessWidget {
  const _PlayerPanelFrame({
    required this.title,
    required this.items,
    required this.bottomSheet,
    this.headerAction,
    this.emptyMessage,
  });

  final String title;
  final List<Widget> items;
  final bool bottomSheet;
  final Widget? headerAction;
  final String? emptyMessage;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final availableHeight =
        mediaQuery.size.height -
        mediaQuery.padding.vertical -
        mediaQuery.viewInsets.vertical;
    final height = math.min(
      bottomSheet ? 640.0 : 560.0,
      availableHeight * (bottomSheet ? 0.82 : 0.72),
    );
    final colors = context.videoColors;
    return Material(
      color: colors.playerPanelSurface,
      elevation: bottomSheet ? 0 : 12,
      borderRadius:
          bottomSheet
              ? const BorderRadius.vertical(top: Radius.circular(12))
              : BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: bottomSheet ? double.infinity : 360,
        height: height,
        child: Column(
          children: [
            if (bottomSheet)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.playerControlMuted.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            SizedBox(
              height: 56,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.playerControlForeground,
                          fontSize: AppTypography.titleMedium,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (headerAction != null) headerAction!,
                    IconButton(
                      tooltip: AppLocalizations.of(context).videoClose,
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
            ),
            Divider(
              height: 1,
              color: colors.playerControlMuted.withValues(alpha: 0.12),
            ),
            Expanded(
              child:
                  emptyMessage != null
                      ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            emptyMessage!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: colors.playerControlMuted,
                              fontSize: AppTypography.bodyLarge,
                            ),
                          ),
                        ),
                      )
                      : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: items.length,
                        itemBuilder: (context, index) => items[index],
                      ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerChoiceTile extends StatelessWidget {
  const _PlayerChoiceTile({
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
    this.metadata,
    this.description,
  });

  final IconData icon;
  final String title;
  final bool selected;
  final void Function(BuildContext) onTap;
  final _TrackMetadata? metadata;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final colors = context.videoColors;
    return ListTile(
      minTileHeight: 56,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Icon(
        selected ? Icons.check_circle_rounded : icon,
        color:
            selected
                ? colors.playerControlForeground
                : colors.playerControlMuted,
      ),
      title: Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color:
              selected
                  ? colors.playerControlForeground
                  : colors.playerControlMuted,
          fontSize: AppTypography.bodyLarge,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      subtitle:
          metadata != null
              ? _TrackMetadataLine(metadata: metadata!)
              : description != null
              ? Text(
                description!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.playerControlMuted.withValues(alpha: 0.72),
                  fontSize: AppTypography.bodySmall,
                ),
              )
              : null,
      onTap: () => onTap(context),
    );
  }
}

class _PlayerNavigationTile extends StatelessWidget {
  const _PlayerNavigationTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.value,
  });

  final IconData icon;
  final String title;
  final String? value;
  final void Function(BuildContext) onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.videoColors;
    return ListTile(
      minTileHeight: 54,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(icon, color: colors.playerControlMuted),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: colors.playerControlForeground,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 150),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (value != null)
              Flexible(
                child: Text(
                  value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.playerControlMuted),
                ),
              ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, color: colors.playerControlMuted),
          ],
        ),
      ),
      onTap: () => onTap(context),
    );
  }
}

class _TrackMetadata {
  const _TrackMetadata({required this.language, required this.source});

  final String language;
  final String source;
}

class _TrackMetadataLine extends StatelessWidget {
  const _TrackMetadataLine({required this.metadata});

  final _TrackMetadata metadata;

  @override
  Widget build(BuildContext context) {
    final colors = context.videoColors;
    return Row(
      children: [
        Flexible(
          child: Text(
            metadata.language,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.playerControlMuted.withValues(alpha: 0.72),
              fontSize: AppTypography.bodySmall,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.playerControlHover,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                metadata.source,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.playerControlMuted,
                  // ignore: font_size_whitelist
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String _formatSpeed(double speed) {
  return speed.toStringAsFixed(speed == speed.roundToDouble() ? 0 : 2);
}

void _closePanelThen(BuildContext context, VoidCallback action) {
  Navigator.pop(context);
  WidgetsBinding.instance.addPostFrameCallback((_) => action());
}
