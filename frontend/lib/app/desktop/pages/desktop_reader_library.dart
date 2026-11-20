part of 'desktop_reader_page.dart';

/// 书库视图（样例 `Reader.tsx` 的 Library）：搜索 + 标签 + 排序 + 网格/列表。
enum _ReaderSort { recent, title, author, progress, added }

enum _ReaderType { all, books, comics }

class _ReaderLibrary extends StatefulWidget {
  const _ReaderLibrary({
    required this.items,
    required this.loadingMore,
    required this.status,
    required this.onStatus,
    required this.onOpen,
    required this.onRead,
  });

  final List<ReaderItem> items;
  final bool loadingMore;
  final DesktopReaderFilter status;
  final ValueChanged<DesktopReaderFilter> onStatus;
  final ValueChanged<ReaderItem> onOpen;
  final ValueChanged<ReaderItem> onRead;

  @override
  State<_ReaderLibrary> createState() => _ReaderLibraryState();
}

class _ReaderLibraryState extends State<_ReaderLibrary> {
  final TextEditingController _search = TextEditingController();
  _ReaderSort _sort = _ReaderSort.recent;
  _ReaderType _type = _ReaderType.all;
  String? _genre;
  bool _grid = true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final needle = _search.text.trim().toLowerCase();
    final typedItems = widget.items
        .where((item) {
          final comic = item.isDisplayedAsComic;
          return switch (_type) {
            _ReaderType.all => true,
            _ReaderType.books => !comic,
            _ReaderType.comics => comic,
          };
        })
        .toList(growable: false);
    final genres =
        <String>{
            for (final item in typedItems)
              ...?item.genres?.where((genre) => genre.trim().isNotEmpty),
          }.toList()
          ..sort();

    final visible =
        typedItems.where((item) {
          final progress = item.progressPercent ?? 0;
          final matchesStatus = switch (widget.status) {
            DesktopReaderFilter.all => true,
            DesktopReaderFilter.inProgress => progress > 0 && progress < 90,
            DesktopReaderFilter.finished => progress >= 90,
            DesktopReaderFilter.unread => progress <= 0,
          };
          if (!matchesStatus) {
            return false;
          }
          if (_genre != null && !(item.genres ?? const []).contains(_genre)) {
            return false;
          }
          if (needle.isEmpty) {
            return true;
          }
          return '${item.title} ${item.authorName ?? ''} ${item.seriesName ?? ''} ${item.description ?? ''} ${(item.genres ?? const <String>[]).join(' ')}'
              .toLowerCase()
              .contains(needle);
        }).toList();

    visible.sort((a, b) {
      final result = switch (_sort) {
        _ReaderSort.recent => (b.updatedAt ?? DateTime(0)).compareTo(
          a.updatedAt ?? DateTime(0),
        ),
        _ReaderSort.title => a.title.toLowerCase().compareTo(
          b.title.toLowerCase(),
        ),
        _ReaderSort.author => (a.authorName ?? '').toLowerCase().compareTo(
          (b.authorName ?? '').toLowerCase(),
        ),
        _ReaderSort.progress => (b.progressPercent ?? 0).compareTo(
          a.progressPercent ?? 0,
        ),
        _ReaderSort.added => (b.createdAt ?? DateTime(0)).compareTo(
          a.createdAt ?? DateTime(0),
        ),
      };
      return result;
    });

    final sortLabels = <_ReaderSort, String>{
      _ReaderSort.recent: l10n.desktopReaderSortRecent,
      _ReaderSort.title: l10n.desktopSortTitle,
      _ReaderSort.author: l10n.desktopSortAuthor,
      _ReaderSort.progress: l10n.desktopSortProgress,
      _ReaderSort.added: l10n.desktopSortAdded,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            DesktopTextField(
              keyName: 'desktop-reader-search',
              controller: _search,
              hint: l10n.desktopReaderSearchHint,
              prefixIcon: DesktopIcons.search,
              width: 280,
              height: 36,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(width: 12),
            DesktopSeg<_ReaderType>(
              options: _ReaderType.values,
              value: _type,
              small: true,
              labelOf:
                  (value) => switch (value) {
                    _ReaderType.all => l10n.desktopFilterAll,
                    _ReaderType.books => l10n.readerSegmentBooks,
                    _ReaderType.comics => l10n.readerSegmentComics,
                  },
              onChanged:
                  (value) => setState(() {
                    _type = value;
                    _genre = null;
                  }),
            ),
            const Spacer(),
            DesktopIconButton(
              icon: DesktopIcons.grid,
              tooltip: l10n.desktopFilesGridView,
              active: _grid,
              onPressed: () => setState(() => _grid = true),
            ),
            DesktopIconButton(
              icon: DesktopIcons.list,
              tooltip: l10n.desktopFilesListView,
              active: !_grid,
              onPressed: () => setState(() => _grid = false),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final status in DesktopReaderFilter.values)
              DesktopChipButton(
                label: switch (status) {
                  DesktopReaderFilter.all => l10n.desktopFilterAll,
                  DesktopReaderFilter.inProgress =>
                    l10n.desktopFilterInProgress,
                  DesktopReaderFilter.finished => l10n.desktopFilterFinished,
                  DesktopReaderFilter.unread => l10n.desktopFilterUnread,
                },
                selected: widget.status == status,
                onTap: () => widget.onStatus(status),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            DesktopChipButton(
              label: l10n.desktopFilterAll,
              selected: _genre == null,
              onTap: () => setState(() => _genre = null),
            ),
            for (final genre in genres.take(10))
              DesktopChipButton(
                label: genre,
                selected: _genre == genre,
                onTap:
                    () =>
                        setState(() => _genre = _genre == genre ? null : genre),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(DesktopIcons.sort, size: 15, color: skin.text3),
            const SizedBox(width: 6),
            Text(
              l10n.desktopReaderSortLabel,
              style: DesktopType.caption(skin.text3),
            ),
            const SizedBox(width: 8),
            DesktopSelect<_ReaderSort>(
              value: _sort,
              width: 190,
              variant: DesktopSelectVariant.small,
              options: [
                for (final value in _ReaderSort.values)
                  DesktopSelectOption(
                    value: value,
                    label: sortLabels[value] ?? '',
                  ),
              ],
              onChanged: (value) => setState(() => _sort = value),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              l10n.desktopReaderTitleCount(visible.length),
              style: DesktopType.caption(skin.text3),
            ),
            const Spacer(),
            if (needle.isNotEmpty ||
                widget.status != DesktopReaderFilter.all ||
                _type != _ReaderType.all ||
                _genre != null)
              DesktopLink(
                label: l10n.desktopReaderClearFilters,
                trailing: false,
                onPressed:
                    () => setState(() {
                      _search.clear();
                      widget.onStatus(DesktopReaderFilter.all);
                      _type = _ReaderType.all;
                      _genre = null;
                    }),
              ),
          ],
        ),
        const SizedBox(height: 18),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 70),
            child: Center(
              child: Text(
                l10n.desktopReaderEmpty,
                style: DesktopType.medium(skin.text3),
              ),
            ),
          )
        else if (_grid)
          _Shelf(items: visible, onOpen: widget.onOpen)
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < visible.length; i++)
                DesktopStagger(
                  index: i,
                  child: _ReaderRow(
                    item: visible[i],
                    onTap: () => widget.onOpen(visible[i]),
                    onRead: () => widget.onRead(visible[i]),
                  ),
                ),
            ],
          ),
        if (widget.loadingMore)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
      ],
    );
  }
}

class _ReaderRow extends StatelessWidget {
  const _ReaderRow({
    required this.item,
    required this.onTap,
    required this.onRead,
  });

  final ReaderItem item;
  final VoidCallback onTap;
  final VoidCallback onRead;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final progress = (item.progressPercent ?? 0).clamp(0.0, 100.0);
    return DesktopHoverLift(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: skin.raise,
          borderRadius: BorderRadius.circular(DesktopMetrics.radiusSmall),
          border: Border.all(color: skin.line),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: DesktopReaderBookCover(
                  itemId: item.id,
                  title: item.title,
                  author: item.authorName ?? '',
                  coverUrl: item.coverUrl,
                  isComic: item.isDisplayedAsComic,
                  readerType: item.readerType,
                  volumeNumber: item.volumeNumber,
                  compact: true,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DesktopType.rowTitle(skin.text),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.authorName ?? item.itemType,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DesktopType.caption(skin.text3),
                  ),
                ],
              ),
            ),
            if (item.rating != null) ...[
              Icon(DesktopIcons.starFilled, size: 11, color: skin.warm),
              const SizedBox(width: 4),
              Text(
                item.rating!.toStringAsFixed(1),
                style: DesktopType.numeric(skin.text3),
              ),
              const SizedBox(width: 18),
            ],
            SizedBox(
              width: 140,
              child: DesktopProgress(fraction: progress / 100),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 44,
              child: Text(
                '${progress.round()}%',
                textAlign: TextAlign.right,
                style: DesktopType.numeric(skin.text3),
              ),
            ),
            const SizedBox(width: 14),
            DesktopButton(
              label:
                  progress > 0 && progress < 90
                      ? AppLocalizations.of(context).readerContinueReading
                      : AppLocalizations.of(context).readerStartReading,
              icon: DesktopIcons.book,
              variant: DesktopButtonVariant.soft,
              onPressed: onRead,
            ),
          ],
        ),
      ),
    );
  }
}
