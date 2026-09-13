import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/reader_colors.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/application/reader_book_provider.dart';
import 'package:omninest/features/reader/application/reader_comic_image_provider.dart';
import 'package:omninest/features/reader/application/reader_comic_service.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/pages/comic_import_confirm_page.dart';
import 'package:omninest/features/reader/presentation/reader_l10n_helpers.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_empty_state.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_snack_bar.dart';

/// 待导入候选文件列表。
class ImportSection extends ConsumerStatefulWidget {
  const ImportSection({required this.onImported, super.key});

  final VoidCallback onImported;

  @override
  ConsumerState<ImportSection> createState() => _ImportSectionState();
}

class _ImportSectionState extends ConsumerState<ImportSection> {
  final Set<String> _importing = {};
  final Map<String, String> _contentKindOverrides = {};

  List<ReaderImportCandidate> _candidates = [];

  @override
  void initState() {
    super.initState();
    _loadCandidates();
  }

  Future<void> _loadCandidates() async {
    try {
      final candidates =
          await ref
              .read(readerCenterControllerProvider.notifier)
              .importCandidates();
      if (mounted) {
        setState(() => _candidates = candidates);
      }
    } on Exception {
      // 加载失败时保持空列表
    }
  }

  @override
  Widget build(BuildContext context) {
    final candidates = _candidates;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              AppLocalizations.of(context).readerPendingImport.toUpperCase(),
              style: TextStyle(
                color: context.readerColors.onSurfaceVariant,
                fontSize: 10,
                height: 1.2,
                letterSpacing: 2.4,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${candidates.length}',
              style: TextStyle(
                color: context.readerColors.onSurfaceVariant,
                fontSize: 10,
                height: 1.2,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (candidates.isEmpty)
          Column(
            children: [
              Icon(
                Icons.upload_file_outlined,
                size: 32,
                color: context.readerColors.onSurfaceVariant.withValues(
                  alpha: 0.4,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                AppLocalizations.of(context).readerNoPendingImport,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.readerColors.onSurfaceVariant,
                  fontSize: AppTypography.bodyMedium,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                AppLocalizations.of(context).readerNoPendingImportHint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.readerColors.onSurfaceVariant.withValues(
                    alpha: 0.7,
                  ),
                  fontSize: AppTypography.labelSmall,
                ),
              ),
            ],
          )
        else
          ...candidates.map(
            (candidate) => CandidateTile(
              candidate: candidate,
              selectedType:
                  _contentKindOverrides[candidate.fileNodeId] ??
                  _defaultContentKind(candidate),
              importing: _importing.contains(candidate.fileNodeId),
              onTypeChanged:
                  _isAmbiguousType(candidate)
                      ? (type) => setState(
                        () =>
                            _contentKindOverrides[candidate.fileNodeId] = type,
                      )
                      : null,
              onImport: () => _doImport(candidate),
            ),
          ),
      ],
    );
  }

  bool _isAmbiguousType(ReaderImportCandidate candidate) {
    final ext = candidate.fileName.toLowerCase();
    return ext.endsWith('.epub');
  }

  Future<void> _doImport(ReaderImportCandidate candidate) async {
    setState(() => _importing.add(candidate.fileNodeId));
    try {
      final item = await ref
          .read(readerCenterControllerProvider.notifier)
          .importFile(
            fileNodeId: candidate.fileNodeId,
            contentKindOverride: _selectedContentKind(candidate),
          );
      if (!mounted) {
        return;
      }
      startBackgroundBookPreparation(ref, item);
      if (item.isComic) {
        await _openComicImportConfirm(item: item, fileName: candidate.fileName);
      }
      if (mounted) {
        showReaderSnackBar(
          context,
          AppLocalizations.of(context).readerImportSuccess(candidate.fileName),
        );
        widget.onImported();
      }
    } on Exception {
      if (mounted) {
        showReaderSnackBar(
          context,
          AppLocalizations.of(context).readerImportFailed,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _importing.remove(candidate.fileNodeId));
      }
    }
  }

  String _selectedContentKind(ReaderImportCandidate candidate) {
    return _contentKindOverrides[candidate.fileNodeId] ??
        _defaultContentKind(candidate);
  }

  String _defaultContentKind(ReaderImportCandidate candidate) {
    return switch (candidate.itemType.toUpperCase()) {
      'CBZ' || 'ZIP' => 'COMIC',
      _ => 'TEXT',
    };
  }

  Future<void> _openComicImportConfirm({
    required ReaderItem item,
    required String fileName,
  }) async {
    ComicManifest manifest;
    try {
      manifest = await ref
          .read(readerComicServiceProvider)
          .loadManifest(item.id);
    } on Exception {
      manifest = ComicManifest(
        itemId: item.id,
        sources: const [],
        catalog: const [],
        pages: const [],
        importStatus: item.importStatus ?? 'PARSING',
      );
    }
    if (!mounted) {
      return;
    }
    await context.push<bool>(
      '/reader/items/${item.id}/import-status',
      extra: ComicImportConfirmArgs(manifest: manifest, fileName: fileName),
    );
  }
}

/// 单个导入候选文件卡片。
class CandidateTile extends StatelessWidget {
  const CandidateTile({
    required this.candidate,
    required this.selectedType,
    required this.importing,
    required this.onImport,
    this.onTypeChanged,
    super.key,
  });

  final ReaderImportCandidate candidate;
  final String selectedType;
  final bool importing;
  final VoidCallback onImport;
  final ValueChanged<String>? onTypeChanged;

  @override
  Widget build(BuildContext context) {
    final rc = context.readerColors;
    final l10n = AppLocalizations.of(context);
    final isEpub = candidate.itemType.toUpperCase() == 'EPUB';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(
            candidateFileTypeIcon(candidate.itemType),
            size: 18,
            color: rc.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  candidate.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: rc.onSurface,
                    fontSize: 14,
                    height: 1.3,
                    fontFamily: kReaderSerifFamily,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      candidate.sizeDisplay,
                      style: TextStyle(
                        color: rc.onSurfaceVariant,
                        fontSize: 10,
                        height: 1.2,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: rc.outlineVariant),
                      ),
                      child: Text(
                        candidate.itemType.toUpperCase(),
                        style: TextStyle(
                          color: rc.onSurfaceVariant,
                          fontSize: 9,
                          height: 1.2,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (isEpub)
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: rc.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final kind in const ['TEXT', 'COMIC'])
                    InkWell(
                      onTap: importing ? null : () => onTypeChanged!(kind),
                      child: Container(
                        height: 24,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color:
                              selectedType == kind
                                  ? rc.sidebarSelectedBg
                                  : Colors.transparent,
                          border: Border(
                            right:
                                kind == 'TEXT'
                                    ? BorderSide(color: rc.outlineVariant)
                                    : BorderSide.none,
                          ),
                        ),
                        child: Text(
                          kind == 'COMIC'
                              ? l10n.readerSegmentComics
                              : l10n.readerSegmentBooks,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.2,
                            color:
                                selectedType == kind
                                    ? rc.sidebarSelectedFg
                                    : rc.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            )
          else
            Text(
              l10n.readerSegmentBooks,
              style: TextStyle(
                color: rc.onSurfaceVariant,
                fontSize: 9,
                height: 1.2,
              ),
            ),
          const SizedBox(width: 12),
          InkWell(
            onTap: importing ? null : onImport,
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(
                  color: importing ? rc.outlineVariant : rc.onSurfaceVariant,
                ),
              ),
              alignment: Alignment.center,
              child:
                  importing
                      ? SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: rc.onSurfaceVariant,
                        ),
                      )
                      : Text(
                        l10n.filesImport,
                        style: TextStyle(
                          color: importing ? rc.onSurfaceVariant : rc.onSurface,
                          fontSize: 11,
                          height: 1.2,
                        ),
                      ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 按文件类型返回候选行图标。
IconData candidateFileTypeIcon(String itemType) {
  return switch (itemType.toUpperCase()) {
    'TXT' => Icons.description_outlined,
    'CBZ' || 'ZIP' => Icons.archive_outlined,
    'PDF' => Icons.picture_as_pdf_outlined,
    _ => Icons.import_contacts_outlined,
  };
}

/// 重新解析区域 — 允许重新导入已有的阅读器条目。
class ReparseSection extends ConsumerStatefulWidget {
  const ReparseSection({
    required this.items,
    required this.onReparsed,
    super.key,
  });

  final List<ReaderItem> items;
  final VoidCallback onReparsed;

  @override
  ConsumerState<ReparseSection> createState() => _ReparseSectionState();
}

class _ReparseSectionState extends ConsumerState<ReparseSection> {
  final Set<String> _reparsing = {};

  @override
  Widget build(BuildContext context) {
    final items = widget.items;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              AppLocalizations.of(context).readerReparse,
              style: TextStyle(
                color: context.readerColors.onSurface,
                fontSize: AppTypography.titleLarge,
                height: 24 / 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(width: 12),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: context.readerColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                AppLocalizations.of(context).readerBookCount(items.length),
                style: TextStyle(
                  color: context.readerColors.onSurfaceVariant,
                  fontSize: AppTypography.labelSmall,
                  height: 14 / 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        Text(
          AppLocalizations.of(context).readerReparseDesc,
          style: TextStyle(
            color: context.readerColors.onSurfaceVariant.withValues(alpha: 0.8),
            fontSize: AppTypography.bodyMedium,
            height: 18 / 13,
          ),
        ),
        const SizedBox(height: 20),
        if (items.isEmpty)
          ReaderEmptyState(
            title: AppLocalizations.of(context).readerNoImportedContent,
            subtitle: AppLocalizations.of(context).readerNoImportedContentHint,
            icon: Icons.refresh_rounded,
          )
        else
          ...items.map(
            (item) => _ReparseTile(
              item: item,
              reparsing: _reparsing.contains(item.id),
              onReparse: () => _doReparse(item),
            ),
          ),
      ],
    );
  }

  Future<void> _doReparse(ReaderItem item) async {
    final fileNodeId = item.fileNodeId;
    if (fileNodeId == null || fileNodeId.isEmpty) {
      if (mounted) {
        showReaderSnackBar(
          context,
          AppLocalizations.of(context).readerNoFileNode,
        );
      }
      return;
    }
    setState(() => _reparsing.add(item.id));
    try {
      await invalidateBookCache(ref, item.id);
      if (!mounted) {
        return;
      }
      ref.read(comicImageLoaderProvider).invalidate(item.id);
      await ref
          .read(readerCenterControllerProvider.notifier)
          .reparseItem(item.id);
      if (!mounted) {
        return;
      }
      showReaderSnackBar(
        context,
        item.isComic
            ? AppLocalizations.of(context).readerComicReparseStarted(item.title)
            : AppLocalizations.of(context).readerReparseSuccess(item.title),
      );
      widget.onReparsed();
    } on Exception {
      if (mounted) {
        showReaderSnackBar(
          context,
          AppLocalizations.of(context).readerReparseFailed,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _reparsing.remove(item.id));
      }
    }
  }
}

class _ReparseTile extends StatelessWidget {
  const _ReparseTile({
    required this.item,
    required this.reparsing,
    required this.onReparse,
  });

  final ReaderItem item;
  final bool reparsing;
  final VoidCallback onReparse;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: context.readerColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: context.readerColors.outlineVariant.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.menu_book_rounded,
            color: context.readerColors.onSurfaceVariant,
            size: 22,
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.readerColors.onSurface,
                    fontSize: AppTypography.bodyLarge,
                    height: 18 / 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  '${readerTypeLabel(AppLocalizations.of(context), item.itemType)}  ·  ${item.authorName ?? AppLocalizations.of(context).readerUnknownAuthor}',
                  style: TextStyle(
                    color: context.readerColors.onSurfaceVariant,
                    fontSize: AppTypography.bodySmall,
                    height: 16 / 12,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 12),
          SizedBox(
            width: 80,
            height: 36,
            child: OutlinedButton(
              onPressed: reparsing ? null : onReparse,
              style: OutlinedButton.styleFrom(
                foregroundColor: context.readerColors.primary,
                side: BorderSide(
                  color: context.readerColors.primary.withValues(alpha: 0.45),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: EdgeInsets.zero,
              ),
              child:
                  reparsing
                      ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.readerColors.primary,
                        ),
                      )
                      : Text(
                        AppLocalizations.of(context).readerReparse,
                        style: const TextStyle(
                          fontSize: AppTypography.bodyMedium,
                        ),
                      ),
            ),
          ),
        ],
      ),
    );
  }
}
