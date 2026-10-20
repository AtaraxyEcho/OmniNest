import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/widgets/infinite_scroll.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/control_tokens.dart';
import 'package:omninest/app/theme/feature/reader_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/features/files/media_import_ui.dart'
    show ImportButtonStyle;
import 'package:omninest/features/reader/application/reader_bookshelf_controller.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_book_cover.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_empty_state.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_library_import_action.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_page_scaffold.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_parse_feedback.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_shelf_row.dart';

/// 书架页：已加入书架的条目编号列表。
class ReaderBookshelfPage extends ConsumerWidget {
  const ReaderBookshelfPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rc = context.readerColors;
    final stateAsync = ref.watch(readerBookshelfControllerProvider);
    final shelf = stateAsync.asData?.value;
    final shelved = shelf?.items ?? const <ReaderItem>[];
    return ReaderPageScaffold(
      target: ReaderPageTarget.bookshelf,
      // 书架自带滚动体：外层若是页级 SingleChildScrollView，列表的
      // builder 惰性会失效（需按内容固有高度全量布局）。
      childOwnScroll: true,
      onRefresh:
          () => ref.read(readerBookshelfControllerProvider.notifier).refresh(),
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                AppLocalizations.of(context).readerNavBookshelf,
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
                '${shelf?.totalElements ?? 0}',
                style: TextStyle(
                  color: rc.onSurfaceVariant,
                  fontSize: AppTypography.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: rc.outlineVariant.withValues(alpha: 0.6)),
        ],
      ),
      child: ReaderParseFeedback(
        child: InfiniteScrollTrigger(
          enabled: (shelf?.hasMore ?? false) && !(shelf?.loadingMore ?? false),
          onLoadMore:
              () =>
                  ref
                      .read(readerBookshelfControllerProvider.notifier)
                      .loadMore(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              if (shelf?.errorMessage != null)
                SliverToBoxAdapter(
                  child: MaterialBanner(
                    content: Text(shelf!.errorMessage!),
                    actions: [
                      TextButton(
                        onPressed:
                            () =>
                                ref
                                    .read(
                                      readerBookshelfControllerProvider
                                          .notifier,
                                    )
                                    .clearError(),
                        child: Text(AppLocalizations.of(context).readerClose),
                      ),
                    ],
                  ),
                ),
              if (shelved.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  // 与书库空态一致：贴内容区顶部、水平居中，不在剩余高度里垂直居中。
                  child: Padding(
                    padding: const EdgeInsets.only(top: 32),
                    child: ReaderEmptyState(
                      title: AppLocalizations.of(context).readerShelfEmpty,
                      subtitle:
                          AppLocalizations.of(context).readerShelfEmptyHint,
                      icon: Icons.auto_stories_outlined,
                      action: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: () => context.go('/reader'),
                            icon: const Icon(
                              Icons.library_books_outlined,
                              size: AppControlTokens.buttonIconSize,
                            ),
                            label: Text(
                              AppLocalizations.of(context).readerGoToLibrary,
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: rc.primary,
                              foregroundColor: rc.surface,
                            ),
                          ),
                          ReaderLibraryImportAction(
                            style: ImportButtonStyle.outlinedButton,
                            label:
                                AppLocalizations.of(context).readerImportBooks,
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    MediaQuery.sizeOf(context).width >= 1024 ? 32 : 24,
                    0,
                    MediaQuery.sizeOf(context).width >= 1024 ? 32 : 24,
                    40,
                  ),
                  // 托管/紧凑档为纸封网格（样例两页签书架），桌面宽档保持行式。
                  sliver:
                      MobileShellScope.isHosted(context) ||
                              MediaQuery.sizeOf(context).width < 600
                          ? SliverGrid(
                            gridDelegate:
                                SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 220,
                                  mainAxisSpacing: 18,
                                  crossAxisSpacing: 14,
                                  childAspectRatio: 0.52,
                                ),
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final item = shelved[index];
                              return _BookshelfCoverTile(item: item);
                            }, childCount: shelved.length),
                          )
                          : SliverList(
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final item = shelved[index];
                              return Container(
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: rc.outlineVariant.withValues(
                                        alpha: 0.6,
                                      ),
                                    ),
                                  ),
                                ),
                                child: ReaderShelfRow(
                                  index: index,
                                  item: item,
                                  onTap:
                                      () => context.push(
                                        '/reader/items/${item.id}',
                                      ),
                                ),
                              );
                            }, childCount: shelved.length),
                          ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 书架纸封网格瓦片（样例 shelf-cover）：封面 + 题名 + 类型/进度微行。
class _BookshelfCoverTile extends StatelessWidget {
  const _BookshelfCoverTile({required this.item});

  final ReaderItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final progress = item.progressPercent ?? 0;
    return InkWell(
      onTap: () => context.push('/reader/items/${item.id}'),
      borderRadius: BorderRadius.circular(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(6),
                bottom: Radius.circular(3),
              ),
              child: ReaderBookCover(item: item, size: ReaderCoverSize.large),
            ),
          ),
          const SizedBox(height: 7),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppTypography.bodySmall,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          if (progress > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                l10n.readerReadingProgress((progress * 100).round()),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppTypography.labelSmall,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
