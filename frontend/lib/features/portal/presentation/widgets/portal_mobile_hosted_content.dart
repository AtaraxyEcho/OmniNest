part of 'portal_mobile_shell.dart';

class _HostedPortalContent extends ConsumerWidget {
  const _HostedPortalContent({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final movie = ref.watch(portalMovieDashboardProvider);
    final music = ref.watch(portalMusicSnapshotProvider);
    final reader = ref.watch(portalReaderDashboardProvider);
    final photos = ref.watch(portalPhotoDashboardProvider);
    final storage = ref.watch(portalStorageStatsProvider);
    final tasks = ref.watch(activeTaskSummaryProvider);
    final online = ref.watch(appOnlineStatusProvider).asData?.value != false;
    final backdropState =
        ref.watch(appBackdropControllerProvider).asData?.value;
    final backdropActive =
        backdropState?.settings.enabled == true &&
        backdropState?.selectedBackdrop != null &&
        backdropState?.selectedBackdrop?.missing == false;
    void retry(PortalDashboardSection section) {
      unawaited(ref.read(portalDashboardActionsProvider).retry(section));
    }

    return Theme(
      data: PortalMobileTheme.resolve(context, backdropActive: backdropActive),
      child: MobilePageSurface(
        exposeBackdrop: backdropActive,
        backdropOpacity: 0,
        child: RefreshIndicator(
          color: context.mobileColors.musicAccent,
          onRefresh: onRefresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: _PortalEnvironmentHeader(backdropActive: backdropActive),
              ),
              SliverPadding(
                padding: MobileLayoutTokens.pagePadding(context),
                sliver: SliverList.list(
                  children: [
                    const SizedBox(height: 4),
                    const _PortalPrimaryActions(),
                    const SizedBox(height: MobileLayoutTokens.sectionGap),
                    MobileSectionHeader(title: l10n.portalMobileContinueUsing),
                    const SizedBox(height: 12),
                    _PortalContinueStrip(
                      movie: movie,
                      music: music,
                      reader: reader,
                      onRetry: retry,
                    ),
                    const SizedBox(height: MobileLayoutTokens.sectionGap),
                    MobileSectionHeader(
                      title: l10n.portalRecentPhotos,
                      action: _PortalTextAction(
                        label: l10n.portalMobileViewAll,
                        onTap: () => context.go('/photos'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _PortalRecentPhotoGrid(
                      photos: photos,
                      onRetry: () => retry(PortalDashboardSection.photos),
                    ),
                    const SizedBox(height: MobileLayoutTokens.sectionGap),
                    MobileSectionHeader(title: l10n.portalMobileSystemSummary),
                    const SizedBox(height: 8),
                    _PortalSystemSummary(
                      storage: storage,
                      tasks: tasks,
                      online: online,
                      onStorageRetry:
                          () => retry(PortalDashboardSection.storage),
                    ),
                    const SizedBox(height: 28),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PortalEnvironmentHeader extends ConsumerWidget {
  const _PortalEnvironmentHeader({required this.backdropActive});

  final bool backdropActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final weather = ref.watch(realtimeWeatherProvider);
    final greeting = switch (now.hour) {
      < 12 => l10n.portalMobileGreetingMorning,
      < 18 => l10n.portalMobileGreetingAfternoon,
      _ => l10n.portalMobileGreetingEvening,
    };
    final pagePadding = MobileLayoutTokens.pagePadding(context);
    final primary =
        backdropActive ? Colors.white : context.mobileColors.textPrimary;
    final secondary =
        backdropActive
            ? Colors.white.withValues(alpha: 0.82)
            : context.mobileColors.textSecondary;
    final shadows =
        backdropActive
            ? <Shadow>[
              Shadow(
                color: Colors.black.withValues(alpha: 0.58),
                blurRadius: 10,
              ),
            ]
            : null;

    return SizedBox(
      height: 174,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          pagePadding.left,
          22,
          pagePadding.right,
          18,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    MaterialLocalizations.of(context).formatShortDate(now),
                    style: TextStyle(
                      color: secondary,
                      fontSize: AppTypography.bodyMedium,
                      fontWeight: FontWeight.w600,
                      shadows: shadows,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    greeting,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: primary,
                      fontSize: AppTypography.headlineMedium,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                      shadows: shadows,
                    ),
                  ),
                  const SizedBox(height: 8),
                  weather.when(
                    data:
                        (value) => Text(
                          l10n.portalWeatherFeelsLike(
                            value.text,
                            value.feelsLike,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: secondary,
                            fontSize: AppTypography.bodyMedium,
                            shadows: shadows,
                          ),
                        ),
                    loading:
                        () => const MobileSkeletonBlock(width: 128, height: 16),
                    error:
                        (_, _) => Text(
                          l10n.portalWeatherDisconnected,
                          style: TextStyle(
                            color: secondary,
                            fontSize: AppTypography.bodyMedium,
                            shadows: shadows,
                          ),
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            weather.when(
              data:
                  (value) => _PortalWeatherReading(
                    icon: value.weatherIcon,
                    temperature: value.temp,
                    foreground: primary,
                    shadows: shadows,
                    onTap:
                        () => showWeatherDetailDialog(context, weather: value),
                  ),
              loading: () => const MobileSkeletonBlock(width: 76, height: 64),
              error:
                  (_, _) => IconButton(
                    tooltip: l10n.coreRetry,
                    onPressed:
                        () => unawaited(
                          ref
                              .read(portalDashboardActionsProvider)
                              .retry(PortalDashboardSection.weather),
                        ),
                    icon: Icon(
                      Icons.cloud_sync_outlined,
                      color: secondary,
                      size: 34,
                    ),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PortalWeatherReading extends StatelessWidget {
  const _PortalWeatherReading({
    required this.icon,
    required this.temperature,
    required this.onTap,
    required this.foreground,
    required this.shadows,
  });

  final String icon;
  final int temperature;
  final VoidCallback onTap;
  final Color foreground;
  final List<Shadow>? shadows;

  @override
  Widget build(BuildContext context) {
    return MobilePressable(
      onTap: onTap,
      semanticLabel: AppLocalizations.of(context).portalWeatherTitle,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            icon,
            style: TextStyle(
              fontSize: AppTypography.headlineMedium,
              shadows: shadows,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$temperature°',
            style: TextStyle(
              color: foreground,
              fontSize: AppTypography.headlineMedium,
              fontWeight: FontWeight.w700,
              shadows: shadows,
            ),
          ),
        ],
      ),
    );
  }
}

class _PortalPrimaryActions extends StatelessWidget {
  const _PortalPrimaryActions();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final actions = [
      (
        icon: Icons.upload_file_rounded,
        label: l10n.portalQuickUpload,
        onTap: () => context.go('/files'),
      ),
      (
        icon: Icons.play_arrow_rounded,
        label: l10n.portalQuickPlay,
        onTap: () => context.go('/music'),
      ),
    ];
    return Row(
      children: [
        for (var index = 0; index < actions.length; index++) ...[
          if (index > 0) const SizedBox(width: 8),
          Expanded(
            child: _PortalPrimaryAction(
              icon: actions[index].icon,
              label: actions[index].label,
              onTap: actions[index].onTap,
            ),
          ),
        ],
      ],
    );
  }
}

class _PortalPrimaryAction extends StatelessWidget {
  const _PortalPrimaryAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MobilePressable(
      onTap: onTap,
      semanticLabel: label,
      child: SizedBox(
        height: MobileLayoutTokens.minimumTarget,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: context.mobileColors.surface,
              borderRadius: BorderRadius.circular(MobileLayoutTokens.radius),
              border: Border.all(color: context.mobileColors.outline),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: context.mobileColors.musicAccent, size: 19),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.mobileColors.textPrimary,
                      fontSize: AppTypography.bodySmall,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PortalContinueStrip extends StatelessWidget {
  const _PortalContinueStrip({
    required this.movie,
    required this.music,
    required this.reader,
    required this.onRetry,
  });

  final AsyncValue<MovieDashboard> movie;
  final AsyncValue<MusicPortalSnapshot> music;
  final AsyncValue<ReaderDashboard> reader;
  final ValueChanged<PortalDashboardSection> onRetry;

  @override
  Widget build(BuildContext context) {
    final items = <_PortalContinueItem>[];
    final movieData = movie.asData?.value;
    final readerData = reader.asData?.value;
    final musicData = music.asData?.value;
    if (movieData != null) {
      for (final item in movieData.continueWatching.take(2)) {
        items.add(
          _PortalContinueItem(
            title: item.title,
            subtitle: AppLocalizations.of(context).portalContinueWatching,
            imageUrl: item.posterUrl,
            progress: item.progressPercent / 100,
            icon: Icons.movie_outlined,
            route: '/video/${item.id}',
            shape: _PortalContinueMediaShape.portrait,
          ),
        );
      }
    }
    if (readerData != null && readerData.continueReading.isNotEmpty) {
      final item = readerData.continueReading.first;
      items.add(
        _PortalContinueItem(
          title: item.title,
          subtitle: AppLocalizations.of(context).portalReading,
          imageUrl: item.coverUrl,
          progress: (item.progressPercent ?? 0) / 100,
          icon: Icons.menu_book_outlined,
          route: '/reader/items/${item.id}',
          shape: _PortalContinueMediaShape.portrait,
        ),
      );
    }
    if (musicData != null) {
      final currentId = musicData.activeTrack?.id;
      for (final track in musicData.recentTracks) {
        if (track.id == currentId) {
          continue;
        }
        items.add(
          _PortalContinueItem(
            title: track.title,
            subtitle: track.artistName,
            imageUrl: track.coverUrl,
            progress: null,
            icon: Icons.music_note_outlined,
            route: '/music/now-playing',
            shape: _PortalContinueMediaShape.square,
          ),
        );
        if (items.length >= 5) {
          break;
        }
      }
    }
    final failedSection =
        movie.hasError
            ? PortalDashboardSection.video
            : music.hasError
            ? PortalDashboardSection.music
            : reader.hasError
            ? PortalDashboardSection.reader
            : null;
    final failureMessage = switch (failedSection) {
      PortalDashboardSection.video =>
        AppLocalizations.of(context).portalLoadMovieFailed,
      PortalDashboardSection.music =>
        AppLocalizations.of(context).portalLoadMusicFailed,
      PortalDashboardSection.reader =>
        AppLocalizations.of(context).portalLoadReadingFailed,
      _ => null,
    };
    if (items.isEmpty && failedSection != null && failureMessage != null) {
      return _ErrorCard(
        message: failureMessage,
        onRetry: () => onRetry(failedSection),
      );
    }
    if (items.isEmpty &&
        (movie.isLoading || music.isLoading || reader.isLoading)) {
      return SizedBox(
        height: 108,
        child: ListView(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          children: const [
            MobileSkeletonBlock(width: 248, height: 108),
            SizedBox(width: 12),
            MobileSkeletonBlock(width: 248, height: 108),
          ],
        ),
      );
    }
    if (items.isEmpty) {
      return MobileInlineState(
        icon: Icons.history_toggle_off_rounded,
        message: AppLocalizations.of(context).portalMobileNoContinue,
      );
    }
    final visibleItems = items.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 108,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: visibleItems.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder:
                (context, index) =>
                    _PortalContinueTile(item: visibleItems[index]),
          ),
        ),
        if (failedSection != null && failureMessage != null) ...[
          const SizedBox(height: 8),
          _PortalInlineRetry(
            message: failureMessage,
            onRetry: () => onRetry(failedSection),
          ),
        ],
      ],
    );
  }
}

class _PortalContinueItem {
  const _PortalContinueItem({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.progress,
    required this.icon,
    required this.route,
    required this.shape,
  });

  final String title;
  final String subtitle;
  final String? imageUrl;
  final double? progress;
  final IconData icon;
  final String route;
  final _PortalContinueMediaShape shape;
}

enum _PortalContinueMediaShape { portrait, square }

class _PortalContinueTile extends StatelessWidget {
  const _PortalContinueTile({required this.item});

  final _PortalContinueItem item;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 248,
      child: MobilePressable(
        onTap: () => context.push(item.route),
        semanticLabel: item.title,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.mobileColors.surface,
            borderRadius: BorderRadius.circular(MobileLayoutTokens.radius),
            border: Border.all(color: context.mobileColors.outline),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                SizedBox(
                  width:
                      item.shape == _PortalContinueMediaShape.portrait
                          ? 58
                          : 88,
                  height: 88,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // 槽位高主导（≤88 高）：仅约束解码高度，竖版海报
                        // 与横版缩略图均无需拉伸即可 cover 裁切。
                        PortalMediaThumbnail(
                          imageUrl: item.imageUrl,
                          fit: BoxFit.cover,
                          cacheHeight: (88 *
                                  MediaQuery.devicePixelRatioOf(context))
                              .ceil()
                              .clamp(176, 352),
                          borderRadius: BorderRadius.zero,
                          fallback: ColoredBox(
                            color: context.mobileColors.surfaceRaised,
                          ),
                        ),
                        if (item.imageUrl == null)
                          Center(
                            child: Icon(
                              item.icon,
                              color: context.mobileColors.textSecondary,
                              size: 26,
                            ),
                          ),
                        if (item.progress != null)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: LinearProgressIndicator(
                              value: item.progress!.clamp(0, 1),
                              minHeight: 3,
                              color: context.mobileColors.musicAccent,
                              backgroundColor: Colors.black45,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.mobileColors.textPrimary,
                          fontSize: AppTypography.bodyLarge,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.mobileColors.textSecondary,
                          fontSize: AppTypography.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PortalRecentPhotoGrid extends StatelessWidget {
  const _PortalRecentPhotoGrid({required this.photos, required this.onRetry});

  final AsyncValue<PhotoDashboard> photos;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return photos.when(
      data: (dashboard) {
        final items = dashboard.recentPhotos.take(6).toList();
        if (items.isEmpty) {
          return MobileInlineState(
            icon: Icons.photo_library_outlined,
            message: AppLocalizations.of(context).portalNoPhotos,
          );
        }
        // 单维约束解码：同时设宽高会把源图拉伸到精确方形（横/竖构图
        // 被压扁），仅约束宽度并由 cover 裁切保持真实纵横比；按单元格
        // 物理宽度加 4:3 余量，横构图裁切后仍清晰。
        return LayoutBuilder(
          builder: (context, constraints) {
            final cellWidth = (constraints.maxWidth - 16) / 3;
            final dpr = MediaQuery.devicePixelRatioOf(context);
            final cacheWidth = (cellWidth * dpr * 4 / 3).ceil().clamp(200, 640);
            return GridView.builder(
              shrinkWrap: true,
              primary: false,
              itemCount: items.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemBuilder: (context, index) {
                final photo = items[index];
                return MobilePressable(
                  semanticLabel: photo.title,
                  onTap: () => context.push('/photos/${photo.id}'),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: PortalMediaThumbnail(
                      imageUrl: photo.coverUrl,
                      cacheWidth: cacheWidth,
                      borderRadius: BorderRadius.zero,
                      fallback: ColoredBox(
                        color: context.mobileColors.surfaceRaised,
                        child: Icon(
                          Icons.image_outlined,
                          color: context.mobileColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
      loading: () => const MobileSkeletonBlock(height: 232),
      error:
          (_, _) => _ErrorCard(
            message: AppLocalizations.of(context).portalLoadPhotoFailed,
            onRetry: onRetry,
          ),
    );
  }
}

class _PortalSystemSummary extends StatelessWidget {
  const _PortalSystemSummary({
    required this.storage,
    required this.tasks,
    required this.online,
    required this.onStorageRetry,
  });

  final AsyncValue<FileStorageStats> storage;
  final AsyncValue<ActiveTaskSummary> tasks;
  final bool online;
  final VoidCallback onStorageRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final storageValue = storage.asData?.value;
    final taskValue = tasks.asData?.value;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.mobileColors.surface,
        border: Border.all(color: context.mobileColors.outline),
        borderRadius: BorderRadius.circular(MobileLayoutTokens.radius),
      ),
      child: Column(
        children: [
          _PortalSystemRow(
            icon: Icons.storage_rounded,
            label: l10n.portalStorageTitle,
            value:
                storageValue != null
                    ? l10n.portalMobileStorageUsed(
                      formatFileSize(storageValue.usedBytes),
                    )
                    : storage.isLoading
                    ? l10n.filesWaitingStats
                    : l10n.portalLoadStorageFailed,
            onTap:
                storage.hasError ? onStorageRetry : () => context.go('/files'),
          ),
          Divider(height: 1, color: context.mobileColors.outline),
          _PortalSystemRow(
            icon: online ? Icons.sync_rounded : Icons.sync_disabled_rounded,
            label: l10n.portalVisualSync,
            value:
                online
                    ? l10n.portalMobileSyncOnline
                    : l10n.portalMobileSyncOffline,
            statusColor:
                online
                    ? context.mobileColors.success
                    : context.mobileColors.warmAccent,
            onTap: () => context.push('/activity'),
          ),
          Divider(height: 1, color: context.mobileColors.outline),
          _PortalSystemRow(
            icon: Icons.task_alt_rounded,
            label: l10n.portalTaskTitle,
            value: l10n.portalMobileTaskSummary(
              taskValue?.activeCount ?? 0,
              taskValue?.failedCount ?? 0,
            ),
            accent:
                (taskValue?.failedCount ?? 0) > 0
                    ? context.mobileColors.danger
                    : context.mobileColors.musicAccent,
            onTap: () => context.push('/activity?tab=tasks'),
          ),
        ],
      ),
    );
  }
}

class _PortalSystemRow extends StatelessWidget {
  const _PortalSystemRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.accent,
    this.statusColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  /// 图标用色；缺省用模块主题色，三行保持同一视觉权重。
  final Color? accent;

  /// 行尾状态色点（在线/离线等状态语义），不再通过图标变色表达。
  final Color? statusColor;

  @override
  Widget build(BuildContext context) {
    final iconAccent = accent ?? context.mobileColors.musicAccent;
    final statusColor = this.statusColor;
    return MobilePressable(
      onTap: onTap,
      semanticLabel: '$label, $value',
      child: SizedBox(
        height: MobileLayoutTokens.listRowHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: iconAccent.withValues(alpha: 0.13),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconAccent, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.mobileColors.textPrimary,
                    fontSize: AppTypography.bodyLarge,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: context.mobileColors.textSecondary,
                    fontSize: AppTypography.bodySmall,
                  ),
                ),
              ),
              if (statusColor != null) ...[
                const SizedBox(width: 6),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                color: context.mobileColors.textSecondary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PortalTextAction extends StatelessWidget {
  const _PortalTextAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: context.mobileColors.musicAccent,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      child: Text(label),
    );
  }
}
