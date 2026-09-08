import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/widgets/app_error_view.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/application/reader_progress_snapshot.dart';
import 'package:omninest/features/reader/application/reader_local_progress.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_book_card.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_empty_state.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_page_scaffold.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_parse_feedback.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_snack_bar.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_styles.dart';
import 'package:omninest/features/reader/presentation/reader_l10n_helpers.dart';

/// 书库页：全部条目网格，支持分段过滤、排序与搜索。
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

  @override
  Widget build(BuildContext context) {
    final stateAsync = ref.watch(readerCenterControllerProvider);
    return ReaderPageScaffold(
      target: ReaderPageTarget.library,
      searchController: _searchController,
      onSearchChanged: (value) {
        ref.read(readerCenterControllerProvider.notifier).setSearchQuery(value);
      },
      onRefresh: () async {
        await ref.read(readerCenterControllerProvider.notifier).refresh();
      },
      child: ReaderParseFeedback(
        child: stateAsync.when(
          data:
              (data) => Column(
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
                                      .read(
                                        readerCenterControllerProvider.notifier,
                                      )
                                      .clearError(),
                          child: Text(AppLocalizations.of(context).readerClose),
                        ),
                      ],
                    ),
                  const SizedBox(height: 4),
                  _LibraryToolbar(
                    itemCount: data.visibleItems.length,
                    sortBy: data.sortBy,
                    onRefresh:
                        () =>
                            ref
                                .read(readerCenterControllerProvider.notifier)
                                .refresh(),
                    onSortChanged:
                        (sortBy) => ref
                            .read(readerCenterControllerProvider.notifier)
                            .setSortBy(sortBy),
                  ),
                  const SizedBox(height: 12),
                  _LibrarySegmentControl(
                    segment: data.librarySegment,
                    onChanged:
                        (segment) => ref
                            .read(readerCenterControllerProvider.notifier)
                            .selectLibrarySegment(segment),
                  ),
                  const SizedBox(height: 20),
                  if (data.visibleItems.isEmpty)
                    ReaderEmptyState(
                      title: AppLocalizations.of(context).readerEmptyHint,
                      subtitle:
                          AppLocalizations.of(context).readerEmptyHintDesc,
                      icon: Icons.library_books_outlined,
                    )
                  else
                    _ReaderGrid(
                      items: data.visibleItems,
                      onOpenItem: _onOpenItem,
                      onDeleteItem: _onDeleteItem,
                      onToggleBookshelf: _onToggleBookshelf,
                    ),
                ],
              ),
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
}

/// 书库工具行：数量徽标 + 排序 + 刷新。
class _LibraryToolbar extends StatelessWidget {
  const _LibraryToolbar({
    required this.itemCount,
    required this.sortBy,
    required this.onRefresh,
    required this.onSortChanged,
  });

  final int itemCount;
  final ReaderSortBy sortBy;
  final VoidCallback onRefresh;
  final ValueChanged<ReaderSortBy> onSortChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            AppLocalizations.of(context).readerBookCount(itemCount),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11,
              height: 14 / 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Spacer(),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<ReaderSortBy>(
              value: sortBy,
              isDense: true,
              icon: Icon(
                Icons.unfold_more_rounded,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 16,
              ),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              dropdownColor: Theme.of(context).colorScheme.surfaceContainerHigh,
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
        ),
        SizedBox(width: 6),
        IconButton(
          tooltip: AppLocalizations.of(context).readerRefresh,
          onPressed: onRefresh,
          icon: Icon(
            Icons.refresh_rounded,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            size: 20,
          ),
        ),
      ],
    );
  }
}

/// 书库分段控件（全部 / 图书 / 漫画）
class _LibrarySegmentControl extends StatelessWidget {
  const _LibrarySegmentControl({
    required this.segment,
    required this.onChanged,
  });

  final ReaderLibrarySegment segment;
  final ValueChanged<ReaderLibrarySegment>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(3),
        child: Row(
          children:
              ReaderLibrarySegment.values.map((s) {
                final isSelected = s == segment;
                return Expanded(
                  child: GestureDetector(
                    onTap: onChanged != null ? () => onChanged!(s) : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color:
                            isSelected
                                ? Theme.of(context).colorScheme.surface
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow:
                            isSelected
                                ? [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ]
                                : null,
                      ),
                      child: Text(
                        _label(context, s),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w400,
                          color:
                              isSelected
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
        ),
      ),
    );
  }

  String _label(BuildContext context, ReaderLibrarySegment s) {
    final l10n = AppLocalizations.of(context);
    return switch (s) {
      ReaderLibrarySegment.all => l10n.readerSegmentAll,
      ReaderLibrarySegment.books => l10n.readerSegmentBooks,
      ReaderLibrarySegment.comics => l10n.readerSegmentComics,
    };
  }
}

class _ReaderGrid extends StatefulWidget {
  const _ReaderGrid({
    required this.items,
    required this.onOpenItem,
    required this.onDeleteItem,
    this.onToggleBookshelf,
  });

  final List<ReaderItem> items;
  final ValueChanged<ReaderItem> onOpenItem;
  final ValueChanged<ReaderItem> onDeleteItem;
  final ValueChanged<ReaderItem>? onToggleBookshelf;

  @override
  State<_ReaderGrid> createState() => _ReaderGridState();
}

class _ReaderGridState extends State<_ReaderGrid> {
  /// 分页渲染：shrinkWrap 网格一次性布局全部子项，初始只暴露前
  /// [_pageSize] 个，条目列表变化时重置。
  static const _pageSize = 60;
  bool _showAll = false;

  @override
  void didUpdateWidget(_ReaderGrid oldWidget) {
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
        final columns = readerGridColumnCount(constraints.maxWidth);
        final grid = GridView.builder(
          itemCount: visibleCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 10,
            mainAxisSpacing: 12,
            childAspectRatio: readerGridChildAspectRatio(context),
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return ReaderBookCard(
              item: item,
              onTap: () => widget.onOpenItem(item),
              onDelete: () => widget.onDeleteItem(item),
              onToggleBookshelf:
                  widget.onToggleBookshelf != null
                      ? () => widget.onToggleBookshelf!(item)
                      : null,
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
}
