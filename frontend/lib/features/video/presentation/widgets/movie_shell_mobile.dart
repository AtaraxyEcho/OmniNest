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
        onBack?.call();
      },
      child: Scaffold(
        backgroundColor: context.movieRedesign.background,
        extendBody: !hosted,
        body: Builder(
          builder: (context) {
            final content = Column(
              children: [
                if (hosted)
                  _MovieMobileSectionBar(
                    section: section,
                    onSectionSelected: onSectionSelected,
                  ),
                Expanded(child: pageContent),
              ],
            );
            if (!hosted) {
              return content;
            }
            return MobilePageSurface(
              exposeBackdrop: true,
              backdropOpacity: 0.54,
              child: content,
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
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
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
      transitionBuilder: (context, animation, secondaryAnimation, child) {
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
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
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
      transitionBuilder: (context, animation, secondaryAnimation, child) {
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
          Text('OmniNest', style: text.display(size: 16, height: 1.0)),
          const SizedBox(width: 6),
          Text(l10n.portalDockMovies, style: text.mono(size: 10)),
          const Spacer(),
          Consumer(
            builder:
                (context, ref, _) => MediaImportButton(
                  subsystemDirectory: 'Media',
                  onImportComplete: onRefresh ?? () async {},
                  style: ImportButtonStyle.iconButton,
                  color: palette.mutedForeground,
                ),
          ),
          IconButton(
            onPressed: () => _showSearchDialog(context),
            icon: Icon(
              Icons.search_rounded,
              size: 20,
              color: palette.mutedForeground,
            ),
            tooltip: l10n.videoSearch,
          ),
          const NotificationIcon(size: 20),
          const SizedBox(width: 4),
          const UserAvatarMenu(),
        ],
      ),
    );
  }

  void _showSearchDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: l10n.videoSearch,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder:
          (context, animation, secondaryAnimation) => Dialog(
            backgroundColor: Colors.transparent,
            child: _MovieSearchOverlay(
              controller: controller,
              onSearch: (query) {
                if (query.trim().isNotEmpty) {
                  Navigator.of(context).pop();
                }
              },
            ),
          ),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
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
          width: 256,
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
                      style: context.movieRedesignText.display(size: 18),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.portalDockMovies,
                      style: context.movieRedesignText.mono(size: 10),
                    ),
                    const Spacer(),
                    IconButton(
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
    final palette = context.movieRedesign;
    const sections = <MovieSection>[
      MovieSection.movies,
      MovieSection.tvShows,
      MovieSection.anime,
      MovieSection.favorites,
    ];
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: palette.background,
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        itemCount: sections.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final value = sections[index];
          final selected = value == section;
          return Material(
            color: selected ? palette.foreground : Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: MovieRedesignPalette.borderRadius,
              side: BorderSide(
                color: selected ? palette.foreground : palette.border,
              ),
            ),
            child: InkWell(
              onTap: () => onSectionSelected?.call(value),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Center(
                  child: Text(
                    value.labelOf(l10n),
                    style: context.movieRedesignText.body(
                      size: 12,
                      weight: FontWeight.w500,
                      color:
                          selected
                              ? palette.background
                              : palette.mutedForeground,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
