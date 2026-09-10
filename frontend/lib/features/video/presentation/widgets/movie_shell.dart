import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/control_tokens.dart';
import 'package:omninest/app/theme/feature/video_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/widgets/responsive_breakpoints.dart';
import 'package:omninest/core/widgets/font_scale_control.dart';
import 'package:omninest/core/widgets/user_avatar_menu.dart';
import 'package:omninest/features/files/media_import_ui.dart';
import 'package:omninest/features/notifications/notification_ui.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/presentation/theme/movie_redesign_theme.dart';
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

  /// 分区英文辅助标注（新版设计中的副标题样式）。
  String subtitleEnOf(AppLocalizations l10n) {
    return switch (this) {
      MovieSection.movies => l10n.videoRedesignSubMovies,
      MovieSection.tvShows => l10n.videoRedesignSubTvShows,
      MovieSection.anime => l10n.videoRedesignSubAnime,
      MovieSection.collections => l10n.videoRedesignSubCollections,
      MovieSection.recent => l10n.videoRedesignSubRecent,
      MovieSection.continueWatching => l10n.videoRedesignSubContinue,
      MovieSection.favorites => l10n.videoRedesignSubFavorites,
      MovieSection.history => l10n.videoRedesignSubHistory,
      MovieSection.management => l10n.videoRedesignSubAdmin,
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
    this.counts = const {},
    super.key,
  });

  final MovieSection section;
  final Widget child;
  final ValueChanged<MovieSection>? onSectionSelected;
  final Widget? trailing;
  final Future<void> Function()? onRefresh;
  final bool childOwnsScroll;

  /// 各分区条目计数，展示在侧栏与抽屉导航项尾部。
  final Map<MovieSection, int> counts;

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
        // 平板宽度（md~lg）下侧栏折叠为图标栏。
        final sidebarCollapsed = isWide && constraints.maxWidth < 1024;
        return Scaffold(
          backgroundColor: context.movieRedesign.background,
          body: Column(
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
              Expanded(
                child:
                    isWide
                        ? Row(
                          children: [
                            MovieSidebar(
                              section: effectiveSection,
                              canManage: canManage,
                              counts: widget.counts,
                              collapsed: sidebarCollapsed,
                              closeOnSelect: false,
                              onSectionSelected: _onSectionSelected,
                            ),
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, contentConstraints) {
                                  final pagePadding = movieRedesignPagePadding(
                                    contentConstraints.maxWidth,
                                  );
                                  final content = MovieSectionTransition(
                                    section: effectiveSection,
                                    child: widget.child,
                                  );
                                  if (widget.childOwnsScroll) {
                                    return Padding(
                                      padding: pagePadding,
                                      child: content,
                                    );
                                  }
                                  return SingleChildScrollView(
                                    padding: pagePadding.copyWith(bottom: 48),
                                    child: content,
                                  );
                                },
                              ),
                            ),
                          ],
                        )
                        : _MovieMobileShell(
                          section: effectiveSection,
                          onSectionSelected: _onSectionSelected,
                          canManage: canManage,
                          counts: widget.counts,
                          onRefresh: widget.onRefresh,
                          onBack: _onBack,
                          childOwnsScroll: widget.childOwnsScroll,
                          child: widget.child,
                        ),
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
    final palette = context.movieRedesign;
    final text = context.movieRedesignText;
    final l10n = AppLocalizations.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 640;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: palette.background,
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          if (showMenu && canManage)
            PopupMenuButton<MovieSection>(
              tooltip: l10n.videoSidebarGroupManagement,
              icon: Icon(
                Icons.admin_panel_settings_outlined,
                size: 18,
                color: palette.mutedForeground,
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
          IconButton(
            onPressed: () => context.go('/portal'),
            tooltip: l10n.videoBackToPortal,
            icon: Icon(
              Icons.arrow_back_rounded,
              size: 18,
              color: palette.mutedForeground,
            ),
          ),
          if (wide) ...[
            const SizedBox(width: 8),
            Icon(Icons.movie_outlined, size: 16, color: palette.primary),
            const SizedBox(width: 6),
            Text(
              'OmniNest',
              style: text.display(size: AppTypography.titleMedium, height: 1.0),
            ),
            const SizedBox(width: 6),
            // ignore: font_size_whitelist
            Text(l10n.portalDockMovies, style: text.mono(size: 10)),
          ],
          const SizedBox(width: 16),
          if (trailing != null)
            Expanded(
              child: Align(alignment: Alignment.centerLeft, child: trailing!),
            )
          else
            const Spacer(),
          const SizedBox(width: 12),
          Consumer(
            builder:
                (context, ref, _) => MediaImportButton(
                  subsystemDirectory: 'Media',
                  onImportComplete: onRefresh ?? () async {},
                  style: ImportButtonStyle.iconButton,
                  color: palette.mutedForeground,
                ),
          ),
          const SizedBox(width: 2),
          IconButton(
            tooltip: l10n.videoRefreshTooltip,
            onPressed: onRefresh,
            icon: Icon(
              Icons.refresh_rounded,
              size: 18,
              color: palette.mutedForeground,
            ),
          ),
          const SizedBox(width: 2),
          const FontScaleControl(size: 18),
          const NotificationIcon(size: 18),
          const SizedBox(width: 4),
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
    this.counts = const {},
    this.collapsed = false,
    this.onSectionSelected,
    super.key,
  });

  final MovieSection section;
  final bool canManage;
  final bool closeOnSelect;
  final Map<MovieSection, int> counts;
  final bool collapsed;
  final ValueChanged<MovieSection>? onSectionSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.movieRedesign;
    final groups = movieSidebarGroups.entries.where(
      (entry) => canManage || entry.key != MovieSidebarGroup.management,
    );
    return Container(
      width:
          collapsed
              ? AppControlTokens.sidebarCollapsedWidth
              : AppControlTokens.sidebarWidth,
      decoration: BoxDecoration(
        color: palette.background,
        border: Border(right: BorderSide(color: palette.border)),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          for (final entry in groups) ...[
            if (!collapsed)
              _MovieGroupLabel(entry.key.labelOf(l10n))
            else
              const SizedBox(height: 8),
            for (final item in entry.value)
              _MovieNavItem(
                item: item,
                label: item.labelOf(l10n),
                subtitleEn: item.subtitleEnOf(l10n),
                icon: item.icon,
                selected: item == section,
                count: counts[item],
                collapsed: collapsed,
                closeOnSelect: closeOnSelect,
                onSectionSelected: onSectionSelected,
              ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}

class _MovieGroupLabel extends StatelessWidget {
  const _MovieGroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.movieRedesign;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.movieRedesignText
              // ignore: font_size_whitelist
              .mono(size: 9, color: palette.mutedForeground)
              .copyWith(letterSpacing: 2),
        ),
      ),
    );
  }
}

class _MovieNavItem extends StatelessWidget {
  const _MovieNavItem({
    required this.item,
    required this.label,
    required this.subtitleEn,
    required this.icon,
    required this.selected,
    required this.collapsed,
    required this.closeOnSelect,
    this.count,
    this.height = 36,
    this.onSectionSelected,
  });

  final MovieSection? item;
  final String label;
  final String subtitleEn;
  final IconData icon;
  final bool selected;
  final bool collapsed;
  final bool closeOnSelect;
  final int? count;

  /// 行高：桌面侧栏 36（py-2），移动端抽屉 40（py-2.5）。
  final double height;
  final ValueChanged<MovieSection>? onSectionSelected;

  @override
  Widget build(BuildContext context) {
    final palette = context.movieRedesign;
    final text = context.movieRedesignText;
    final foreground = selected ? palette.foreground : palette.mutedForeground;
    final iconColor = selected ? palette.primary : foreground;
    // 对应原型 px-4：图标前先留 16px 内边距，折叠态图标在 48px 内居中。
    final content = SizedBox(
      height: height,
      child: Row(
        children: [
          if (collapsed)
            Expanded(
              child: Center(child: Icon(icon, size: 15, color: iconColor)),
            )
          else ...[
            const SizedBox(width: 16),
            Icon(icon, size: 15, color: iconColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.body(
                  size: 14,
                  weight: FontWeight.w500,
                  color: foreground,
                ),
              ),
            ),
            if (count != null)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  count.toString(),
                  // ignore: font_size_whitelist
                  style: text.mono(size: 10, color: palette.mutedForeground),
                ),
              ),
          ],
        ],
      ),
    );
    final button = Material(
      color: selected ? palette.muted : Colors.transparent,
      child: InkWell(
        onTap: () {
          final target = item;
          if (target != null) {
            onSectionSelected?.call(target);
          }
          if (closeOnSelect) {
            Navigator.of(context).maybePop();
          }
        },
        hoverColor: palette.muted.withValues(alpha: 0.5),
        child: content,
      ),
    );
    if (collapsed) {
      return Tooltip(message: '$label · $subtitleEn', child: button);
    }
    return button;
  }
}
