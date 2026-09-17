part of 'movie_management.dart';

/// 影片管理工作区：序号列表、状态筛选、行内操作与任务进度弹窗。
class MovieAdminSection extends ConsumerStatefulWidget {
  const MovieAdminSection({super.key});

  @override
  ConsumerState<MovieAdminSection> createState() => _MovieAdminSectionState();
}

class _MovieAdminSectionState extends ConsumerState<MovieAdminSection> {
  static const int _pageSize = 20;

  int _page = 0;
  String? _runningAction;

  MovieCenterController get _controller =>
      ref.read(movieCenterControllerProvider.notifier);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(movieCenterControllerProvider).asData?.value;
    if (state == null) {
      return const SizedBox.shrink();
    }
    final entries = _buildEntries(state.filteredMovies);
    final pageCount = (entries.length / _pageSize).ceil().clamp(1, 1 << 30);
    final safePage = _page.clamp(0, pageCount - 1);
    final pageEntries = entries
        .skip(safePage * _pageSize)
        .take(_pageSize)
        .toList(growable: false);
    final activeTaskCount =
        state.tasks
            .where(
              (task) =>
                  task.status.toUpperCase() == 'RUNNING' ||
                  task.status.toUpperCase() == 'QUEUED',
            )
            .length;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.only(top: 4),
          sliver: SliverToBoxAdapter(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: MovieRedesignSectionHeader(
                    title: l10n.videoSectionMovieAdmin,
                    subtitleEn: l10n.videoRedesignSubAdmin,
                    subtitle: l10n.videoMovieAdminSubtitle,
                  ),
                ),
                const SizedBox(width: 16),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _buildHeaderActions(context, l10n, activeTaskCount),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.zero,
          sliver: SliverToBoxAdapter(child: _buildStatCards(context, entries)),
        ),
        SliverPadding(
          padding: const EdgeInsets.only(top: 12),
          sliver: SliverToBoxAdapter(
            child: _buildFilterChips(context, l10n, state.filter),
          ),
        ),
        if (pageEntries.isEmpty)
          SliverPadding(
            padding: const EdgeInsets.only(top: 24),
            sliver: SliverToBoxAdapter(
              child: MovieRedesignEmptyState(
                icon: Icons.admin_panel_settings_outlined,
                title: l10n.videoMovieAdminEmpty,
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.only(top: 10),
            sliver: SliverList.builder(
              itemCount: pageEntries.length,
              itemBuilder: (context, index) {
                return _buildRow(
                  context,
                  l10n,
                  entry: pageEntries[index],
                  rowNumber: safePage * _pageSize + index + 1,
                );
              },
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 32),
          sliver: SliverToBoxAdapter(
            child: _buildPager(context, l10n, safePage, pageCount),
          ),
        ),
      ],
    );
  }

  /// 四张统计卡：总条目 / 已匹配 / 待刮削 / 失败。
  Widget _buildStatCards(BuildContext context, List<_AdminRowEntry> entries) {
    final palette = context.movieRedesign;
    final text = context.movieRedesignText;
    final l10n = AppLocalizations.of(context);
    String statusOf(_AdminRowEntry entry) =>
        entry.item.metadataStatus.toUpperCase();
    final matched = entries.where((e) => statusOf(e) == 'MATCHED').length;
    final pending =
        entries
            .where((e) => statusOf(e) != 'MATCHED' && statusOf(e) != 'FAILED')
            .length;
    final failed = entries.where((e) => statusOf(e) == 'FAILED').length;
    final stats = [
      (
        l10n.videoRedesignStatTotal,
        l10n.videoRedesignStatTotalEn,
        entries.length,
      ),
      (l10n.videoMatched, l10n.videoRedesignStatusMatched, matched),
      (l10n.videoPendingScrape, l10n.videoRedesignStatusPending, pending),
      (l10n.videoMatchFailed, l10n.videoRedesignStatusFailed, failed),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        // 原型 grid-cols-2 sm:grid-cols-4。
        final wide = constraints.maxWidth >= 640;
        final columns = wide ? 4 : 2;
        final gap = 10.0;
        final cardWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final (label, labelEn, value) in stats)
              SizedBox(
                width: cardWidth,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: palette.card,
                    borderRadius: MovieRedesignPalette.borderRadius,
                    border: Border.all(color: palette.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$value',
                        style: text.mono(
                          size: wide ? 24.0 : 20.0,
                          color: palette.foreground,
                          weight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        style: text.body(
                          size: AppTypography.bodyMedium,
                          color: palette.foreground,
                        ),
                      ),
                      // ignore: font_size_whitelist
                      Text(labelEn, style: text.mono(size: 10)),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildHeaderActions(
    BuildContext context,
    AppLocalizations l10n,
    int activeTaskCount,
  ) {
    final palette = context.movieRedesign;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _AdminTextAction(
          label: l10n.videoAdminLibrarySources,
          onTap: () => context.go('/admin/storage'),
        ),
        _AdminTextAction(
          label:
              activeTaskCount > 0
                  ? '${l10n.videoTaskProgressDialog} $activeTaskCount'
                  : l10n.videoTaskProgressDialog,
          onTap: _showTaskProgressDialog,
        ),
        IconButton(
          tooltip: l10n.videoRefreshTooltip,
          onPressed: () => _controller.refresh(),
          icon: Icon(
            Icons.refresh_rounded,
            size: 18,
            color: palette.mutedForeground,
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChips(
    BuildContext context,
    AppLocalizations l10n,
    MovieLibraryFilter currentFilter,
  ) {
    final chips = [
      MovieRedesignChip(
        value: MovieLibraryFilter.all.name,
        label: l10n.videoRedesignFilterAll,
      ),
      MovieRedesignChip(
        value: MovieLibraryFilter.matched.name,
        label: l10n.videoRedesignFilterMatched,
      ),
      MovieRedesignChip(
        value: MovieLibraryFilter.pending.name,
        label: l10n.videoRedesignFilterPending,
      ),
      MovieRedesignChip(
        value: MovieLibraryFilter.failed.name,
        label: l10n.videoRedesignFilterFailed,
      ),
    ];
    return MovieRedesignFilterSortBar(
      filters: chips,
      filterValue: currentFilter.name,
      onFilter: (value) {
        setState(() => _page = 0);
        _controller.setFilter(
          MovieLibraryFilter.values.firstWhere((f) => f.name == value),
        );
      },
    );
  }

  Widget _buildRow(
    BuildContext context,
    AppLocalizations l10n, {
    required _AdminRowEntry entry,
    required int rowNumber,
  }) {
    final palette = context.movieRedesign;
    final text = context.movieRedesignText;
    final item = entry.item;
    final categoryLabel =
        entry.episodeCount != null
            ? (entry.isAnime
                ? l10n.videoSectionAnime
                : l10n.videoSectionTvShows)
            : (item.mediaType == 'MOVIE'
                ? l10n.videoSectionMovies
                : item.mediaType);
    final displayTitle =
        entry.seriesTitle?.trim().isNotEmpty == true
            ? entry.seriesTitle!.trim()
            : item.title;
    final metaLine =
        entry.episodeCount != null
            ? '$categoryLabel · ${l10n.videoSeriesEpisodeCount(entry.episodeCount!)}'
            : '${item.mediaType == 'MOVIE' ? l10n.videoSectionMovies : item.mediaType} · ${item.year}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: MovieRedesignPalette.borderRadius,
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              '$rowNumber',
              key: ValueKey('admin-row-number-$rowNumber'),
              style: text.mono(size: AppTypography.bodySmall),
            ),
          ),
          _PosterThumb(item: item),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.body(
                    size: AppTypography.bodyLarge,
                    weight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  metaLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.mono(size: AppTypography.bodySmall),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _MetadataStatusPill(status: item.metadataStatus),
          const SizedBox(width: 8),
          _NfoStatusPill(status: item.nfoStatus),
          const SizedBox(width: 10),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => showMovieMetadataEditor(context, item),
              borderRadius: MovieRedesignPalette.borderRadius,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  l10n.videoEdit,
                  style: text.mono(
                    size: AppTypography.bodySmall,
                    color: palette.primary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _buildRowMenu(context, l10n, item),
        ],
      ),
    );
  }

  Widget _buildRowMenu(
    BuildContext context,
    AppLocalizations l10n,
    MovieVideoItem item,
  ) {
    final busy = _runningAction != null;
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_horiz_rounded,
        color: context.videoColors.onSurfaceVariant,
      ),
      onSelected: (action) {
        switch (action) {
          case 'scrape':
            _runAction('scrape', () => _controller.createScrapeTask(item));
          case 'parse':
            _runAction('parse', () => _controller.probeItem(item));
          case 'transcode':
            _runAction(
              'transcode',
              () => _controller.createTranscodeTask(item),
            );
          case 'audio':
            _runAction('audio', () => _controller.createAudioExtractTask(item));
          case 'nfo':
            unawaited(_showNfoPreview(context, item));
          case 'delete':
            unawaited(_confirmAndDeleteItem(context, l10n, item));
        }
      },
      itemBuilder:
          (context) => [
            _menuItem(
              value: 'scrape',
              icon: Icons.manage_search_rounded,
              label: l10n.videoMetadataScrape,
              enabled: !busy || _runningAction == 'scrape',
            ),
            _menuItem(
              value: 'parse',
              icon: Icons.travel_explore_rounded,
              label: l10n.videoParse,
              enabled: !busy || _runningAction == 'parse',
            ),
            _menuItem(
              value: 'nfo',
              icon: Icons.description_outlined,
              label: 'NFO',
              enabled: true,
            ),
            _menuItem(
              value: 'transcode',
              icon: Icons.video_settings_rounded,
              label: l10n.videoTranscode,
              enabled: !busy || _runningAction == 'transcode',
            ),
            _menuItem(
              value: 'audio',
              icon: Icons.audio_file_rounded,
              label: l10n.videoAudioExtract,
              enabled: !busy || _runningAction == 'audio',
            ),
            _menuItem(
              value: 'delete',
              icon: Icons.delete_outline_rounded,
              label: l10n.videoDelete,
              enabled: !busy,
            ),
          ],
    );
  }

  Future<void> _confirmAndDeleteItem(
    BuildContext context,
    AppLocalizations l10n,
    MovieVideoItem item,
  ) async {
    if (_runningAction != null) {
      return;
    }
    setState(() => _runningAction = 'delete');
    try {
      final deleted = await confirmAndRunFilePurge(
        context,
        resourceName: item.title,
        action: (cascade) => _controller.deleteItem(item, cascade: cascade),
      );
      if (!deleted || !mounted || !context.mounted) {
        return;
      }
      showMovieFeedback(context, l10n.videoMovedToRecycleBin);
    } catch (error) {
      if (!mounted || !context.mounted) {
        return;
      }
      showMovieFeedback(context, movieErrorMessage(error), isError: true);
    } finally {
      if (mounted) {
        setState(() => _runningAction = null);
      }
    }
  }

  PopupMenuItem<String> _menuItem({
    required String value,
    required IconData icon,
    required String label,
    required bool enabled,
  }) {
    return PopupMenuItem<String>(
      value: value,
      enabled: enabled,
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 10),
          Text(label),
        ],
      ),
    );
  }

  Widget _buildPager(
    BuildContext context,
    AppLocalizations l10n,
    int safePage,
    int pageCount,
  ) {
    if (pageCount <= 1) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: l10n.videoPreviousPage,
          onPressed:
              safePage > 0 ? () => setState(() => _page = safePage - 1) : null,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        const SizedBox(width: 8),
        Text(
          '${safePage + 1} / $pageCount',
          style: context.movieRedesignText.mono(
            size: 12,
            color: context.movieRedesign.foreground,
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: l10n.videoNextPage,
          onPressed:
              safePage < pageCount - 1
                  ? () => setState(() => _page = safePage + 1)
                  : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }

  List<_AdminRowEntry> _buildEntries(List<MovieVideoItem> items) {
    final state = ref.read(movieCenterControllerProvider).asData?.value;
    final seriesById = <String, MovieSeries>{
      for (final series in [...?state?.tvSeries, ...?state?.animeSeries])
        series.id: series,
    };
    final seriesMap = <String, List<MovieVideoItem>>{};
    final standalone = <MovieVideoItem>[];
    for (final item in items) {
      final seriesId = item.seriesId;
      if (seriesId != null && seriesId.isNotEmpty) {
        seriesMap.putIfAbsent(seriesId, () => []).add(item);
      } else {
        standalone.add(item);
      }
    }
    MovieVideoItem pickRepresentative(List<MovieVideoItem> episodes) {
      // 代表集：优先展示有进度的分集，其次第一集，避免总落在第 1 集之外。
      final withProgress = episodes.where((e) => e.metadataStatus != 'MATCHED');
      return withProgress.isNotEmpty ? withProgress.first : episodes.first;
    }

    return <_AdminRowEntry>[
      for (final entry in seriesMap.entries)
        () {
          final series = seriesById[entry.key];
          final episodes = entry.value;
          episodes.sort((a, b) {
            final aNum = a.episodeNumber ?? 0;
            final bNum = b.episodeNumber ?? 0;
            return aNum.compareTo(bNum);
          });
          return _AdminRowEntry(
            item: pickRepresentative(episodes),
            episodeCount: episodes.length,
            seriesTitle: series?.title,
            isAnime: series?.seriesType == 'ANIME',
          );
        }(),
      for (final item in standalone) _AdminRowEntry(item: item),
    ];
  }

  Future<void> _runAction(
    String actionId,
    Future<void> Function() action,
  ) async {
    if (_runningAction != null) {
      return;
    }
    setState(() => _runningAction = actionId);
    try {
      await action();
      if (mounted) {
        _showSubmittedFeedback();
      }
    } catch (error) {
      if (mounted) {
        showMovieFeedback(context, movieErrorMessage(error), isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _runningAction = null);
      }
    }
  }

  void _showSubmittedFeedback() {
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.videoTaskSubmitted),
          action: SnackBarAction(
            label: l10n.videoSnackViewProgress,
            onPressed: _showTaskProgressDialog,
          ),
        ),
      );
  }

  void _showTaskProgressDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => const _MovieAdminTaskDialog(),
    );
  }
}

class _AdminRowEntry {
  const _AdminRowEntry({
    required this.item,
    this.episodeCount,
    this.seriesTitle,
    this.isAnime = false,
  });

  final MovieVideoItem item;
  final int? episodeCount;

  /// 多集分组行的系列名与动漫归类（单文件条目为空）。
  final String? seriesTitle;
  final bool isAnime;
}

class _PosterThumb extends StatelessWidget {
  const _PosterThumb({required this.item});

  final MovieVideoItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 62,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: MovieRedesignPalette.borderRadius,
        color: context.movieRedesign.muted,
        border: Border.all(color: context.movieRedesign.border),
      ),
      child:
          item.posterImageUrl != null
              ? MoviePosterImage(
                imageUrl: item.posterImageUrl,
                cacheWidth: MoviePosterImage.decodeWidth(context, 44, cap: 176),
                fallback: Icon(
                  Icons.movie_rounded,
                  size: 18,
                  color: context.movieRedesign.mutedForeground,
                ),
              )
              : Icon(
                Icons.movie_rounded,
                size: 18,
                color: context.movieRedesign.mutedForeground,
              ),
    );
  }
}

class _MetadataStatusPill extends StatelessWidget {
  const _MetadataStatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = switch (status) {
      'MATCHED' => l10n.videoMatched,
      'PENDING' => l10n.videoPendingScrape,
      'FAILED' => l10n.videoMatchFailed,
      'MANUAL' => l10n.videoManualEdit,
      _ => status,
    };
    final color = switch (status) {
      'MATCHED' => Colors.green.shade600,
      'PENDING' => Colors.amber.shade700,
      'FAILED' => Theme.of(context).colorScheme.error,
      _ => context.videoColors.onSurfaceVariant,
    };
    return _StatusPill(label: label, color: color);
  }
}

class _NfoStatusPill extends StatelessWidget {
  const _NfoStatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color =
        status.toUpperCase() == 'NONE'
            ? context.videoColors.onSurfaceVariant
            : context.videoColors.primary;
    return _StatusPill(label: 'NFO · $status', color: color);
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: MovieRedesignPalette.borderRadius,
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Text(
        label,
        // ignore: font_size_whitelist
        style: context.movieRedesignText.mono(size: 10, color: color),
      ),
    );
  }
}

/// 管理区头部单行文字动作（等宽样式，替代旧版实底按钮）。
class _AdminTextAction extends StatelessWidget {
  const _AdminTextAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.movieRedesign;
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: MovieRedesignPalette.borderRadius,
        side: BorderSide(color: palette.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: MovieRedesignPalette.borderRadius,
        hoverColor: palette.foreground.withValues(alpha: 0.06),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            label,
            style: context.movieRedesignText.mono(
              size: 12,
              color: palette.foreground,
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _showNfoPreview(BuildContext context, MovieVideoItem item) async {
  final container = ProviderScope.containerOf(context);
  final nfoAsync = container.read(movieNfoPreviewProvider(item.id));
  await showDialog<void>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          backgroundColor: context.videoColors.surfaceContainerHigh,
          title: Text(
            AppLocalizations.of(context).videoNfoPreviewTitle(item.title),
          ),
          content: SizedBox(
            width: 600,
            height: 500,
            child: nfoAsync.when(
              data:
                  (nfo) => SingleChildScrollView(
                    child: SelectableText(
                      nfo.content,
                      style: TextStyle(
                        fontFamily: AppTypography.monoFamily,
                        fontFamilyFallback: AppTypography.monoFamilyFallback,
                        fontSize: AppTypography.bodySmall,
                        color: context.videoColors.onSurface,
                      ),
                    ),
                  ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error:
                  (e, _) => Center(
                    child: Text(
                      AppLocalizations.of(
                        context,
                      ).videoLoadFailedWith(e.toString()),
                    ),
                  ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(AppLocalizations.of(context).videoClose),
            ),
          ],
        ),
  );
}
