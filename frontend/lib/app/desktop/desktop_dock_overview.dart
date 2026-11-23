part of 'desktop_dock.dart';

class _ContextualOverviewBody extends ConsumerWidget {
  const _ContextualOverviewBody({super.key});

  String? _resolvePath(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<DesktopRouterScope>();
    final router = scope?.router;
    if (router == null) {
      return null;
    }
    final configuration = router.routerDelegate.currentConfiguration;
    final matches = configuration.matches;
    final location =
        matches.isNotEmpty
            ? matches.last.matchedLocation
            : configuration.uri.toString();
    return Uri.parse(location).path;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<DesktopRouterScope>();
    final router = scope?.router;
    if (router == null) {
      return const _DefaultContextOverview(path: null);
    }
    return ListenableBuilder(
      listenable: router.routerDelegate,
      builder: (context, _) {
        final path = _resolvePath(context) ?? '';
        if (path.startsWith(DesktopRoutes.files)) {
          return const _FilesContextOverview();
        }
        if (path.startsWith(DesktopRoutes.photos)) {
          return const _PhotosContextOverview();
        }
        return _DefaultContextOverview(path: path);
      },
    );
  }
}

class _FilesContextOverview extends ConsumerWidget {
  const _FilesContextOverview();

  Future<void> _uploadFromDock(
    BuildContext context,
    WidgetRef ref,
    FileBrowserState state,
  ) async {
    final files = await FilePick.openMultipleFiles();
    if (files.isEmpty || !context.mounted) {
      return;
    }
    final result = await ref
        .read(fileBrowserControllerProvider.notifier)
        .uploadFiles(files, target: UploadTarget.of(state));
    if (!context.mounted) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    showDesktopToast(
      context,
      l10n.desktopFilesUploadDone(result.completed, result.total),
      kind:
          result.failed > 0 ? DesktopToastKind.warn : DesktopToastKind.success,
      icon: result.failed > 0 ? DesktopIcons.info : DesktopIcons.upload,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final state = ref.watch(
      fileBrowserControllerProvider.select((async) => async.asData?.value),
    );
    final controller = ref.read(fileBrowserControllerProvider.notifier);

    final shared = state?.spaceType == 'SHARED';
    final breadcrumbs =
        state == null
            ? const <FileNode>[]
            : (shared ? state.sharedSpaceBreadcrumbs : state.breadcrumbs);
    final pathLabel =
        breadcrumbs.isEmpty
            ? (shared ? l10n.filesSharedSpace : l10n.desktopFilesAll)
            : '/${breadcrumbs.map((b) => b.name).join('/')}';
    final currentItems =
        state == null
            ? const <FileNode>[]
            : switch (state.section) {
              FileManagerSection.recent => state.recentFiles,
              FileManagerSection.favorites => state.favoriteFiles,
              FileManagerSection.recycleBin => state.recycleBin,
              _ => state.files,
            };
    final folderCount = currentItems.where((n) => n.isFolder).length;
    final fileCount = currentItems.length - folderCount;
    final totalBytes = currentItems.fold<int>(
      0,
      (sum, node) => sum + (node.isFolder ? 0 : node.sizeBytes),
    );
    final canCreateOrUpload =
        state != null &&
        (state.section == FileManagerSection.allFiles ||
            state.section == FileManagerSection.sharedSpace);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _OverviewHeroCard(
          icon: shared ? DesktopIcons.users : DesktopIcons.folderFilled,
          eyebrow: isZh ? '当前目录概览' : 'FOLDER OVERVIEW',
          title:
              breadcrumbs.isEmpty
                  ? (shared ? l10n.filesSharedSpace : l10n.desktopFilesAll)
                  : breadcrumbs.last.name,
          subtitle:
              isZh
                  ? '$folderCount 个文件夹 · $fileCount 个文件'
                  : '$folderCount folders · $fileCount files',
        ),
        const SizedBox(height: 14),
        if (canCreateOrUpload)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                DesktopButton(
                  label: l10n.desktopFilesUpload,
                  icon: DesktopIcons.upload,
                  variant: DesktopButtonVariant.primary,
                  onPressed:
                      () => unawaited(_uploadFromDock(context, ref, state)),
                ),
                DesktopButton(
                  label: l10n.filesNewFolder,
                  icon: DesktopIcons.plus,
                  variant: DesktopButtonVariant.soft,
                  onPressed: () {
                    if (state.draftFolderName != null) {
                      return;
                    }
                    controller.beginFolderCreation(
                      dedupeFolderName(l10n.filesNewFolderDefault, state.files),
                    );
                  },
                ),
              ],
            ),
          ),
        DesktopEyebrow(l10n.desktopFileSection),
        DesktopKeyValues(
          entries: [
            MapEntry(
              isZh ? '所属空间' : 'Space',
              shared ? l10n.importToSharedSpace : l10n.importToPersonalSpace,
            ),
            MapEntry(isZh ? '当前路径' : 'Path', pathLabel),
            MapEntry(l10n.desktopFilesFilterFolders, '$folderCount'),
            MapEntry(l10n.desktopFilesFilesGroup, '$fileCount'),
            MapEntry(l10n.desktopFilesSize, formatFileSize(totalBytes)),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          isZh
              ? '单击任意文件或文件夹可在此查看缩略图、属性、共享状态与版本记录。'
              : 'Select any file or folder to inspect preview, metadata, sharing, and version history.',
          style: DesktopType.caption(skin.text3),
        ),
      ],
    );
  }
}

class _PhotosContextOverview extends ConsumerWidget {
  const _PhotosContextOverview();

  static String _formatDay(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final dashboard = ref.watch(
      photoDashboardProvider.select((async) => async.asData?.value),
    );
    final photos =
        ref.watch(
          photoListProvider.select((async) => async.asData?.value.items),
        ) ??
        const <PhotoItem>[];

    DateTime? earliest;
    DateTime? latest;
    var loadedBytes = 0;
    for (final item in photos) {
      loadedBytes += item.fileSize;
      final dt = item.dateTaken ?? item.createdAt;
      if (dt == null) continue;
      if (earliest == null || dt.isBefore(earliest)) earliest = dt;
      if (latest == null || dt.isAfter(latest)) latest = dt;
    }
    final rangeText =
        earliest != null && latest != null
            ? (earliest.year == latest.year &&
                    earliest.month == latest.month &&
                    earliest.day == latest.day
                ? _formatDay(latest)
                : '${_formatDay(earliest)} ~ ${_formatDay(latest)}')
            : '—';

    final latestPhoto =
        photos.firstOrNull ?? dashboard?.recentPhotos.firstOrNull;
    final totalPhotos = dashboard?.totalPhotos ?? photos.length;
    final totalVideos = dashboard?.totalVideos ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (latestPhoto != null &&
            (latestPhoto.coverUrl?.isNotEmpty == true ||
                latestPhoto.sourceUrl?.isNotEmpty == true)) ...[
          AspectRatio(
            aspectRatio: 16 / 10,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: DesktopCover(
                url: latestPhoto.coverUrl ?? latestPhoto.sourceUrl,
                kind: DesktopCoverKind.network,
                fallbackIcon: DesktopIcons.image,
                iconSize: 36,
              ),
            ),
          ),
          const SizedBox(height: 14),
        ] else ...[
          _OverviewHeroCard(
            icon: DesktopIcons.image,
            eyebrow: isZh ? '图库概览' : 'LIBRARY OVERVIEW',
            title: l10n.modulePhotosTitle,
            subtitle: l10n.desktopPhotosCount(totalPhotos, totalVideos),
          ),
          const SizedBox(height: 14),
        ],
        Text(l10n.modulePhotosTitle, style: DesktopType.displaySm(skin.text)),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 14),
          child: Text(
            l10n.desktopPhotosCount(totalPhotos, totalVideos),
            style: DesktopType.dense(skin.text2),
          ),
        ),
        if (latestPhoto != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                DesktopButton(
                  label: isZh ? '查看最新照片' : 'Open latest',
                  icon: DesktopIcons.image,
                  variant: DesktopButtonVariant.primary,
                  onPressed: () {
                    if (photos.isNotEmpty) {
                      ref
                          .read(photoBrowseScopeProvider.notifier)
                          .set(photos, PhotoBrowseSource.library);
                    }
                    desktopPush(
                      context,
                      DesktopRoutes.photoDetail(latestPhoto.id),
                    );
                  },
                ),
              ],
            ),
          ),
        DesktopEyebrow(isZh ? '图库统计' : 'LIBRARY STATS'),
        DesktopKeyValues(
          entries: [
            MapEntry(isZh ? '照片数量' : 'Photos', '$totalPhotos'),
            MapEntry(isZh ? '视频数量' : 'Videos', '$totalVideos'),
            if (dashboard != null)
              MapEntry(l10n.photosTabAlbums, '${dashboard.totalAlbums}'),
            if (dashboard != null)
              MapEntry(l10n.photosTabFavorites, '${dashboard.totalFavorites}'),
            MapEntry(isZh ? '拍摄时间范围' : 'Date range', rangeText),
            if (loadedBytes > 0)
              MapEntry(
                isZh ? '已加载占用' : 'Loaded size',
                formatFileSize(loadedBytes),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          isZh
              ? '勾选照片、点击卡片右上角 i 或右键「检查信息」可查看完整 EXIF 拍摄参数。'
              : 'Select photos, click the card info badge, or right-click to inspect EXIF details.',
          style: DesktopType.caption(skin.text3),
        ),
      ],
    );
  }
}

class _DefaultContextOverview extends ConsumerWidget {
  const _DefaultContextOverview({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final currentItem = ref.watch(
      musicCenterControllerProvider.select(
        (async) => async.asData?.value.currentItem,
      ),
    );
    final snapshot = ref.watch(
      musicPortalSnapshotProvider.select((async) => async.asData?.value),
    );
    final track = currentItem?.track;
    final portalTrack = snapshot?.activeTrack;
    final hasRouter =
        context.dependOnInheritedWidgetOfExactType<DesktopRouterScope>() !=
        null;

    if (track != null || portalTrack != null) {
      final title = track?.title ?? portalTrack!.title;
      final artist = track?.artistName ?? portalTrack!.artistName;
      final album = track?.albumTitle ?? '';
      final coverUrl =
          track?.coverUrl ??
          track?.coverThumbUrl ??
          portalTrack?.coverUrl ??
          portalTrack?.listCoverUrl;
      final duration = track?.durationSeconds;
      final quality = track?.qualityText;
      final format = track?.format.toUpperCase();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DesktopEyebrow(l10n.desktopDockNowPlaying),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: AspectRatio(
                aspectRatio: 1,
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: skin.shadow,
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DesktopCover(
                        url: coverUrl,
                        kind: DesktopCoverKind.music,
                        fallbackIcon: DesktopIcons.music,
                        iconSize: 40,
                      ),
                      if (format != null && format.isNotEmpty)
                        Positioned(
                          left: 10,
                          top: 10,
                          child: DesktopChip(format),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(title, style: DesktopType.displaySm(skin.text)),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 14),
            child: Text(
              album.isNotEmpty ? '$artist · $album' : artist,
              style: DesktopType.dense(skin.text2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (hasRouter)
                  DesktopButton(
                    label: l10n.desktopOpenNowPlaying,
                    icon: DesktopIcons.expand,
                    variant: DesktopButtonVariant.primary,
                    onPressed:
                        () => desktopPush(context, DesktopRoutes.nowPlaying),
                  ),
                DesktopButton(
                  label: l10n.desktopDockQueue,
                  icon: DesktopIcons.queue,
                  variant: DesktopButtonVariant.soft,
                  onPressed:
                      () => ref
                          .read(desktopShellProvider.notifier)
                          .setDockTab(DesktopDockTab.queue),
                ),
              ],
            ),
          ),
          DesktopEyebrow(l10n.desktopNavMusic),
          DesktopKeyValues(
            entries: [
              if (album.isNotEmpty) MapEntry(l10n.desktopColAlbum, album),
              if (duration != null)
                MapEntry(
                  l10n.musicFieldDuration,
                  formatDesktopClock(Duration(seconds: duration)),
                ),
              if (format != null && format.isNotEmpty)
                MapEntry(l10n.musicFieldFormat, format),
              if (quality != null && quality.isNotEmpty)
                MapEntry(isZh ? '音质参数' : 'Audio quality', quality),
            ],
          ),
        ],
      );
    }

    final currentPath = path ?? '';
    final (IconData icon, String title, String desc) = switch (currentPath) {
      final p when p.startsWith(DesktopRoutes.music) => (
        DesktopIcons.music,
        l10n.desktopNavMusic,
        isZh
            ? '单击曲目行可在此查看音质参数与快捷操作，双击立即播放。'
            : 'Click any track to inspect audio metadata, or double-click to play.',
      ),
      final p when p.startsWith(DesktopRoutes.movies) => (
        DesktopIcons.film,
        l10n.desktopNavMovies,
        isZh
            ? '单击影片直达详情页；右键卡片「快速查看」可在此预览简介与参数。'
            : 'Click any title to open details, or right-click for quick look.',
      ),
      final p when p.startsWith(DesktopRoutes.reader) => (
        DesktopIcons.book,
        l10n.desktopNavReader,
        isZh
            ? '单击书籍直接开始阅读；右键书籍可在此查看进度与出版信息。'
            : 'Click a book to read, or right-click to inspect reading progress.',
      ),
      _ => (
        DesktopIcons.info,
        isZh ? '智能检查器' : 'Inspector',
        isZh
            ? '选中文件、照片或曲目后，这里会实时展示缩略图、元信息与快捷操作。'
            : 'Select a file, photo, or track to inspect preview, metadata, and quick actions.',
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _OverviewHeroCard(
          icon: icon,
          eyebrow: isZh ? '上下文检查器' : 'CONTEXT INSPECTOR',
          title: title,
          subtitle: desc,
        ),
        if (hasRouter) ...[
          const SizedBox(height: 16),
          DesktopEyebrow(isZh ? '快速前往' : 'QUICK JUMP'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              DesktopButton(
                label: l10n.desktopNavFiles,
                icon: DesktopIcons.folder,
                variant: DesktopButtonVariant.soft,
                onPressed: () => desktopGo(context, DesktopRoutes.files),
              ),
              DesktopButton(
                label: l10n.modulePhotosTitle,
                icon: DesktopIcons.image,
                variant: DesktopButtonVariant.soft,
                onPressed: () => desktopGo(context, DesktopRoutes.photos),
              ),
              DesktopButton(
                label: l10n.desktopNavMusic,
                icon: DesktopIcons.music,
                variant: DesktopButtonVariant.soft,
                onPressed: () => desktopGo(context, DesktopRoutes.music),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _OverviewHeroCard extends StatelessWidget {
  const _OverviewHeroCard({
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String eyebrow;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: skin.raise,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: skin.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: skin.accentWash(0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: skin.accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  eyebrow.toUpperCase(),
                  style: DesktopType.eyebrow(skin.text3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(title, style: DesktopType.displaySm(skin.text)),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: DesktopType.dense(skin.text2).copyWith(height: 1.45),
          ),
        ],
      ),
    );
  }
}
