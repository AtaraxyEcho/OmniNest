import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/navigation/navigation_extensions.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/reader/application/reader_comic_image_provider.dart';
import 'package:omninest/features/reader/application/reader_comic_service.dart';
import 'package:omninest/features/reader/domain/comic_models.dart';
import 'package:omninest/features/reader/presentation/widgets/comic_catalog_tree.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_snack_bar.dart';

/// 漫画导入解析状态页。
///
/// 展示异步解析结果和当前清单快照。
class ComicImportConfirmPage extends ConsumerStatefulWidget {
  const ComicImportConfirmPage({
    required this.itemId,
    required this.manifest,
    required this.fileName,
    super.key,
  });

  final String itemId;
  final ComicManifest manifest;
  final String fileName;

  @override
  ConsumerState<ComicImportConfirmPage> createState() =>
      _ComicImportConfirmPageState();
}

/// 漫画导入状态路由携带的初始清单。
@immutable
class ComicImportConfirmArgs {
  const ComicImportConfirmArgs({
    required this.manifest,
    required this.fileName,
  });

  final ComicManifest manifest;
  final String fileName;
}

class _ComicImportConfirmPageState
    extends ConsumerState<ComicImportConfirmPage> {
  bool _isRefreshing = false;
  late ComicManifest _manifest;

  @override
  void initState() {
    super.initState();
    _manifest = widget.manifest;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(comicManifestMonitorProvider(widget.itemId), (_, next) {
      final manifest = next.asData?.value.manifest;
      if (manifest == null || identical(manifest, _manifest)) {
        return;
      }
      setState(() => _manifest = manifest);
    });
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).readerComicImportStatusTitle),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSummary(),
            const SizedBox(height: 24),
            _buildCatalogPreview(),
            const SizedBox(height: 24),
            _buildPagePreview(),
            const SizedBox(height: 32),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  /// 汇总信息。
  Widget _buildSummary() {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.fileName,
              style: const TextStyle(
                fontSize: AppTypography.titleMedium,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _SummaryChip(
                  icon: Icons.source,
                  label: l10n.readerComicSourceCount(_manifest.sources.length),
                ),
                _SummaryChip(
                  icon: Icons.folder_outlined,
                  label: l10n.readerComicCatalogCount(_manifest.catalog.length),
                ),
                _SummaryChip(
                  icon: Icons.image_outlined,
                  label: l10n.readerPageCount(_manifest.totalPages),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              l10n.readerComicImportStatusValue(
                _localizedImportStatus(l10n, _manifest.importStatus),
              ),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (_manifest.parseTask case final task?) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(value: task.progress / 100),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${task.progress}%',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 目录预览。
  Widget _buildCatalogPreview() {
    if (_manifest.catalog.isEmpty) {
      return _EmptyInfo(
        icon: Icons.folder_off_outlined,
        text: AppLocalizations.of(context).readerComicCatalogPending,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context).readerComicCatalogPreview,
          style: const TextStyle(
            fontSize: AppTypography.titleLarge,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ComicCatalogTree(
            nodes: _manifest.catalog,
            pages: _manifest.pages,
            sources: _manifest.sources,
            shrinkWrap: true,
            onNodeTap: (_) {},
          ),
        ),
      ],
    );
  }

  /// 页面预览（前几页缩略图）。
  Widget _buildPagePreview() {
    final previewPages = _manifest.pages.take(6).toList();
    if (previewPages.isEmpty) {
      return _EmptyInfo(
        icon: Icons.image_not_supported_outlined,
        text: AppLocalizations.of(context).readerComicPagesPending,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context).readerComicPagePreview,
          style: const TextStyle(
            fontSize: AppTypography.titleLarge,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 0.7,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: previewPages.length,
          itemBuilder: (context, index) {
            final page = previewPages[index];
            return Card(
              clipBehavior: Clip.antiAlias,
              child: _ComicPageThumbnail(itemId: widget.itemId, page: page),
            );
          },
        ),
      ],
    );
  }

  /// 操作按钮。
  Widget _buildActions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _isRefreshing ? null : _refreshManifest,
            child: Text(AppLocalizations.of(context).readerRefresh),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: FilledButton(
            onPressed:
                _isRefreshing
                    ? null
                    : () => context.popOrGo('/reader/items/${widget.itemId}'),
            child:
                _isRefreshing
                    ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : Text(AppLocalizations.of(context).readerDone),
          ),
        ),
      ],
    );
  }

  Future<void> _refreshManifest({bool silent = false}) async {
    if (silent) {
      _isRefreshing = true;
    } else {
      setState(() => _isRefreshing = true);
    }
    ComicManifest? refreshedManifest;
    try {
      refreshedManifest = await ref
          .read(readerComicServiceProvider)
          .loadManifest(widget.itemId);
    } catch (e) {
      if (mounted && !silent) {
        showReaderSnackBar(
          context,
          AppLocalizations.of(context).readerRefreshFailed,
        );
      }
    } finally {
      if (mounted) {
        if (silent && refreshedManifest == null) {
          _isRefreshing = false;
        } else {
          setState(() {
            if (refreshedManifest != null) {
              _manifest = refreshedManifest;
            }
            _isRefreshing = false;
          });
        }
      }
    }
  }

  String _localizedImportStatus(AppLocalizations l10n, String status) {
    return switch (status.toUpperCase()) {
      'PENDING' => l10n.readerComicImportPending,
      'PARSING' => l10n.readerComicImportParsing,
      'PARTIAL_FAILED' => l10n.readerComicImportPartialFailed,
      'FAILED' => l10n.readerComicImportFailed,
      _ => l10n.readerComicImportReady,
    };
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _ComicPageThumbnail extends ConsumerWidget {
  const _ComicPageThumbnail({required this.itemId, required this.page});

  final String itemId;
  final ComicPage page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder(
      future: ref
          .read(comicImageLoaderProvider)
          .getImage(itemId, page.sourcePath, pageId: page.id),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return Container(
            color: Colors.black12,
            alignment: Alignment.center,
            child: Text(
              l10n.readerPageNumber(page.pageIndex + 1),
              style: Theme.of(context).textTheme.labelSmall,
              textAlign: TextAlign.center,
            ),
          );
        }
        return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
      },
    );
  }
}

class _EmptyInfo extends StatelessWidget {
  const _EmptyInfo({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}
