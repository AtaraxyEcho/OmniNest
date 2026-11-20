part of 'desktop_movie_detail_page.dart';

enum _MovieDetailTab { overview, files, subtitles }

class _Overview extends StatefulWidget {
  const _Overview({required this.item});

  final MovieVideoItem item;

  @override
  State<_Overview> createState() => _OverviewState();
}

class _OverviewState extends State<_Overview> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final scraped = !_notScraped(item);
    final synopsis =
        item.overview?.trim().isNotEmpty == true
            ? item.overview!.trim()
            : (scraped
                ? l10n.desktopMoviesNoOverview
                : l10n.desktopMoviesNoMetadataHint);
    final screenWidth = MediaQuery.sizeOf(context).width;

    final overview = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.videoOverviewLabel.toUpperCase(),
          style: DesktopType.eyebrow(skin.text3),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final style = DesktopType.body(skin.text2).copyWith(height: 1.65);
              final painter = TextPainter(
                text: TextSpan(text: synopsis, style: style),
                maxLines: 3,
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout(maxWidth: constraints.maxWidth);
              // 只有三行确实被截断时才给展开入口；短简介多一个链接会
              // 让用户误以为还有隐藏内容。
              final canExpand = scraped && painter.didExceedMaxLines;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    synopsis,
                    maxLines: _expanded ? null : 3,
                    overflow:
                        _expanded
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                    style: style,
                  ),
                  if (canExpand) ...[
                    const SizedBox(height: 2),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => setState(() => _expanded = !_expanded),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          foregroundColor: skin.accent,
                        ),
                        child: Text(
                          _expanded
                              ? l10n.desktopMoviesShowLess
                              : l10n.desktopMoviesReadMore,
                          style: DesktopType.button(skin.accent),
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Text(
          l10n.desktopMoviesCastCrew.toUpperCase(),
          style: DesktopType.eyebrow(skin.text3),
        ),
        const SizedBox(height: 10),
        _CastAndCrew(item: item),
        const SizedBox(height: 18),
        DesktopMovieDetailActions(item: item),
      ],
    );

    if (screenWidth < 1180) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [overview, const SizedBox(height: 28), _SpecCard(item: item)],
      );
    }
    // 样例 `.bp-grid { grid-template-columns: minmax(0,1.3fr) minmax(280px,1fr); gap:40px }`。
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 13, child: overview),
        const SizedBox(width: 40),
        Expanded(
          flex: 10,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 280),
            child: _SpecCard(item: item),
          ),
        ),
      ],
    );
  }
}

class _CastAndCrew extends StatelessWidget {
  const _CastAndCrew({required this.item});

  final MovieVideoItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final crew = item.crewMembers;
    final director =
        crew.where((member) {
          final job = '${member.job} ${member.department}'.toLowerCase();
          return job.contains('director');
        }).firstOrNull;
    final writer =
        crew.where((member) {
          final job = '${member.job} ${member.department}'.toLowerCase();
          return job.contains('writer') || job.contains('screenplay');
        }).firstOrNull;
    final cards = <(String, String, bool)>[
      for (var index = 0; index < item.castMembers.length && index < 8; index++)
        (
          item.castMembers[index].name,
          item.castMembers[index].character?.trim().isNotEmpty == true
              ? item.castMembers[index].character!.trim()
              : (index == 0
                  ? l10n.desktopMoviesLead
                  : l10n.desktopMoviesCastMember),
          false,
        ),
      if (director != null && director.name.trim().isNotEmpty)
        (director.name, l10n.desktopMoviesDirector, true),
      if (writer != null && writer.name.trim().isNotEmpty)
        (writer.name, l10n.desktopMoviesWriter, true),
    ];
    if (cards.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          l10n.desktopMoviesNoCastCrew,
          style: DesktopType.caption(DesktopSkin.of(context).text3),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // 样例 `.cast-grid`：auto-fill minmax(210px,1fr)、gap 8。
        const gap = 8.0;
        const minimum = 210.0;
        final columns =
            math
                .max(
                  1,
                  ((constraints.maxWidth + gap) / (minimum + gap)).floor(),
                )
                .toInt();
        final cardWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards)
              SizedBox(
                width: cardWidth,
                height: 60,
                child: _CastCard(card: card),
              ),
          ],
        );
      },
    );
  }
}

class _CastCard extends StatelessWidget {
  const _CastCard({required this.card});

  final (String, String, bool) card;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: skin.raise,
        border: Border.all(color: skin.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color:
                  card.$3 ? skin.raise2 : skin.accent.withValues(alpha: 0.16),
            ),
            child: Text(
              _initials(card.$1),
              style: DesktopType.caption(card.$3 ? skin.text2 : skin.accent),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  card.$1,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesktopType.rowTitle(skin.text),
                ),
                Text(
                  card.$2,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesktopType.caption(skin.text3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty);
  final initials = parts.take(2).map((part) => part.characters.first).join();
  return initials.isEmpty ? '·' : initials.toUpperCase();
}

class _MovieFilesTab extends ConsumerWidget {
  const _MovieFilesTab({
    required this.videoItemId,
    required this.transcoding,
    required this.onTranscode,
  });

  final String videoItemId;
  final bool transcoding;
  final VoidCallback onTranscode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final files = ref.watch(movieItemFilesProvider(videoItemId));
    return files.when(
      loading:
          () => const SizedBox(
            height: 120,
            child: Center(
              child: SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
      error:
          (error, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                failureToast(l10n, l10n.desktopMoviesFileUnavailable, error),
                style: DesktopType.caption(skin.bad),
              ),
              const SizedBox(height: 10),
              DesktopButton(
                label: l10n.commonRetry,
                icon: DesktopIcons.retry,
                variant: DesktopButtonVariant.soft,
                onPressed:
                    () => ref.invalidate(movieItemFilesProvider(videoItemId)),
              ),
            ],
          ),
      data: (result) {
        if (result.files.isEmpty) {
          return DesktopEmpty(
            icon: DesktopIcons.folder,
            message: l10n.desktopSeriesFilesEmpty,
            actionLabel: null,
          );
        }
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < result.files.length; index++)
                _MovieFileRow(file: result.files[index], first: index == 0),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: skin.line)),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final switchControl =
                        result.transcodingEnabled
                            ? DesktopButton(
                              label: l10n.videoTranscode,
                              icon: DesktopIcons.film,
                              variant: DesktopButtonVariant.soft,
                              busy: transcoding,
                              onPressed: transcoding ? null : onTranscode,
                            )
                            : IgnorePointer(
                              child: DesktopToggle(
                                value: false,
                                onChanged: (_) {},
                                label: l10n.desktopMoviesTranscoding,
                              ),
                            );
                    final description = Text(
                      result.transcodingEnabled
                          ? l10n.desktopMoviesTranscodingEnabledDescription
                          : l10n.desktopMoviesTranscodingDisabledDescription,
                      style: DesktopType.caption(skin.text3),
                    );
                    if (constraints.maxWidth < 560) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.desktopMoviesTranscoding,
                            style: DesktopType.rowTitle(skin.text),
                          ),
                          const SizedBox(height: 4),
                          description,
                          const SizedBox(height: 12),
                          switchControl,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.desktopMoviesTranscoding,
                                style: DesktopType.rowTitle(skin.text),
                              ),
                              const SizedBox(height: 4),
                              description,
                            ],
                          ),
                        ),
                        const SizedBox(width: 20),
                        switchControl,
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MovieFileRow extends StatelessWidget {
  const _MovieFileRow({required this.file, required this.first});

  final MovieVideoFile file;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final resolution =
        file.resolutionWidth != null && file.resolutionHeight != null
            ? '${file.resolutionWidth}×${file.resolutionHeight}'
            : null;
    final details = <String>[
      file.primary
          ? l10n.desktopMoviesPrimaryFile
          : l10n.desktopMoviesAlternateFile,
      if ((file.videoCodec ?? '').trim().isNotEmpty) file.videoCodec!.trim(),
      if ((file.audioCodec ?? '').trim().isNotEmpty) file.audioCodec!.trim(),
      if (resolution != null) resolution,
      if ((file.containerFormat ?? '').trim().isNotEmpty)
        file.containerFormat!.trim(),
      if ((file.versionLabel ?? '').trim().isNotEmpty)
        file.versionLabel!.trim(),
      if ((file.videoCodec ?? '').trim().isEmpty &&
          (file.mimeType ?? '').trim().isNotEmpty)
        file.mimeType!.trim(),
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 4),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: skin.line, width: first ? 0 : 1)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final name = Text(
            file.fileName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DesktopType.rowTitle(skin.text),
          );
          final detail = Text(
            details,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DesktopType.caption(skin.text3),
          );
          final size = Text(
            formatFileSize(file.sizeBytes),
            style: DesktopType.dense(skin.text2),
          );
          if (constraints.maxWidth < 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                name,
                const SizedBox(height: 4),
                detail,
                const SizedBox(height: 6),
                size,
              ],
            );
          }
          return Row(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 170, maxWidth: 240),
                child: name,
              ),
              const SizedBox(width: 14),
              Expanded(child: detail),
              const SizedBox(width: 14),
              size,
              if (file.primary) ...[
                const SizedBox(width: 12),
                DesktopChip(l10n.desktopMoviesPrimaryFile),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _RelatedRail extends StatelessWidget {
  const _RelatedRail({required this.items});

  final List<MovieVideoItem> items;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final viewportWidth = MediaQuery.sizeOf(context).width;
    // 样例 `.poster-grid`：auto-fill minmax(clamp(190px,15vw,250px),1fr)、gap 22。
    const gap = 22.0;
    final minimum = (viewportWidth * 0.15).clamp(190.0, 250.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            math
                .max(
                  1,
                  ((constraints.maxWidth + gap) / (minimum + gap)).floor(),
                )
                .toInt();
        final cardWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final item in items)
              SizedBox(
                width: cardWidth,
                child: DesktopHoverLift(
                  onTap: () => desktopPush(context, '/video/${item.id}'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AspectRatio(
                        aspectRatio: 2 / 3,
                        child: DesktopImage(
                          url: item.posterUrl,
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DesktopType.bodyStrong(
                          DesktopSkin.of(context).text,
                        ).copyWith(fontSize: 13.5),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (item.releaseDate != null)
                            '${item.releaseDate!.year}',
                          if (item.genres.isNotEmpty) _kindLabel(item, l10n),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DesktopType.caption(
                          DesktopSkin.of(context).text3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SpecCard extends ConsumerWidget {
  const _SpecCard({required this.item});

  final MovieVideoItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final resolution =
        item.resolutionWidth != null && item.resolutionHeight != null
            ? '${item.resolutionWidth}×${item.resolutionHeight}'
            : null;
    final video = [
      if ((item.videoCodec ?? '').trim().isNotEmpty) item.videoCodec!.trim(),
      if (resolution != null) resolution,
      if ((item.containerFormat ?? '').trim().isNotEmpty)
        item.containerFormat!.trim(),
    ].join(' · ');
    final studio = (item.metadata['studio'] ?? '').toString().trim();
    final subtitles = ref.watch(movieSubtitlesProvider(item.id)).asData?.value;
    final rows = <(String, String)>[
      (l10n.videoStudio, studio.isEmpty ? '—' : studio),
      (l10n.desktopMoviesDetailLibrary, '/Library/Movies'),
      (l10n.desktopMoviesDetailVisibility, l10n.videoLibraryVisibilityMembers),
      (l10n.videoVideo, video.isEmpty ? '—' : video),
      (
        l10n.videoAudio,
        (item.audioCodec ?? '').trim().isEmpty ? '—' : item.audioCodec!.trim(),
      ),
      (l10n.videoSubtitles, subtitles == null ? '—' : '${subtitles.length}'),
      (
        l10n.readerDetailAdded,
        item.updatedAt == null ? '—' : _formatDate(item.updatedAt!),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.desktopBookDetails.toUpperCase(),
          style: DesktopType.eyebrow(skin.text3),
        ),
        const SizedBox(height: 16),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 140,
                  child: Text(row.$1, style: DesktopType.dense(skin.text3)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    row.$2,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: DesktopType.dense(skin.text),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

String _formatDate(DateTime value) {
  final local = value.toLocal();
  String two(int part) => part.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}
