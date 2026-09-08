part of 'movie_management.dart';

class LocalLibrarySourcesPanel extends ConsumerStatefulWidget {
  const LocalLibrarySourcesPanel({this.fillHeight = false, super.key});

  /// 工作台模式：填满父级剩余高度，隐藏命令栏与失效影片面板
  /// （操作与面板由页面头部和底部条承载），供桌面端固定布局使用。
  final bool fillHeight;

  @override
  ConsumerState<LocalLibrarySourcesPanel> createState() =>
      _LocalLibrarySourcesPanelState();
}

class _LocalLibrarySourcesPanelState
    extends ConsumerState<LocalLibrarySourcesPanel> {
  String? _selectedSourceId;
  String? _scanningSourceId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locations = ref.watch(videoStorageLocationsProvider);
    final sources = ref.watch(videoLibrarySourcesProvider);
    final commandBar = _MediaLibraryCommandBar(
      canAdd:
          locations.asData?.value.any((location) => location.available) == true,
      onRefresh: () {
        ref.invalidate(videoStorageLocationsProvider);
        ref.invalidate(videoLibrarySourcesProvider);
      },
      onAdd:
          () => showDialog<void>(
            context: context,
            builder:
                (context) =>
                    VideoLibrarySourceDialog(locations: locations.requireValue),
          ),
    );
    final content = locations.when(
      loading: () => const LinearProgressIndicator(),
      error:
          (error, _) => MovieNoticePanel(
            icon: Icons.warning_amber_rounded,
            title: l10n.videoStorageLocationUnavailable,
            message: movieErrorMessage(error),
          ),
      data:
          (items) => sources.when(
            loading: () => const LinearProgressIndicator(),
            error:
                (error, _) => MovieNoticePanel(
                  icon: Icons.error_outline_rounded,
                  title: l10n.videoLoadSourcesFailed,
                  message: movieErrorMessage(error),
                ),
            data: (sourceItems) {
              if (sourceItems.isEmpty) {
                return _MediaLibraryEmptyState(
                  canAdd: items.any((location) => location.available),
                  onAdd:
                      () => showDialog<void>(
                        context: context,
                        builder:
                            (context) =>
                                VideoLibrarySourceDialog(locations: items),
                      ),
                );
              }
              final selectedSource = sourceItems.firstWhere(
                (source) => source.id == _selectedSourceId,
                orElse: () => sourceItems.first,
              );
              return _buildWorkspace(
                context,
                items,
                sourceItems,
                selectedSource,
              );
            },
          ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.fillHeight) ...[commandBar, const SizedBox(height: 12)],
        if (widget.fillHeight) Expanded(child: content) else content,
      ],
    );
  }

  Widget _buildWorkspace(
    BuildContext context,
    List<VideoStorageLocation> locations,
    List<VideoLibrarySource> sources,
    VideoLibrarySource selectedSource,
  ) {
    final latestRun = ref.watch(latestMediaScanRunProvider(selectedSource.id));
    final backendScanning = latestRun.maybeWhen(
      data: (run) => run?.active == true,
      orElse: () => false,
    );
    final navigator = _MediaLibrarySourceNavigator(
      sources: sources,
      selectedSourceId: selectedSource.id,
      bounded: widget.fillHeight,
      onSelected: (source) => setState(() => _selectedSourceId = source.id),
    );
    final workspace = _MediaLibrarySourceWorkspace(
      source: selectedSource,
      locations: locations,
      bounded: widget.fillHeight,
      scanning: _scanningSourceId == selectedSource.id || backendScanning,
      onEdit:
          () => showDialog<void>(
            context: context,
            builder:
                (context) => VideoLibrarySourceDialog(
                  locations: locations,
                  source: selectedSource,
                ),
          ),
      onScan: () => _scan(selectedSource),
      onDelete: () => _delete(selectedSource),
    );
    if (widget.fillHeight) {
      return Row(
        key: const Key('mediaLibraryDesktopSplit'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 320, child: navigator),
          const SizedBox(width: 12),
          Expanded(child: workspace),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final split = constraints.maxWidth >= 960;
        final stackedNavigator = _MediaLibrarySourceNavigator(
          sources: sources,
          selectedSourceId: selectedSource.id,
          bounded: split,
          onSelected: (source) => setState(() => _selectedSourceId = source.id),
        );
        final stackedWorkspace = _MediaLibrarySourceWorkspace(
          source: selectedSource,
          locations: locations,
          bounded: split,
          scanning: _scanningSourceId == selectedSource.id || backendScanning,
          onEdit:
              () => showDialog<void>(
                context: context,
                builder:
                    (context) => VideoLibrarySourceDialog(
                      locations: locations,
                      source: selectedSource,
                    ),
              ),
          onScan: () => _scan(selectedSource),
          onDelete: () => _delete(selectedSource),
        );
        if (!split) {
          return Column(
            key: const Key('mediaLibraryMobileStack'),
            children: [
              stackedNavigator,
              const SizedBox(height: 12),
              stackedWorkspace,
              const SizedBox(height: 12),
              const _UnavailableLocalMediaPanel(),
            ],
          );
        }
        return Column(
          key: const Key('mediaLibraryDesktopSplit'),
          children: [
            SizedBox(
              height: 620,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 320, child: stackedNavigator),
                  const SizedBox(width: 12),
                  Expanded(child: stackedWorkspace),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const _UnavailableLocalMediaPanel(),
          ],
        );
      },
    );
  }

  Future<void> _scan(VideoLibrarySource source) async {
    setState(() => _scanningSourceId = source.id);
    try {
      final task = await ref
          .read(videoLibrarySourceActionsProvider)
          .scan(source.id);
      if (mounted) {
        showMovieFeedback(context, task.message);
      }
    } on Exception catch (error) {
      if (mounted) {
        showMovieFeedback(context, movieErrorMessage(error), isError: true);
      }
    } finally {
      // 入队后由来源 scanStatus 和 latestMediaScanRunProvider 继续展示真实后台状态。
      if (mounted && _scanningSourceId == source.id) {
        setState(() => _scanningSourceId = null);
      }
    }
  }

  Future<void> _delete(VideoLibrarySource source) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(l10n.videoDeleteLibrarySource),
            content: Text(l10n.videoDeleteLibrarySourceConfirm(source.name)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(l10n.videoCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(l10n.filesDelete),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _scanningSourceId = source.id);
    try {
      await ref.read(videoLibrarySourceActionsProvider).delete(source.id);
      if (mounted) {
        setState(() {
          _scanningSourceId = null;
          if (_selectedSourceId == source.id) _selectedSourceId = null;
        });
        showMovieFeedback(context, l10n.videoDeleteLibrarySourceDone);
      }
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _scanningSourceId = null);
        showMovieFeedback(context, movieErrorMessage(error), isError: true);
      }
    }
  }
}

class _MediaLibraryCommandBar extends StatelessWidget {
  const _MediaLibraryCommandBar({
    required this.canAdd,
    required this.onRefresh,
    required this.onAdd,
  });

  final bool canAdd;
  final VoidCallback onRefresh;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: context.videoColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: context.videoColors.outlineVariant.withValues(alpha: 0.36),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final heading = Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: context.videoColors.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.video_library_outlined,
                  color: context.videoColors.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.videoLocalLibrarySources,
                      style: TextStyle(
                        color: context.videoColors.onSurface,
                        fontSize: AppTypography.titleMedium,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      l10n.videoLocalLibrarySourcesSubtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.videoColors.onSurfaceVariant,
                        fontSize: AppTypography.bodySmall,
                        height: 16 / 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: onRefresh,
                tooltip: l10n.videoRefreshSources,
                icon: const Icon(Icons.refresh_rounded),
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: canAdd ? onAdd : null,
                icon: const Icon(Icons.add_rounded),
                label: Text(l10n.videoAddLibrarySource),
              ),
            ],
          );
          if (constraints.maxWidth < 620) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                heading,
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: actions,
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: heading),
              const SizedBox(width: 16),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _MediaLibraryEmptyState extends StatelessWidget {
  const _MediaLibraryEmptyState({required this.canAdd, required this.onAdd});

  /// 无可用存储位置时禁用创建入口，避免对话框打开后无位置可选。
  final bool canAdd;

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget addButton = FilledButton.icon(
      onPressed: canAdd ? onAdd : null,
      icon: const Icon(Icons.add_rounded),
      label: Text(l10n.videoAddLibrarySource),
    );
    if (!canAdd) {
      addButton = Tooltip(
        message: l10n.videoNoAvailableStorageLocationHint,
        child: addButton,
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 42),
      decoration: BoxDecoration(
        color: context.videoColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: context.videoColors.outlineVariant.withValues(alpha: 0.36),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.create_new_folder_outlined,
            size: 42,
            color: context.videoColors.primary,
          ),
          const SizedBox(height: 14),
          Text(
            l10n.videoNoLibrarySources,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.videoColors.onSurface,
              fontSize: AppTypography.titleMedium,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Text(
              l10n.videoLocalLibrarySourcesSubtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.videoColors.onSurfaceVariant,
                height: 20 / 14,
              ),
            ),
          ),
          const SizedBox(height: 18),
          addButton,
        ],
      ),
    );
  }
}
