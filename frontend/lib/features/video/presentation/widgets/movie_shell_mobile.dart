part of 'movie_shell.dart';

/// 新版移动端底部导航：电影/剧集/动漫/继续观看/收藏 + 更多（打开分区抽屉）。
const List<MovieSection> _movieMobileBottomSections = [
  MovieSection.movies,
  MovieSection.tvShows,
  MovieSection.anime,
  MovieSection.continueWatching,
  MovieSection.favorites,
];

class _MovieMobileShell extends StatelessWidget {
  const _MovieMobileShell({
    required this.section,
    required this.child,
    required this.canManage,
    required this.childOwnsScroll,
    this.counts = const {},
    this.onSectionSelected,
    this.onRefresh,
    this.onBack,
  });

  final MovieSection section;
  final Widget child;
  final bool canManage;
  final Map<MovieSection, int> counts;
  final bool childOwnsScroll;
  final ValueChanged<MovieSection>? onSectionSelected;
  final Future<void> Function()? onRefresh;
  final VoidCallback? onBack;

  /// 托管四段次序（For you/Films/Series/Anime），滑动切换依据。
  static const List<MovieSection> _hostedSections = [
    MovieSection.continueWatching,
    MovieSection.movies,
    MovieSection.tvShows,
    MovieSection.anime,
  ];

  /// 当前生效分段（不在四段内的管理分区按首段计）。
  MovieSection get effectiveSection =>
      _hostedSections.contains(section) ? section : _hostedSections.first;

  /// 返回链路：优先走调用方回调；缺省时直弹 Navigator（页面被
  /// PopScope(canPop: false) 拦截，maybePop 会回落到自身形成递归），
  /// 栈底直达链接回到媒体库空间。
  void _handleBack(BuildContext context) {
    // 模块内逐级回退：非首栏先回 For you，首栏才离开模块。
    if (MobileShellScope.isHosted(context) &&
        effectiveSection != _hostedSections.first &&
        onSectionSelected != null) {
      onSectionSelected!(_hostedSections.first);
      return;
    }
    final back = onBack;
    if (back != null) {
      back();
      return;
    }
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      context.go('/library');
    }
  }

  @override
  Widget build(BuildContext context) {
    final hosted = MobileShellScope.isHosted(context);
    final navIndex = _selectedIndex;
    final isMore = navIndex == _movieMobileBottomSections.length;

    final pageContent =
        isMore && !hosted
            ? const SizedBox.shrink()
            : childOwnsScroll
            ? Column(
              children: [
                if (!hosted)
                  _MovieMobileTopBar(
                    section: section,
                    canManage: canManage,
                    counts: counts,
                    onRefresh: onRefresh,
                    onSectionSelected: onSectionSelected,
                  ),
                Expanded(
                  child: RefreshIndicator(
                    color: context.movieRedesign.primary,
                    onRefresh: onRefresh ?? () async {},
                    child: MovieSectionTransition(
                      section: section,
                      slideDistance: 0.024,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: child,
                      ),
                    ),
                  ),
                ),
              ],
            )
            : RefreshIndicator(
              displacement: 40,
              edgeOffset: hosted ? 0 : 44,
              strokeWidth: 2.5,
              color: context.movieRedesign.primary,
              onRefresh: () async {
                await (onRefresh ?? () async {})();
                await Future<void>.delayed(const Duration(milliseconds: 200));
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  if (!hosted)
                    SliverAppBar(
                      pinned: true,
                      elevation: 0,
                      scrolledUnderElevation: 0,
                      backgroundColor: context.movieRedesign.background,
                      surfaceTintColor: Colors.transparent,
                      titleSpacing: 0,
                      automaticallyImplyLeading: false,
                      title: _MovieMobileTopBar(
                        section: section,
                        canManage: canManage,
                        counts: counts,
                        onRefresh: onRefresh,
                        onSectionSelected: onSectionSelected,
                      ),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    sliver: SliverToBoxAdapter(
                      child: MovieSectionTransition(
                        section: section,
                        slideDistance: 0.024,
                        child: child,
                      ),
                    ),
                  ),
                ],
              ),
            );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack(context);
      },
      child: Scaffold(
        backgroundColor: context.movieRedesign.background,
        extendBody: !hosted,
        body: Builder(
          builder: (context) {
            final content = Column(
              children: [
                if (hosted) ...[
                  MobileModuleHeader(
                    title: AppLocalizations.of(context).moduleMoviesTitle,
                    subtitle: AppLocalizations.of(context).moviesModuleSubtitle(
                      counts[MovieSection.movies] ?? 0,
                      counts[MovieSection.continueWatching] ?? 0,
                    ),
                    onBack: () => _handleBack(context),
                    actions: [
                      MobileGlassIconButton(
                        tooltip: AppLocalizations.of(context).videoSearch,
                        icon: Icons.search_rounded,
                        onPressed: () => _showMovieMobileSearchDialog(context),
                      ),
                    ],
                  ),
                ],
                if (hosted)
                  _MovieMobileSectionBar(
                    section: section,
                    onSectionSelected: onSectionSelected,
                  ),
                Expanded(
                  child: MobileSectionSwipe(
                    onSwipe: (toNext) {
                      final target = adjacentSection(
                        _hostedSections,
                        effectiveSection,
                        toNext,
                      );
                      if (target != null) {
                        onSectionSelected?.call(target);
                      }
                    },
                    child: pageContent,
                  ),
                ),
              ],
            );
            if (!hosted) {
              return content;
            }
            // 样例 module-overlay：深玻璃表面（≈.94 不透明）+ 650 限宽居中。
            return MobilePageSurface(
              exposeBackdrop: true,
              backdropOpacity: 0.92,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 650),
                  child: content,
                ),
              ),
            );
          },
        ),
        bottomNavigationBar:
            hosted
                ? null
                : _MovieMobileBottomNav(
                  section: section,
                  counts: counts,
                  canManage: canManage,
                  onSectionSelected: onSectionSelected,
                  onMore: () => _openSectionDrawer(context),
                ),
      ),
    );
  }

  int get _selectedIndex {
    final index = _movieMobileBottomSections.indexOf(section);
    return index >= 0 ? index : _movieMobileBottomSections.length;
  }

  void _openSectionDrawer(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    showWorkstationGeneralDialog<void>(
      context: context,
      dismissible: true,
      barrierLabel: l10n.videoBrowse,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerLeft,
          child: _MovieMobileDrawer(
            section: section,
            canManage: canManage,
            counts: counts,
            onSectionSelected: onSectionSelected,
          ),
        );
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(-1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }
}

/// 移动端 44px 顶栏：汉堡 + 品牌 + 操作区。
class _MovieMobileTopBar extends StatelessWidget {
  const _MovieMobileTopBar({
    required this.section,
    required this.canManage,
    required this.counts,
    this.onRefresh,
    this.onSectionSelected,
  });

  final MovieSection section;
  final bool canManage;
  final Map<MovieSection, int> counts;
  final Future<void> Function()? onRefresh;
  final ValueChanged<MovieSection>? onSectionSelected;

  void _openSectionDrawer(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    showWorkstationGeneralDialog<void>(
      context: context,
      dismissible: true,
      barrierLabel: l10n.videoBrowse,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerLeft,
          child: _MovieMobileDrawer(
            section: section,
            canManage: canManage,
            counts: counts,
            onSectionSelected: onSectionSelected,
          ),
        );
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(-1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.movieRedesign;
    final text = context.movieRedesignText;
    final l10n = AppLocalizations.of(context);
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: palette.background,
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => _openSectionDrawer(context),
            tooltip: l10n.videoBrowse,
            icon: Icon(Icons.menu_rounded, size: 20, color: palette.foreground),
          ),
          const SizedBox(width: 2),
          Icon(Icons.movie_outlined, size: 16, color: palette.primary),
          const SizedBox(width: 6),
          Text(
            'OmniNest',
            style: text.display(size: AppTypography.titleMedium, height: 1.0),
          ),
          const SizedBox(width: 6),
          // ignore: font_size_whitelist
          Text(l10n.portalDockMovies, style: text.mono(size: 10)),
          const Spacer(),
          Consumer(
            builder: (context, ref, _) {
              final canManage =
                  ref.watch(userCapabilitiesProvider).canManageMediaLibrary;
              if (!canManage) {
                return const SizedBox.shrink();
              }
              return MediaImportButton(
                subsystemDirectory: 'Media',
                acceptedExtensions: const <String>[
                  'mp4',
                  'mkv',
                  'webm',
                  'mov',
                  'm4v',
                  'avi',
                  'flv',
                  'wmv',
                  'ts',
                  'm2ts',
                ],
                onImportCompleteWithResult: (result) async {
                  final taskApi = ref.read(taskApiProvider);
                  for (final file in result.imported) {
                    final taskId = file.mediaAutoImportTaskId;
                    if (taskId == null || taskId.isEmpty) {
                      continue;
                    }
                    try {
                      await taskApi.waitForTerminal(
                        taskId,
                        timeout: const Duration(minutes: 2),
                        interval: const Duration(seconds: 2),
                      );
                    } on Object {
                      // 轮询异常不阻断上传结果，但结果未确认需要用户可感知。
                      if (context.mounted) {
                        showOmniFeedback(
                          context,
                          AppLocalizations.of(
                            context,
                          ).videoAutoImportStatusUnknown,
                          severity: OmniFeedbackSeverity.warning,
                        );
                      }
                    }
                  }
                  await onRefresh?.call();
                  return null;
                },
                onImportComplete: onRefresh ?? () async {},
                style: ImportButtonStyle.iconButton,
                color: palette.mutedForeground,
              );
            },
          ),
          IconButton(
            onPressed: () => _showMovieMobileSearchDialog(context),
            icon: Icon(
              Icons.search_rounded,
              size: 20,
              color: palette.mutedForeground,
            ),
            tooltip: l10n.videoSearch,
          ),
          const FontScaleControl(size: 20),
          const NotificationIcon(size: 20),
          const SizedBox(width: 4),
          const UserAvatarMenu(),
        ],
      ),
    );
  }
}

/// 移动影视搜索浮层（hosted 横幅与非托管顶栏共用）。
void _showMovieMobileSearchDialog(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  showWorkstationGeneralDialog<void>(
    context: context,
    dismissible: true,
    barrierLabel: l10n.videoSearch,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder:
        (context, animation, secondaryAnimation) => Dialog(
          backgroundColor: Colors.transparent,
          child: _MovieSearchOverlay(
            onSearch: (query) {
              if (query.trim().isNotEmpty) {
                Navigator.of(context).pop();
              }
            },
          ),
        ),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.9, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// 新版移动端底部导航：5 个主分区 + 更多抽屉入口。
class _MovieMobileBottomNav extends StatelessWidget {
  const _MovieMobileBottomNav({
    required this.section,
    required this.counts,
    required this.canManage,
    required this.onSectionSelected,
    required this.onMore,
  });

  final MovieSection section;
  final Map<MovieSection, int> counts;
  final bool canManage;
  final ValueChanged<MovieSection>? onSectionSelected;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final palette = context.movieRedesign;
    final text = context.movieRedesignText;
    final l10n = AppLocalizations.of(context);
    final isMore = !_movieMobileBottomSections.contains(section);
    return Container(
      decoration: BoxDecoration(
        color: palette.background,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              for (final value in _movieMobileBottomSections)
                Expanded(
                  child: InkWell(
                    onTap: () => onSectionSelected?.call(value),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          value.icon,
                          size: 20,
                          color:
                              value == section
                                  ? palette.primary
                                  : palette.mutedForeground,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          value.labelOf(l10n),
                          style: text.mono(
                            size: 9,
                            color:
                                value == section
                                    ? palette.primary
                                    : palette.mutedForeground,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: InkWell(
                  onTap: onMore,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.menu_rounded,
                        size: 20,
                        color:
                            isMore ? palette.primary : palette.mutedForeground,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.videoMore,
                        style: text.mono(
                          size: 9,
                          color:
                              isMore
                                  ? palette.primary
                                  : palette.mutedForeground,
                        ),
                      ),
                    ],
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

/// 新版移动端分区抽屉：品牌行 + 三组导航（含计数与管理守卫）。
class _MovieMobileDrawer extends StatelessWidget {
  const _MovieMobileDrawer({
    required this.section,
    required this.canManage,
    required this.counts,
    this.onSectionSelected,
  });

  final MovieSection section;
  final bool canManage;
  final Map<MovieSection, int> counts;
  final ValueChanged<MovieSection>? onSectionSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.movieRedesign;
    final groups = movieSidebarGroups.entries.where(
      (entry) => canManage || entry.key != MovieSidebarGroup.management,
    );
    return Material(
      color: palette.background,
      child: SafeArea(
        right: false,
        child: SizedBox(
          width: AppControlTokens.sidebarWidth,
          height: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.movie_outlined,
                      size: 16,
                      color: palette.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'OmniNest',
                      style: context.movieRedesignText.display(
                        size: AppTypography.titleLarge,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.portalDockMovies,
                      // ignore: font_size_whitelist
                      style: context.movieRedesignText.mono(size: 10),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: l10n.videoClose,
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: palette.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, thickness: 1, color: palette.border),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    for (final entry in groups) ...[
                      _MovieGroupLabel(entry.key.labelOf(l10n)),
                      for (final item in entry.value)
                        _MovieNavItem(
                          item: item,
                          label: item.labelOf(l10n),
                          subtitleEn: item.subtitleEnOf(l10n),
                          icon: item.icon,
                          selected: item == section,
                          count: counts[item],
                          collapsed: false,
                          closeOnSelect: true,
                          height: 40,
                          onSectionSelected: onSectionSelected,
                        ),
                      const SizedBox(height: 4),
                    ],
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

class _MovieMobileSectionBar extends StatelessWidget {
  const _MovieMobileSectionBar({
    required this.section,
    required this.onSectionSelected,
  });

  final MovieSection section;
  final ValueChanged<MovieSection>? onSectionSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const sections = <MovieSection>[
      MovieSection.continueWatching,
      MovieSection.movies,
      MovieSection.tvShows,
      MovieSection.anime,
    ];
    String labelOf(MovieSection value) => switch (value) {
      MovieSection.continueWatching => l10n.videoSectionForYou,
      MovieSection.movies => l10n.videoSectionFilms,
      MovieSection.tvShows => l10n.videoSectionSeries,
      _ => value.labelOf(l10n),
    };
    final effective = sections.contains(section) ? section : sections.first;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
        child: MobileSegmentedControl<MovieSection>(
          values: sections,
          selected: effective,
          labelBuilder: labelOf,
          onSelected: (value) => onSectionSelected?.call(value),
        ),
      ),
    );
  }
}
