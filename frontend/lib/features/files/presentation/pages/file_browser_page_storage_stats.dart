part of 'file_browser_page.dart';

/// 托管态存储统计：原型 `.feature-page` + `.storage-*` 语言的移动版。
///
/// 三格摘要取真实计数，配额与类型分布用 3px 占比条 + 百分比状态丸。稿子里的
/// 14 天增长柱与重复文件清理卡没有对应数据源，因此不实现，避免做出假数据。
class _HostedStorageStatsPage extends ConsumerWidget {
  const _HostedStorageStatsPage({required this.stats});

  final FileStorageStats? stats;

  static FileBrowserFileCategory _categoryOf(String category) {
    return switch (category.toUpperCase()) {
      'IMAGE' => FileBrowserFileCategory.image,
      'VIDEO' => FileBrowserFileCategory.video,
      'AUDIO' => FileBrowserFileCategory.audio,
      'DOCUMENT' => FileBrowserFileCategory.document,
      'NOVEL' => FileBrowserFileCategory.novel,
      'COMIC' => FileBrowserFileCategory.comic,
      'ARCHIVE' => FileBrowserFileCategory.archive,
      _ => FileBrowserFileCategory.other,
    };
  }

  static MobileStatusTone _quotaTone(String status) {
    return switch (status.toUpperCase()) {
      'EXCEEDED' || 'OVER' => MobileStatusTone.danger,
      'WARNING' || 'NEAR_LIMIT' => MobileStatusTone.warning,
      _ => MobileStatusTone.calm,
    };
  }

  void _retry(WidgetRef ref) {
    unawaited(
      ref
          .read(fileBrowserControllerProvider.notifier)
          .loadSection(FileManagerSection.storageStats),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final current = stats;
    if (current == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HostedSectionMetaRow(text: l10n.filesStorageStatsDesc),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: EnvEmptyState(
              icon: OmniIcons.cloud,
              title: l10n.filesStorageEmptyTitle,
              message: l10n.filesStorageEmptyMessage,
              actionLabel: l10n.filesStorageRetry,
              onAction: () => _retry(ref),
            ),
          ),
        ],
      );
    }

    final usedBytes = current.usedBytes;
    final types = [...current.typeDistribution]
      ..sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HostedSectionMetaRow(
          text:
              current.isQuotaUnlimited
                  ? l10n.filesStorageQuotaUnlimited
                  : l10n.filesStorageQuotaLine(
                    formatFileSize(usedBytes),
                    formatFileSize(current.quotaBytes),
                  ),
          action:
              current.isQuotaUnlimited
                  ? null
                  : MobileStatusPill(
                    label: current.quotaStatus,
                    tone: _quotaTone(current.quotaStatus),
                  ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MobileTransferSummary(
                entries: [
                  MobileTransferSummaryEntry(
                    value: '${current.totalFiles}',
                    label: l10n.filesStorageSummaryFiles,
                  ),
                  MobileTransferSummaryEntry(
                    value: '${current.totalFolders}',
                    label: l10n.filesStorageSummaryFolders,
                  ),
                  MobileTransferSummaryEntry(
                    value: formatFileSize(usedBytes),
                    label: l10n.filesStorageSummaryUsed,
                  ),
                ],
              ),
              if (!current.isQuotaUnlimited) ...[
                const SizedBox(height: 14),
                MobileTransferRow(
                  icon: OmniIcons.cloud,
                  title: l10n.filesStorageQuotaTitle,
                  detail:
                      '${formatFileSize(usedBytes)} / '
                      '${formatFileSize(current.quotaBytes)}',
                  progress: current.usageRatio,
                  statusLabel: '${(current.usageRatio * 100).round()}%',
                ),
              ],
              if (types.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 20, 0, 6),
                  child: Text(
                    l10n.filesStorageTypeDistribution.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 9, // ignore: font_size_whitelist
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w700,
                      color: MobileEnvColors.inkFaint,
                    ),
                  ),
                ),
                for (final type in types)
                  MobileTransferRow(
                    icon: _categoryOf(type.category).omniIcon,
                    title: _categoryOf(type.category).labelOf(l10n),
                    detail:
                        '${type.count} · '
                        '${formatFileSize(type.sizeBytes)}',
                    progress: usedBytes <= 0 ? 0.0 : type.sizeBytes / usedBytes,
                    statusLabel:
                        '${usedBytes <= 0 ? 0 : ((type.sizeBytes / usedBytes) * 100).round()}%',
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

extension _FileBrowserFileCategoryOmniIcon on FileBrowserFileCategory {
  /// 类型分布行用稿子同源的手绘描边图标，避免混入 Material 图标。
  OmniIconsData get omniIcon {
    return switch (this) {
      FileBrowserFileCategory.image => OmniIcons.image,
      FileBrowserFileCategory.video => OmniIcons.film,
      FileBrowserFileCategory.audio => OmniIcons.music,
      FileBrowserFileCategory.document ||
      FileBrowserFileCategory.novel ||
      FileBrowserFileCategory.comic => OmniIcons.book,
      FileBrowserFileCategory.archive => OmniIcons.folder,
      _ => OmniIcons.grid,
    };
  }
}
