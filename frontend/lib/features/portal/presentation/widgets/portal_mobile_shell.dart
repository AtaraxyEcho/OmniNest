import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/app/theme/feature/portal_mobile_theme.dart';
import 'package:omninest/app/theme/mobile_layout_tokens.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_controller.dart';
import 'package:omninest/features/backdrop/backdrop_ui.dart';
import 'package:omninest/core/widgets/animated_card.dart';
import 'package:omninest/features/notifications/notification_ui.dart';
import 'package:omninest/core/widgets/font_scale_control.dart';
import 'package:omninest/core/widgets/user_avatar_menu.dart';
import 'package:omninest/features/music/music_portal.dart';
import 'package:omninest/features/portal/application/portal_dashboard_providers.dart';
import 'package:omninest/features/portal/application/weather_provider.dart';
import 'package:omninest/features/portal/presentation/widgets/storage_overview_widget.dart';
import 'package:omninest/features/portal/presentation/widgets/continue_watching_widget.dart';
import 'package:omninest/features/portal/presentation/widgets/now_playing_widget.dart';
import 'package:omninest/features/portal/presentation/widgets/reading_progress_widget.dart';
import 'package:omninest/features/portal/presentation/widgets/recent_photos_widget.dart';
import 'package:omninest/features/portal/presentation/widgets/weather_detail_dialog.dart';
import 'package:omninest/features/portal/presentation/widgets/portal_weather_profile.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/features/portal/presentation/widgets/portal_glass_components.dart';
import 'package:omninest/features/portal/presentation/widgets/portal_glass_sliver_app_bar.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/utils/file_size_formatter.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/portal/presentation/widgets/portal_media_thumbnail.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/tasks/application/task_controller.dart';
import 'package:omninest/features/tasks/domain/task_record.dart';
import 'package:omninest/features/video/domain/movie_models.dart';

part 'portal_mobile_system_widgets.dart';
part 'portal_mobile_quick_actions.dart';
part 'portal_mobile_weather_card.dart';
part 'portal_mobile_hosted_content.dart';

/// Portal 移动端入口，入场动画只在首次挂载时播放。
class PortalMobileShell extends ConsumerStatefulWidget {
  const PortalMobileShell({super.key});

  @override
  ConsumerState<PortalMobileShell> createState() => _PortalMobileShellState();
}

class _PortalMobileShellState extends ConsumerState<PortalMobileShell> {
  static const _animTotal = Duration(milliseconds: 220);
  static const _entryDuration = Duration(milliseconds: 220);
  static const _cardCount = 7;

  DateTime? _lastBackPress;
  static Duration _stagger(int index) =>
      Duration(milliseconds: (_animTotal.inMilliseconds * index) ~/ _cardCount);

  Future<void> _onRefresh() async {
    final actions = ref.read(portalDashboardActionsProvider);
    // 用户显式下拉刷新，不受分区节流限制。
    await actions.refreshAll(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hosted = MobileShellScope.isHosted(context);
    if (hosted) {
      return _HostedPortalContent(onRefresh: _onRefresh);
    }
    final storageStats = ref.watch(portalStorageStatsProvider);
    final movieDashboard = ref.watch(portalMovieDashboardProvider);
    final musicSnapshot = ref.watch(portalMusicSnapshotProvider);
    final photoDashboard = ref.watch(portalPhotoDashboardProvider);
    final readerDashboard = ref.watch(portalReaderDashboardProvider);
    final backdropState =
        ref.watch(appBackdropControllerProvider).asData?.value;
    final appBackdropActive =
        backdropState?.settings.enabled == true &&
        backdropState?.selectedBackdrop != null &&
        backdropState?.selectedBackdrop?.missing == false;
    final portalTheme = PortalMobileTheme.resolve(
      context,
      backdropActive: appBackdropActive,
    );
    final scheme = portalTheme.colorScheme;
    final foreground = scheme.onSurface;
    final animationsDisabled =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    Widget entrance(String key, int index, Widget child) {
      return AnimatedCard(
        key: ValueKey(key),
        delay: animationsDisabled ? Duration.zero : _stagger(index),
        duration: _entryDuration,
        enabled: !animationsDisabled,
        child: child,
      );
    }

    void retry(PortalDashboardSection section) {
      unawaited(ref.read(portalDashboardActionsProvider).retry(section));
    }

    Widget mobileSurface(Widget child) {
      if (hosted) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainer.withValues(alpha: 0.92),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: child,
          ),
        );
      }
      return PortalGlassCard(
        padding: EdgeInsets.zero,
        borderRadius: 8,
        surfaceAlpha: appBackdropActive ? 0.62 : 0.90,
        shadow: !appBackdropActive,
        backgroundColor: scheme.surfaceContainer,
        borderColor: scheme.outlineVariant,
        child: child,
      );
    }

    final content = PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final now = DateTime.now();
        if (_lastBackPress == null ||
            now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
          _lastBackPress = now;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.portalPressBackAgain),
              duration: const Duration(seconds: 2),
            ),
          );
          return;
        }
        Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor:
            appBackdropActive
                ? Colors.transparent
                : Theme.of(context).scaffoldBackgroundColor,
        extendBodyBehindAppBar: true,
        body: Stack(
          children: [
            // 主内容
            RefreshIndicator(
              displacement: 40,
              edgeOffset: 0,
              strokeWidth: 2.5,
              color: scheme.primary,
              onRefresh: _onRefresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  if (!hosted)
                    PortalGlassSliverAppBar(
                      title: const Text('OmniNest'),
                      actions: [
                        IconButton(
                          tooltip: l10n.portalLocalBackdropTitle,
                          onPressed:
                              () => showAppBackdropSettings(
                                context,
                                palette: AppBackdropPalette(
                                  text: foreground,
                                  muted: scheme.onSurfaceVariant,
                                  accent: scheme.primary,
                                  accentAlt: scheme.tertiary,
                                ),
                              ),
                          icon: Icon(
                            Icons.wallpaper_rounded,
                            color: foreground,
                            size: 20,
                          ),
                        ),
                        FontScaleControl(size: 20, color: foreground),
                        NotificationIcon(size: 20, color: foreground),
                        const SizedBox(width: 8),
                        const UserAvatarMenu(),
                      ],
                    ),
                  // 卡片列表
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, hosted ? 16 : 100),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        entrance(
                          'weather',
                          0,
                          mobileSurface(const _WeatherCard()),
                        ),
                        if (hosted) ...[
                          const SizedBox(height: 12),
                          entrance(
                            'hosted-quick-actions',
                            1,
                            mobileSurface(const _MobileQuickActions()),
                          ),
                        ],
                        if (!hosted) ...[
                          const SizedBox(height: 12),
                          entrance(
                            'weekly-stats',
                            1,
                            mobileSurface(
                              _WeeklyStatsCard(
                                readingCount: readerDashboard.whenOrNull(
                                  data: (d) => d.overview.continueCount,
                                ),
                                musicPlays: musicSnapshot.whenOrNull(
                                  data: (snapshot) => snapshot.recentPlayCount,
                                ),
                                photoCount: photoDashboard.whenOrNull(
                                  data: (d) => d.totalPhotos,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          entrance(
                            'quick-actions',
                            2,
                            mobileSurface(const _MobileQuickActions()),
                          ),
                        ],
                        const SizedBox(height: 12),
                        entrance(
                          'continue-watching',
                          3,
                          mobileSurface(
                            movieDashboard.when(
                              data:
                                  (d) => ContinueWatchingWidget(
                                    items: d.continueWatching,
                                  ),
                              loading: () => const _SkeletonCard(height: 100),
                              error:
                                  (_, _) => _ErrorCard(
                                    message: l10n.portalLoadMovieFailed,
                                    onRetry:
                                        () =>
                                            retry(PortalDashboardSection.video),
                                  ),
                            ),
                          ),
                        ),
                        if (!hosted) ...[
                          const SizedBox(height: 12),
                          entrance(
                            'now-playing',
                            4,
                            mobileSurface(
                              musicSnapshot.when(
                                data:
                                    (snapshot) => NowPlayingWidget(
                                      track: snapshot.featuredTrack,
                                    ),
                                loading: () => const _SkeletonCard(height: 80),
                                error:
                                    (_, _) => _ErrorCard(
                                      message: l10n.portalLoadMusicFailed,
                                      onRetry:
                                          () => retry(
                                            PortalDashboardSection.music,
                                          ),
                                    ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        if (hosted) ...[
                          entrance(
                            'hosted-storage',
                            5,
                            storageStats.when(
                              data:
                                  (s) => mobileSurface(
                                    StorageOverviewWidget(stats: s),
                                  ),
                              loading: () => const _SkeletonCard(height: 100),
                              error:
                                  (_, _) => _ErrorCard(
                                    message: l10n.portalLoadStorageFailed,
                                    onRetry:
                                        () => retry(
                                          PortalDashboardSection.storage,
                                        ),
                                  ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          entrance(
                            'hosted-reading',
                            5,
                            readerDashboard.when(
                              data:
                                  (d) => mobileSurface(
                                    ReadingProgressWidget(
                                      item: d.continueReading.firstOrNull,
                                    ),
                                  ),
                              loading: () => const _SkeletonCard(height: 100),
                              error:
                                  (_, _) => _ErrorCard(
                                    message: l10n.portalLoadReadingFailed,
                                    onRetry:
                                        () => retry(
                                          PortalDashboardSection.reader,
                                        ),
                                  ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          entrance(
                            'hosted-recent-photos',
                            6,
                            photoDashboard.when(
                              data:
                                  (d) => mobileSurface(
                                    RecentPhotosWidget(
                                      photos: d.recentPhotos.take(3).toList(),
                                    ),
                                  ),
                              loading: () => const _SkeletonCard(height: 100),
                              error:
                                  (_, _) => _ErrorCard(
                                    message: l10n.portalLoadPhotoFailed,
                                    onRetry:
                                        () => retry(
                                          PortalDashboardSection.photos,
                                        ),
                                  ),
                            ),
                          ),
                        ] else ...[
                          entrance(
                            'storage-reading',
                            5,
                            _TwoColumnRow(
                              left: storageStats.when(
                                data:
                                    (s) => mobileSurface(
                                      StorageOverviewWidget(stats: s),
                                    ),
                                loading: () => const _SkeletonCard(height: 100),
                                error:
                                    (_, _) => _ErrorCard(
                                      message: l10n.portalLoadStorageFailed,
                                      onRetry:
                                          () => retry(
                                            PortalDashboardSection.storage,
                                          ),
                                    ),
                              ),
                              right: readerDashboard.when(
                                data:
                                    (d) => mobileSurface(
                                      ReadingProgressWidget(
                                        item: d.continueReading.firstOrNull,
                                      ),
                                    ),
                                loading: () => const _SkeletonCard(height: 100),
                                error:
                                    (_, _) => _ErrorCard(
                                      message: l10n.portalLoadReadingFailed,
                                      onRetry:
                                          () => retry(
                                            PortalDashboardSection.reader,
                                          ),
                                    ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          entrance(
                            'recent-photos',
                            6,
                            photoDashboard.when(
                              data:
                                  (d) => mobileSurface(
                                    RecentPhotosWidget(
                                      photos: d.recentPhotos.take(3).toList(),
                                    ),
                                  ),
                              loading: () => const _SkeletonCard(height: 100),
                              error:
                                  (_, _) => _ErrorCard(
                                    message: l10n.portalLoadPhotoFailed,
                                    onRetry:
                                        () => retry(
                                          PortalDashboardSection.photos,
                                        ),
                                  ),
                            ),
                          ),
                        ],
                      ]),
                    ),
                  ),
                ],
              ),
            ),
            if (!hosted)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: PortalGlassDock(
                  currentIndex: -1,
                  onTap: (index) {
                    final routes = [
                      '/files',
                      '/video',
                      '/music',
                      '/photos',
                      '/reader',
                    ];
                    context.go(routes[index]);
                  },
                  items: [
                    PortalGlassDockItem(
                      icon: Icons.folder_outlined,
                      selectedIcon: Icons.folder_rounded,
                      label: l10n.portalDockFiles,
                    ),
                    PortalGlassDockItem(
                      icon: Icons.movie_outlined,
                      selectedIcon: Icons.movie_rounded,
                      label: l10n.portalDockMovies,
                    ),
                    PortalGlassDockItem(
                      icon: Icons.music_note_outlined,
                      selectedIcon: Icons.music_note_rounded,
                      label: l10n.portalDockMusic,
                    ),
                    PortalGlassDockItem(
                      icon: Icons.photo_library_outlined,
                      selectedIcon: Icons.photo_library_rounded,
                      label: l10n.portalDockPhotos,
                    ),
                    PortalGlassDockItem(
                      icon: Icons.menu_book_outlined,
                      selectedIcon: Icons.menu_book_rounded,
                      label: l10n.portalDockReading,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
    return Theme(data: portalTheme, child: content);
  }
}

/// 双列等高布局
class _TwoColumnRow extends StatelessWidget {
  const _TwoColumnRow({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 140,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left),
          const SizedBox(width: 12),
          Expanded(child: right),
        ],
      ),
    );
  }
}

// ─── 骨架屏 & 错误卡片 ──────────────────────────────────────────────────────

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.height});
  final double height;
  @override
  Widget build(BuildContext context) {
    return Card(
      child: SizedBox(
        height: height,
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: scheme.error, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            TextButton(onPressed: onRetry, child: Text(l10n.coreRetry)),
          ],
        ),
      ),
    );
  }
}

class _PortalInlineRetry extends StatelessWidget {
  const _PortalInlineRetry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Icon(Icons.sync_problem_rounded, size: 16, color: scheme.error),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        TextButton(onPressed: onRetry, child: Text(l10n.coreRetry)),
      ],
    );
  }
}
