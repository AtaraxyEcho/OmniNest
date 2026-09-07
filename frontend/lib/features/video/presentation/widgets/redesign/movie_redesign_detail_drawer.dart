import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/domain/movie_library_models.dart';
import 'package:omninest/features/video/domain/movie_playback_models.dart';
import 'package:omninest/features/video/presentation/theme/movie_redesign_theme.dart';
import 'package:omninest/features/video/presentation/widgets/movie_feedback.dart';
import 'package:omninest/features/video/presentation/widgets/redesign/movie_redesign_status.dart';

/// 新版详情抽屉：右侧滑出，展示压题图、元信息、简介、立即播放、字幕轨与版本。
class MovieRedesignDetailDrawer extends ConsumerStatefulWidget {
  const MovieRedesignDetailDrawer({
    required this.item,
    required this.onClose,
    super.key,
  });

  final MovieVideoItem item;
  final VoidCallback onClose;

  @override
  ConsumerState<MovieRedesignDetailDrawer> createState() =>
      _MovieRedesignDetailDrawerState();
}

class _MovieRedesignDetailDrawerState
    extends ConsumerState<MovieRedesignDetailDrawer> {
  bool _uploading = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.movieRedesign;
    final text = context.movieRedesignText;
    final l10n = AppLocalizations.of(context);
    final item = widget.item;
    final wide = MediaQuery.sizeOf(context).width >= 640;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
      },
      child: Focus(
        autofocus: true,
        child: Material(
          color: Colors.transparent,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (wide)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onClose,
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.60),
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: Material(
                  color: palette.background,
                  child: SizedBox(
                    width: wide ? 384 : double.infinity,
                    height: double.infinity,
                    child: Column(
                      children: [
                        _DrawerHeader(item: item, onClose: widget.onClose),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _MetaRow(item: item),
                                if (item.overview != null &&
                                    item.overview!.trim().isNotEmpty) ...[
                                  const SizedBox(height: 16),
                                  Text(
                                    item.overview!,
                                    style: text.body(
                                      size: 14,
                                      height: 22 / 14,
                                      color: palette.foreground,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  child: Material(
                                    color: palette.primary,
                                    borderRadius:
                                        MovieRedesignPalette.borderRadius,
                                    child: InkWell(
                                      borderRadius:
                                          MovieRedesignPalette.borderRadius,
                                      onTap: () {
                                        widget.onClose();
                                        context.push('/video/${item.id}/play');
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 10,
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            const Icon(
                                              Icons.play_arrow_rounded,
                                              size: 14,
                                              color: Colors.white,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              l10n.videoRedesignPlayNow,
                                              style: text.body(
                                                size: 14,
                                                weight: FontWeight.w500,
                                                color: palette.onPrimary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                _SubtitleSection(
                                  item: item,
                                  uploading: _uploading,
                                  onUpload: _pickAndUploadSubtitle,
                                ),
                                const SizedBox(height: 20),
                                _VersionsSection(item: item),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUploadSubtitle() async {
    final l10n = AppLocalizations.of(context);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['vtt', 'srt', 'ass', 'ssa', 'ttml', 'sub'],
      withData: true,
    );
    final file = result?.files.singleOrNull;
    if (file == null || file.bytes == null || !mounted) {
      return;
    }
    final language = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _SubtitleUploadModal(fileName: file.name),
    );
    if (language == null || language.isEmpty || !mounted) {
      return;
    }
    setState(() => _uploading = true);
    try {
      await ref
          .read(movieCenterControllerProvider.notifier)
          .uploadSubtitle(
            videoItemId: widget.item.id,
            fileName: file.name,
            bytes: file.bytes!,
            mimeType: _subtitleMime(file.extension),
            language: language,
          );
      if (!mounted) {
        return;
      }
      ref.invalidate(movieSubtitlesProvider(widget.item.id));
      showMovieFeedback(context, l10n.videoSubtitleUploaded);
    } catch (error) {
      if (!mounted) {
        return;
      }
      showMovieFeedback(context, movieErrorMessage(error), isError: true);
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  String _subtitleMime(String? ext) {
    return switch (ext?.toLowerCase()) {
      'vtt' => 'text/vtt',
      'srt' => 'application/x-subrip',
      'ttml' => 'application/ttml+xml',
      _ => 'text/plain',
    };
  }
}

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({required this.item, required this.onClose});

  final MovieVideoItem item;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final palette = context.movieRedesign;
    final text = context.movieRedesignText;
    // 对应原型 h-48 sm:h-56。
    final wide = MediaQuery.sizeOf(context).width >= 640;
    final headerHeight = wide ? 224.0 : 192.0;
    final coverUrl = item.backdropImageUrl ?? item.posterImageUrl;
    final originalTitle =
        (item.originalTitle?.trim().isNotEmpty ?? false)
            ? item.originalTitle
            : null;
    return SizedBox(
      height: headerHeight,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (coverUrl != null)
            Image.network(
              coverUrl,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              filterQuality: FilterQuality.medium,
              errorBuilder:
                  (context, error, stackTrace) =>
                      ColoredBox(color: palette.muted),
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) {
                  return child;
                }
                return ColoredBox(color: palette.muted);
              },
            )
          else
            ColoredBox(color: palette.muted),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.30, 1.0],
                colors: [Colors.transparent, palette.background],
              ),
            ),
          ),
          Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Material(
                color: Colors.black.withValues(alpha: 0.40),
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: onClose,
                  customBorder: const CircleBorder(),
                  child: const SizedBox(
                    width: 32,
                    height: 32,
                    child: Icon(
                      Icons.arrow_back_rounded,
                      size: 15,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: text.display(size: 24, height: 1.1),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (originalTitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      originalTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.body(
                        size: 14,
                        color: palette.mutedForeground,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.item});

  final MovieVideoItem item;

  @override
  Widget build(BuildContext context) {
    final text = context.movieRedesignText;
    final genres = item.genres.where((g) => g.trim().isNotEmpty).toList();
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (item.rating != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.star, size: 12, color: MovieRedesignPalette.star),
              const SizedBox(width: 4),
              Text(
                item.rating!.toStringAsFixed(1),
                style: text.body(
                  size: 14,
                  weight: FontWeight.w500,
                  color: MovieRedesignPalette.star,
                ),
              ),
            ],
          ),
        Text(item.year, style: text.mono(size: 12)),
        if (item.runtimeSeconds != null && item.runtimeSeconds! > 0)
          Text(item.runtimeText, style: text.mono(size: 12)),
        if (genres.isNotEmpty)
          Text(genres.take(2).join(' / '), style: text.mono(size: 12)),
        MovieRedesignStatusLabel(
          status: movieRedesignStatusFrom(item.metadataStatus),
        ),
      ],
    );
  }
}

class _SubtitleSection extends ConsumerWidget {
  const _SubtitleSection({
    required this.item,
    required this.uploading,
    required this.onUpload,
  });

  final MovieVideoItem item;
  final bool uploading;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.movieRedesign;
    final text = context.movieRedesignText;
    final l10n = AppLocalizations.of(context);
    final tracksAsync = ref.watch(movieSubtitlesProvider(item.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${l10n.videoSubtitle} ${l10n.videoRedesignSubtitlesEn}',
                style: text.body(size: 12, weight: FontWeight.w500),
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: uploading ? null : onUpload,
                borderRadius: MovieRedesignPalette.borderRadius,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.upload_rounded,
                        size: 11,
                        color: palette.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        l10n.videoRedesignUploadSubtitle,
                        style: text.mono(size: 10, color: palette.primary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        tracksAsync.when(
          loading:
              () => _FrameBox(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('…', style: text.mono(size: 12)),
                ),
              ),
          error:
              (error, _) => _FrameBox(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    l10n.videoLoadFailedWith(movieErrorMessage(error)),
                    style: text.mono(size: 12),
                  ),
                ),
              ),
          data: (tracks) {
            if (tracks.isEmpty) {
              return _FrameBox(
                dashed: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.videoRedesignNoSubtitles,
                          style: text.mono(size: 12),
                        ),
                        const SizedBox(height: 8),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: uploading ? null : onUpload,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              child: Text(
                                l10n.videoRedesignUploadSubtitle,
                                style: text.mono(
                                  size: 12,
                                  color: palette.primary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }
            return _FrameBox(
              child: Column(
                children: [
                  for (var i = 0; i < tracks.length; i++) ...[
                    if (i > 0)
                      Divider(height: 1, thickness: 1, color: palette.border),
                    _SubtitleRow(track: tracks[i]),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _SubtitleRow extends StatelessWidget {
  const _SubtitleRow({required this.track});

  final SubtitleTrack track;

  @override
  Widget build(BuildContext context) {
    final palette = context.movieRedesign;
    final text = context.movieRedesignText;
    final l10n = AppLocalizations.of(context);
    final format = _formatOf(track.url);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.body(size: 12, weight: FontWeight.w500),
                ),
                Text(track.language, style: text.mono(size: 10)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              borderRadius: MovieRedesignPalette.borderRadius,
              border: Border.all(
                color:
                    track.embedded
                        ? MovieRedesignPalette.subtitleEmbedded.withValues(
                          alpha: 0.30,
                        )
                        : palette.border,
              ),
              color:
                  track.embedded
                      ? MovieRedesignPalette.subtitleEmbedded.withValues(
                        alpha: 0.10,
                      )
                      : Colors.transparent,
            ),
            child: Text(
              track.embedded
                  ? l10n.videoRedesignSubtitleEmbedded
                  : l10n.videoRedesignSubtitleExternal,
              style: text.mono(
                size: 10,
                color:
                    track.embedded
                        ? MovieRedesignPalette.subtitleEmbedded
                        : palette.mutedForeground,
              ),
            ),
          ),
          if (format != null) ...[
            const SizedBox(width: 8),
            Text(format, style: text.mono(size: 10)),
          ],
        ],
      ),
    );
  }

  String? _formatOf(String? url) {
    if (url == null) {
      return null;
    }
    final match = RegExp(
      r'\.(vtt|srt|ass|ssa|ttml|sub)(?:\?|$)',
    ).firstMatch(url);
    return match?.group(1)?.toUpperCase();
  }
}

class _VersionsSection extends ConsumerWidget {
  const _VersionsSection({required this.item});

  final MovieVideoItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = context.movieRedesignText;
    final l10n = AppLocalizations.of(context);
    final versionsAsync = ref.watch(movieVersionsProvider(item.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${l10n.videoRedesignVersions} ${l10n.videoRedesignVersionsEn}',
          style: text.body(size: 12, weight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        _FrameBox(
          child: Column(
            children: [
              _VersionRow(
                label: l10n.videoRedesignOriginalVersion,
                detail: _codecResolution(
                  item.videoCodec,
                  item.resolutionHeight,
                ),
              ),
              versionsAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
                data:
                    (versions) => Column(
                      children: [
                        for (final version in versions)
                          _VersionRow(
                            label: version.versionLabel ?? 'H.265',
                            detail: _codecResolution(
                              version.videoCodec,
                              version.resolutionHeight,
                            ),
                          ),
                      ],
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _codecResolution(String? codec, int? height) {
    final parts = [
      if (codec != null && codec.trim().isNotEmpty) codec.trim().toUpperCase(),
      if (height != null && height > 0) '${height}p',
    ];
    return parts.join(' ');
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({required this.label, required this.detail});

  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final palette = context.movieRedesign;
    final text = context.movieRedesignText;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.body(size: 12),
            ),
          ),
          const SizedBox(width: 8),
          if (detail.isNotEmpty)
            Text(
              detail,
              style: text.mono(size: 10, color: palette.mutedForeground),
            ),
        ],
      ),
    );
  }
}

class _FrameBox extends StatelessWidget {
  const _FrameBox({required this.child, this.dashed = false});

  final Widget child;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final palette = context.movieRedesign;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: MovieRedesignPalette.borderRadius,
        border: Border.all(color: palette.border),
      ),
      child: child,
    );
  }
}

/// 字幕上传弹窗：文件已选定后选择语言并确认。
class _SubtitleUploadModal extends StatefulWidget {
  const _SubtitleUploadModal({required this.fileName});

  final String fileName;

  @override
  State<_SubtitleUploadModal> createState() => _SubtitleUploadModalState();
}

class _SubtitleUploadModalState extends State<_SubtitleUploadModal> {
  String _language = 'zh';

  static const _languageOptions = [
    ('zh', '中文 Chinese'),
    ('en', 'English'),
    ('ja', '日本語 Japanese'),
    ('ko', '한국어 Korean'),
    ('und', 'Undetermined'),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.movieRedesign;
    final text = context.movieRedesignText;
    final l10n = AppLocalizations.of(context);
    return Dialog(
      backgroundColor: palette.card,
      shape: RoundedRectangleBorder(
        borderRadius: MovieRedesignPalette.borderRadius,
        side: BorderSide(color: palette.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 384),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.videoRedesignUploadSubtitle,
                      style: text.display(size: 18),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: palette.mutedForeground,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: MovieRedesignPalette.borderRadius,
                  border: Border.all(color: palette.border),
                ),
                child: Text(
                  widget.fileName,
                  style: text.mono(size: 12, color: palette.foreground),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 16),
              Text(l10n.videoRedesignLanguage, style: text.mono(size: 10)),
              const SizedBox(height: 4),
              Container(
                decoration: BoxDecoration(
                  borderRadius: MovieRedesignPalette.borderRadius,
                  border: Border.all(color: palette.border),
                  color: palette.muted,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _language,
                    isExpanded: true,
                    borderRadius: MovieRedesignPalette.borderRadius,
                    dropdownColor: palette.card,
                    style: text
                        .body(size: 14, color: palette.foreground)
                        .copyWith(decoration: TextDecoration.none),
                    items: [
                      for (final (value, label) in _languageOptions)
                        DropdownMenuItem(
                          value: value,
                          child: Text(label, style: text.mono(size: 12)),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() => _language = value);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: Material(
                  color: palette.primary,
                  borderRadius: MovieRedesignPalette.borderRadius,
                  child: InkWell(
                    onTap: () => Navigator.of(context).pop(_language),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Center(
                        child: Text(
                          l10n.videoRedesignConfirmUpload,
                          style: text.body(
                            size: 14,
                            weight: FontWeight.w500,
                            color: palette.onPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
