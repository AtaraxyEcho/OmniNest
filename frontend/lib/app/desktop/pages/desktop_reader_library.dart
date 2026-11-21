part of 'desktop_reader_page.dart';

/// 书库视图（样例 `Reader.tsx` 的 Library）：搜索 + 标签 + 排序 + 网格/列表。
enum _ReaderSort { recent, title, author, progress, added }

enum _ReaderType { all, books, comics }

class _ReaderLibraryQueryResult {
  const _ReaderLibraryQueryResult({
    required this.visible,
    required this.genres,
  });

  final List<ReaderItem> visible;
  final List<String> genres;
}

_ReaderLibraryQueryResult _buildReaderLibraryQuery({
  required List<ReaderItem> items,
  required String searchText,
  required DesktopReaderFilter status,
  required _ReaderType type,
  required String? genre,
  required _ReaderSort sort,
}) {
  final needle = searchText.trim().toLowerCase();
  final typedItems = items
      .where((item) {
        final comic = item.isDisplayedAsComic;
        return switch (type) {
          _ReaderType.all => true,
          _ReaderType.books => !comic,
          _ReaderType.comics => comic,
        };
      })
      .toList(growable: false);
  final genres =
      <String>{
          for (final item in typedItems)
            ...?item.genres?.where((g) => g.trim().isNotEmpty),
        }.toList()
        ..sort();

  final visible =
      typedItems.where((item) {
        final progress = item.progressPercent ?? 0;
        final matchesStatus = switch (status) {
          DesktopReaderFilter.all => true,
          DesktopReaderFilter.inProgress => progress > 0 && progress < 90,
          DesktopReaderFilter.finished => progress >= 90,
          DesktopReaderFilter.unread => progress <= 0,
        };
        if (!matchesStatus) {
          return false;
        }
        if (genre != null && !(item.genres ?? const []).contains(genre)) {
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
    return switch (sort) {
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
  });

  return _ReaderLibraryQueryResult(visible: visible, genres: genres);
}

/// 书库顶部吸顶筛选/排序/视图切换栏（样例 `Reader.tsx:153-165` 的 `<StickyBar>`）。
class _ReaderLibraryStickyBar extends StatelessWidget {
  const _ReaderLibraryStickyBar({
    required this.search,
    required this.type,
    required this.sort,
    required this.grid,
    required this.onSearchChanged,
    required this.onTypeChanged,
    required this.onSortChanged,
    required this.onGridChanged,
  });

  final TextEditingController search;
  final _ReaderType type;
  final _ReaderSort sort;
  final bool grid;
  final VoidCallback onSearchChanged;
  final ValueChanged<_ReaderType> onTypeChanged;
  final ValueChanged<_ReaderSort> onSortChanged;
  final ValueChanged<bool> onGridChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final sortLabels = <_ReaderSort, String>{
      _ReaderSort.recent: l10n.desktopReaderSortRecent,
      _ReaderSort.title: l10n.desktopSortTitle,
      _ReaderSort.author: l10n.desktopSortAuthor,
      _ReaderSort.progress: l10n.desktopSortProgress,
      _ReaderSort.added: l10n.desktopSortAdded,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: LayoutBuilder(
        builder: (context, barConstraints) {
          final searchField = DesktopTextField(
            keyName: 'desktop-reader-search',
            controller: search,
            hint: l10n.desktopReaderSearchHint,
            prefixIcon: DesktopIcons.search,
            width: barConstraints.maxWidth < 920 ? 220 : 280,
            height: 36,
            onChanged: (_) => onSearchChanged(),
          );
          final typeSeg = DesktopSeg<_ReaderType>(
            options: _ReaderType.values,
            value: type,
            small: true,
            labelOf:
                (value) => switch (value) {
                  _ReaderType.all => l10n.desktopFilterAll,
                  _ReaderType.books => l10n.readerSegmentBooks,
                  _ReaderType.comics => l10n.readerSegmentComics,
                },
            onChanged: onTypeChanged,
          );
          final sortGroup = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.desktopReaderSortLabel,
                style: DesktopType.caption(skin.text3),
              ),
              const SizedBox(width: 8),
              DesktopSelect<_ReaderSort>(
                value: sort,
                width: 148,
                variant: DesktopSelectVariant.small,
                options: [
                  for (final value in _ReaderSort.values)
                    DesktopSelectOption(
                      value: value,
                      label: sortLabels[value] ?? '',
                    ),
                ],
                onChanged: onSortChanged,
              ),
            ],
          );
          final viewToggle = _LibraryViewToggle(
            isGrid: grid,
            gridTooltip: l10n.desktopFilesGridView,
            listTooltip: l10n.desktopFilesListView,
            onChanged: onGridChanged,
          );
          if (barConstraints.maxWidth < 760) {
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [searchField, typeSeg, sortGroup, viewToggle],
            );
          }
          return Row(
            children: [
              searchField,
              const SizedBox(width: 12),
              typeSeg,
              const Spacer(),
              sortGroup,
              const SizedBox(width: 10),
              viewToggle,
            ],
          );
        },
      ),
    );
  }
}

class _ReaderLibraryBody extends StatelessWidget {
  const _ReaderLibraryBody({
    required this.query,
    required this.loadingMore,
    required this.status,
    required this.type,
    required this.genre,
    required this.grid,
    required this.hasSearchNeedle,
    required this.onStatus,
    required this.onGenre,
    required this.onClearFilters,
    required this.onOpen,
    required this.onRead,
  });

  final _ReaderLibraryQueryResult query;
  final bool loadingMore;
  final DesktopReaderFilter status;
  final _ReaderType type;
  final String? genre;
  final bool grid;
  final bool hasSearchNeedle;
  final ValueChanged<DesktopReaderFilter> onStatus;
  final ValueChanged<String?> onGenre;
  final VoidCallback onClearFilters;
  final ValueChanged<ReaderItem> onOpen;
  final ValueChanged<ReaderItem> onRead;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final visible = query.visible;
    final genres = query.genres;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final filterStatus in DesktopReaderFilter.values)
              DesktopChipButton(
                label: switch (filterStatus) {
                  DesktopReaderFilter.all => l10n.desktopFilterAll,
                  DesktopReaderFilter.inProgress =>
                    l10n.desktopFilterInProgress,
                  DesktopReaderFilter.finished => l10n.desktopFilterFinished,
                  DesktopReaderFilter.unread => l10n.desktopFilterUnread,
                },
                selected: status == filterStatus,
                onTap: () => onStatus(filterStatus),
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
              selected: genre == null,
              onTap: () => onGenre(null),
            ),
            for (final itemGenre in genres.take(10))
              DesktopChipButton(
                label: itemGenre,
                selected: genre == itemGenre,
                onTap: () => onGenre(genre == itemGenre ? null : itemGenre),
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
            if (hasSearchNeedle ||
                status != DesktopReaderFilter.all ||
                type != _ReaderType.all ||
                genre != null)
              DesktopLink(
                label: l10n.desktopReaderClearFilters,
                trailing: false,
                onPressed: onClearFilters,
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
        else if (grid)
          _Shelf(items: visible, onOpen: onOpen)
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < visible.length; i++)
                DesktopStagger(
                  index: i,
                  child: _ReaderRow(
                    item: visible[i],
                    onTap: () => onOpen(visible[i]),
                    onRead: () => onRead(visible[i]),
                  ),
                ),
            ],
          ),
        if (loadingMore)
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

/// 1:1 样例 `.vtoggle`（desktop.css:454）：3px 内距、10px 圆角、两个 30×28 紧凑视图按钮。
class _LibraryViewToggle extends StatelessWidget {
  const _LibraryViewToggle({
    required this.isGrid,
    required this.gridTooltip,
    required this.listTooltip,
    required this.onChanged,
  });

  final bool isGrid;
  final String gridTooltip;
  final String listTooltip;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    Widget btn({
      required IconData icon,
      required String tooltip,
      required bool active,
      required VoidCallback onTap,
    }) {
      return Tooltip(
        message: tooltip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: MotionToken.reduced(
                context,
                const Duration(milliseconds: 200),
              ),
              curve: Curves.easeOutCubic,
              width: 30,
              height: 28,
              decoration: BoxDecoration(
                color: active ? skin.raise3 : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Center(
                child: Icon(
                  icon,
                  size: 16,
                  color: active ? skin.text : skin.text3,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: skin.raise,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: skin.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(
            icon: DesktopIcons.grid,
            tooltip: gridTooltip,
            active: isGrid,
            onTap: () => onChanged(true),
          ),
          btn(
            icon: DesktopIcons.list,
            tooltip: listTooltip,
            active: !isGrid,
            onTap: () => onChanged(false),
          ),
        ],
      ),
    );
  }
}
