import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/feature/video_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/widgets/workbench_top_bar.dart';
import 'package:omninest/core/widgets/workbench_navigation_bar.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/features/files/media_import_ui.dart';
import 'package:omninest/features/notifications/notification_ui.dart';
import 'package:omninest/core/widgets/responsive_breakpoints.dart';
import 'package:omninest/core/widgets/user_avatar_menu.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/presentation/widgets/movie_responsive_layout.dart';
import 'package:omninest/features/video/presentation/widgets/movie_section_transition.dart';

part 'movie_shell_search_overlay.dart';
part 'movie_shell_mobile.dart';

/// 根据内容宽度计算文字缩放因子。
/// 960px 以下不缩放，2560px 以上最大 1.25x。
double movieTextScale(double width) {
  if (width <= 960) return 1.0;
  final t = ((width - 960) / 1600).clamp(0.0, 1.0);
  return 1.0 + 0.25 * t;
}

/// 应用缩放后的字号，最小不低于 12。
double ms(double width, double base) =>
    base * movieTextScale(width) < 12 ? 12 : base * movieTextScale(width);

extension MovieSectionMeta on MovieSection {
  String labelOf(AppLocalizations l10n) {
    return switch (this) {
      MovieSection.movies => l10n.videoSectionMovies,
      MovieSection.tvShows => l10n.videoSectionTvShows,
      MovieSection.anime => l10n.videoSectionAnime,
      MovieSection.collections => l10n.videoSectionCollections,
      MovieSection.recent => l10n.videoSectionRecent,
      MovieSection.continueWatching => l10n.videoSectionContinueWatching,
      MovieSection.favorites => l10n.videoSectionFavorites,
      MovieSection.history => l10n.videoSectionHistory,
      MovieSection.management => l10n.videoSectionMovieAdmin,
    };
  }

  IconData get icon {
    return switch (this) {
      MovieSection.movies => Icons.movie_rounded,
      MovieSection.tvShows => Icons.tv_rounded,
      MovieSection.anime => Icons.animation_rounded,
      MovieSection.collections => Icons.video_collection_rounded,
      MovieSection.recent => Icons.new_releases_outlined,
      MovieSection.continueWatching => Icons.play_circle_outline_rounded,
      MovieSection.favorites => Icons.favorite_rounded,
      MovieSection.history => Icons.manage_history_rounded,
      MovieSection.management => Icons.admin_panel_settings_outlined,
    };
  }

  bool get requiresManagementRole {
    return switch (this) {
      MovieSection.management => true,
      _ => false,
    };
  }
}

enum MovieSidebarGroup {
  library,
  mine,
  management;

  String labelOf(AppLocalizations l10n) {
    return switch (this) {
      MovieSidebarGroup.library => l10n.videoSidebarGroupLibrary,
      MovieSidebarGroup.mine => l10n.videoSidebarGroupMine,
      MovieSidebarGroup.management => l10n.videoSidebarGroupManagement,
    };
  }
}

const Map<MovieSidebarGroup, List<MovieSection>> movieSidebarGroups = {
  MovieSidebarGroup.library: [
    MovieSection.movies,
    MovieSection.tvShows,
    MovieSection.anime,
    MovieSection.collections,
    MovieSection.recent,
  ],
  MovieSidebarGroup.mine: [
    MovieSection.continueWatching,
    MovieSection.favorites,
    MovieSection.history,
  ],
  MovieSidebarGroup.management: [MovieSection.management],
};

class MovieShell extends ConsumerStatefulWidget {
  const MovieShell({
    required this.section,
    required this.child,
    this.onSectionSelected,
    this.trailing,
    this.onRefresh,
    this.childOwnsScroll = false,
    super.key,
  });

  final MovieSection section;
  final Widget child;
  final ValueChanged<MovieSection>? onSectionSelected;
  final Widget? trailing;
  final Future<void> Function()? onRefresh;
  final bool childOwnsScroll;

  @override
  ConsumerState<MovieShell> createState() => _MovieShellState();
}

class _MovieShellState extends ConsumerState<MovieShell> {
  final List<MovieSection> _sectionHistory = [];
  MovieSection? _lastSection;

  void _onSectionSelected(MovieSection section) {
    if (_lastSection != null && _lastSection != section) {
      _sectionHistory.add(_lastSection!);
    }
    _lastSection = section;
    widget.onSectionSelected?.call(section);
  }

  void _onBack() {
    if (_sectionHistory.isNotEmpty) {
      final prev = _sectionHistory.removeLast();
      _lastSection = prev;
      widget.onSectionSelected?.call(prev);
    } else {
      context.go('/portal');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final user = ref.watch(authSessionProvider).asData?.value.user;
    final canManage =
        user?.permissions.contains('media:library:manage') ?? false;
    // 管理分区不再静默回退到电影：无权限时由内容区显示明确提示。
    final effectiveSection = widget.section;

    // 跟踪初始切片
    _lastSection ??= effectiveSection;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = !ResponsiveBreakpoints.isCompact(constraints.maxWidth);
        return Scaffold(
          backgroundColor: context.videoColors.surface,
          body: Stack(
            children: [
              const _MovieBackdrop(),
              Column(
                children: [
                  if (isWide)
                    MovieTopBar(
                      section: effectiveSection,
                      showMenu: false,
                      canManage: canManage,
                      onSectionSelected: _onSectionSelected,
                      trailing: widget.trailing,
                      onRefresh: widget.onRefresh,
                      userName: user?.displayName ?? user?.username ?? 'M',
                    ),
                  if (isWide)
                    Expanded(
                      child: Row(
                        children: [
                          MovieSidebar(
                            section: effectiveSection,
                            canManage: canManage,
                            closeOnSelect: false,
                            onSectionSelected: _onSectionSelected,
                          ),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, contentConstraints) {
                                final horizontalPadding =
                                    contentConstraints.maxWidth < 1000
                                        ? 24.0
                                        : contentConstraints.maxWidth < 1600
                                        ? 32.0
                                        : 40.0;
                                final availableWidth =
                                    contentConstraints.maxWidth -
                                    horizontalPadding * 2;
                                final contentWidth =
                                    availableWidth
                                        .clamp(0.0, movieDesktopContentMaxWidth)
                                        .toDouble();
                                final content = MovieSectionTransition(
                                  section: effectiveSection,
                                  child: widget.child,
                                );
                                if (widget.childOwnsScroll) {
                                  return content;
                                }
                                return SingleChildScrollView(
                                  padding: EdgeInsets.fromLTRB(
                                    horizontalPadding,
                                    32,
                                    horizontalPadding,
                                    48,
                                  ),
                                  child: Center(
                                    child: SizedBox(
                                      width: contentWidth,
                                      child: content,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Expanded(
                      child: _MovieMobileShell(
                        section: effectiveSection,
                        onSectionSelected: _onSectionSelected,
                        canManage: canManage,
                        onRefresh: widget.onRefresh,
                        onBack: _onBack,
                        childOwnsScroll: widget.childOwnsScroll,
                        child: widget.child,
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class MovieTopBar extends StatelessWidget {
  const MovieTopBar({
    required this.section,
    required this.showMenu,
    required this.userName,
    this.canManage = false,
    this.onSectionSelected,
    this.trailing,
    this.onRefresh,
    super.key,
  });

  final MovieSection section;
  final bool showMenu;
  final String userName;
  final bool canManage;
  final ValueChanged<MovieSection>? onSectionSelected;
  final Widget? trailing;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: context.videoColors.surfaceContainer.withValues(alpha: 0.70),
        border: Border(
          bottom: BorderSide(
            color: context.videoColors.outlineVariant.withValues(alpha: 0.32),
          ),
        ),
      ),
      child: Row(
        children: [
          if (showMenu && canManage)
            PopupMenuButton<MovieSection>(
              tooltip: AppLocalizations.of(context).videoSidebarGroupManagement,
              icon: Icon(
                Icons.admin_panel_settings_outlined,
                color: context.videoColors.onSurfaceVariant,
              ),
              onSelected: onSectionSelected,
              itemBuilder:
                  (context) =>
                      MovieSection.values
                          .where((s) => s.requiresManagementRole)
                          .map(
                            (s) => PopupMenuItem(
                              value: s,
                              child: Row(
                                children: [
                                  Icon(s.icon, size: 18),
                                  const SizedBox(width: 12),
                                  Text(s.labelOf(AppLocalizations.of(context))),
                                ],
                              ),
                            ),
                          )
                          .toList(),
            ),
          TextButton.icon(
            onPressed: () => context.go('/portal'),
            icon: Icon(
              Icons.arrow_back_rounded,
              size: 18,
              color: context.videoColors.onSurfaceVariant,
            ),
            label: Text(
              'Portal',
              style: TextStyle(
                fontSize: 13,
                height: 18 / 13,
                fontWeight: FontWeight.w700,
                color: context.videoColors.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            section.labelOf(AppLocalizations.of(context)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.videoColors.primary,
              fontSize: 16,
              height: 24 / 16,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(width: 20),
          if (trailing != null)
            Expanded(
              child: Align(alignment: Alignment.centerRight, child: trailing!),
            )
          else
            const Spacer(),
          const SizedBox(width: 16),
          Consumer(
            builder:
                (context, ref, _) => MediaImportButton(
                  subsystemDirectory: 'Media',
                  onImportComplete: onRefresh ?? () async {},
                  style: ImportButtonStyle.iconButton,
                  color: context.videoColors.onSurfaceVariant,
                ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: AppLocalizations.of(context).videoRefreshTooltip,
            onPressed: onRefresh,
            icon: Icon(
              Icons.refresh_rounded,
              size: 20,
              color: context.videoColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 4),
          const NotificationIcon(size: 20),
          const SizedBox(width: 8),
          const UserAvatarMenu(),
        ],
      ),
    );
  }
}

class MovieSidebar extends StatelessWidget {
  const MovieSidebar({
    required this.section,
    required this.canManage,
    required this.closeOnSelect,
    this.onSectionSelected,
    super.key,
  });

  final MovieSection section;
  final bool canManage;
  final bool closeOnSelect;
  final ValueChanged<MovieSection>? onSectionSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final groups = movieSidebarGroups.entries.where(
      (entry) => canManage || entry.key != MovieSidebarGroup.management,
    );
    return Container(
      width: 280,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      decoration: BoxDecoration(
        color: context.videoColors.surfaceContainerLow,
        border: Border(
          right: BorderSide(
            color: context.videoColors.outlineVariant.withValues(alpha: 0.24),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _MovieBrand(),
          const SizedBox(height: 28),
          Expanded(
            child: ListView(
              children: [
                for (final entry in groups) ...[
                  _MovieGroupLabel(entry.key.labelOf(l10n)),
                  const SizedBox(height: 8),
                  for (final item in entry.value)
                    _MovieNavItem(
                      item: item,
                      label: item.labelOf(l10n),
                      icon: item.icon,
                      selected: item == section,
                      closeOnSelect: closeOnSelect,
                      onSectionSelected: onSectionSelected,
                    ),
                  const SizedBox(height: 18),
                ],
              ],
            ),
          ),
          if (!canManage) const _MovieAccessHint(),
        ],
      ),
    );
  }
}

class _MovieBackdrop extends StatelessWidget {
  const _MovieBackdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: context.videoColors.surface),
      child: const SizedBox.expand(),
    );
  }
}

/// 移动端布局：底部导航栏 + 简洁 TopBar + 可滚动内容。
///
/// 底部导航 5 项：电影、剧集、动漫、收藏、更多。
/// "更多"导航到浏览入口页面，包含合集、最近添加、继续观看、观看历史。
