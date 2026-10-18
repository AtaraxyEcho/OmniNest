import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/widgets/infinite_scroll.dart';
import 'package:omninest/app/module_entry_refresh_listener.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/reader_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/widgets/app_error_view.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/core/widgets/env_empty_state.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/omni_icons.dart';
import 'package:omninest/features/files/media_import_ui.dart'
    show ImportButtonStyle;
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/application/reader_import_queue_controller.dart';
import 'package:omninest/features/reader/application/reader_progress_snapshot.dart';
import 'package:omninest/features/reader/application/reader_local_progress.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_empty_state.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_import_queue_cards.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_library_cards.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_library_import_action.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_page_fill.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_page_scaffold.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_space_content.dart';

import 'package:omninest/features/reader/presentation/widgets/reader_parse_feedback.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_snack_bar.dart';

/// 书库页：全部条目网格，支持分段过滤、排序与搜索。
class ReaderCenterPage extends ConsumerStatefulWidget {
  const ReaderCenterPage({super.key});

  @override
  ConsumerState<ReaderCenterPage> createState() => _ReaderCenterPageState();
}

class _ReaderCenterPageState extends ConsumerState<ReaderCenterPage> {
  final TextEditingController _searchController = TextEditingController();
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
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    await ref.read(readerCenterControllerProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final stateAsync = ref.watch(readerCenterControllerProvider);
    final state = stateAsync.asData?.value;
    // 分段/关键词已经下沉服务端；首屏不足一栅格两行时仍要把分页补到能触底，
    // 否则 InfiniteScrollTrigger 永远不会被滚到。
    scheduleReaderPageFill(
      ref,
      visibleCount: state?.visibleItems.length ?? 0,
      hasMore: state?.itemsHasMore ?? false,
      isLoadingMore: state?.itemsLoadingMore ?? false,
    );
    return ModuleEntryRefreshListener(
      modulePath: '/reader',
      onRefresh:
          () => unawaited(
            ref.read(readerCenterControllerProvider.notifier).refresh(),
          ),
      child: ReaderPageScaffold(
        target: ReaderPageTarget.library,
        onRefresh: _onRefresh,
        // 书库网格自带滚动体：续页只追加、不裁剪，必须交给视口惰性构建，
        // 否则滚到第 6 页时同屏挂着 300 张卡片与 300 个封面请求。
        childOwnScroll: true,
        // 托管态空间内不再渲染书库页头（搜索/分段页签）：全量书库经
        // 「书架」动作进入；桌面端维持完整页头。
        header:
            MobileShellScope.isHosted(context) ||
                    stateAsync.asData?.value == null
                ? null
                : _LibraryHeader(
                  itemCount: stateAsync.asData!.value.visibleItems.length,
                  searchController: _searchController,
                  segment: stateAsync.asData!.value.librarySegment,
                  onSearchChanged: (value) {
                    ref
                        .read(readerCenterControllerProvider.notifier)
                        .setSearchQuery(value);
                  },
                  onSegmentChanged:
                      (segment) => ref
                          .read(readerCenterControllerProvider.notifier)
                          .selectLibrarySegment(segment),
                ),
        child: ReaderParseFeedback(
          child: InfiniteScrollTrigger(
            enabled:
                (stateAsync.asData?.value.itemsHasMore ?? false) &&
                !(stateAsync.asData?.value.itemsLoadingMore ?? false),
            onLoadMore:
                () =>
                    ref
                        .read(readerCenterControllerProvider.notifier)
                        .loadMoreItems(),
            child: stateAsync.when(
              data: _buildContent,
              error:
                  (error, stackTrace) => _buildScrollHost([
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: AppErrorView(
                        message: describeUserFacingError(error).displayMessage,
                        onRetry:
                            () =>
                                ref.invalidate(readerCenterControllerProvider),
                      ),
                    ),
                  ]),
              loading:
                  () => _buildScrollHost([
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: AppLoading(),
                    ),
                  ]),
            ),
          ),
        ),
      ),
    );
  }

  /// 内容滚动体：页面自带滚动，骨架不再包一层 SingleChildScrollView。
  ///
  /// 内边距与骨架默认取值一致（[ReaderPageScaffold.contentPaddingOf]），
  /// 所有内容以 sliver 形式交给同一个视口，网格只构建可见范围。
  Widget _buildScrollHost(List<Widget> slivers) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        SliverPadding(
          padding: ReaderPageScaffold.contentPaddingOf(context),
          sliver: SliverMainAxisGroup(slivers: slivers),
        ),
      ],
    );
  }

  Widget _buildContent(ReaderCenterState data) {
    final l10n = AppLocalizations.of(context);
    final visibleItems = data.visibleItems;
    final importJobs = ref.watch(readerImportQueueProvider);
    final hosted = MobileShellScope.isHosted(context);
    final browseAll =
        data.librarySegment == ReaderLibrarySegment.all &&
        data.searchQuery.trim().isEmpty;

    final slivers = <Widget>[
      if (data.errorMessage != null)
        SliverToBoxAdapter(
          child: MaterialBanner(
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
        ),
      if (importJobs.isNotEmpty)
        SliverToBoxAdapter(
          child: Column(
            children: [
              const SizedBox(height: 8),
              for (final job in importJobs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ImportJobRow(job: job),
                ),
            ],
          ),
        ),
    ];

    if (hosted) {
      if (!browseAll) {
        // 检索/分段态：书库网格保留为结果视图。
        slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 28)));
        slivers.add(
          visibleItems.isEmpty
              ? SliverToBoxAdapter(
                child: EnvEmptyState(
                  icon: OmniIcons.book,
                  title: l10n.libraryEmptyBooksTitle,
                  message: l10n.libraryEmptyBooksMessage,
                ),
              )
              : _LibraryGridSliver(
                items: visibleItems,
                onOpenItem: _onOpenItem,
                onToggleBookshelf: _onToggleBookshelf,
                onDeleteItem: _onDeleteItem,
              ),
        );
      } else {
        slivers.add(
          SliverToBoxAdapter(child: _buildHostedSpace(data, visibleItems)),
        );
      }
      return _buildScrollHost(slivers);
    }

    final showContinue = browseAll && data.continueItems.isNotEmpty;
    if (showContinue) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _ContinueSection(
              items: data.continueItems.take(6).toList(),
              onOpenItem: _openContinueReading,
            ),
          ),
        ),
      );
    }
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 32)));
    slivers.add(
      visibleItems.isEmpty
          ? SliverToBoxAdapter(
            child: ReaderEmptyState(
              title: l10n.readerEmptyHint,
              subtitle: l10n.readerEmptyHintDesc,
              icon: Icons.library_books_outlined,
              action: ReaderLibraryImportAction(
                style: ImportButtonStyle.filledButton,
                label: l10n.readerImportBooks,
              ),
            ),
          )
          : _LibraryGridSliver(
            items: visibleItems,
            onOpenItem: _onOpenItem,
            onToggleBookshelf: _onToggleBookshelf,
            onDeleteItem: _onDeleteItem,
          ),
    );
    return _buildScrollHost(slivers);
  }

  /// 托管态 Reader 空间：样例 shelf 视图四段（特写/洞察/书轨/最近笔记）。
  Widget _buildHostedSpace(
    ReaderCenterState data,
    List<ReaderItem> visibleItems,
  ) {
    final l10n = AppLocalizations.of(context);
    // 复用控制器随下拉刷新一起更新的 dashboard：单独 watch readerDashboardProvider
    // 拿到的是没跟着刷新的旧缓存，导入或读完一本书后特写与书轨仍显示上一批书。
    final recent = data.dashboard.recentItems;
    final pool = recent.isNotEmpty ? recent : visibleItems;
    final feature = data.continueItems.firstOrNull ?? pool.firstOrNull;
    final railItems =
        pool.where((item) => item.id != feature?.id).take(10).toList();

    final overview = ref.watch(readerStatsOverviewProvider).asData?.value;
    final streak = ref.watch(readerStatsProvider).asData?.value.currentStreak;
    final weekMinutes = overview?.dailyMinutes.fold<int>(
      0,
      (sum, entry) => sum + entry.minutes,
    );

    final annotations =
        ref.watch(readerRecentAnnotationsProvider).asData?.value ??
        const <ReaderAnnotation>[];
    final notes = <ReaderSpaceNote>[
      for (final annotation in annotations)
        if ((annotation.highlightText ?? annotation.note)?.isNotEmpty == true)
          ReaderSpaceNote(
            annotationId: annotation.id,
            itemId: annotation.readerItemId,
            quote: annotation.highlightText ?? annotation.note ?? '',
            createdAt: annotation.createdAt,
          ),
    ];
    final bookTitles = <String, String>{
      for (final item in pool)
        if (item.id.isNotEmpty) item.id: item.title,
    };

    if (feature == null && railItems.isEmpty) {
      // 整库为空：居中空态 + 导入 CTA（空态须可行动，而非纯提示）。
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EnvEmptyState(
            icon: OmniIcons.book,
            title: l10n.libraryEmptyBooksTitle,
            message: l10n.libraryEmptyBooksMessage,
          ),
          const SizedBox(height: 4),
          Center(
            child: ReaderLibraryImportAction(
              style: ImportButtonStyle.outlinedButton,
              label: l10n.readerImportBooks,
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 托管态不渲染书库页头，这里是库里有了书之后唯一的导入入口。
        Align(
          alignment: Alignment.centerRight,
          child: ReaderLibraryImportAction(
            style: ImportButtonStyle.outlinedButton,
            label: l10n.readerImportBooks,
          ),
        ),
        ReaderSpaceContent(
          featureItem: feature,
          railItems: railItems,
          notes: notes,
          bookTitles: bookTitles,
          insightMinutes: weekMinutes,
          insightBooksFinished: overview?.completedCount ?? 0,
          insightStreakDays: streak,
          onResume: _openContinueReading,
          onOpenItem: _onOpenItem,
          onOpenBookshelf: () => context.push('/reader/bookshelf'),
          onOpenStats: () => context.push('/reader/stats'),
        ),
      ],
    );
  }

  /// 书库/书架卡片：一律先进入详情页。
  void _onOpenItem(ReaderItem item) {
    if (item.id.isEmpty) {
      showReaderSnackBar(
        context,
        AppLocalizations.of(context).readerOperationFailed,
      );
      return;
    }
    context.push('/reader/items/${item.id}');
  }

  /// 继续阅读卡：直接打开阅读器（定位到上次章节），返回时回到当前页。
  ///
  /// 漫画与 PDF 先按形态分流：它们的进度记录借用同一张进度表，但章节语义不同
  /// ——PDF 上报固定写 `chapterId: 'pdf'`，漫画上报不带章节，按文本章节路由
  /// 会把它们推进 `ReaderViewPage` 或退回详情页。
  Future<void> _openContinueReading(ReaderItem item) async {
    if (item.id.isEmpty) {
      showReaderSnackBar(
        context,
        AppLocalizations.of(context).readerOperationFailed,
      );
      return;
    }
    if (item.isComic) {
      context.push('/reader/comics/${item.id}/read');
      return;
    }
    if (item.itemType.toUpperCase() == 'PDF') {
      context.push('/reader/pdfs/${item.id}/read');
      return;
    }
    final localSnapshot = ReaderProgressSnapshot.fromLocal(
      await ReaderLocalProgress.loadLatest(item.id),
    );
    if (!mounted) {
      return;
    }
    // 跨设备：并行取服务器进度（500ms 超时兜底），按 updatedAt 取全局
    // 最新解析章节；服务器不可达时退回本地，阅读器内加载层仍会修正。
    ReaderProgressSnapshot? serverSnapshot;
    try {
      final detail = await ref
          .read(readerItemDetailProvider(item.id).future)
          .timeout(const Duration(milliseconds: 500));
      serverSnapshot = ReaderProgressSnapshot.fromServer(detail.progress);
    } on Exception {
      serverSnapshot = null;
    }
    if (!mounted) {
      return;
    }
    final best = ReaderProgressSnapshot.latest(localSnapshot, serverSnapshot);
    if (best != null && best.hasReadableProgress) {
      final chapterId = Uri.encodeComponent(best.chapterId);
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
    } on Exception catch (error) {
      if (mounted) {
        showReaderSnackBar(
          context,
          describeUserFacingError(
            error,
            l10n: AppLocalizations.of(context),
          ).displayMessage,
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
    } on Exception catch (error) {
      if (mounted) {
        showReaderSnackBar(
          context,
          describeUserFacingError(
            error,
            l10n: AppLocalizations.of(context),
          ).displayMessage,
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
    required this.onSearchChanged,
    required this.onSegmentChanged,
  });

  final int itemCount;
  final TextEditingController searchController;
  final ReaderLibrarySegment segment;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<ReaderLibrarySegment> onSegmentChanged;

  @override
  Widget build(BuildContext context) {
    final rc = context.readerColors;
    final l10n = AppLocalizations.of(context);
    final hosted = MobileShellScope.isHosted(context);
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
                fontSize: MediaQuery.sizeOf(context).width >= 1024 ? 36 : 30,
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
                fontSize: AppTypography.bodySmall,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            // 托管态模块顶栏隐藏，导入入口承接至书库页头。
            if (hosted) ...[const SizedBox(width: 12), _LibraryImportButton()],
          ],
        ),
        const SizedBox(height: 18),
        _SearchAndFilterRow(
          searchController: searchController,
          segment: segment,
          onSearchChanged: onSearchChanged,
          onSegmentChanged: onSegmentChanged,
        ),
      ],
    );
  }
}

/// 托管态书库页头的导入入口（模块顶栏隐藏后由页头承接）。
class _LibraryImportButton extends StatelessWidget {
  const _LibraryImportButton();

  @override
  Widget build(BuildContext context) {
    return const ReaderLibraryImportAction();
  }
}

/// 搜索框 + 下划线过滤页签 + 排序刷新。
class _SearchAndFilterRow extends StatelessWidget {
  const _SearchAndFilterRow({
    required this.searchController,
    required this.segment,
    required this.onSearchChanged,
    required this.onSegmentChanged,
  });

  final TextEditingController searchController;
  final ReaderLibrarySegment segment;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<ReaderLibrarySegment> onSegmentChanged;

  @override
  Widget build(BuildContext context) {
    final rc = context.readerColors;
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 10,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 224, minWidth: 160),
              child: TextField(
                controller: searchController,
                onChanged: onSearchChanged,
                style: TextStyle(
                  color: rc.onSurface,
                  fontSize: AppTypography.bodyMedium,
                  height: 1.2,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: rc.surfaceContainerHigh,
                  hintText: l10n.readerSearchBooksHint,
                  hintStyle: TextStyle(
                    color: rc.onSurfaceVariant,
                    fontSize: AppTypography.bodyMedium,
                  ),
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
          ],
        ),
        // 分割线是整行的收尾，不是搜索框与页签的同伴：留在 Wrap 里会被当成一个
        // 流式子项另起一 run，既叠上 runSpacing，又画不出贯穿宽度的线。
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
                    fontSize: AppTypography.bodyMedium,
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
            // ignore: font_size_whitelist
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

/// 书库网格 sliver：封面 + 标题作者，交给视口按需构建。
///
/// 条目由 controller 滚动续页累积（只追加不裁剪），因此这里必须是真正的
/// `SliverGrid` 而不是 `shrinkWrap` 网格：后者会把已加载的全部条目一次实例化。
class _LibraryGridSliver extends StatelessWidget {
  const _LibraryGridSliver({
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
  Widget build(BuildContext context) {
    // 列数与卡片高度都由可用横向尺寸决定，sliver 约束直接给出该尺寸。
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        final columns = _columnCount(width);
        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 16,
            mainAxisSpacing: 20,
            mainAxisExtent: _tileHeight(context, width, columns),
          ),
          delegate: SliverChildBuilderDelegate((context, index) {
            final item = items[index];
            return ReaderLibraryGridCard(
              item: item,
              onTap: () => onOpenItem(item),
              onToggleBookshelf: onToggleBookshelf,
              onDelete: onDeleteItem == null ? null : () => onDeleteItem!(item),
            );
          }, childCount: items.length),
        );
      },
    );
  }

  int _columnCount(double width) {
    // 比原配置多一列：封面仍 2:3，但单卡更窄更矮。
    if (width >= 1280) return 7;
    if (width >= 1024) return 6;
    if (width >= 640) return 5;
    return 3;
  }

  double _tileHeight(BuildContext context, double width, int columns) {
    final tileWidth = (width - 16.0 * (columns - 1)) / columns;
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
    // 恢复原先 2:3 封面比例；文字区略压（标题两行 + 作者一行）。
    return tileWidth * 1.5 + 6 + 34.0 * textScale + 14.0 * textScale + 2;
  }
}
