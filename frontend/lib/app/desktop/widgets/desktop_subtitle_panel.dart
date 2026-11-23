import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_dialogs.dart';
import 'package:omninest/app/desktop/widgets/desktop_surfaces.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/features/video/domain/movie_models.dart';

/// 电影与剧集/番剧详情页共享字幕面板（限宽 760）。
///
/// 统一顶部工具栏（左侧统计/分集选择器，右侧上传按钮）、`DesktopHover` 卡片行、
/// 3 枚紧凑徽章（可读语言 / 等宽大写格式 / 外挂或内置）以及外挂删除前的
/// `showDesktopConfirm` 二次确认。
class DesktopSubtitlePanel extends StatelessWidget {
  const DesktopSubtitlePanel({
    required this.tracks,
    required this.uploading,
    required this.deletingTrackId,
    required this.onUpload,
    required this.onDelete,
    this.leading,
    this.emptyMessage,
    super.key,
  });

  final List<SubtitleTrack> tracks;
  final bool uploading;
  final String? deletingTrackId;
  final VoidCallback onUpload;
  final Future<void> Function(SubtitleTrack track) onDelete;

  /// 顶栏左侧插槽（剧集页放分集下拉框；电影页不传时自动展示字幕数量统计）。
  final Widget? leading;
  final String? emptyMessage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final isZh = Localizations.localeOf(context).languageCode == 'zh';

    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child:
                      leading ??
                      Text(
                        isZh
                            ? '共 ${tracks.length} 条字幕轨'
                            : '${tracks.length} subtitle track${tracks.length == 1 ? '' : 's'}',
                        style: DesktopType.dense(skin.text2),
                      ),
                ),
                const SizedBox(width: 12),
                DesktopButton(
                  label: l10n.videoDetailUploadSubtitle,
                  icon: DesktopIcons.upload,
                  variant: DesktopButtonVariant.soft,
                  busy: uploading,
                  onPressed: uploading ? null : onUpload,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (tracks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: DesktopEmpty(
                  icon: DesktopIcons.captions,
                  message: emptyMessage ?? l10n.videoNoSubtitlesAvailable,
                  actionLabel: null,
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < tracks.length; i++)
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: i == tracks.length - 1 ? 0 : 8,
                      ),
                      child: _DesktopSubtitleRow(
                        track: tracks[i],
                        deleting: deletingTrackId == tracks[i].id,
                        anyDeleting: deletingTrackId != null,
                        onDelete:
                            () => unawaited(_confirmDelete(context, tracks[i])),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, SubtitleTrack track) async {
    final l10n = AppLocalizations.of(context);
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final confirmed = await showDesktopConfirm(
      context,
      title: l10n.videoDeleteSubtitleTooltip,
      message:
          isZh
              ? '确认删除外挂字幕「${track.label}」？此操作无法撤销。'
              : 'Delete external subtitle "${track.label}"? This cannot be undone.',
      confirmLabel: l10n.videoDeleteSubtitleTooltip,
      cancelLabel: l10n.videoCancel,
      destructive: true,
    );
    if (!confirmed) return;
    await onDelete(track);
  }
}

class _DesktopSubtitleRow extends StatelessWidget {
  const _DesktopSubtitleRow({
    required this.track,
    required this.deleting,
    required this.anyDeleting,
    required this.onDelete,
  });

  final SubtitleTrack track;
  final bool deleting;
  final bool anyDeleting;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final languageLabel = _readableLanguage(track.language, isZh: isZh);
    final formatLabel = _formatBadge(track);
    final sourceLabel =
        track.embedded
            ? l10n.videoRedesignSubtitleEmbedded
            : l10n.videoRedesignSubtitleExternal;

    return DesktopHover(
      cursor: SystemMouseCursors.basic,
      builder:
          (context, hovered) => AnimatedContainer(
            duration: DesktopMotion.of(
              context,
              const Duration(milliseconds: 140),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: hovered ? skin.raise : skin.panel,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: hovered ? skin.line2 : skin.line),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color:
                        track.embedded
                            ? skin.raise2
                            : skin.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    DesktopIcons.captions,
                    size: 16,
                    color: track.embedded ? skin.text2 : skin.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DesktopType.rowTitle(skin.text),
                      ),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _SubtitleBadge(
                            label: languageLabel,
                            background: skin.raise2,
                            foreground: skin.text2,
                          ),
                          _SubtitleBadge(
                            label: formatLabel,
                            background: skin.raise2,
                            foreground: skin.text2,
                            mono: true,
                          ),
                          _SubtitleBadge(
                            label: sourceLabel,
                            background:
                                track.embedded
                                    ? skin.raise2
                                    : skin.accent.withValues(alpha: 0.14),
                            foreground:
                                track.embedded ? skin.text3 : skin.accent,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (!track.embedded) ...[
                  const SizedBox(width: 10),
                  if (deleting)
                    const SizedBox.square(
                      dimension: 28,
                      child: Padding(
                        padding: EdgeInsets.all(6),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    DesktopIconButton(
                      icon: DesktopIcons.trash,
                      tooltip: l10n.videoDeleteSubtitleTooltip,
                      onPressed: anyDeleting ? null : onDelete,
                    ),
                ],
              ],
            ),
          ),
    );
  }
}

class _SubtitleBadge extends StatelessWidget {
  const _SubtitleBadge({
    required this.label,
    required this.background,
    required this.foreground,
    this.mono = false,
  });

  final String label;
  final Color background;
  final Color foreground;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: (mono
                ? DesktopType.mono(foreground)
                : DesktopType.micro(foreground))
            .copyWith(
              fontSize: DesktopType.sizeCaption,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

String _readableLanguage(String raw, {required bool isZh}) {
  final code = raw.trim().toLowerCase();
  if (code.isEmpty || code == 'und' || code == 'unknown') {
    return isZh ? '未知语言' : 'Unknown';
  }
  return switch (code) {
    'zh' ||
    'zh-cn' ||
    'zh-hans' ||
    'chi' ||
    'zho' ||
    'chs' => isZh ? '简体中文' : 'Chinese (Simplified)',
    'zh-tw' ||
    'zh-hk' ||
    'zh-hant' ||
    'cht' => isZh ? '繁体中文' : 'Chinese (Traditional)',
    'en' || 'eng' || 'en-us' || 'en-gb' => 'English',
    'ja' || 'jpn' => '日本語',
    'ko' || 'kor' => '한국어',
    'fr' || 'fre' || 'fra' => 'Français',
    'de' || 'ger' || 'deu' => 'Deutsch',
    'es' || 'spa' => 'Español',
    'ru' || 'rus' => 'Русский',
    _ => code.toUpperCase(),
  };
}

String _formatBadge(SubtitleTrack track) {
  final raw = track.kind.trim();
  if (raw.isNotEmpty && raw.toLowerCase() != 'subtitles') {
    return raw.toUpperCase();
  }
  final url = track.url?.toLowerCase() ?? '';
  final label = track.label.toLowerCase();
  for (final ext in const ['ass', 'ssa', 'srt', 'vtt', 'pgs', 'sup', 'sub']) {
    if (url.endsWith('.$ext') || label.endsWith('.$ext')) {
      return ext.toUpperCase();
    }
  }
  return raw.isEmpty ? 'SUB' : raw.toUpperCase();
}
