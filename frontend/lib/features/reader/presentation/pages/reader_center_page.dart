import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/feature/reader_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/widgets/app_error_view.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/application/reader_progress_snapshot.dart';
import 'package:omninest/features/reader/application/reader_local_progress.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/reader_l10n_helpers.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_empty_state.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_library_cards.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_page_scaffold.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_parse_feedback.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_snack_bar.dart';

/// 书库页：全部条目网格，支持分段过滤、排序与搜索。
/// 参考设计标题衬线字体（中文回退系统字体，保持正体）。
const String kReaderSerifFamily = 'InstrumentSerif';

class ReaderCenterPage extends ConsumerStatefulWidget {
  const ReaderCenterPage({super.key});

  @override
  ConsumerState<ReaderCenterPage> createState() => _ReaderCenterPageState();
}

class _ReaderCenterPageState extends ConsumerState<ReaderCenterPage> {
  final TextEditingController _searchController = TextEditingController();
  VoidCallback? _routeListener;
  GoRouter? _router;
  DateTime _lastRefresh = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    // 模块内页签切换会重建本页：已有数据时做节流刷新，保证书库数据新鲜。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final hasData =
          ref.read(readerCenterControllerProvider).asData?.value != null;
      final now = DateTime.now();
      if (hasData && now.difference(_lastRefresh).inMilliseconds > 500) {
        _lastRefresh = now;
        ref.read(readerCenterControllerProvider.notifier).refresh();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final router = GoRouter.of(context);
      _router = router;
      void listener() {
        final path = router.routeInformationProvider.value.uri.path;
        if (path == '/reader' && mounted) {
          final now = DateTime.now();
          if (now.difference(_lastRefresh).inMilliseconds > 500) {
            _lastRefresh = now;
            ref.read(readerCenterControllerProvider.notifier).refresh();
          }
        }
      }

      _routeListener = listener;
      router.routeInformationProvider.addListener(listener);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 搜索词由 controller 持有，跨页签切换保留
    final query =
        ref.read(readerCenterControllerProvider).asData?.value.searchQuery ??
        '';
    if (_searchController.text != query) {
      _searchController.text = query;
    }
  }

  @override
  void dispose() {
    if (_routeListener != null && _router != null) {
      _router!.routeInformationProvider.removeListener(_routeListener!);
    }
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    await ref.read(readerCenterControllerProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final stateAsync = ref.watch(readerCenterControllerProvider);
    return ReaderPageScaffold(
      target: ReaderPageTarget.library,
      searchController: _searchController,
      onSearchChanged: (value) {
        ref.read(readerCenterControllerProvider.notifier).setSearchQuery(value);
      },
      onRefresh: _onRefresh,
      header:
          stateAsync.asData?.value == null
              ? null
              : _LibraryHeader(
                itemCount: stateAsync.asData!.value.visibleItems.length,
                searchController: _searchController,
                segment: stateAsync.asData!.value.librarySegment,
                sortBy: stateAsync.asData!.value.sortBy,
                onSearchChanged: (value) {
                  ref
                      .read(readerCenterControllerProvider.notifier)
                      .setSearchQuery(value);
                },
                onSegmentChanged:
                    (segment) => ref
                        .read(readerCenterControllerProvider.notifier)
                        .selectLibrarySegment(segment),
                onSortChanged:
                    (sortBy) => ref
                        .read(readerCenterControllerProvider.notifier)
                        .setSortBy(sortBy),
                onRefresh: _onRefresh,
              ),
      child: ReaderParseFeedback(
        child: stateAsync.when(
          data: _buildContent,
          error:
              (error, stackTrace) => AppErrorView(
                message: describeUserFacingError(error).displayMessage,
                onRetry: () => ref.invalidate(readerCenterControllerProvider),
              ),
          loading: () => const AppLoading.grid(gridAspectRatio: 0.72),
        ),
      ),
    );
  }

  Widget _buildContent(ReaderCenterState data) {
    final l10n = AppLocalizations.of(context);
    final visibleItems = data.visibleItems;
    final showContinue =
        data.librarySegment == ReaderLibrarySegment.all &&
        data.searchQuery.trim().isEmpty &&
        data.continueItems.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (data.errorMessage != null)
          MaterialBanner(
            content: Text(data.errorMessage!),
            actions: [
              TextButton(
                onPressed:
                    () =>
                        ref
                            .read(readerCenterControllerProvider.notifier)
                            .clearError(),
                child: Text(l10n.readerClose),
              ),
            ],
          ),
        if (showContinue) ...[
          const SizedBox(height: 28),
          _ContinueSection(
            items: data.continueItems.take(6).toList(),
            onOpenItem: _onOpenItem,
          ),
        ],
        const SizedBox(height: 32),
        if (visibleItems.isEmpty)
          ReaderEmptyState(
            title: l10n.readerEmptyHint,
            subtitle: l10n.readerEmptyHintDesc,
            icon: Icons.library_books_outlined,
          )
        else
          _LibraryGrid(
            items: visibleItems,
            onOpenItem: _onOpenItem,
            onToggleBookshelf: _onToggleBookshelf,
            onDeleteItem: _onDeleteItem,
          ),
      ],
    );
  }

  Future<void> _onOpenItem(ReaderItem item) async {
    if (item.id.isEmpty) {
      if (mounted) {
        showReaderSnackBar(
          context,
          AppLocalizations.of(context).readerOperationFailed,
        );
      }
      return;
    }
    // 漫画先进入详情页，阅读清单就绪后再由用户进入阅读器。
    if (item.isComic) {
      context.push('/reader/items/${item.id}');
      return;
    }

    final localSnapshot = ReaderProgressSnapshot.fromLocal(
      await ReaderLocalProgress.loadLatest(item.id),
    );
    if (!mounted) {
      return;
    }
    if (localSnapshot.hasReadableProgress) {
      final chapterId = Uri.encodeComponent(localSnapshot.chapterId);
      context.push('/reader/items/${item.id}/chapters/$chapterId');
      return;
    }
    context.push('/reader/items/${item.id}');
  }

  Future<void> _onToggleBookshelf(ReaderItem item) async {
    try {
      final result = await ref
          .read(readerCenterControllerProvider.notifier)
          .toggleBookshelf(item.id);
      if (mounted) {
        showReaderSnackBar(
          context,
          result.addedToBookshelf
              ? AppLocalizations.of(context).readerAddedToBookshelf
              : AppLocalizations.of(context).readerRemovedFromBookshelf,
        );
      }
    } on Exception {
      if (mounted) {
        showReaderSnackBar(
          context,
          AppLocalizations.of(context).readerOperationFailed,
        );
      }
    }
  }

  Future<void> _onDeleteItem(ReaderItem item) async {
    try {
      await ref
          .read(readerCenterControllerProvider.notifier)
          .deleteItem(item.id);
      if (!mounted) return;
      showReaderSnackBar(
        context,
        AppLocalizations.of(context).readerDeletedItem(item.title),
      );
    } on Exception {
      if (mounted) {
        showReaderSnackBar(
          context,
          AppLocalizations.of(context).readerDeleteItemFailed,
        );
      }
    }
  }
}

/// 书库页头：标题 + 搜索 + 过滤页签 + 排序。
class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader({
    required this.itemCount,
    required this.searchController,
    required this.segment,
    required this.sortBy,
    required this.onSearchChanged,
    required this.onSegmentChanged,
    required this.onSortChanged,
    required this.onRefresh,
  });

  final int itemCount;
  final TextEditingController searchController;
  final ReaderLibrarySegment segment;
  final ReaderSortBy sortBy;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<ReaderLibrarySegment> onSegmentChanged;
  final ValueChanged<ReaderSortBy> onSortChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final rc = context.readerColors;
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              l10n.readerNavLibrary,
              style: TextStyle(
                color: rc.onSurface,
                fontSize: 30,
                height: 1.15,
                fontFamily: kReaderSerifFamily,
                fontStyle: FontStyle.italic,
                letterSpacing: -0.5,
              ),
            ),
            const Spacer(),
            Text(
              '$itemCount',
              style: TextStyle(
                color: rc.onSurfaceVariant,
                fontSize: 12,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _SearchAndFilterRow(
          searchController: searchController,
          segment: segment,
          sortBy: sortBy,
          onSearchChanged: onSearchChanged,
          onSegmentChanged: onSegmentChanged,
          onSortChanged: onSortChanged,
          onRefresh: onRefresh,
        ),
      ],
    );
  }
}

/// 搜索框 + 下划线过滤页签 + 排序刷新。
class _SearchAndFilterRow extends StatelessWidget {
  const _SearchAndFilterRow({
    required this.searchController,
    required this.segment,
    required this.sortBy,
    required this.onSearchChanged,
    required this.onSegmentChanged,
    required this.onSortChanged,
    required this.onRefresh,
  });

  final TextEditingController searchController;
  final ReaderLibrarySegment segment;
  final ReaderSortBy sortBy;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<ReaderLibrarySegment> onSegmentChanged;
  final ValueChanged<ReaderSortBy> onSortChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final rc = context.readerColors;
    final l10n = AppLocalizations.of(context);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 10,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 224, minWidth: 160),
          child: TextField(
            controller: searchController,
            onChanged: onSearchChanged,
            style: TextStyle(color: rc.onSurface, fontSize: 13, height: 1.2),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: rc.surfaceContainerHigh,
              hintText: l10n.readerSearchBooksHint,
              hintStyle: TextStyle(color: rc.onSurfaceVariant, fontSize: 13),
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 18,
                color: rc.onSurfaceVariant,
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 36),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 9,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(2),
                borderSide: BorderSide(color: rc.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(2),
                borderSide: BorderSide(color: rc.outlineVariant),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(2),
                borderSide: BorderSide(color: rc.onSurface),
              ),
            ),
          ),
        ),
        _FilterTabs(segment: segment, onChanged: onSegmentChanged),
        _SortAndRefresh(
          sortBy: sortBy,
          onSortChanged: onSortChanged,
          onRefresh: onRefresh,
        ),
        const SizedBox(height: 16),
        Container(height: 1, color: rc.outlineVariant.withValues(alpha: 0.6)),
      ],
    );
  }
}

/// 下划线过滤页签（全部 / 书籍 / 漫画）。
class _FilterTabs extends StatelessWidget {
  const _FilterTabs({required this.segment, required this.onChanged});

  final ReaderLibrarySegment segment;
  final ValueChanged<ReaderLibrarySegment> onChanged;

  @override
  Widget build(BuildContext context) {
    final rc = context.readerColors;
    final l10n = AppLocalizations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children:
          ReaderLibrarySegment.values.map((s) {
            final selected = s == segment;
            return InkWell(
              onTap: () => onChanged(s),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                height: 32,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: selected ? rc.onSurface : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  switch (s) {
                    ReaderLibrarySegment.all => l10n.readerSegmentAll,
                    ReaderLibrarySegment.books => l10n.readerSegmentBooks,
                    ReaderLibrarySegment.comics => l10n.readerSegmentComics,
                  },
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? rc.onSurface : rc.onSurfaceVariant,
                  ),
                ),
              ),
            );
          }).toList(),
    );
  }
}

/// 排序下拉 + 刷新按钮。
class _SortAndRefresh extends StatelessWidget {
  const _SortAndRefresh({
    required this.sortBy,
    required this.onSortChanged,
    required this.onRefresh,
  });

  final ReaderSortBy sortBy;
  final ValueChanged<ReaderSortBy> onSortChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final rc = context.readerColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonHideUnderline(
          child: DropdownButton<ReaderSortBy>(
            value: sortBy,
            isDense: true,
            icon: Icon(
              Icons.unfold_more_rounded,
              color: rc.onSurfaceVariant,
              size: 16,
            ),
            style: TextStyle(
              color: rc.onSurface,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            dropdownColor: rc.surfaceContainerHigh,
            items:
                ReaderSortBy.values
                    .map(
                      (s) => DropdownMenuItem(
                        value: s,
                        child: Text(
                          readerSortLabel(AppLocalizations.of(context), s),
                        ),
                      ),
                    )
                    .toList(),
            onChanged: (v) {
              if (v != null) onSortChanged(v);
            },
          ),
        ),
        const SizedBox(width: 6),
        IconButton(
          tooltip: AppLocalizations.of(context).readerRefresh,
          onPressed: onRefresh,
          icon: Icon(
            Icons.refresh_rounded,
            color: rc.onSurfaceVariant,
            size: 20,
          ),
        ),
      ],
    );
  }
}

/// 继续阅读横滑区。
class _ContinueSection extends StatelessWidget {
  const _ContinueSection({required this.items, required this.onOpenItem});

  final List<ReaderItem> items;
  final ValueChanged<ReaderItem> onOpenItem;

  @override
  Widget build(BuildContext context) {
    final rc = context.readerColors;
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.readerContinueReading,
          style: TextStyle(
            color: rc.onSurfaceVariant,
            fontSize: 10,
            height: 1.2,
            letterSpacing: 2.4,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            children: [
              for (final item in items) ...[
                ReaderContinueCard(item: item, onTap: () => onOpenItem(item)),
                const SizedBox(width: 12),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 书库网格：封面 + 标题作者，分页渲染防一次性构建过多。
class _LibraryGrid extends StatefulWidget {
  const _LibraryGrid({
    required this.items,
    required this.onOpenItem,
    this.onToggleBookshelf,
    this.onDeleteItem,
  });

  final List<ReaderItem> items;
  final ValueChanged<ReaderItem> onOpenItem;
  final ValueChanged<ReaderItem>? onToggleBookshelf;
  final ValueChanged<ReaderItem>? onDeleteItem;

  @override
  State<_LibraryGrid> createState() => _LibraryGridState();
}

class _LibraryGridState extends State<_LibraryGrid> {
  static const _pageSize = 60;
  bool _showAll = false;

  @override
  void didUpdateWidget(_LibraryGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.items, widget.items)) {
      _showAll = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final visibleCount =
        _showAll || items.length <= _pageSize ? items.length : _pageSize;
    final hiddenCount = items.length - visibleCount;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columnCount(constraints.maxWidth);
        final grid = GridView.builder(
          itemCount: visibleCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 16,
            mainAxisSpacing: 28,
            mainAxisExtent: _tileHeight(constraints.maxWidth, columns),
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return ReaderLibraryGridCard(
              item: item,
              onTap: () => widget.onOpenItem(item),
              onToggleBookshelf: widget.onToggleBookshelf,
              onDelete:
                  widget.onDeleteItem == null
                      ? null
                      : () => widget.onDeleteItem!(item),
            );
          },
        );
        if (hiddenCount <= 0) {
          return grid;
        }
        return Column(
          children: [
            grid,
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: TextButton.icon(
                onPressed: () => setState(() => _showAll = true),
                icon: const Icon(Icons.expand_more_rounded, size: 18),
                label: Text(
                  AppLocalizations.of(context).readerShowAllBooks(hiddenCount),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  int _columnCount(double width) {
    if (width >= 1400) return 6;
    if (width >= 1000) return 5;
    if (width >= 640) return 4;
    if (width >= 480) return 3;
    return 3;
  }

  double _tileHeight(double width, int columns) {
    final tileWidth = (width - 16 * (columns - 1)) / columns;
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    // 封面 2:3 + 间距 8 + 标题两行 34 + 作者 14
    return tileWidth * 1.5 + 8 + 34 * textScale + 14 * textScale;
  }
}
