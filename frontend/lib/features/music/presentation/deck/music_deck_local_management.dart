part of 'music_deck_content.dart';

/// 本地资源分区：导入、刮削、扫描入口与曲目行的编辑/删除动作。
class _LocalManagementContent extends ConsumerWidget {
  const _LocalManagementContent({required this.center});

  final MusicCenterState center;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scanJob = ref.watch(musicScanJobControllerProvider);
    final activeScan = scanJob.job ?? center.lastScanJob;
    final scanRunning = scanJob.polling;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ContentHeader(
          title: l10n.musicDeckLocalManagement,
          subtitle: l10n.musicLocalManagementSubtitle,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 三个操作按钮统一为描边样式 + 中性前景，
              // 不使用主题 primary（模块语境下为绿色）。
              MediaImportButton(
                subsystemDirectory: 'Music',
                acceptedExtensions: const [
                  'mp3',
                  'flac',
                  'aac',
                  'm4a',
                  'ogg',
                  'opus',
                  'wav',
                  'wma',
                ],
                onImportComplete: () async {
                  // 上传完成后立即扫描，把新文件导入曲库并刷新列表。
                  await ref
                      .read(musicScanJobControllerProvider.notifier)
                      .startScan();
                  await ref
                      .read(musicCenterControllerProvider.notifier)
                      .refresh();
                },
                style: ImportButtonStyle.outlinedButton,
                color: context.musicColors.onSurface,
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => _confirmScrapeLibrary(context, ref),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.musicColors.onSurface,
                ),
                icon: const Icon(Icons.travel_explore_rounded, size: 18),
                label: Text(l10n.musicScrapeLibrary),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed:
                    scanRunning ? null : () => _confirmStartScan(context, ref),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.musicColors.onSurface,
                ),
                icon: const Icon(Icons.radar_rounded, size: 18),
                label: Text(l10n.musicStartScan),
              ),
            ],
          ),
        ),
        if (activeScan != null) ...[
          const SizedBox(height: 12),
          Text(
            l10n.musicScanStatus(
              activeScan.id,
              activeScan.status,
              activeScan.progress,
              activeScan.scannedFiles,
            ),
            style: TextStyle(
              color: context.musicColors.onSurfaceVariant,
              fontSize: AppTypography.bodySmall,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: activeScan.progress > 0 ? activeScan.progress / 100 : null,
              minHeight: 4,
            ),
          ),
          if (activeScan.message != null && activeScan.message!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              activeScan.message!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.musicColors.onSurfaceVariant,
                fontSize: AppTypography.bodySmall,
              ),
            ),
          ],
          if (scanJob.timedOut)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.musicScanPollTimeout,
                style: TextStyle(
                  color: context.musicColors.onSurfaceVariant,
                  fontSize: AppTypography.bodySmall,
                ),
              ),
            ),
        ],
        const SizedBox(height: 16),
        Expanded(
          child:
              center.tracks.isEmpty
                  ? _InlineEmpty(message: l10n.musicNoMetadataHint)
                  : ListView.separated(
                    itemCount: center.tracks.length,
                    separatorBuilder:
                        (context, index) => Divider(
                          color: context.musicColors.outline,
                          height: 1,
                        ),
                    itemBuilder: (context, index) {
                      final track = center.tracks[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        leading: SizedBox.square(
                          dimension: 44,
                          child: MusicDeckArtwork(
                            title: track.title,
                            imageUrl: track.listCoverUrl,
                          ),
                        ),
                        title: Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.musicColors.onSurface,
                          ),
                        ),
                        subtitle: Text(
                          '${track.artistName} · ${track.albumTitle}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.musicColors.onSurfaceVariant,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: l10n.musicEditMetadata,
                              onPressed:
                                  () => context.push(
                                    '/music/tracks/${track.id}/metadata',
                                  ),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: l10n.musicDeleteLocalTrack,
                              onPressed:
                                  () => _deleteTrackHandler(context, ref)(
                                    MusicPlayableItem.local(track),
                                  ),
                              icon: Icon(
                                Icons.delete_outline_rounded,
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
        ),
      ],
    );
  }
}
