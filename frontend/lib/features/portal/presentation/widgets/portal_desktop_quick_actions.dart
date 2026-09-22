part of 'portal_desktop_visual_shells.dart';

class _PortalFocusQuickActions extends ConsumerWidget {
  const _PortalFocusQuickActions({
    required this.palette,
    required this.item,
    required this.data,
    required this.onOpenImmersivePlayback,
  });

  final PortalVisualPalette palette;
  final PortalFocusItem item;
  final _PortalDesktopData data;
  final VoidCallback onOpenImmersivePlayback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final systemAction = _resolveSystemAction(context);
    final immersiveAction = _resolveImmersiveAction(context);
    final l10n = AppLocalizations.of(context);
    final maxWidth = item.module == PortalFocusModule.music ? 720.0 : 760.0;
    // video/photos/reader 的预览升级为分页浏览网格（首屏 10 条 + 无感
    // 续载），与音乐队列卡同一套分页基建。
    final preview = switch (item.module) {
      PortalFocusModule.music => _PortalModulePreviewShell(
        palette: palette,
        title: item.heroEyebrow ?? item.title,
        systemAction: systemAction,
        secondaryAction: immersiveAction,
        child: _PortalMusicFocusPreview(
          palette: palette,
          onOpenQueue: () => showMusicDeckQueue(context),
        ),
      ),
      PortalFocusModule.video => _PortalModulePagedPreview<
        PortalVideoPreviewItem
      >(
        palette: palette,
        item: item,
        systemAction: systemAction,
        provider: portalVideoPreviewProvider,
        entryBuilder:
            (video, index) => _PortalFocusPreviewEntry(
              icon:
                  video.isContinueWatching
                      ? Icons.play_circle_rounded
                      : Icons.movie_rounded,
              title: video.title,
              subtitle:
                  video.isContinueWatching
                      ? '${video.progressPercent!.clamp(0, 100).round()}% · ${l10n.portalContinueWatching}'
                      : (video.secondaryText ?? ''),
              route: video.route,
              module: PortalFocusModule.video,
              imageUrl: video.posterUrl,
              cacheKey: 'portal-preview:video:${video.id}',
            ),
      ),
      PortalFocusModule.photos => _PortalModulePagedPreview<PhotoItem>(
        palette: palette,
        item: item,
        systemAction: systemAction,
        provider: portalRecentPhotosProvider,
        entryBuilder:
            (photo, index) => _PortalFocusPreviewEntry(
              icon: Icons.photo_rounded,
              title: photo.title,
              subtitle: photo.format.toUpperCase(),
              route: '/photos/${photo.id}',
              module: PortalFocusModule.photos,
              imageUrl: photo.coverUrl,
              cacheKey: 'portal-preview:photos:${photo.id}',
            ),
      ),
      PortalFocusModule.reader => _PortalModulePagedPreview<ReaderItem>(
        palette: palette,
        item: item,
        systemAction: systemAction,
        provider: portalReaderShelfProvider,
        entryBuilder:
            (readerItem, index) => _PortalFocusPreviewEntry(
              icon:
                  readerItem.isComic
                      ? Icons.auto_stories_rounded
                      : Icons.menu_book_rounded,
              title: readerItem.title,
              subtitle:
                  readerItem.currentChapterTitle?.isNotEmpty == true
                      ? readerItem.currentChapterTitle!
                      : readerItem.authorName ?? l10n.portalDockReading,
              route:
                  readerItem.isComic
                      ? '/reader/comics/${readerItem.id}/read'
                      : '/reader/items/${readerItem.id}',
              module: PortalFocusModule.reader,
              imageUrl: readerItem.coverUrl,
              readerItemId: readerItem.hasCover ? readerItem.id : null,
            ),
      ),
      _ => _PortalFocusPreviewPanel(
        palette: palette,
        item: item,
        data: data,
        systemAction: systemAction,
      ),
    };
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(width: double.infinity, child: preview),
      ),
    );
  }

  _PortalHeroAction _resolveSystemAction(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return switch (item.module) {
      PortalFocusModule.reader => _PortalHeroAction(
        icon: Icons.library_books_rounded,
        label: l10n.portalEnterSystem,
        route: '/reader',
      ),
      PortalFocusModule.video => _PortalHeroAction(
        icon: Icons.video_library_rounded,
        label: l10n.portalEnterSystem,
        route: '/video',
      ),
      PortalFocusModule.photos => _PortalHeroAction(
        icon: Icons.grid_view_rounded,
        label: l10n.portalEnterSystem,
        route: '/photos',
      ),
      PortalFocusModule.music => _PortalHeroAction(
        icon: Icons.queue_music_rounded,
        label: l10n.portalEnterSystem,
        route: '/music',
      ),
      PortalFocusModule.files => _PortalHeroAction(
        icon: Icons.folder_rounded,
        label: l10n.portalEnterSystem,
        route: '/files',
      ),
      PortalFocusModule.weather => _PortalHeroAction(
        icon: Icons.cloud_rounded,
        label: l10n.portalWeatherTitle,
        route: '/portal',
      ),
      PortalFocusModule.tasks || PortalFocusModule.admin => _PortalHeroAction(
        icon: Icons.admin_panel_settings_rounded,
        label: l10n.portalAdmin,
        route: '/admin',
      ),
    };
  }

  _PortalHeroAction? _resolveImmersiveAction(BuildContext context) {
    if (item.module != PortalFocusModule.music) {
      return null;
    }
    final l10n = AppLocalizations.of(context);
    return _PortalHeroAction(
      icon: Icons.graphic_eq_rounded,
      label: l10n.portalImmersivePlayback,
      onTap: onOpenImmersivePlayback,
    );
  }
}

class _PortalMusicFocusPreview extends ConsumerWidget {
  const _PortalMusicFocusPreview({
    required this.palette,
    required this.onOpenQueue,
  });

  final PortalVisualPalette palette;
  final VoidCallback onOpenQueue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final miniPlayer = MusicDeckMiniPlayer(
      compact: true,
      palette: MusicMiniPlayerPalette(
        text: palette.text,
        muted: palette.muted,
        accent: palette.accentAlt,
        onAccent: palette.text,
      ),
      managePlaybackSession: true,
      embedded: true,
      onOpenQueue: onOpenQueue,
    );
    // 队列卡数据就绪且有内容时展示虚拟化队列网格；加载中或队列为空
    // 时仅保留迷你播放器。
    final hasQueue =
        ref.watch(portalPlaybackQueueProvider).asData?.value.items.isNotEmpty ==
        true;
    if (!hasQueue) {
      return miniPlayer;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final grid = _PortalPagedPreviewGrid<MusicPlayableItem>(
          palette: palette,
          provider: portalPlaybackQueueProvider,
          entryBuilder:
              (item, index) => _PortalFocusPreviewEntry(
                icon: Icons.music_note_rounded,
                title: item.track.title,
                subtitle: item.track.artistName,
                route: '/music',
                module: PortalFocusModule.music,
                imageUrl: item.track.coverUrl,
                cacheKey: 'portal-preview:music:${item.track.id}',
                onTap:
                    () => unawaited(
                      ref.read(musicPortalActionsProvider).playQueueAt(index),
                    ),
              ),
        );
        if (!constraints.maxHeight.isFinite) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              miniPlayer,
              const SizedBox(height: 10),
              SizedBox(height: 320, child: grid),
            ],
          );
        }
        return Column(
          children: [
            miniPlayer,
            const SizedBox(height: 10),
            Expanded(child: grid),
          ],
        );
      },
    );
  }
}

/// 通用分页预览网格：GridView 虚拟化滚动，滚到距底约一行高度时静默
/// 追加下一页；复用专注预览卡片视觉。音乐队列、影视继续观看、最近
/// 照片与书架浏览共用。
class _PortalPagedPreviewGrid<T> extends ConsumerStatefulWidget {
  const _PortalPagedPreviewGrid({
    required this.palette,
    required this.provider,
    required this.entryBuilder,
  });

  final PortalVisualPalette palette;
  final AsyncNotifierProvider<
    PortalPagedListController<T>,
    PortalPagedListState<T>
  >
  provider;

  final _PortalFocusPreviewEntry Function(T item, int index) entryBuilder;

  @override
  ConsumerState<_PortalPagedPreviewGrid<T>> createState() =>
      _PortalPagedPreviewGridState<T>();
}

class _PortalPagedPreviewGridState<T>
    extends ConsumerState<_PortalPagedPreviewGrid<T>> {
  final ScrollController _scrollController = ScrollController();
  static const double _loadMoreRemainingExtent = 240;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    if (position.maxScrollExtent - position.pixels <=
        _loadMoreRemainingExtent) {
      unawaited(ref.read(widget.provider.notifier).loadMore());
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(widget.provider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            constraints.maxWidth.isFinite && constraints.maxWidth > 0
                ? constraints.maxWidth
                : 560.0;
        final columns =
            width >= 620
                ? 4
                : width >= 420
                ? 3
                : width >= 280
                ? 2
                : 1;
        final spacing =
            columns == 1
                ? 0.0
                : columns >= 3
                ? 12.0
                : 10.0;
        final rawCardWidth = (width - spacing * (columns - 1)) / columns;
        final cardWidth =
            rawCardWidth
                .clamp(math.min(112.0, width), columns == 1 ? width : 176.0)
                .toDouble();
        final cardHeight = (cardWidth * 1.32).clamp(150.0, 232.0).toDouble();
        return state.maybeWhen(
          data: (value) {
            if (value.items.isEmpty) {
              return const SizedBox.shrink();
            }
            final showFooter = value.hasMore || value.loadingMore;
            return GridView.builder(
              controller: _scrollController,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: spacing,
                crossAxisSpacing: spacing,
                childAspectRatio: cardWidth / cardHeight,
              ),
              itemCount: value.items.length + (showFooter ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= value.items.length) {
                  if (value.errorMessage != null) {
                    return Center(
                      child: TextButton(
                        onPressed:
                            () => unawaited(
                              ref.read(widget.provider.notifier).loadMore(),
                            ),
                        child: Text(AppLocalizations.of(context).coreRetry),
                      ),
                    );
                  }
                  return const Center(
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                return _PortalFocusPreviewCard(
                  palette: widget.palette,
                  entry: widget.entryBuilder(value.items[index], index),
                  width: cardWidth,
                  height: cardHeight,
                );
              },
            );
          },
          orElse:
              () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
        );
      },
    );
  }
}

/// 模块分页预览外壳：模块预览壳 + 分页网格 + 空态回落。
class _PortalModulePagedPreview<T> extends ConsumerWidget {
  const _PortalModulePagedPreview({
    required this.palette,
    required this.item,
    required this.systemAction,
    required this.provider,
    required this.entryBuilder,
  });

  final PortalVisualPalette palette;
  final PortalFocusItem item;
  final _PortalHeroAction systemAction;
  final AsyncNotifierProvider<
    PortalPagedListController<T>,
    PortalPagedListState<T>
  >
  provider;
  final _PortalFocusPreviewEntry Function(T item, int index) entryBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(provider);
    return _PortalModulePreviewShell(
      palette: palette,
      title: item.heroEyebrow ?? item.title,
      systemAction: systemAction,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final grid = _PortalPagedPreviewGrid<T>(
            palette: palette,
            provider: provider,
            entryBuilder: entryBuilder,
          );
          // 三态分流：加载中给轻量占位（避免把首帧的 AsyncLoading 当成
          // 空态闪一次“暂无内容”文案）；有数据才起网格；空数据保留空态。
          final child = switch (state) {
            AsyncData(:final value) when value.items.isNotEmpty =>
              constraints.maxHeight.isFinite
                  ? grid
                  : SizedBox(height: 360, child: grid),
            AsyncData() => _PortalFocusEmptyPreview(
              palette: palette,
              item: item,
            ),
            AsyncError() => _PortalFocusEmptyPreview(
              palette: palette,
              item: item,
            ),
            _ => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          };
          return child;
        },
      ),
    );
  }
}

class _PortalFocusPreviewPanel extends StatelessWidget {
  const _PortalFocusPreviewPanel({
    required this.palette,
    required this.item,
    required this.data,
    required this.systemAction,
  });

  final PortalVisualPalette palette;
  final PortalFocusItem item;
  final _PortalDesktopData data;
  final _PortalHeroAction systemAction;

  @override
  Widget build(BuildContext context) {
    // reader/video/photos 已升级为分页浏览网格；其余模块（文件/天气/
    // 任务/管理）无列表预览，展示模块空预览。
    return _PortalModulePreviewShell(
      palette: palette,
      title: item.heroEyebrow ?? item.title,
      systemAction: systemAction,
      child: _PortalFocusEmptyPreview(palette: palette, item: item),
    );
  }
}

class _PortalFocusPreviewEntry {
  const _PortalFocusPreviewEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
    required this.module,
    this.imageUrl,
    this.readerItemId,
    this.cacheKey,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
  final PortalFocusModule module;
  final String? imageUrl;
  final String? readerItemId;

  /// 稳定缓存键（内容标识构造），与签名 URL 解耦。
  final String? cacheKey;

  /// 就地点击回调；优先于 [route] 导航（播放队列等就地操作场景）。
  final VoidCallback? onTap;
}

class _PortalModulePreviewShell extends StatelessWidget {
  const _PortalModulePreviewShell({
    required this.palette,
    required this.title,
    required this.systemAction,
    required this.child,
    this.secondaryAction,
  });

  final PortalVisualPalette palette;
  final String title;
  final _PortalHeroAction systemAction;
  final _PortalHeroAction? secondaryAction;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boundedHeight =
            constraints.maxHeight.isFinite && constraints.maxHeight > 0;
        final shell = Container(
          width: double.infinity,
          constraints:
              boundedHeight ? null : const BoxConstraints(minHeight: 360),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: AppTypography.bodyMedium,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (secondaryAction != null) ...[
                    _PortalHeroActionButton(
                      palette: palette,
                      action: secondaryAction!,
                      compact: true,
                    ),
                    const SizedBox(width: 8),
                  ],
                  _PortalHeroActionButton(
                    palette: palette,
                    action: systemAction,
                    compact: true,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (boundedHeight)
                Expanded(
                  child: Align(alignment: Alignment.topLeft, child: child),
                )
              else
                child,
            ],
          ),
        );
        if (!boundedHeight) {
          return shell;
        }
        return SizedBox(height: constraints.maxHeight, child: shell);
      },
    );
  }
}

class _PortalFocusPreviewImage extends ConsumerStatefulWidget {
  const _PortalFocusPreviewImage({required this.palette, required this.entry});

  final PortalVisualPalette palette;
  final _PortalFocusPreviewEntry entry;

  @override
  ConsumerState<_PortalFocusPreviewImage> createState() =>
      _PortalFocusPreviewImageState();
}

class _PortalFocusPreviewImageState
    extends ConsumerState<_PortalFocusPreviewImage> {
  // 预览封面自愈上限：重签后仍失败则保持降级态，避免无限重试循环。
  static const int _maxRecoverAttempts = 2;
  int _recoverAttempts = 0;

  void _handleCoverError() {
    if (_recoverAttempts >= _maxRecoverAttempts) {
      return;
    }
    final section = PortalDashboardActions.sectionFor(widget.entry.module);
    if (section == null) {
      return;
    }
    _recoverAttempts++;
    unawaited(ref.read(portalDashboardActionsProvider).retry(section));
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final palette = widget.palette;
    final fallback = Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(entry.icon, color: palette.text, size: 22),
    );
    final readerItemId = entry.readerItemId?.trim();
    if (readerItemId != null && readerItemId.isNotEmpty) {
      return AuthCoverImage(
        itemId: readerItemId,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        borderRadius: BorderRadius.circular(7),
        fallback: fallback,
      );
    }
    return PortalMediaThumbnail(
      imageUrl: entry.imageUrl,
      cacheKey: entry.cacheKey,
      onLoadError: _handleCoverError,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      // 单维约束解码：双维会把海报拉伸到固定比例，仅约束高度后由
      // cover 裁切，覆盖 540 上限槽位在常见 DPR 下的清晰度。
      cacheHeight: 720,
      borderRadius: BorderRadius.circular(7),
      fallback: fallback,
    );
  }
}

class _PortalFocusPreviewCard extends StatelessWidget {
  const _PortalFocusPreviewCard({
    required this.palette,
    required this.entry,
    required this.width,
    required this.height,
  });

  final PortalVisualPalette palette;
  final _PortalFocusPreviewEntry entry;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          if (entry.onTap != null) {
            entry.onTap!();
            return;
          }
          // Admin 用 push 保留 Portal shell 状态（返回时 pop）。
          if (entry.route == '/admin') {
            context.push(entry.route);
          } else {
            context.go(entry.route);
          }
        },
        child: SizedBox(
          width: width,
          height: height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _PortalFocusPreviewImage(
                      palette: palette,
                      entry: entry,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    entry.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: AppTypography.bodySmall,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    entry.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.muted,
                      fontSize: AppTypography.labelSmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PortalFocusEmptyPreview extends StatelessWidget {
  const _PortalFocusEmptyPreview({required this.palette, required this.item});

  final PortalVisualPalette palette;
  final PortalFocusItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Icon(item.icon.iconData, color: palette.text, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.muted,
                fontSize: AppTypography.bodySmall,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PortalHeroAction {
  const _PortalHeroAction({
    required this.icon,
    required this.label,
    this.route,
    this.onTap,
  }) : assert(route != null || onTap != null);

  final IconData icon;
  final String label;
  final String? route;
  final VoidCallback? onTap;
}

class _PortalHeroActionButton extends StatelessWidget {
  const _PortalHeroActionButton({
    required this.palette,
    required this.action,
    this.compact = false,
  });

  final PortalVisualPalette palette;
  final _PortalHeroAction action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap:
            action.onTap ??
            () {
              // Admin 用 push 保留 Portal shell 状态（返回时 pop）。
              if (action.route == '/admin') {
                context.push(action.route!);
              } else {
                context.go(action.route!);
              }
            },
        child: Container(
          height: compact ? 32 : 36,
          constraints: BoxConstraints(maxWidth: compact ? 116 : 168),
          padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(action.icon, color: palette.text, size: 16),
              SizedBox(width: compact ? 6 : 8),
              Flexible(
                child: Text(
                  action.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: compact ? 11 : 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
