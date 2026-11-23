import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_backdrop_layer.dart';
import 'package:omninest/app/desktop/desktop_routes.dart';
import 'package:omninest/app/desktop/desktop_shell_state.dart';
import 'package:omninest/app/desktop/pages/desktop_home_lists.dart';
import 'package:omninest/app/desktop/pages/desktop_home_sections.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_glass.dart';
import 'package:omninest/app/desktop/widgets/desktop_skeleton.dart';
import 'package:omninest/app/desktop/widgets/desktop_sky.dart';
import 'package:omninest/app/desktop/widgets/desktop_surfaces.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_palette.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/widgets/desktop_shell_scope.dart';
import 'package:omninest/core/utils/file_size_formatter.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/features/files/file_dashboard.dart';
import 'package:omninest/features/music/music_portal.dart';
import 'package:omninest/features/photos/photo_dashboard.dart';
import 'package:omninest/features/portal/portal_weather.dart';
import 'package:omninest/features/reader/reader_dashboard.dart';
import 'package:omninest/features/video/video_dashboard.dart';

part 'desktop_home_hero.dart';

/// 桌面首页（样例 `Home.tsx`）：天象 hero + 四指标 + 继续观看 +
/// 此刻聆听 / 在读 + 最近照片 + 最近文件 / 动态。
///
/// 全部数据来自各模块的只读门面，没有演示占位：空库时每个分区
/// 落到各自的空态与前往入口，而不是留白或假数字。
class DesktopHomePage extends ConsumerStatefulWidget {
  const DesktopHomePage({super.key});

  /// 问候语与天象都跟当前时刻走。视觉基线需要确定的时刻，
  /// 测试在此注入固定时钟，生产路径始终读真实时间。
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  @override
  ConsumerState<DesktopHomePage> createState() => _DesktopHomePageState();
}

class _DesktopHomePageState extends ConsumerState<DesktopHomePage> {
  static const Duration _trunkGateTimeout = Duration(milliseconds: 500);

  final ScrollController _scroll = ScrollController();
  Timer? _trunkGateTimer;
  bool _trunkGateReleased = false;

  bool _isAsyncSettled(AsyncValue<Object?> state) =>
      !(state.isLoading && !state.hasValue);

  bool _isCoreTrunkSettled() {
    // 实时天气不阻塞首屏主干，仅等待 4 个核心媒体库概览 + 文件存储统计。
    return _isAsyncSettled(ref.read(movieDashboardProvider)) &&
        _isAsyncSettled(ref.read(photoDashboardProvider)) &&
        _isAsyncSettled(ref.read(musicPortalSnapshotProvider)) &&
        _isAsyncSettled(ref.read(readerDashboardProvider)) &&
        _isAsyncSettled(ref.read(fileStorageStatsProvider));
  }

  @override
  void initState() {
    super.initState();
    // 已有缓存时直出不闪；冷启动无缓存时启动 500ms 软超时门控。
    if (_isCoreTrunkSettled()) {
      _trunkGateReleased = true;
    } else {
      _trunkGateTimer = Timer(_trunkGateTimeout, () {
        if (!mounted || _trunkGateReleased) {
          return;
        }
        setState(() => _trunkGateReleased = true);
      });
    }
  }

  @override
  void dispose() {
    _trunkGateTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final now = DesktopHomePage.clock();
    final hour = now.hour + now.minute / 60;
    final user = ref.watch(authSessionProvider).asData?.value.user;
    final name =
        (user?.displayName?.trim().isNotEmpty ?? false)
            ? user!.displayName!.trim()
            : (user?.username ?? '');
    final movieSnapshot = ref.watch(
      movieDashboardProvider.select((state) {
        final dashboard = state.asData?.value;
        final resume =
            dashboard != null && dashboard.continueWatching.isNotEmpty
                ? dashboard.continueWatching.first
                : null;
        return (
          count: dashboard?.stats.movieCount ?? 0,
          addedToday: dashboard?.itemsAddedToday ?? 0,
          resumeId: resume?.id,
          resumeTitle: resume?.title,
          resumeArtUrl: resume?.posterUrl,
          resumeProgress: resume?.progressPercent ?? 0,
          loading: state.isLoading && !state.hasValue,
          failed: state.hasError && !state.hasValue,
        );
      }),
    );
    final photoSnapshot = ref.watch(
      photoDashboardProvider.select((state) {
        return (
          count: state.asData?.value.totalPhotos ?? 0,
          addedToday: state.asData?.value.itemsAddedToday ?? 0,
          loading: state.isLoading && !state.hasValue,
          failed: state.hasError && !state.hasValue,
        );
      }),
    );
    final readerSnapshot = ref.watch(
      readerDashboardProvider.select((state) {
        return (
          total: state.asData?.value.overview.totalItems ?? 0,
          addedToday: state.asData?.value.itemsAddedToday ?? 0,
          loading: state.isLoading && !state.hasValue,
          failed: state.hasError && !state.hasValue,
        );
      }),
    );
    final readingStats = ref.watch(
      readerStatsProvider.select((state) {
        return (
          streak: state.asData?.value.currentStreak ?? 0,
          longest: state.asData?.value.longestStreak ?? 0,
          loading: state.isLoading && !state.hasValue,
          failed: state.hasError && !state.hasValue,
        );
      }),
    );
    final storageSnapshot = ref.watch(
      fileStorageStatsProvider.select((state) {
        return (
          storage: state.asData?.value,
          loading: state.isLoading && !state.hasValue,
          failed: state.hasError && !state.hasValue,
        );
      }),
    );
    final storage = storageSnapshot.storage;
    final musicSnapshot = ref.watch(
      musicPortalSnapshotProvider.select((state) {
        final music = state.asData?.value;
        final track = music?.featuredTrack ?? music?.activeTrack;
        return (
          trackId: track?.id,
          trackTitle: track?.title,
          trackArtist: track?.artistName,
          trackCoverUrl: track?.listCoverUrl ?? track?.coverUrl,
          listeningHours: (music?.weekListeningSeconds ?? 0) / 3600,
          itemsAddedToday: music?.itemsAddedToday ?? 0,
          trackCount: music?.trackCount ?? 0,
          loading: state.isLoading && !state.hasValue,
          failed: state.hasError && !state.hasValue,
        );
      }),
    );
    // 实时天气不阻塞主干渲染，就绪后独立更新天气角标。
    final weather = ref.watch(
      realtimeWeatherProvider.select((state) => state.asData?.value),
    );
    final reduceMotion = ref.watch(
      desktopAppearanceProvider.select((a) => a.reduceMotion),
    );
    // 壳层已经完成了背景素材、作用域与路由的统一判定；首页直接消费这
    // 一位，避免异步状态切换时 Hero 比壁纸层晚一帧或早一帧。
    final backdropActive =
        DesktopShellScope.isHosted(context)
            ? DesktopShellScope.isBackdropActive(context)
            : desktopBackdropVisibleForRoute(ref, DesktopRoutes.home);

    // hero 的次按钮跟样例一样直呼曲名：泛化的「开始聆听」在播放条已经
    // 有曲目时反而比按钮旁边那行文案更模糊。库空时才退回泛化文案。
    final listenLabel = musicSnapshot.trackTitle ?? l10n.desktopStartListening;
    final greeting =
        hour < 5
            ? l10n.desktopGreetingNight
            : hour < 12
            ? l10n.desktopGreetingMorning
            : hour < 18
            ? l10n.desktopGreetingAfternoon
            : l10n.desktopGreetingEvening;
    final libraryTotal =
        movieSnapshot.count +
        photoSnapshot.count +
        musicSnapshot.trackCount +
        readerSnapshot.total;
    final libraryAddedToday =
        movieSnapshot.addedToday +
        photoSnapshot.addedToday +
        musicSnapshot.itemsAddedToday +
        readerSnapshot.addedToday;
    final homeContentLoading =
        movieSnapshot.loading ||
        photoSnapshot.loading ||
        musicSnapshot.loading ||
        readerSnapshot.loading;
    final homeContentFailed =
        movieSnapshot.failed ||
        photoSnapshot.failed ||
        musicSnapshot.failed ||
        readerSnapshot.failed;

    final coreTrunkReady = !homeContentLoading && !storageSnapshot.loading;
    if (coreTrunkReady && !_trunkGateReleased) {
      _trunkGateReleased = true;
      _trunkGateTimer?.cancel();
      _trunkGateTimer = null;
    }
    final trunkLoading = !_trunkGateReleased;

    return Scrollbar(
      controller: _scroll,
      child: SingleChildScrollView(
        controller: _scroll,
        child: DesktopPage(
          topPadding: DesktopMetrics.pageTopPaddingCompact,
          // 样例只给 `.hero-sky` 与各列表条目挂入场动画，区块容器本身不动；
          // 交错覆盖在 `.stat`/`.rail`/`.mini-list`/`.timeline` 各自内部完成。
          children: [
            DesktopSkeletonSwitcher(
              regionId: 'home-trunk',
              hasData: !trunkLoading,
              loading: trunkLoading,
              skeleton: const _HomeTrunkSkeleton(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DesktopRise(
                    duration: DesktopMotion.slow,
                    // 样例 `.bd-on .hero-sky .sky { display:none }`：自定义壁纸在场
                    // 时首页不再叠实时天象，否则两层天气画面互相打架。
                    child: _HeroSky(
                      showSky: !backdropActive,
                      // 样例眉标只到「周六，11 月 14 日」：年份在首页永不需要，
                      // 带上它会把这行从三格撑成四格，压掉右边天气卡的对齐。
                      dateLabel: DateFormat.MMMMEEEEd(locale).format(now),
                      greeting: l10n.desktopGreeting(greeting, name),
                      lead:
                          homeContentFailed
                              ? l10n.photosOperationFailed
                              : movieSnapshot.resumeTitle == null
                              ? l10n.desktopHomeLeadQuiet(libraryTotal)
                              : l10n.desktopHomeLeadResume(
                                libraryTotal,
                                movieSnapshot.resumeTitle!,
                              ),
                      hour: hour,
                      weather: weather,
                      contentLoading: homeContentLoading,
                      contentFailed: homeContentFailed,
                      retryLabel: l10n.commonRetry,
                      onRetryContent: () {
                        ref.invalidate(movieDashboardProvider);
                        ref.invalidate(photoDashboardProvider);
                        ref.invalidate(musicPortalSnapshotProvider);
                        ref.invalidate(readerDashboardProvider);
                      },
                      reduceMotion: reduceMotion,
                      backdropActive: backdropActive,
                      resumeLabel:
                          movieSnapshot.resumeTitle == null
                              ? null
                              : l10n.desktopResumeTitle(
                                movieSnapshot.resumeTitle!,
                              ),
                      resumeTitle: movieSnapshot.resumeTitle,
                      resumeArtUrl: movieSnapshot.resumeArtUrl,
                      resumeProgress: movieSnapshot.resumeProgress,
                      listenLabel: listenLabel,
                      listenArtist:
                          musicSnapshot.trackArtist ??
                          l10n.desktopStartListening,
                      listenArtUrl: musicSnapshot.trackCoverUrl,
                      onResume:
                          movieSnapshot.resumeId == null
                              ? null
                              : () => context.push(
                                DesktopRoutes.moviePlay(
                                  movieSnapshot.resumeId!,
                                ),
                              ),
                      onStartListening: () {
                        final trackId = musicSnapshot.trackId;
                        if (trackId == null) {
                          context.go(DesktopRoutes.music);
                          return;
                        }
                        ref
                            .read(musicPortalActionsProvider)
                            .playTrackById(trackId);
                        context.push(DesktopRoutes.nowPlaying);
                      },
                    ),
                  ),
                  const SizedBox(height: 22),
                  _StatsRow(
                    libraryTotal: libraryTotal,
                    libraryAddedToday: libraryAddedToday,
                    listeningHours: musicSnapshot.listeningHours,
                    readingStreak: readingStats.streak,
                    longestReadingStreak: readingStats.longest,
                    storage: storage,
                    loading: [
                      movieSnapshot.loading ||
                          photoSnapshot.loading ||
                          musicSnapshot.loading ||
                          readerSnapshot.loading,
                      musicSnapshot.loading,
                      readingStats.loading,
                      storageSnapshot.loading,
                    ],
                    failed: [
                      movieSnapshot.failed ||
                          photoSnapshot.failed ||
                          musicSnapshot.failed ||
                          readerSnapshot.failed,
                      musicSnapshot.failed,
                      readingStats.failed,
                      storageSnapshot.failed,
                    ],
                    retry: [
                      () {
                        ref.invalidate(movieDashboardProvider);
                        ref.invalidate(photoDashboardProvider);
                        ref.invalidate(musicPortalSnapshotProvider);
                        ref.invalidate(readerDashboardProvider);
                      },
                      () => ref.invalidate(musicPortalSnapshotProvider),
                      () => ref.invalidate(readerStatsProvider),
                      () => ref.invalidate(fileStorageStatsProvider),
                    ],
                  ),
                  DesktopSection(
                    eyebrow: l10n.desktopPickUpWhereYouLeft,
                    title: l10n.desktopContinueWatching,
                    actionLabel: l10n.desktopAllMovies,
                    onAction: () => context.go(DesktopRoutes.movies),
                    child: const DesktopContinueRail(),
                  ),
                ],
              ),
            ),
            _TwoColumns(
              left: DesktopSection(
                eyebrow: l10n.desktopFreshArrivals,
                title: l10n.desktopEveningListening,
                actionLabel: l10n.desktopOpenMusic,
                onAction: () => context.go(DesktopRoutes.music),
                child: const DesktopListeningRow(),
              ),
              right: DesktopSection(
                eyebrow: l10n.desktopBooksEyebrow,
                title: l10n.desktopCurrentlyReading,
                actionLabel: l10n.desktopOpenReader,
                onAction: () => context.go(DesktopRoutes.reader),
                child: const DesktopReadingCard(),
              ),
            ),
            DesktopSection(
              eyebrow: l10n.desktopFreshArrivals,
              title: l10n.desktopRecentPhotos,
              actionLabel: l10n.desktopOpenPhotos,
              onAction: () => context.go(DesktopRoutes.photos),
              child: const DesktopPhotoStrip(),
            ),
            _TwoColumns(
              equal: true,
              left: DesktopSection(
                title: l10n.desktopRecentFiles,
                actionLabel: l10n.desktopOpenFiles,
                onAction: () => context.go(DesktopRoutes.files),
                child: const DesktopRecentFiles(),
              ),
              right: DesktopSection(
                title: l10n.desktopActivity,
                actionLabel: l10n.desktopNotifications,
                onAction: () => context.push(DesktopRoutes.notifications),
                child: const DesktopActivityTimeline(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 首屏主干联合骨架：严格对齐 Hero + 4 统计卡 + ContinueRail 高度，
/// 在 4 媒体库概览 + 存储统计全就绪或达到 500ms 软超时后统一淡入。
class _HomeTrunkSkeleton extends StatelessWidget {
  const _HomeTrunkSkeleton();

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final cardRadius = BorderRadius.circular(DesktopMetrics.radiusCard);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(32, 28, 32, 26),
          decoration: BoxDecoration(
            color: skin.panel,
            borderRadius: BorderRadius.circular(DesktopMetrics.radiusHero),
            border: Border.all(color: skin.line),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              DesktopSkeletonBox(width: 148, height: 11, radius: 5, index: 0),
              SizedBox(height: 14),
              DesktopSkeletonBox(width: 300, height: 34, radius: 8, index: 1),
              SizedBox(height: 12),
              DesktopSkeletonBox(width: 360, height: 15, radius: 6, index: 2),
              SizedBox(height: 24),
              Row(
                children: [
                  DesktopSkeletonBox(
                    width: 168,
                    height: 42,
                    radius: 12,
                    index: 3,
                  ),
                  SizedBox(width: 12),
                  DesktopSkeletonBox(
                    width: 154,
                    height: 42,
                    radius: 12,
                    index: 4,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Padding(
          padding: const EdgeInsets.only(bottom: 40),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 720 ? 2 : 4;
              const gap = 14.0;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (var i = 0; i < 4; i++)
                    SizedBox(
                      width: width,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                        decoration: BoxDecoration(
                          color: skin.panel,
                          borderRadius: cardRadius,
                          border: Border.all(color: skin.line),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            DesktopSkeletonBox(
                              width: 30,
                              height: 30,
                              radius: 9,
                              index: i * 4,
                            ),
                            const SizedBox(height: 14),
                            DesktopSkeletonBox(
                              width: 76,
                              height: 11,
                              radius: 5,
                              index: i * 4 + 1,
                            ),
                            const SizedBox(height: 5),
                            DesktopSkeletonBox(
                              width: 104,
                              height: 30,
                              radius: 6,
                              index: i * 4 + 2,
                            ),
                            const SizedBox(height: 4),
                            DesktopSkeletonBox(
                              width: 116,
                              height: 11,
                              radius: 5,
                              index: i * 4 + 3,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DesktopSkeletonBox(width: 124, height: 10, radius: 5, index: 1),
            SizedBox(height: 8),
            DesktopSkeletonBox(width: 168, height: 22, radius: 6, index: 2),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 340 * 9 / 16 + 16,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 12, top: 4),
            itemCount: 4,
            separatorBuilder:
                (context, index) =>
                    const SizedBox(width: DesktopMetrics.railGap),
            itemBuilder:
                (context, index) => SizedBox(
                  width: 340,
                  child: DesktopSkeletonBox(
                    height: 191,
                    radius: 16,
                    index: index,
                  ),
                ),
          ),
        ),
        const SizedBox(height: 36),
      ],
    );
  }
}

/// 样例 `.cols-2`：宽屏两栏，窄于 1100 叠成单列。
class _TwoColumns extends StatelessWidget {
  const _TwoColumns({
    required this.left,
    required this.right,
    this.equal = false,
  });

  final Widget left;
  final Widget right;
  final bool equal;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 1100) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [left, right],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: equal ? 10 : 14, child: left),
            const SizedBox(width: 36),
            Expanded(flex: 10, child: right),
          ],
        );
      },
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.libraryTotal,
    required this.libraryAddedToday,
    required this.listeningHours,
    required this.readingStreak,
    required this.longestReadingStreak,
    required this.storage,
    required this.loading,
    required this.failed,
    required this.retry,
  });

  final int libraryTotal;
  final int libraryAddedToday;
  final double listeningHours;
  final int readingStreak;
  final int longestReadingStreak;
  final FileStorageStats? storage;
  final List<bool> loading;
  final List<bool> failed;
  final List<VoidCallback> retry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final used = storage == null ? 0.0 : storage!.usedBytes / 1073741824;
    final cards = <Widget>[
      _StatCard(
        icon: DesktopIcons.library,
        label: l10n.desktopStatLibrary,
        value: '$libraryTotal',
        numericValue: libraryTotal.toDouble(),
        caption: l10n.desktopStatLibraryAddedToday(libraryAddedToday),
        loading: loading[0],
        failed: failed[0],
        onRetry: retry[0],
      ),
      _StatCard(
        icon: DesktopIcons.music,
        label: l10n.desktopStatListening,
        value: listeningHours.toStringAsFixed(1),
        numericValue: listeningHours,
        decimals: 1,
        unit: l10n.desktopStatHours,
        caption: l10n.desktopStatListeningSub,
        loading: loading[1],
        failed: failed[1],
        onRetry: retry[1],
      ),
      _StatCard(
        icon: DesktopIcons.book,
        label: l10n.desktopStatReading,
        value: '$readingStreak',
        numericValue: readingStreak.toDouble(),
        unit: l10n.desktopStatDays,
        caption: l10n.desktopStatLongestStreakCaption(longestReadingStreak),
        loading: loading[2],
        failed: failed[2],
        onRetry: retry[2],
      ),
      _StatCard(
        icon: DesktopIcons.cloud,
        label: l10n.desktopStatStorage,
        value: used.toStringAsFixed(1),
        numericValue: used,
        decimals: 1,
        unit: 'GB',
        caption:
            storage == null || storage!.isQuotaUnlimited
                ? l10n.desktopStatNoQuota
                : l10n.desktopStatOfTotal(formatFileSize(storage!.quotaBytes)),
        loading: loading[3],
        failed: failed[3],
        onRetry: retry[3],
      ),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 40),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth < 720 ? 2 : 4;
          const gap = 14.0;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              // 样例 `.stat`：每张卡按 `--i * 55ms` 各自入场。
              for (var i = 0; i < cards.length; i++)
                SizedBox(
                  width: width,
                  child: DesktopStagger(index: i, child: cards[i]),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.caption,
    this.unit,
    this.numericValue,
    this.decimals = 0,
    required this.loading,
    required this.failed,
    required this.onRetry,
  });

  final IconData icon;
  final String label;
  final String value;
  final String caption;
  final String? unit;

  /// 有值时从 0 滚到目标值（样例 `CountUp`，1100ms 三次缓出）。
  final double? numericValue;
  final int decimals;
  final bool loading;
  final bool failed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final cardRadius = BorderRadius.circular(DesktopMetrics.radiusCard);
    final statGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color.lerp(skin.panel, Colors.white, 0.03)!, skin.panel],
    );
    if (loading) {
      return DesktopGlassSurface(
        borderRadius: cardRadius,
        blur: 20,
        saturation: 1.0,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          decoration: BoxDecoration(
            gradient: statGradient,
            borderRadius: cardRadius,
            border: Border.all(color: skin.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const DesktopSkeletonBox(width: 30, height: 30, radius: 9),
              const SizedBox(height: 14),
              const DesktopSkeletonBox(width: 76, height: 11, radius: 5),
              const SizedBox(height: 5),
              const DesktopSkeletonBox(width: 104, height: 30, radius: 6),
              const SizedBox(height: 4),
              const DesktopSkeletonBox(width: 116, height: 11, radius: 5),
            ],
          ),
        ),
      );
    }
    return DesktopHover(
      enabled: true,
      cursor: SystemMouseCursors.basic,
      builder:
          (context, hovered) => AnimatedContainer(
            duration: DesktopMotion.of(context, DesktopMotion.lift),
            curve: DesktopMotion.spring,
            transform: Matrix4.translationValues(0, hovered ? -3 : 0, 0),
            child: DesktopGlassSurface(
              borderRadius: cardRadius,
              blur: 20,
              saturation: 1.0,
              child: AnimatedContainer(
                duration: DesktopMotion.of(context, DesktopMotion.lift),
                curve: DesktopMotion.spring,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                decoration: BoxDecoration(
                  gradient: statGradient,
                  borderRadius: cardRadius,
                  border: Border.all(color: hovered ? skin.line2 : skin.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: skin.accentWash(0.14),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(icon, size: 16, color: skin.accent),
                    ),
                    const SizedBox(height: 14),
                    Text(label, style: DesktopType.caption(skin.text3)),
                    const SizedBox(height: 2),
                    if (failed)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text('—', style: DesktopType.statValue(skin.text)),
                          const Spacer(),
                          DesktopLink(
                            label: l10n.commonRetry,
                            onPressed: onRetry,
                          ),
                        ],
                      )
                    else
                      numericValue == null
                          ? Text(
                            unit == null ? value : '$value$unit',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DesktopType.statValue(skin.text),
                          )
                          : TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: numericValue),
                            duration: DesktopMotion.progress,
                            curve: Curves.easeOutCubic,
                            builder:
                                (context, animated, _) => Text(
                                  unit == null
                                      ? animated.toStringAsFixed(decimals)
                                      : '${animated.toStringAsFixed(decimals)}$unit',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: DesktopType.statValue(skin.text),
                                ),
                          ),
                    const SizedBox(height: 2),
                    Text(
                      failed ? l10n.photosOperationFailed : caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesktopType.caption(skin.text3),
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
  }
}
