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
          children: [
            Text(
              AppLocalizations.of(context).readerPendingImport,
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
                AppLocalizations.of(
                  context,
                ).readerPendingImportCount(candidates.length),
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
          AppLocalizations.of(context).readerPendingImportDesc,
          style: TextStyle(
            color: context.readerColors.onSurfaceVariant.withValues(alpha: 0.8),
            fontSize: AppTypography.bodyMedium,
            height: 18 / 13,
          ),
        ),
        const SizedBox(height: 20),
        if (candidates.isEmpty)
          ReaderEmptyState(
            title: AppLocalizations.of(context).readerNoPendingImport,
            subtitle: AppLocalizations.of(context).readerNoPendingImportHint,
            icon: Icons.file_upload_outlined,
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
            color: context.readerColors.primary,
            size: 22,
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  candidate.fileName,
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
                Row(
                  children: [
                    if (onTypeChanged != null)
                      Container(
                        height: 24,
                        padding: EdgeInsets.only(left: 8),
                        decoration: BoxDecoration(
                          color: context.readerColors.surfaceContainerHighest
                              .withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: context.readerColors.outlineVariant
                                .withValues(alpha: 0.24),
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedType,
                            isDense: true,
                            icon: Icon(Icons.expand_more_rounded, size: 14),
                            style: TextStyle(
                              color: context.readerColors.onSurfaceVariant,
                              fontSize: AppTypography.labelSmall,
                              fontWeight: FontWeight.w600,
                            ),
                            dropdownColor:
                                context.readerColors.surfaceContainerHigh,
                            items: [
                              DropdownMenuItem(
                                value: 'TEXT',
                                child: Text(
                                  AppLocalizations.of(
                                    context,
                                  ).readerSegmentBooks,
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'COMIC',
                                child: Text(
                                  AppLocalizations.of(
                                    context,
                                  ).readerSegmentComics,
                                ),
                              ),
                            ],
                            onChanged:
                                importing
                                    ? null
                                    : (value) {
                                      if (value != null) onTypeChanged!(value);
                                    },
                          ),
                        ),
                      )
                    else
                      Text(
                        _contentKindLabel(context, selectedType),
                        style: TextStyle(
                          color: context.readerColors.onSurfaceVariant,
                          fontSize: AppTypography.bodySmall,
                          height: 16 / 12,
                        ),
                      ),
                    Text(
                      '  ·  ${candidate.sizeDisplay}',
                      style: TextStyle(
                        color: context.readerColors.onSurfaceVariant,
                        fontSize: AppTypography.bodySmall,
                        height: 16 / 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(width: 12),
          SizedBox(
            width: 80,
            height: 36,
            child: FilledButton(
              onPressed: importing ? null : onImport,
              style: FilledButton.styleFrom(
                backgroundColor: context.readerColors.primaryContainer,
                foregroundColor: context.readerColors.onPrimaryContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: EdgeInsets.zero,
              ),
              child:
                  importing
                      ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.readerColors.onPrimaryContainer,
                        ),
                      )
                      : Text(
                        AppLocalizations.of(context).filesImport,
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

  String _contentKindLabel(BuildContext context, String contentKind) {
    final l10n = AppLocalizations.of(context);
    return switch (contentKind) {
      'COMIC' => l10n.readerSegmentComics,
      _ => l10n.readerSegmentBooks,
    };
  }
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
