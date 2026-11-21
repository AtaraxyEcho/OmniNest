part of 'desktop_settings_page.dart';

class _StorageSection extends ConsumerWidget {
  const _StorageSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(fileStorageStatsProvider);
    return _Card(
      title: l10n.desktopStorageCloudTitle,
      child: state.when(
        data: (stats) => _StorageDistribution(stats: stats),
        error:
            (error, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  errorReason(error, l10n),
                  style: DesktopType.dense(DesktopSkin.of(context).text3),
                ),
                const SizedBox(height: 8),
                DesktopButton(
                  label: l10n.coreRetry,
                  icon: DesktopIcons.restore,
                  variant: DesktopButtonVariant.ghost,
                  onPressed: () => ref.invalidate(fileStorageStatsProvider),
                ),
              ],
            ),
        loading: () => const _StorageDistributionSkeleton(),
      ),
    );
  }
}

class _StorageDistribution extends ConsumerStatefulWidget {
  const _StorageDistribution({required this.stats});

  final FileStorageStats stats;

  @override
  ConsumerState<_StorageDistribution> createState() =>
      _StorageDistributionState();
}

class _StorageDistributionState extends ConsumerState<_StorageDistribution> {
  bool _scanningDuplicates = false;
  int? _hoveredSegmentIndex;

  static Color _color(String category) {
    return switch (category.toUpperCase()) {
      'VIDEO' => DesktopPalette.storageVideo,
      'IMAGE' => DesktopPalette.storagePhotos,
      'AUDIO' => DesktopPalette.storageMusic,
      'DOCUMENT' => DesktopPalette.storageDocuments,
      'NOVEL' || 'COMIC' => DesktopPalette.kindText,
      'ARCHIVE' => DesktopPalette.kindFolder,
      _ => DesktopPalette.kindText,
    };
  }

  String _label(AppLocalizations l10n, String category) {
    return switch (category.toUpperCase()) {
      'VIDEO' => l10n.desktopStorageVideo,
      'IMAGE' => l10n.desktopStoragePhotos,
      'AUDIO' => l10n.desktopStorageMusic,
      _ => l10n.desktopStorageDocuments,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final stats = widget.stats;
    final used = formatFileSize(stats.usedBytes);
    final hasQuota = !stats.isQuotaUnlimited;
    final quotaLabel =
        hasQuota
            ? l10n.desktopStorageUsage(used, formatFileSize(stats.quotaBytes))
            : l10n.desktopStorageNoQuota;
    final categoryBytes = <String, int>{
      'VIDEO': 0,
      'IMAGE': 0,
      'AUDIO': 0,
      'DOCUMENT': 0,
    };
    for (final item in stats.typeDistribution) {
      final category = switch (item.category.toUpperCase()) {
        'VIDEO' => 'VIDEO',
        'IMAGE' => 'IMAGE',
        'AUDIO' => 'AUDIO',
        _ => 'DOCUMENT',
      };
      categoryBytes.update(
        category,
        (bytes) => bytes + item.sizeBytes,
        ifAbsent: () => item.sizeBytes,
      );
    }
    final distributionBytes = categoryBytes.values.fold<int>(
      0,
      (total, bytes) => total + bytes,
    );
    final denominator = math.max(
      hasQuota ? stats.quotaBytes : stats.usedBytes,
      distributionBytes,
    );
    final scale = denominator <= 0 ? 1 : denominator;
    final segments = <({FileTypeStats item, int flex})>[
      for (final entry in categoryBytes.entries)
        (
          item: FileTypeStats(
            category: entry.key,
            count: 0,
            sizeBytes: entry.value,
          ),
          flex:
              entry.value <= 0
                  ? 0
                  : math.max(1, (entry.value / scale * 10000).round()).toInt(),
        ),
    ];
    final segmentFlex = segments.fold<int>(
      0,
      (total, segment) => total + segment.flex,
    );
    final remainingFlex = math.max(0, 10000 - segmentFlex).toInt();
    final chartSegments = <DesktopChartSegment>[
      for (final segment in segments)
        DesktopChartSegment(
          flex: segment.flex,
          color: _color(segment.item.category),
          label: _label(l10n, segment.item.category),
          valueLabel: formatFileSize(segment.item.sizeBytes),
          percentLabel:
              segment.item.sizeBytes <= 0
                  ? null
                  : '${(segment.item.sizeBytes / scale * 100).toStringAsFixed(1)}%',
        ),
    ];
    final animationsDisabled = MediaQuery.disableAnimationsOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(used, style: DesktopType.bigNum(skin.text)),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                quotaLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DesktopType.dense(skin.text3),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        DesktopInteractiveSegmentedBar(
          segments: chartSegments,
          remainingFlex: remainingFlex,
          trackColor: skin.raise3,
          height: 14,
          borderRadius: 8,
          hoveredIndex: _hoveredSegmentIndex,
          onHoverChanged: (index) {
            if (_hoveredSegmentIndex != index) {
              setState(() => _hoveredSegmentIndex = index);
            }
          },
        ),
        if (stats.typeDistribution.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              l10n.desktopStorageNoBreakdown,
              style: DesktopType.caption(skin.text3),
            ),
          )
        else ...[
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final cellWidth = (constraints.maxWidth - 30) / 2;
              return Wrap(
                spacing: 30,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < segments.length; i++)
                    SizedBox(
                      width: cellWidth,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.basic,
                        onEnter: (_) {
                          if (segments[i].flex > 0 &&
                              _hoveredSegmentIndex != i) {
                            setState(() => _hoveredSegmentIndex = i);
                          }
                        },
                        onExit: (_) {
                          if (_hoveredSegmentIndex == i) {
                            setState(() => _hoveredSegmentIndex = null);
                          }
                        },
                        child: AnimatedOpacity(
                          opacity:
                              _hoveredSegmentIndex == null ||
                                      _hoveredSegmentIndex == i
                                  ? 1.0
                                  : 0.4,
                          duration:
                              animationsDisabled
                                  ? Duration.zero
                                  : const Duration(milliseconds: 140),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: _color(segments[i].item.category),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _label(l10n, segments[i].item.category),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: DesktopType.caption(skin.text2),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                formatFileSize(segments[i].item.sizeBytes),
                                style: DesktopType.numeric(skin.text3),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: DesktopButton(
            label: l10n.desktopStorageFindDuplicates,
            icon: DesktopIcons.sparkle,
            variant: DesktopButtonVariant.soft,
            busy: _scanningDuplicates,
            onPressed: _scanningDuplicates ? null : _scanDuplicates,
          ),
        ),
      ],
    );
  }

  Future<void> _scanDuplicates() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _scanningDuplicates = true);
    try {
      final summary = await ref.read(fileRepositoryProvider).scanDuplicates();
      if (!mounted) return;
      if (summary.duplicateGroupCount == 0) {
        showDesktopToast(
          context,
          summary.filesWithoutVerifiedHash == 0
              ? l10n.desktopStorageDuplicateScanNone
              : l10n.desktopStorageDuplicateScanNonePartial,
          icon: DesktopIcons.sparkle,
        );
      } else {
        showDesktopToast(
          context,
          l10n.desktopStorageDuplicateScanFound(
            formatFileSize(summary.reclaimableBytes),
          ),
          icon: DesktopIcons.sparkle,
        );
      }
      if (summary.filesWithoutVerifiedHash > 0) {
        showDesktopToast(
          context,
          l10n.desktopStorageDuplicateScanSkipped(
            '${summary.filesWithoutVerifiedHash}',
          ),
          kind: DesktopToastKind.warn,
          icon: DesktopIcons.info,
        );
      }
    } catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          errorReason(error, l10n),
          kind: DesktopToastKind.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _scanningDuplicates = false);
      }
    }
  }
}

class _StorageDistributionSkeleton extends StatelessWidget {
  const _StorageDistributionSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DesktopSkeletonBox(width: 220, height: 50),
        const SizedBox(height: 16),
        const DesktopSkeletonBox(height: 14),
        const SizedBox(height: 12),
        Wrap(
          spacing: 30,
          runSpacing: 10,
          children: [
            for (var index = 0; index < 4; index++)
              SizedBox(
                width: 230,
                child: Row(
                  children: [
                    DesktopSkeletonBox(width: 8, height: 8, index: index),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DesktopSkeletonBox(width: 100, index: index + 1),
                    ),
                    const SizedBox(width: 18),
                    DesktopSkeletonBox(width: 48, index: index + 2),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        const DesktopSkeletonBox(width: 150, height: 34),
      ],
    );
  }
}
