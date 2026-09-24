import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/reader_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/core/widgets/app_error_view.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/application/reader_comic_service.dart';
import 'package:omninest/features/reader/application/reader_book_provider.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/domain/reader_status_constants.dart';
import 'package:omninest/features/reader/presentation/pages/comic_detail_page.dart';
import 'package:omninest/features/reader/presentation/pages/reader_detail_text_content.dart';
import 'package:omninest/features/reader/presentation/reader_l10n_helpers.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_page_scaffold.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_snack_bar.dart';
import 'package:omninest/core/errors/error_message.dart';

/// 阅读条目详情页：Hero（封面/进度/阅读动作）+ 简介/章节/批注/书签页签。
///
/// 文本与漫画条目均按参考设计重绘；漫画的目录树与来源管理由
/// ComicDetailPage 以同构布局承载。
class ReaderItemDetailPage extends ConsumerStatefulWidget {
  const ReaderItemDetailPage({required this.itemId, super.key});

  final String itemId;

  @override
  ConsumerState<ReaderItemDetailPage> createState() =>
      _ReaderItemDetailPageState();
}

class _ReaderItemDetailPageState extends ConsumerState<ReaderItemDetailPage> {
  bool _bookshelfBusy = false;

  void _handleBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/reader');
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(readerItemDetailProvider(widget.itemId));

    // 详情视图渲染在模块内容区域内（顶栏/侧栏/底导航保持可见），返回条为固定页头。
    // 漫画与正文分支自带 Sliver 滚动体（章节/批注/书签需懒建），声明后骨架不再二次包裹。
    final detailItem = detailAsync.asData?.value.item;
    final isComicDetail = detailItem?.isComic ?? false;
    final isPdfDetail =
        detailItem != null &&
        detailItem.itemType.toUpperCase() == 'PDF' &&
        !isComicDetail;
    return ReaderPageScaffold(
      target: ReaderPageTarget.library,
      enablePopGuard: false,
      childOwnScroll: detailItem != null && !isPdfDetail,
      headerPadding: EdgeInsets.zero,
      header: _DetailBackBar(onTap: _handleBack),
      child: detailAsync.when(
        data: (detail) {
          final isPdf =
              detail.item.itemType.toUpperCase() == 'PDF' &&
              !detail.item.isComic;
          if (isPdf) {
            return _PdfDetailContent(
              item: detail.item,
              progress: detail.progress,
              bookshelfBusy: _bookshelfBusy,
              onToggleBookshelf: _toggleBookshelf,
              onRead: () {
                context.push('/reader/pdfs/${detail.item.id}/read');
              },
              onEditMetadata:
                  () =>
                      context.push('/reader/items/${detail.item.id}/metadata'),
              onDelete: _deleteItem,
            );
          }
          final isComic = detail.item.isComic;
          if (isComic) {
            return _ComicDetailWrapper(
              item: detail.item,
              itemId: widget.itemId,
              progress: detail.progress,
              onEditMetadata:
                  () =>
                      context.push('/reader/items/${detail.item.id}/metadata'),
              onDelete: _deleteItem,
            );
          }

          final bookAsync = ref.watch(parsedBookProvider(widget.itemId));
          if (bookAsync.isLoading) {
            return AppLoading.detail();
          }
          if (bookAsync.hasError) {
            return AppErrorView(
              message: AppLocalizations.of(context).readerChapterLoadFailed,
              onRetry: () => ref.invalidate(parsedBookProvider(widget.itemId)),
            );
          }

          // 从本地解析获取章节列表（后端不返回章节）
          final parsedBook = bookAsync.asData?.value;
          final effectiveItem = _buildEffectiveItem(detail.item, parsedBook);

          return ReaderDetailTextContent(
            item: effectiveItem,
            progress: detail.progress,
            chapters: parsedBook?.chapters ?? const [],
            bookshelfBusy: _bookshelfBusy,
            onToggleBookshelf: _toggleBookshelf,
            onReadChapter: (chapterId, {required resume}) {
              // 显式选章（目录/书签）进目标章章首（entry=chapter）；
              // 继续阅读不传 entry，走续读恢复（resume 意图）。
              context.push(
                '/reader/items/${detail.item.id}/chapters/$chapterId'
                '${resume ? '' : '?entry=chapter'}',
              );
            },
            onEditMetadata:
                () => context.push('/reader/items/${detail.item.id}/metadata'),
            onReparse: _reparse,
            onDelete: _deleteItem,
          );
        },
        error:
            (error, stackTrace) => AppErrorView(
              message: describeUserFacingError(error).message,
              onRetry:
                  () => ref.invalidate(readerItemDetailProvider(widget.itemId)),
            ),
        loading: () => AppLoading.detail(),
      ),
    );
  }

  Future<void> _toggleBookshelf() async {
    setState(() => _bookshelfBusy = true);
    try {
      await ref
          .read(readerCenterControllerProvider.notifier)
          .toggleBookshelf(widget.itemId);
      if (mounted) {
        ref.invalidate(readerItemDetailProvider(widget.itemId));
        ref.invalidate(readerCenterControllerProvider);
      }
    } on Exception {
      if (!mounted) return;
      showReaderSnackBar(
        context,
        AppLocalizations.of(context).readerOperationFailed,
      );
    } finally {
      if (mounted) {
        setState(() => _bookshelfBusy = false);
      }
    }
  }

  Future<void> _reparse() async {
    try {
      await ref
          .read(readerCenterControllerProvider.notifier)
          .reparseItem(widget.itemId);
      if (mounted) {
        ref.invalidate(readerItemDetailProvider(widget.itemId));
      }
    } on Exception {
      if (!mounted) return;
      showReaderSnackBar(
        context,
        AppLocalizations.of(context).readerOperationFailed,
      );
    }
  }

  Future<void> _deleteItem() async {
    final itemTitle =
        ref
            .read(readerItemDetailProvider(widget.itemId))
            .asData
            ?.value
            .item
            .title ??
        '';
    try {
      await ref
          .read(readerCenterControllerProvider.notifier)
          .deleteItem(widget.itemId);
      if (!mounted) return;
      showReaderSnackBar(
        context,
        AppLocalizations.of(context).readerDeletedItem(itemTitle),
      );
      context.go('/reader');
    } on Exception {
      if (!mounted) return;
      showReaderSnackBar(
        context,
        AppLocalizations.of(context).readerDeleteItemFailed,
      );
    }
  }

  /// 使用解析的元数据覆盖 API 数据（如果 API 数据是临时文件名）
  ReaderItem _buildEffectiveItem(ReaderItem apiItem, ParsedBook? parsedBook) {
    if (parsedBook == null) return apiItem;

    final parsedTitle = parsedBook.title;
    final parsedAuthor = parsedBook.author;
    final needsTitleUpdate =
        parsedTitle != null &&
        parsedTitle.isNotEmpty &&
        parsedTitle != apiItem.title;
    final needsAuthorUpdate =
        parsedAuthor != null &&
        parsedAuthor.isNotEmpty &&
        apiItem.authorName == null;

    if (!needsTitleUpdate && !needsAuthorUpdate) return apiItem;

    return ReaderItem(
      id: apiItem.id,
      createdAt: apiItem.createdAt,
      fileNodeId: apiItem.fileNodeId,
      itemType: apiItem.itemType,
      title: needsTitleUpdate ? parsedTitle : apiItem.title,
      authorName: needsAuthorUpdate ? parsedAuthor : apiItem.authorName,
      coverUrl: apiItem.coverUrl,
      description: apiItem.description,
      publisher: apiItem.publisher,
      language: apiItem.language,
      rating: apiItem.rating,
      progressPercent: apiItem.progressPercent,
      updatedAt: apiItem.updatedAt,
      addedToBookshelf: apiItem.addedToBookshelf,
      spaceType: apiItem.spaceType,
      currentChapterTitle: apiItem.currentChapterTitle,
      metadataStatus: apiItem.metadataStatus,
      releaseDate: apiItem.releaseDate,
      genres: apiItem.genres,
      serialStatus: apiItem.serialStatus,
      contentKind: apiItem.contentKind,
      importStatus: apiItem.importStatus,
      parseErrorCode: apiItem.parseErrorCode,
      parseErrorMessage: apiItem.parseErrorMessage,
    );
  }
}

/// PDF 详情：无服务端章节清单，直接进入客户端渲染阅读器。
class _PdfDetailContent extends StatelessWidget {
  const _PdfDetailContent({
    required this.item,
    required this.progress,
    required this.bookshelfBusy,
    required this.onToggleBookshelf,
    required this.onRead,
    required this.onEditMetadata,
    required this.onDelete,
  });

  final ReaderItem item;
  final ReaderProgress? progress;
  final bool bookshelfBusy;
  final VoidCallback onToggleBookshelf;
  final VoidCallback onRead;
  final VoidCallback onEditMetadata;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final percent =
        ((progress?.progressPercent ?? 0) * 100).clamp(0, 100).toDouble();
    // 内容较短，随骨架滚动体滚动；不自带 ListView 以免嵌套滚动。
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(item.title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            '${readerTypeLabel(l10n, item.itemType)}'
            '${item.authorName == null ? '' : ' · ${item.authorName}'}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(value: percent / 100),
          const SizedBox(height: 8),
          Text(readerProgressLabelText(l10n, percent)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onRead,
            icon: const Icon(Icons.menu_book_outlined),
            label: Text(l10n.readerPdfTitle),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: bookshelfBusy ? null : onToggleBookshelf,
            icon: Icon(
              item.addedToBookshelf
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_add_rounded,
            ),
            label: Text(
              item.addedToBookshelf
                  ? l10n.readerAddedToBookshelf
                  : l10n.readerAddToBookshelf,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: onEditMetadata,
            child: Text(l10n.readerEditMetadata),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => _confirmDelete(context),
            child: Text(l10n.readerDeleteBook),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(l10n.readerConfirmDelete),
            content: Text(l10n.readerConfirmDeleteMsg(item.title)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(l10n.coreCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(dialogContext).colorScheme.error,
                ),
                child: Text(l10n.filesDelete),
              ),
            ],
          ),
    );
    if (!context.mounted || confirmed != true) {
      return;
    }
    onDelete();
  }
}

/// 漫画详情包装器 — 加载清单后将目录节点传递给 ComicDetailPage。
class _ComicDetailWrapper extends ConsumerWidget {
  const _ComicDetailWrapper({
    required this.item,
    required this.itemId,
    this.progress,
    this.onEditMetadata,
    this.onDelete,
  });

  final ReaderItem item;
  final String itemId;
  final ReaderProgress? progress;
  final VoidCallback? onEditMetadata;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monitor = ref.watch(comicManifestMonitorProvider(itemId));
    final manifest = monitor.asData?.value.manifest;
    if (manifest == null && monitor.asData?.value.refreshError == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (manifest == null) {
      return AppErrorView(
        message: AppLocalizations.of(context).readerRefreshFailed,
        onRetry: () => ref.invalidate(comicManifestMonitorProvider(itemId)),
      );
    }
    final terminal =
        manifest.importStatus != ReaderImportStatus.pending &&
        manifest.importStatus != ReaderImportStatus.parsing;
    if (terminal && item.isParsing) {
      // 后端已终态而本地解析标志未跟上：限流兜底刷新一次，避免以
      // 网络往返为周期的零间隔隐式轮询。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Timer(const Duration(milliseconds: 500), () {
          if (context.mounted) {
            ref.invalidate(readerItemDetailProvider(itemId));
          }
        });
      });
    }
    // 外层详情页已提供 ReaderPageScaffold（页头/滚动/材质）；
    // 此处再嵌一层会在无界约束下产生嵌套 Scaffold 布局错误。
    return ComicDetailPage(
      item: item,
      chapters: manifest.catalog,
      pages: manifest.pages,
      sources: manifest.sources,
      progress: progress,
      canRead: manifest.pages.isNotEmpty,
      parseProgress: manifest.parseTask?.progress,
      onRetrySource: (source) => _retryComicSource(context, ref, source),
      onDeleteSource: (source) => _deleteComicSource(context, ref, source),
      onEditMetadata: onEditMetadata,
      onDelete: onDelete,
    );
  }

  Future<bool> _retryComicSource(
    BuildContext context,
    WidgetRef ref,
    ComicSource source,
  ) async {
    final ok = await ref
        .read(readerComicServiceProvider)
        .retrySource(itemId, source.id);
    if (ok && context.mounted) {
      ref.invalidate(comicManifestMonitorProvider(itemId));
    }
    return ok;
  }

  Future<bool> _deleteComicSource(
    BuildContext context,
    WidgetRef ref,
    ComicSource source,
  ) async {
    try {
      await ref
          .read(readerComicServiceProvider)
          .deleteSource(itemId, source.id);
      if (!context.mounted) {
        return true;
      }
      ref.invalidate(comicManifestMonitorProvider(itemId));
      ref.invalidate(readerItemDetailProvider(itemId));
      await ref.read(comicManifestMonitorProvider(itemId).future);
      return true;
    } on Exception {
      return false;
    }
  }
}

/// 详情页固定页头返回条：通栏底边框，点击区域仅按钮内容。
class _DetailBackBar extends StatelessWidget {
  const _DetailBackBar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rc = context.readerColors;
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: rc.outlineVariant)),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 48,
            padding: EdgeInsets.symmetric(
              horizontal: MediaQuery.sizeOf(context).width >= 1024 ? 32 : 24,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.arrow_back_rounded,
                  size: 16,
                  color: rc.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.coreBack,
                  style: TextStyle(
                    color: rc.onSurfaceVariant,
                    fontSize: AppTypography.bodyMedium,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
