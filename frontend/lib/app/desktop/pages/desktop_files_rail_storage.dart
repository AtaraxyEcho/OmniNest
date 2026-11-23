part of 'desktop_files_page.dart';

/// 轨道底部存储分布条 + 图例（个人空间与共享空间共用）。
class _StorageDistributionBody extends StatelessWidget {
  const _StorageDistributionBody({
    required this.typeDistribution,
    required this.fallbackRatio,
    required this.footerText,
    required this.footerColor,
  });

  final List<FileTypeStats> typeDistribution;
  final double fallbackRatio;
  final String footerText;
  final Color footerColor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final types = typeDistribution.take(3).toList(growable: false);
    final remainingBytes = typeDistribution
        .skip(3)
        .fold<int>(0, (sum, entry) => sum + entry.sizeBytes);
    final segments = <({String label, int bytes, Color color})>[
      for (var index = 0; index < types.length; index++)
        (
          label: _categoryLabel(l10n, types[index].category),
          bytes: types[index].sizeBytes,
          color: switch (index) {
            0 => skin.accent,
            1 => skin.info,
            _ => skin.warn,
          },
        ),
      if (remainingBytes > 0)
        (
          label: l10n.filesCategoryOther,
          bytes: remainingBytes,
          color: skin.text3,
        ),
    ];
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 4),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: skin.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.desktopFilesGroupStorage.toUpperCase(),
            style: DesktopType.eyebrow(skin.text3),
          ),
          const SizedBox(height: 10),
          if (segments.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 8,
                child: Row(
                  children: [
                    for (var index = 0; index < segments.length; index++) ...[
                      if (index > 0) const SizedBox(width: 2),
                      Expanded(
                        flex: segments[index].bytes.clamp(1, 0x7fffffff),
                        child: ColoredBox(color: segments[index].color),
                      ),
                    ],
                  ],
                ),
              ),
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 8,
                child: Stack(
                  children: [
                    Positioned.fill(child: ColoredBox(color: skin.raise2)),
                    FractionallySizedBox(
                      widthFactor: fallbackRatio,
                      child: ColoredBox(color: skin.accent),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 10),
          for (final segment in segments)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: segment.color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      segment.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesktopType.nano(skin.text2),
                    ),
                  ),
                  Text(
                    formatFileSize(segment.bytes),
                    style: DesktopType.nano(skin.text3),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 3),
          Text(footerText, style: DesktopType.caption(footerColor)),
        ],
      ),
    );
  }

  String _categoryLabel(AppLocalizations l10n, String category) =>
      switch (category.toUpperCase()) {
        'FOLDER' => l10n.filesCategoryFolder,
        'IMAGE' || 'PHOTO' => l10n.filesCategoryImage,
        'VIDEO' => l10n.filesCategoryVideo,
        'AUDIO' => l10n.filesCategoryAudio,
        'DOCUMENT' || 'PDF' || 'TEXT' => l10n.filesCategoryDocument,
        'NOVEL' => l10n.filesCategoryNovel,
        'COMIC' => l10n.filesCategoryComic,
        'ARCHIVE' => l10n.filesCategoryArchive,
        _ => l10n.filesCategoryOther,
      };
}

class _RailStorageCard extends StatelessWidget {
  const _RailStorageCard({required this.stats});

  final FileStorageStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    return _StorageDistributionBody(
      typeDistribution: stats.typeDistribution,
      fallbackRatio: stats.usageRatio,
      footerText: l10n.desktopFilesStorageUsed(
        formatFileSize(stats.usedBytes),
        stats.isQuotaUnlimited
            ? l10n.filesUnlimited
            : formatFileSize(stats.quotaBytes),
      ),
      footerColor: skin.text3,
    );
  }
}

class _RailSharedStorageCard extends StatelessWidget {
  const _RailSharedStorageCard({required this.usage});

  final SharedSpaceUsage usage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final capacity =
        usage.isUnlimited
            ? l10n.filesSharedSpaceUnlimited
            : formatFileSize(usage.maxBytes);
    return _StorageDistributionBody(
      typeDistribution: usage.typeDistribution,
      fallbackRatio: usage.usageRatio,
      footerText: l10n.filesSharedSpaceInfo(
        formatFileSize(usage.usedBytes),
        capacity,
        usage.fileCount,
      ),
      footerColor: skin.text2,
    );
  }
}

/// 冷启动存储统计尚未就绪时的等高轻骨架占位，防止底部存储卡晚到引起侧栏跳动。
class _RailStorageSkeleton extends StatelessWidget {
  const _RailStorageSkeleton();

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return ExcludeSemantics(
      child: Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 4),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: skin.line)),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: DesktopSkeletonBox(width: 68, height: 10, radius: 4),
            ),
            SizedBox(height: 10),
            DesktopSkeletonBox(width: double.infinity, height: 8, radius: 8),
            SizedBox(height: 10),
            Row(
              children: [
                DesktopSkeletonBox(width: 8, height: 8, radius: 3),
                SizedBox(width: 8),
                Expanded(
                  child: DesktopSkeletonBox(
                    width: double.infinity,
                    height: 10,
                    radius: 4,
                  ),
                ),
                SizedBox(width: 12),
                DesktopSkeletonBox(width: 38, height: 10, radius: 4),
              ],
            ),
            SizedBox(height: 7),
            Row(
              children: [
                DesktopSkeletonBox(width: 8, height: 8, radius: 3),
                SizedBox(width: 8),
                Expanded(
                  child: DesktopSkeletonBox(
                    width: double.infinity,
                    height: 10,
                    radius: 4,
                  ),
                ),
                SizedBox(width: 12),
                DesktopSkeletonBox(width: 34, height: 10, radius: 4),
              ],
            ),
            SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: DesktopSkeletonBox(width: 112, height: 11, radius: 4),
            ),
          ],
        ),
      ),
    );
  }
}
