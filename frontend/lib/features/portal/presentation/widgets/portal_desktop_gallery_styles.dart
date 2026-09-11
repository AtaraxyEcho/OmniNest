part of 'portal_desktop_visual_shells.dart';

class _BackdropLibraryPortal extends ConsumerStatefulWidget {
  const _BackdropLibraryPortal({
    required this.palette,
    required this.weatherOverride,
    required this.localBackdropActive,
    required this.onOpenImmersivePlayback,
  });

  final PortalVisualPalette palette;
  final WeatherData? weatherOverride;
  final bool localBackdropActive;
  final VoidCallback onOpenImmersivePlayback;

  @override
  ConsumerState<_BackdropLibraryPortal> createState() =>
      _BackdropLibraryPortalState();
}

class _BackdropLibraryPortalState
    extends ConsumerState<_BackdropLibraryPortal> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final data = _PortalDesktopData.from(
      ref,
      weatherOverride: widget.weatherOverride,
    );
    final items = data.coverSnapshots(context);
    final primary = data.primarySnapshot(context);
    final activeIndex = _resolveCarouselIndex(
      items: items,
      preferred: primary,
      selectedIndex: _selectedIndex,
    );
    final active = items[activeIndex];
    final failedSection = data.firstFailedSection;
    final content = LayoutBuilder(
      builder: (context, constraints) {
        final tier = resolvePortalDesktopLayoutTier(constraints.maxWidth);
        final availableHeight = _resolvePortalViewportHeight(
          context,
          constraints,
        );
        final verticalTight = availableHeight < 700;
        final layoutHeight = availableHeight.clamp(520.0, 980.0).toDouble();
        final heightScale = (layoutHeight / 720).clamp(0.84, 1.0).toDouble();
        // 排版缩放与内容限宽同源：超宽窗口下内容封顶，字号不再随窗口放大。
        final contentWidth = math.min(
          constraints.maxWidth,
          kPortalDesktopContentMaxWidth,
        );
        final heroFontScale =
            (contentWidth / kPortalDesktopContentMaxWidth)
                .clamp(0.94, 1.0)
                .toDouble() *
            heightScale;
        // 三栏在 1120-1399（平板与窄桌面窗）启用紧凑边栏，保证 hero
        // 文案与封面并排不局促；边栏加宽吃掉富余宽度使文案与封面贴合。
        final compactColumns =
            tier == PortalDesktopLayoutTier.wide && constraints.maxWidth < 1400;
        final dense = verticalTight || compactColumns;
        final panelGap = dense ? 12.0 : 16.0;
        final railWidth = dense ? 228.0 : 272.0;
        final attentionWidth = dense ? 300.0 : 336.0;
        final heroPadding = EdgeInsets.all(dense ? 20 : 24);
        final heroInnerGap = dense ? 16.0 : 24.0;
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: availableHeight),
            // 内容整体封顶并双向居中：超宽窗口两侧留给壁纸；高屏下
            // 内容块（≤980 高）在顶栏与窗口底之间垂直居中，不再顶贴。
            // minHeight 保证内容超高时仍按常规滚动。
            child: Align(
              alignment: Alignment.center,
              child: ConstrainedBox(
                key: const ValueKey('omninest.portal.content-cap'),
                constraints: const BoxConstraints(
                  maxWidth: kPortalDesktopContentMaxWidth,
                ),
                child: switch (tier) {
                  PortalDesktopLayoutTier.singleColumn => _SingleColumnVisual(
                    palette: widget.palette,
                    item: active,
                    data: data,
                    lightweight: widget.localBackdropActive,
                    onOpenImmersivePlayback: widget.onOpenImmersivePlayback,
                  ),
                  PortalDesktopLayoutTier.twoColumn => SizedBox(
                    height: layoutHeight,
                    child: Column(
                      children: [
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: PortalVisualPanel(
                                  palette: widget.palette,
                                  padding: heroPadding,
                                  lightweight: widget.localBackdropActive,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: _HeroCopy(
                                          palette: widget.palette,
                                          eyebrow:
                                              active.heroEyebrow ??
                                              l10n.portalVisualEyebrowCompact,
                                          title: active.title,
                                          body:
                                              active.heroBody ??
                                              active.subtitle,
                                          action: active.actionLabel,
                                          fontScale: heroFontScale,
                                          onAction:
                                              () => context.go(active.route),
                                          quickActions: _PortalFocusQuickActions(
                                            palette: widget.palette,
                                            item: active,
                                            data: data,
                                            onOpenImmersivePlayback:
                                                widget.onOpenImmersivePlayback,
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: heroInnerGap),
                                      Expanded(
                                        child: _PortalHeroCoverDisplay(
                                          palette: widget.palette,
                                          item: active,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              SizedBox(width: panelGap),
                              SizedBox(
                                width: attentionWidth,
                                key: const ValueKey(
                                  'omninest.portal.side-column',
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      flex: 5,
                                      child: _AttentionPanel(
                                        palette: widget.palette,
                                        data: data,
                                        activeModule: active.module,
                                        lightweight: widget.localBackdropActive,
                                      ),
                                    ),
                                    SizedBox(height: panelGap),
                                    Expanded(
                                      flex: 4,
                                      child: _StatusRail(
                                        palette: widget.palette,
                                        data: data,
                                        lightweight: widget.localBackdropActive,
                                        scrollable: true,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: verticalTight ? 8 : 16),
                        _VisualFilmStrip(
                          palette: widget.palette,
                          items: items,
                          activeIndex: activeIndex,
                          lightweight: widget.localBackdropActive,
                          onSelected:
                              (index) => setState(() => _selectedIndex = index),
                        ),
                      ],
                    ),
                  ),
                  PortalDesktopLayoutTier.wide => SizedBox(
                    height: layoutHeight,
                    child: Column(
                      children: [
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                width: railWidth,
                                child: _StatusRail(
                                  palette: widget.palette,
                                  data: data,
                                  lightweight: widget.localBackdropActive,
                                ),
                              ),
                              SizedBox(width: panelGap),
                              Expanded(
                                child: PortalVisualPanel(
                                  palette: widget.palette,
                                  padding: heroPadding,
                                  lightweight: widget.localBackdropActive,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 6,
                                        child: _HeroCopy(
                                          palette: widget.palette,
                                          eyebrow:
                                              active.heroEyebrow ??
                                              l10n.portalVisualEyebrowRecentContent,
                                          title: active.title,
                                          body:
                                              active.heroBody ??
                                              active.subtitle,
                                          action: active.actionLabel,
                                          fontScale: heroFontScale,
                                          onAction:
                                              () => context.go(active.route),
                                          quickActions: _PortalFocusQuickActions(
                                            palette: widget.palette,
                                            item: active,
                                            data: data,
                                            onOpenImmersivePlayback:
                                                widget.onOpenImmersivePlayback,
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: heroInnerGap),
                                      Expanded(
                                        flex: 5,
                                        child: _PortalHeroCoverDisplay(
                                          palette: widget.palette,
                                          item: active,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              SizedBox(width: panelGap),
                              SizedBox(
                                width: attentionWidth,
                                child: _AttentionPanel(
                                  palette: widget.palette,
                                  data: data,
                                  activeModule: active.module,
                                  lightweight: widget.localBackdropActive,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: verticalTight ? 8 : 16),
                        _VisualFilmStrip(
                          palette: widget.palette,
                          items: items,
                          activeIndex: activeIndex,
                          lightweight: widget.localBackdropActive,
                          onSelected:
                              (index) => setState(() => _selectedIndex = index),
                        ),
                      ],
                    ),
                  ),
                },
              ),
            ),
          ),
        );
      },
    );
    return Stack(
      children: [
        content,
        if (failedSection != null)
          Positioned(
            top: 12,
            right: 12,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: _PortalDesktopFailureBanner(
                palette: widget.palette,
                message: data.failureMessage(context, failedSection),
                onRetry:
                    () => unawaited(
                      ref
                          .read(portalDashboardActionsProvider)
                          .retry(failedSection),
                    ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PortalDesktopFailureBanner extends StatelessWidget {
  const _PortalDesktopFailureBanner({
    required this.palette,
    required this.message,
    required this.onRetry,
  });

  final PortalVisualPalette palette;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Material(
      color: palette.structuralStrongSurface(alpha: 0.92),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sync_problem_rounded,
              color: palette.accentAlt,
              size: 18,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.text,
                  fontSize: AppTypography.bodyMedium,
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: onRetry, child: Text(l10n.coreRetry)),
          ],
        ),
      ),
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy({
    required this.palette,
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.action,
    this.onAction,
    this.quickActions,
    this.fontScale = 1,
  });

  final PortalVisualPalette palette;
  final String eyebrow;
  final String title;
  final String body;
  final String action;
  final VoidCallback? onAction;
  final Widget? quickActions;
  final double fontScale;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boundedHeight = constraints.hasBoundedHeight;
        final quickActionsWidget = quickActions;
        final hasQuickActions = quickActionsWidget != null;
        final quickActionsChild =
            quickActionsWidget == null
                ? null
                : boundedHeight
                ? Expanded(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: quickActionsWidget,
                  ),
                )
                : quickActionsWidget;
        return Column(
          mainAxisAlignment:
              boundedHeight
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (boundedHeight && !hasQuickActions) const Spacer(),
            Text(
              eyebrow,
              style: TextStyle(
                color: palette.muted,
                fontSize: AppTypography.bodySmall * fontScale,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: PortalHeroEllipsizedTitle(
                title,
                style: TextStyle(
                  color: palette.text,
                  fontSize: AppTypography.displayLarge * fontScale,
                  height: 1.06,
                  letterSpacing: 0,
                  fontWeight: FontWeight.w800,
                  shadows: [
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.30),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Text(
                body,
                maxLines: hasQuickActions ? 3 : null,
                overflow:
                    hasQuickActions ? TextOverflow.ellipsis : TextOverflow.clip,
                style: TextStyle(
                  color: palette.muted,
                  height: 1.68,
                  fontSize: AppTypography.bodyLarge * fontScale,
                ),
              ),
            ),
            const SizedBox(height: 22),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 238),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: onAction,
                  child: Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: palette.structuralStrongSurface(alpha: 0.68),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: palette.muted.withValues(alpha: 0.24),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            action,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.text,
                              fontSize: AppTypography.bodyLarge * fontScale,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.arrow_forward_rounded,
                          color: palette.text,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (quickActionsChild != null) ...[
              const SizedBox(height: 16),
              quickActionsChild,
            ],
            if (boundedHeight && !hasQuickActions) const Spacer(),
          ],
        );
      },
    );
  }
}

class _PortalHeroCoverDisplay extends StatelessWidget {
  const _PortalHeroCoverDisplay({required this.palette, required this.item});

  final PortalVisualPalette palette;
  final PortalFocusItem item;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 460.0;
        final availableWidth =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 400.0;
        // 封面卡宽高上限 400×540：与限宽后 hero 面板的封面份额匹配，
        // 避免高窗下封面顶满 620 高、与文案之间拉出空带。
        final coverHeight =
            math
                .min(availableHeight * 0.84, 540.0)
                .clamp(320.0, 540.0)
                .toDouble();
        final coverWidth =
            math
                .min(availableWidth, coverHeight * 0.74)
                .clamp(240.0, 400.0)
                .toDouble();
        return Center(
          child: SizedBox(
            key: const ValueKey('omninest.portal.hero-cover'),
            width: coverWidth,
            height: coverHeight,
            child: PortalGradientCover(
              palette: palette,
              title: item.title,
              subtitle: item.subtitle,
              variant: item.variant,
              height: coverHeight,
              imageUrl: item.imageUrl,
              readerItemId: item.readerItemId,
              fallbackIcon: item.icon.iconData,
              maxCoverWidth: coverWidth,
              maxCoverHeight: coverHeight,
              foregroundFit: BoxFit.contain,
              foregroundPadding: const EdgeInsets.fromLTRB(16, 16, 16, 74),
              borderWidth: 1.2,
            ),
          ),
        );
      },
    );
  }
}
