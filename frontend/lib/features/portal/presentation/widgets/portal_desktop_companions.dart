part of 'portal_desktop_visual_shells.dart';

class _VisualFilmStrip extends StatelessWidget {
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
  Widget build(BuildContext context) {
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

class _StatusRail extends StatelessWidget {
  const _StatusRail({
    required this.palette,
    required this.data,
    this.lightweight = false,
  });

  final PortalVisualPalette palette;
  final _PortalDesktopData data;
  final bool lightweight;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final l10n = AppLocalizations.of(context);
    return PortalVisualPanel(
      palette: palette,
      lightweight: lightweight,
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
          const Spacer(),
          PortalMetricLine(
            palette: palette,
            label: l10n.portalWeatherTitle,
            value: data.weatherSummary(context),
            onTap: () => _openWeatherDetails(context, data),
          ),
          PortalMetricLine(
            palette: palette,
            label: l10n.portalAdmin,
            value: data.taskSummary,
            onTap: () => context.go('/admin'),
          ),
          PortalMetricLine(
            palette: palette,
            label: l10n.portalStorageTitle,
            value: data.storageSummary(context),
          ),
        ],
      ),
    );
  }
}

class _AttentionPanel extends StatelessWidget {
  const _AttentionPanel({
    required this.palette,
    required this.data,
    required this.activeModule,
    this.lightweight = false,
  });

  final PortalVisualPalette palette;
  final _PortalDesktopData data;
  final PortalFocusModule activeModule;
  final bool lightweight;

  @override
  Widget build(BuildContext context) {
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
                  const SizedBox(height: 14),
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
                      onOpenQueue: () => showMusicDeckQueue(context),
                    ),
                    const SizedBox(height: 12),
                  ],
                  _NoticeTile(
                    palette: palette,
                    title: l10n.portalWeatherTitle,
                    subtitle: data.weatherSummary(context),
                    detail: data.weatherDetailSummary(context),
                    icon: Icons.cloud_outlined,
                    onTap: () => _openWeatherDetails(context, data),
                  ),
                  _NoticeTile(
                    palette: palette,
                    title: l10n.portalAdmin,
                    subtitle: data.taskSummary,
                    detail: l10n.portalAdminSubtitle,
                    icon: Icons.admin_panel_settings_rounded,
                    onTap: () => context.go('/admin'),
                  ),
                  _NoticeTile(
                    palette: palette,
                    title: l10n.portalStorageTitle,
                    subtitle: data.storageSummary(context),
                  ),
                  const SizedBox(height: 12),
                  PortalQuickLinks(palette: palette),
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
      margin: const EdgeInsets.only(bottom: 10),
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

class _StatusDock extends StatelessWidget {
  const _StatusDock({required this.palette, required this.data});

  final PortalVisualPalette palette;
  final _PortalDesktopData data;

  @override
  Widget build(BuildContext context) {
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
                    SizedBox(
                      width: 170,
                      child: PortalMetricLine(
                        palette: palette,
                        label: l10n.portalAdmin,
                        value: data.taskSummary,
                        onTap: () => context.go('/admin'),
                      ),
                    ),
                    const SizedBox(width: 14),
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
                Expanded(
                  child: PortalMetricLine(
                    palette: palette,
                    label: l10n.portalAdmin,
                    value: data.taskSummary,
                    onTap: () => context.go('/admin'),
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
                PortalGradientCover(
                  palette: palette,
                  title: item.title,
                  subtitle: item.subtitle,
                  height: 320,
                  imageUrl: item.imageUrl,
                  readerItemId: item.readerItemId,
                  fallbackIcon: item.icon.iconData,
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
