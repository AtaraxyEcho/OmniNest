part of 'movie_detail_page.dart';

/// 影片详情页字幕页签、字幕语言对话框与演员头像。
class _SubtitlesTab extends ConsumerWidget {
  const _SubtitlesTab({
    required this.item,
    required this.uploading,
    required this.onUpload,
  });

  final MovieVideoItem item;
  final bool uploading;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tracksAsync = ref.watch(movieSubtitlesProvider(item.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: uploading ? null : onUpload,
              borderRadius: MovieRedesignPalette.borderRadius,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  borderRadius: MovieRedesignPalette.borderRadius,
                  border: Border.all(color: MovieDetailTheme.border),
                ),
                child: Text(
                  l10n.videoDetailUploadSubtitle,
                  style: MovieDetailTheme.mono(
                    12,
                    color:
                        uploading
                            ? MovieDetailTheme.mutedText
                            : MovieDetailTheme.secondaryText,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        tracksAsync.when(
          loading:
              () => const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          error:
              (error, _) => Text(
                movieErrorMessage(error),
                style: MovieDetailTheme.mono(AppTypography.bodySmall),
              ),
          data: (tracks) {
            if (tracks.isEmpty) {
              return Text(
                l10n.videoRedesignNoSubtitles,
                style: MovieDetailTheme.mono(AppTypography.bodySmall),
              );
            }
            return Column(
              children: [
                for (final track in tracks)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 1),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: MovieDetailTheme.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            track.label,
                            style: MovieDetailTheme.body(
                              14,
                              color: MovieDetailTheme.foreground,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          _formatOf(track.url) ?? '',
                          style: MovieDetailTheme.mono(AppTypography.bodySmall),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          track.embedded
                              ? l10n.videoRedesignSubtitleEmbedded
                              : l10n.videoRedesignSubtitleExternal,
                          style: MovieDetailTheme.mono(AppTypography.bodySmall),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  String? _formatOf(String? url) {
    if (url == null) {
      return null;
    }
    return RegExp(
      r'\.(vtt|srt|ass|ssa|ttml|sub)(?:\?|$)',
    ).firstMatch(url)?.group(1)?.toUpperCase();
  }
}

class _SubtitleLanguageDialog extends StatefulWidget {
  const _SubtitleLanguageDialog({required this.fileName});

  final String fileName;

  @override
  State<_SubtitleLanguageDialog> createState() =>
      _SubtitleLanguageDialogState();
}

class _SubtitleLanguageDialogState extends State<_SubtitleLanguageDialog> {
  String _language = 'zh';

  static const _languageCodes = ['zh', 'en', 'ja', 'ko', 'und'];

  String _languageLabel(AppLocalizations l10n, String code) {
    return switch (code) {
      'zh' => l10n.videoSubtitleLangZh,
      'en' => l10n.videoSubtitleLangEn,
      'ja' => l10n.videoSubtitleLangJa,
      'ko' => l10n.videoSubtitleLangKo,
      _ => l10n.videoSubtitleLangUnd,
    };
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.movieDetailPalette;
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
              Text(
                widget.fileName,
                style: MovieDetailTheme.mono(
                  AppTypography.bodySmall,
                  color: palette.foreground,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.videoRedesignLanguage,
                // ignore: font_size_whitelist
                style: MovieDetailTheme.mono(10),
              ),
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
                    items: [
                      for (final code in _languageCodes)
                        DropdownMenuItem(
                          value: code,
                          child: Text(
                            _languageLabel(l10n, code),
                            style: MovieDetailTheme.mono(
                              AppTypography.bodySmall,
                            ),
                          ),
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
                          style: MovieDetailTheme.body(
                            14,
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

/// CAST 头像：48px 圆形，刮削图缺失时回退姓名首字母。
class _CastAvatar extends StatelessWidget {
  const _CastAvatar({required this.name, this.profileUrl});

  final String name;
  final String? profileUrl;

  @override
  Widget build(BuildContext context) {
    final url = profileUrl;
    return Container(
      width: 48,
      height: 48,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: MovieDetailTheme.surface,
      ),
      child:
          url != null && url.isNotEmpty
              ? CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                memCacheWidth: 96,
                errorWidget:
                    (context, error, stackTrace) => _CastInitials(name: name),
              )
              : _CastInitials(name: name),
    );
  }
}

class _CastInitials extends StatelessWidget {
  const _CastInitials({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name.characters.first.toUpperCase() : '?';
    return Center(
      child: Text(
        initial,
        style: MovieDetailTheme.mono(
          AppTypography.titleMedium,
          color: MovieDetailTheme.accent,
        ),
      ),
    );
  }
}
