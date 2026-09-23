part of 'portal_desktop_visual_shells.dart';

/// 胶片条迷你卡封面自愈：加载失败（签名 URL 过期为主因）时按模块
/// 有限次重试对应数据分区，重签 URL 后由稳定缓存键命中或重新下载。
class _VisualFilmStrip extends ConsumerStatefulWidget {
  const _VisualFilmStrip({
    required this.palette,
    required this.items,
    required this.activeIndex,
    required this.onSelected,
    this.lightweight = false,
  });

  final PortalVisualPalette palette;
  final List<PortalFocusItem> items;
  final int activeIndex;
  final ValueChanged<int> onSelected;
  final bool lightweight;

  @override
  ConsumerState<_VisualFilmStrip> createState() => _VisualFilmStripState();
}

class _VisualFilmStripState extends ConsumerState<_VisualFilmStrip> {
  static const int _maxRecoverAttempts = 2;
  final Map<PortalFocusModule, int> _recoverAttempts = {};

  PortalDashboardSection? _sectionFor(PortalFocusModule module) {
    // 仅封面数据来自可重签分区的模块参与自愈；files 等模块无封面。
    return PortalDashboardActions.sectionFor(module);
  }

  void _handleCoverError(PortalFocusModule module) {
    final attempts = _recoverAttempts[module] ?? 0;
    if (attempts >= _maxRecoverAttempts) {
      return;
    }
    _recoverAttempts[module] = attempts + 1;
    final section = _sectionFor(module);
    if (section != null) {
      unawaited(ref.read(portalDashboardActionsProvider).retry(section));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final items = widget.items;
    final activeIndex = widget.activeIndex;
    final onSelected = widget.onSelected;
    final lightweight = widget.lightweight;
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final dense = viewportHeight < 760;
    final relaxed = viewportHeight >= 840;
    final panelPadding = EdgeInsets.all(dense ? 8 : 14);
    final itemHeight = dense ? 82.0 : (relaxed ? 126.0 : 110.0);
    final itemWidth = dense ? 126.0 : (relaxed ? 180.0 : 158.0);
    final gap = dense ? 8.0 : 12.0;
    return PortalVisualPanel(
      palette: palette,
      padding: panelPadding,
      lightweight: lightweight,
      child: SizedBox(
        height: itemHeight,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, _) => SizedBox(width: gap),
          itemBuilder: (context, index) {
            final item = items[index];
            final active = index == activeIndex;
            return SizedBox(
              width: itemWidth,
              height: double.infinity,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onFocusChange: (focused) {
                    if (focused) {
                      onSelected(index);
                    }
                  },
                  onTap: () => onSelected(index),
                  child: AnimatedContainer(
                    duration: PortalMotion.duration(
                      context,
                      const Duration(milliseconds: 180),
                    ),
                    curve: Curves.easeOutCubic,
                    padding: EdgeInsets.all(active ? 3 : 0),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color:
                            active
                                ? palette.accent.withValues(alpha: 0.80)
                                : Colors.transparent,
                        width: active ? 1.4 : 0,
                      ),
                    ),
                    child: PortalGradientCover(
                      palette: palette,
                      title: item.title,
                      subtitle: item.subtitle,
                      variant: item.variant,
                      imageUrl: item.imageUrl,
                      readerItemId: item.readerItemId,
                      coverCacheKey: item.coverCacheKey,
                      onCoverError: () => _handleCoverError(item.module),
                      fallbackIcon: item.icon.iconData,
                      height: itemHeight,
                      maxCoverWidth: itemWidth,
                      maxCoverHeight: itemHeight,
                      minCoverHeight: itemHeight,
                      directImage: true,
                      foregroundPadding: EdgeInsets.fromLTRB(
                        8,
                        8,
                        8,
                        dense ? 40 : 52,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StatusRail extends ConsumerWidget {
  const _StatusRail({
    required this.palette,
    required this.data,
    this.lightweight = false,
    this.scrollable = false,
  });

  final PortalVisualPalette palette;
  final _PortalDesktopData data;
  final bool lightweight;

  /// 两栏中间档中与关注面板纵向分高，空间不足时改为固定间距加滚动，
  /// 避免固定内容（日期+指标行）在缩水高度里溢出。
  final bool scrollable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final l10n = AppLocalizations.of(context);
    // 宽布局下面板拉伸满列高：日期块与指标行均布填充，消除数据空态时
    // 日期与指标之间的大段空白；滚动变体保持固定间距顶对齐。
    final dateBlock = Padding(
      // 与指标行的横向 12 内边距对齐左缘。
      padding: const EdgeInsets.only(left: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            now.day.toString().padLeft(2, '0'),
            style: TextStyle(
              color: palette.text,
              // ignore: font_size_whitelist
              fontSize: 58,
              height: 0.9,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${now.year}.${now.month.toString().padLeft(2, '0')}',
            style: TextStyle(color: palette.muted),
          ),
        ],
      ),
    );
    final content = Column(
      mainAxisAlignment:
          scrollable ? MainAxisAlignment.start : MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        dateBlock,
        const SizedBox(height: 12),
        PortalMetricLine(
          palette: palette,
          label: l10n.portalWeatherTitle,
          value: data.weatherSummary(context),
          onTap: () => _openWeatherDetails(context, data),
        ),
        const SizedBox(height: 12),
        if (ref.watch(canAccessAdminConsoleProvider)) ...[
          PortalMetricLine(
            palette: palette,
            label: l10n.portalAdmin,
            value: data.taskSummary,
            onTap: () => context.push('/admin'),
          ),
          const SizedBox(height: 12),
        ],
        PortalMetricLine(
          palette: palette,
          label: l10n.portalStorageTitle,
          value: data.storageSummary(context),
        ),
      ],
    );
    return PortalVisualPanel(
      palette: palette,
      lightweight: lightweight,
      child: scrollable ? SingleChildScrollView(child: content) : content,
    );
  }
}

class _AttentionPanel extends ConsumerWidget {
  const _AttentionPanel({
    required this.palette,
    required this.data,
    required this.activeModule,
    required this.onOpenImmersivePlayback,
    this.lightweight = false,
  });

  final PortalVisualPalette palette;
  final _PortalDesktopData data;
  final PortalFocusModule activeModule;
  final bool lightweight;

  /// 内嵌迷你播放器封面的跳转目标：进入沉浸播放详情页。
  final VoidCallback onOpenImmersivePlayback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return PortalVisualPanel(
      palette: palette,
      lightweight: lightweight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableHeight = _resolvePortalViewportHeight(
            context,
            constraints,
          );
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: availableHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.portalVisualStatusTitle,
                    style: TextStyle(
                      color: palette.muted,
                      fontSize: AppTypography.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (activeModule != PortalFocusModule.music) ...[
                    MusicDeckMiniPlayer(
                      compact: true,
                      palette: MusicMiniPlayerPalette(
                        text: palette.text,
                        muted: palette.muted,
                        accent: palette.accentAlt,
                        onAccent: palette.text,
                      ),
                      managePlaybackSession: true,
                      embedded: true,
                      onOpenPlayer: onOpenImmersivePlayback,
                      onOpenQueue: () => showMusicDeckQueue(context),
                    ),
                    const SizedBox(height: 14),
                  ],
                  _NoticeTile(
                    palette: palette,
                    title: l10n.portalWeatherTitle,
                    subtitle: data.weatherSummary(context),
                    detail: data.weatherDetailSummary(context),
                    icon: Icons.cloud_outlined,
                    onTap: () => _openWeatherDetails(context, data),
                  ),
                  if (ref.watch(canAccessAdminConsoleProvider))
                    _NoticeTile(
                      palette: palette,
                      title: l10n.portalAdmin,
                      subtitle: data.taskSummary,
                      detail: l10n.portalAdminSubtitle,
                      icon: Icons.admin_panel_settings_rounded,
                      onTap: () => context.push('/admin'),
                    ),
                  _NoticeTile(
                    palette: palette,
                    title: l10n.portalStorageTitle,
                    subtitle: data.storageSummary(context),
                  ),
                  const SizedBox(height: 20),
                  PortalQuickLinks(
                    palette: palette,
                    includeAdmin: ref.watch(canAccessAdminConsoleProvider),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _NoticeTile extends StatelessWidget {
  const _NoticeTile({
    required this.palette,
    required this.title,
    required this.subtitle,
    this.detail,
    this.icon,
    this.onTap,
  });

  final PortalVisualPalette palette;
  final String title;
  final String subtitle;
  final String? detail;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.structuralStrongSurface(alpha: 0.60),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.muted.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: palette.text, size: 16),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: AppTypography.bodyLarge,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (onTap != null)
                Icon(
                  Icons.open_in_full_rounded,
                  color: palette.muted,
                  size: 14,
                ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.muted,
              fontSize: AppTypography.bodySmall,
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: 3),
            Text(
              detail!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.muted.withValues(alpha: 0.82),
                fontSize: AppTypography.labelSmall,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
    if (onTap == null) {
      return child;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: child,
      ),
    );
  }
}

class _StatusDock extends ConsumerWidget {
  const _StatusDock({required this.palette, required this.data});

  final PortalVisualPalette palette;
  final _PortalDesktopData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final compactDock = MediaQuery.sizeOf(context).height < 700;
    return _WeatherReactiveDockSurface(
      palette: palette,
      weather: data.weatherData,
      child: PortalVisualPanel(
        palette: palette,
        padding: EdgeInsets.symmetric(
          horizontal: compactDock ? 12 : 16,
          vertical: compactDock ? 8 : 12,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                compactDock ||
                (constraints.maxWidth.isFinite && constraints.maxWidth < 900);
            if (compact) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 170,
                      child: PortalMetricLine(
                        palette: palette,
                        label: l10n.portalWeatherTitle,
                        value: data.weatherSummary(context),
                        onTap: () => _openWeatherDetails(context, data),
                      ),
                    ),
                    const SizedBox(width: 14),
                    if (ref.watch(canAccessAdminConsoleProvider)) ...[
                      SizedBox(
                        width: 170,
                        child: PortalMetricLine(
                          palette: palette,
                          label: l10n.portalAdmin,
                          value: data.taskSummary,
                          onTap: () => context.push('/admin'),
                        ),
                      ),
                      const SizedBox(width: 14),
                    ],
                    SizedBox(
                      width: 170,
                      child: PortalMetricLine(
                        palette: palette,
                        label: l10n.portalStorageTitle,
                        value: data.storageSummary(context),
                      ),
                    ),
                    const SizedBox(width: 18),
                    PortalQuickLinks(palette: palette, includeAdmin: false),
                  ],
                ),
              );
            }
            return Row(
              children: [
                Expanded(
                  child: PortalMetricLine(
                    palette: palette,
                    label: l10n.portalWeatherTitle,
                    value: data.weatherSummary(context),
                    onTap: () => _openWeatherDetails(context, data),
                  ),
                ),
                if (ref.watch(canAccessAdminConsoleProvider))
                  Expanded(
                    child: PortalMetricLine(
                      palette: palette,
                      label: l10n.portalAdmin,
                      value: data.taskSummary,
                      onTap: () => context.push('/admin'),
                    ),
                  ),
                Expanded(
                  child: PortalMetricLine(
                    palette: palette,
                    label: l10n.portalStorageTitle,
                    value: data.storageSummary(context),
                  ),
                ),
                Expanded(
                  child: PortalQuickLinks(
                    palette: palette,
                    includeAdmin: false,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SingleColumnVisual extends StatelessWidget {
  const _SingleColumnVisual({
    required this.palette,
    required this.item,
    required this.data,
    required this.onOpenImmersivePlayback,
    this.lightweight = false,
  });

  final PortalVisualPalette palette;
  final PortalFocusItem item;
  final _PortalDesktopData data;
  final VoidCallback onOpenImmersivePlayback;
  final bool lightweight;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PortalVisualPanel(
            palette: palette,
            padding: const EdgeInsets.all(24),
            lightweight: lightweight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HeroCopy(
                  palette: palette,
                  eyebrow: item.heroEyebrow ?? l10n.portalVisualEyebrowCompact,
                  title: item.title,
                  body: item.heroBody ?? item.subtitle,
                  action: item.actionLabel,
                  onAction: () => context.go(item.route),
                  quickActions: _PortalFocusQuickActions(
                    palette: palette,
                    item: item,
                    data: data,
                    onOpenImmersivePlayback: onOpenImmersivePlayback,
                  ),
                ),
                const SizedBox(height: 18),
                // 与桌面 hero 封面同一规则：入口收在角落圆钮上，整张封面不再
                // 可点，避免误触；音乐直进沉浸播放详情，其余模块回各自分区路由。
                SizedBox(
                  height: 320,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      PortalGradientCover(
                        palette: palette,
                        title: item.title,
                        subtitle: item.subtitle,
                        height: 320,
                        imageUrl: item.imageUrl,
                        readerItemId: item.readerItemId,
                        fallbackIcon: item.icon.iconData,
                      ),
                      Positioned(
                        top: 10,
                        right: 10,
                        child: _PortalCoverEntryButton(
                          onTap:
                              item.module == PortalFocusModule.music
                                  ? onOpenImmersivePlayback
                                  : () => context.go(item.route),
                          module: item.module,
                          tooltip: item.actionLabel,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _StatusDock(palette: palette, data: data),
        ],
      ),
    );
  }
}
