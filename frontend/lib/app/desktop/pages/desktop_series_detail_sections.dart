part of 'desktop_series_detail_page.dart';

class _SeriesMetaStrip extends StatelessWidget {
  const _SeriesMetaStrip({required this.series, required this.seasons});

  final MovieSeries series;
  final List<MovieSeason> seasons;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final episodeCount = seasons.fold<int>(
      0,
      (sum, season) => sum + (season.episodeCount ?? 0),
    );
    final hasEpisodeCount = seasons.any(
      (season) => season.episodeCount != null,
    );
    final cells = <(String, String, String)>[
      (l10n.videoRating, series.rating?.toStringAsFixed(1) ?? '—', 'TMDB'),
      (
        l10n.videoYear,
        series.firstAirDate?.year.toString() ?? '—',
        series.seriesType,
      ),
      (
        l10n.desktopSeriesEpisodes,
        hasEpisodeCount ? '$episodeCount' : '—',
        l10n.desktopSeriesSeasonCount(seasons.length),
      ),
      (
        l10n.videoGenre,
        series.genres.isEmpty ? '—' : series.genres.take(2).join(' · '),
        '',
      ),
      (
        l10n.videoContentRating,
        series.contentRating?.isNotEmpty == true ? series.contentRating! : '—',
        '',
      ),
    ];
    return Container(
      decoration: BoxDecoration(
        color: skin.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: skin.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          for (var index = 0; index < cells.length; index++)
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  border:
                      index == 0
                          ? null
                          : Border(left: BorderSide(color: skin.line)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      cells[index].$1.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesktopType.eyebrow(skin.text3),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      cells[index].$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesktopType.sectionTitle(
                        skin.text,
                      ).copyWith(letterSpacing: -24 * 0.01),
                    ),
                    if (cells[index].$3.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        cells[index].$3,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DesktopType.caption(skin.text3),
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

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.detail});

  final MovieSeriesDetail detail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final series = detail.series;
    final synopsis =
        series.overview?.trim().isNotEmpty == true
            ? series.overview!
            : l10n.desktopMoviesNoMetadataHint;
    final credits = <Widget>[
      for (final person in detail.cast.take(12))
        _PersonTile(
          name: person.name,
          role: person.character ?? l10n.videoCast,
          image: person.profilePath,
        ),
      for (final person in detail.crew.take(8))
        _PersonTile(
          name: person.name,
          role: person.job ?? l10n.videoCrew,
          image: person.profilePath,
        ),
    ];
    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.videoOverview.toUpperCase(),
          style: DesktopType.eyebrow(skin.text3),
        ),
        const SizedBox(height: 8),
        _SeriesSynopsis(text: synopsis),
        if (credits.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            l10n.desktopMoviesCastCrew,
            style: DesktopType.sectionTitle(skin.text),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 12, children: credits),
        ],
        if (detail.writable) ...[
          const SizedBox(height: 22),
          _SeriesOverviewActions(series: series, cast: detail.cast),
        ],
      ],
    );
    final right = _SeriesFactsCard(series: series, seasons: detail.seasons);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [left, const SizedBox(height: 20), right],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 13, child: left),
            const SizedBox(width: 40),
            Expanded(
              flex: 10,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 280),
                child: right,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 样例 `.bp-about.clamp`：三行折叠 + accent 链接。
class _SeriesSynopsis extends StatefulWidget {
  const _SeriesSynopsis({required this.text});

  final String text;

  @override
  State<_SeriesSynopsis> createState() => _SeriesSynopsisState();
}

class _SeriesSynopsisState extends State<_SeriesSynopsis> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final style = DesktopType.body(skin.text2).copyWith(height: 1.65);
          final painter = TextPainter(
            text: TextSpan(text: widget.text, style: style),
            maxLines: 3,
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout(maxWidth: constraints.maxWidth);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.text,
                maxLines: _expanded ? null : 3,
                overflow:
                    _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                style: style,
              ),
              if (painter.didExceedMaxLines) ...[
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
    );
  }
}

class _SeriesFactsCard extends StatelessWidget {
  const _SeriesFactsCard({required this.series, required this.seasons});

  final MovieSeries series;
  final List<MovieSeason> seasons;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: skin.panel,
        border: Border.all(color: skin.line),
        borderRadius: BorderRadius.circular(DesktopMetrics.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.videoHeroInfo.toUpperCase(),
            style: DesktopType.eyebrow(skin.text3),
          ),
          const SizedBox(height: 12),
          DesktopKeyValues(
            entries: [
              MapEntry(l10n.videoType, series.seriesType),
              MapEntry(
                l10n.videoYear,
                series.firstAirDate?.year.toString() ?? '—',
              ),
              MapEntry(l10n.desktopSeriesSeasonCountLabel, '${seasons.length}'),
              if (series.contentRating?.isNotEmpty == true)
                MapEntry(l10n.videoContentRating, series.contentRating!),
              MapEntry(l10n.videoScrapeStatus, series.metadataStatus),
            ],
          ),
        ],
      ),
    );
  }
}

class _SeriesOverviewActions extends StatelessWidget {
  const _SeriesOverviewActions({required this.series, required this.cast});

  final MovieSeries series;
  final List<MovieCastMember> cast;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        DesktopButton(
          label: l10n.desktopMoviesEditDetails,
          icon: DesktopIcons.edit,
          variant: DesktopButtonVariant.soft,
          onPressed: () {
            unawaited(
              showDesktopDrawer<void>(
                context,
                width: 520,
                barrierDismissible: false,
                builder: (_) => _SeriesEditDialog(series: series, cast: cast),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _SeriesEditDialog extends ConsumerStatefulWidget {
  const _SeriesEditDialog({required this.series, required this.cast});

  final MovieSeries series;
  final List<MovieCastMember> cast;

  @override
  ConsumerState<_SeriesEditDialog> createState() => _SeriesEditDialogState();
}

/// 样例 `FilmEditor` 的剧集分支：统一封面控件 + 标题/类型/年份/时长/评分/
/// 演员/简介 + 恢复原始元数据，字段与影片共用一套排版。
class _SeriesEditDialogState extends ConsumerState<_SeriesEditDialog> {
  late final TextEditingController _title = TextEditingController(
    text: widget.series.title,
  );
  late final TextEditingController _genre = TextEditingController(
    text: widget.series.genres.join(', '),
  );
  late final TextEditingController _year = TextEditingController(
    text: widget.series.firstAirDate?.year.toString() ?? '',
  );
  late final TextEditingController _runtime = TextEditingController(
    text: (widget.series.metadata['manualRuntime'] ?? '').toString(),
  );
  late final TextEditingController _rating = TextEditingController(
    text: widget.series.rating?.toStringAsFixed(1) ?? '',
  );
  late final TextEditingController _cast = TextEditingController(
    text: widget.cast.map((member) => member.name).join(', '),
  );
  late final TextEditingController _posterUrl = TextEditingController(
    text: _initialExternalPosterUrl(widget.series),
  );
  late final String _initialPosterUrl = _posterUrl.text;
  late final TextEditingController _overview = TextEditingController(
    text: widget.series.overview ?? '',
  );
  DesktopPickedCover? _pickedPoster;
  bool _clearPoster = false;
  bool _saving = false;
  String? _titleError;
  String? _yearError;
  String? _ratingError;
  String? _posterUrlError;

  bool get _canRestoreOriginal =>
      widget.series.metadata['manualMetadataOriginal'] is Map;

  static String _initialExternalPosterUrl(MovieSeries series) {
    final manual = series.metadata['manualPosterUrl']?.toString().trim();
    if (manual != null && manual.isNotEmpty) {
      return manual;
    }
    final fallback = series.posterUrl?.trim();
    if (series.posterFileId == null &&
        fallback != null &&
        _isHttpUrl(fallback)) {
      return fallback;
    }
    return '';
  }

  static bool _isHttpUrl(String value) {
    if (value.length > 2048) return false;
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme.toLowerCase() == 'http' ||
            uri.scheme.toLowerCase() == 'https') &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
  }

  @override
  void dispose() {
    _title.dispose();
    _genre.dispose();
    _year.dispose();
    _runtime.dispose();
    _rating.dispose();
    _cast.dispose();
    _posterUrl.dispose();
    _overview.dispose();
    super.dispose();
  }

  List<String> _split(String value) => value
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final title = _title.text.trim();
    final yearText = _year.text.trim();
    final ratingText = _rating.text.trim();
    final posterUrl = _posterUrl.text.trim();
    final year = int.tryParse(yearText);
    final rating = double.tryParse(ratingText);
    setState(() {
      _titleError = title.isEmpty ? l10n.videoTitleRequired : null;
      _yearError =
          yearText.isNotEmpty &&
                  (!RegExp(r'^\d{4}$').hasMatch(yearText) || year == null)
              ? 'YYYY'
              : null;
      _ratingError =
          ratingText.isNotEmpty &&
                  (rating == null ||
                      !rating.isFinite ||
                      rating < 0 ||
                      rating > 10)
              ? '0.0 – 10.0'
              : null;
      _posterUrlError =
          _pickedPoster == null &&
                  !_clearPoster &&
                  posterUrl.isNotEmpty &&
                  !_isHttpUrl(posterUrl)
              ? l10n.videoMetaPosterUrlInvalid
              : null;
    });
    if (_titleError != null ||
        _yearError != null ||
        _ratingError != null ||
        _posterUrlError != null) {
      return;
    }
    setState(() => _saving = true);
    try {
      final posterUrlChanged = posterUrl != _initialPosterUrl.trim();
      await ref
          .read(movieCenterControllerProvider.notifier)
          .updateSeriesMetadata(
            seriesId: widget.series.id,
            title: title,
            overview: _overview.text.trim(),
            seriesType: widget.series.seriesType,
            firstAirDate:
                year == null ? null : DateTime(year, DateTime.january, 1),
            rating: rating,
            genres: _split(_genre.text),
            cast: _split(_cast.text),
            runtime: _runtime.text.trim(),
            posterUrl:
                !_clearPoster && _pickedPoster == null && posterUrlChanged
                    ? posterUrl
                    : null,
            posterBytes: _pickedPoster?.bytes,
            posterFileName: _pickedPoster?.fileName,
            clearPoster: _clearPoster && _pickedPoster == null,
          );
      if (!mounted) return;
      ref.invalidate(movieSeriesDetailProvider(widget.series.id));
      showDesktopToast(
        context,
        l10n.videoMetadataSaved,
        kind: DesktopToastKind.success,
        icon: DesktopIcons.check,
      );
      closeDesktopModal(context);
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.desktopMoviesEditDetails, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _restoreOriginal() async {
    if (_saving || !_canRestoreOriginal) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      await ref
          .read(movieCenterControllerProvider.notifier)
          .updateSeriesMetadata(
            seriesId: widget.series.id,
            title:
                _title.text.trim().isEmpty
                    ? widget.series.title
                    : _title.text.trim(),
            restoreOriginal: true,
          );
      if (!mounted) return;
      ref.invalidate(movieSeriesDetailProvider(widget.series.id));
      showDesktopToast(
        context,
        l10n.readerMetadataRestored,
        kind: DesktopToastKind.success,
        icon: DesktopIcons.undo,
      );
      closeDesktopModal(context);
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.desktopMoviesEditDetails, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    return DesktopDrawerFrame(
      eyebrow: l10n.videoMetaEyebrow,
      title: l10n.videoMetaEditDetails,
      footer: Row(
        children: [
          if (_canRestoreOriginal)
            DesktopButton(
              label: l10n.readerRestoreOriginalMetadata,
              icon: DesktopIcons.undo,
              onPressed: _saving ? null : () => unawaited(_restoreOriginal()),
            ),
          const Spacer(),
          DesktopButton(
            label: l10n.coreCancel,
            onPressed: _saving ? null : () => closeDesktopModal(context),
          ),
          const SizedBox(width: 10),
          DesktopButton(
            label: l10n.videoDetailSave,
            variant: DesktopButtonVariant.primary,
            busy: _saving,
            onPressed: _saving ? null : () => unawaited(_save()),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DesktopCoverField(
            label: l10n.videoMetaFieldPosterUrl,
            shape: DesktopCoverFieldShape.poster,
            previewUrl: widget.series.posterImageUrl,
            fallbackIcon: DesktopIcons.film,
            urlController: _posterUrl,
            pickedCover: _pickedPoster,
            cleared: _clearPoster,
            urlError: _posterUrlError,
            enabled: !_saving,
            onPicked: (picked) {
              setState(() {
                _pickedPoster = picked;
                _clearPoster = false;
                _posterUrlError = null;
              });
            },
            onClear: () {
              setState(() {
                _pickedPoster = null;
                _clearPoster = true;
                _posterUrlError = null;
              });
            },
            onUrlChanged: (_) {
              setState(() {
                _pickedPoster = null;
                _clearPoster = false;
                _posterUrlError = null;
              });
            },
          ),
          const SizedBox(height: 16),
          DesktopTextField(
            controller: _title,
            label: l10n.videoMetaFieldTitle,
            required: true,
            error: _titleError,
            autofocus: true,
            onChanged: (_) => setState(() => _titleError = null),
          ),
          const SizedBox(height: 14),
          DesktopTextField(
            controller: _genre,
            label: l10n.videoMetaFieldGenre,
            hint: l10n.videoMetaCommaSeparated,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                flex: 8,
                child: DesktopTextField(
                  controller: _year,
                  label: l10n.videoMetaFieldYear,
                  hint: '2024',
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  error: _yearError,
                  onChanged: (_) => setState(() => _yearError = null),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 14,
                child: DesktopTextField(
                  controller: _runtime,
                  label: l10n.videoMetaFieldRuntime,
                  hint: '48m',
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 8,
                child: DesktopTextField(
                  controller: _rating,
                  label: l10n.videoMetaFieldRating,
                  hint: '8.0',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  error: _ratingError,
                  onChanged: (_) => setState(() => _ratingError = null),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          DesktopTextField(
            controller: _cast,
            label: l10n.videoMetaFieldCast,
            hint: l10n.videoMetaCommaSeparated,
          ),
          const SizedBox(height: 14),
          DesktopTextField(
            controller: _overview,
            label: l10n.videoMetaFieldSynopsis,
            maxLines: 5,
            height: 124,
          ),
          const SizedBox(height: 14),
          Text(
            l10n.videoMetadataScopeNote,
            style: DesktopType.caption(skin.text3),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({required this.name, required this.role, this.image});

  final String name;
  final String role;
  final String? image;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return SizedBox(
      width: 220,
      child: Row(
        children: [
          ClipOval(
            child: SizedBox(
              width: 38,
              height: 38,
              child: DesktopCover(
                url: image,
                fallbackIcon: DesktopIcons.user,
                cacheKey: 'desktop-series-person:$image',
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesktopType.denseStrong(skin.text),
                ),
                Text(
                  role,
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

class _RelatedSeriesRail extends StatelessWidget {
  const _RelatedSeriesRail({required this.items});

  final List<MovieSeries> items;

  @override
  Widget build(BuildContext context) {
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
            for (final series in items)
              SizedBox(
                width: cardWidth,
                child: DesktopHoverLift(
                  onTap:
                      () => desktopPush(context, '/video/series/${series.id}'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AspectRatio(
                        aspectRatio: 2 / 3,
                        child: DesktopCover(
                          url: series.posterImageUrl,
                          fallbackIcon: DesktopIcons.film,
                          cacheKey: 'desktop-related-series:${series.id}',
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        series.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DesktopType.bodyStrong(
                          DesktopSkin.of(context).text,
                        ).copyWith(fontSize: DesktopType.sizeBodyPlus),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${series.year} · ${series.genres.take(1).join()}',
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
