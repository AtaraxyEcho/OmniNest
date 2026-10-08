part of 'portal_mobile_shell.dart';

/// Spatial Home：个人数字空间的进入面。
///
/// 首页只承担「进入 OmniNest」：时间与环境状态、一个最重要的续接
/// 内容、少量最近动态与高频动作；不再堆叠仪表盘卡片。
/// 舞台限宽与列数按 600/720/980 三档切换，见 [PortalMobileTier]。
class _HostedPortalContent extends ConsumerWidget {
  const _HostedPortalContent({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      color: MobileEnvColors.accent,
      onRefresh: onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = constraints.maxHeight;
          final tier = PortalMobileTier.resolveWidth(constraints.maxWidth);
          final spacious = viewport > 640;
          // 样例 home-stage 顶部内边距为 5vh：时钟从视口顶部 5% 处开始，
          // 不再使用固定高度盒子沉底（会在眉标上方堆出大片死空间）。
          final headerTop = (viewport * 0.05).clamp(20.0, 48.0);
          final horizontal = tier.homeHorizontalPadding;
          final header = _SpatialEnvironmentHeader(
            topPadding: headerTop,
            leftAligned: tier.twoColumnHome,
            heroMaxFontSize: tier.heroTimeMaxFontSize,
          );
          final focus = const _SpatialFocusCard();
          final lower = <Widget>[
            const _SpatialRecentHeading(),
            const SizedBox(height: 12),
            _SpatialRecentStrip(tier: tier),
            const SizedBox(height: 12),
            _SpatialQuickLine(tier: tier),
          ];

          final scroll = CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: horizontal),
                sliver: SliverToBoxAdapter(
                  child:
                      tier.twoColumnHome
                          // 原型 ≥980：`.home-stage` 为 1.1fr/.9fr 双栏，
                          // 时间块左对齐、焦点卡同排右侧。
                          ? Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(flex: 11, child: header),
                              const SizedBox(width: 30),
                              Expanded(flex: 9, child: focus),
                            ],
                          )
                          : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              header,
                              // 样例手机档 time-block 与 home-focus 近乎相连
                              //（auto-margin 余量很小），高屏略增。
                              SizedBox(height: spacious ? 24 : 12),
                              focus,
                            ],
                          ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  horizontal,
                  tier.twoColumnHome ? 36 : 0,
                  horizontal,
                  24,
                ),
                sliver: SliverList.list(
                  children:
                      tier.twoColumnHome
                          ? lower
                          : <Widget>[
                            SizedBox(height: spacious ? 36 : 24),
                            ...lower,
                          ],
                ),
              ),
            ],
          );

          final stageMaxWidth = tier.stageMaxWidth;
          if (stageMaxWidth == null) {
            return scroll;
          }
          // 原型 `.app-frame` 限宽：720-979 收 760，≥980 由壳层侧栏轨
          // 约束舞台，本模块沿用基线上限避免内容摊满超宽视口。
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: stageMaxWidth),
              child: scroll,
            ),
          );
        },
      ),
    );
  }
}

/// 环境头部：星期·日期、大时钟与天气，直接呈现在壁纸环境上。
///
/// 水平内衬由宿主 [SliverPadding] 统一给出，头部只保留顶部留白；
/// 双栏档按原型 `.time-block{text-align:left}` 左对齐。
class _SpatialEnvironmentHeader extends ConsumerStatefulWidget {
  const _SpatialEnvironmentHeader({
    required this.topPadding,
    required this.leftAligned,
    required this.heroMaxFontSize,
  });

  /// 顶部内边距（样例 5vh 折算，由宿主按视口高度计算）。
  final double topPadding;

  /// 是否左对齐（≥980 双栏档）。
  final bool leftAligned;

  /// 大时钟字号上限（样例 108，≥980 档 130）。
  final double heroMaxFontSize;

  @override
  ConsumerState<_SpatialEnvironmentHeader> createState() =>
      _SpatialEnvironmentHeaderState();
}

class _SpatialEnvironmentHeaderState
    extends ConsumerState<_SpatialEnvironmentHeader> {
  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final weather = ref.watch(realtimeWeatherProvider);
    final localizations = MaterialLocalizations.of(context);
    // 原型眉标为「星期 · 短日期」，拉丁文案统一大写。
    final eyebrow =
        '${DateFormat('EEEE').format(_now)} · ${localizations.formatShortMonthDay(_now)}';
    final timeOfDay = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(_now),
      alwaysUse24HourFormat: true,
    );
    // 居中层里只有时钟会被 LayoutBuilder 拿到拉满宽的盒子（眉标与天气条是自己
    // 收缩宽度的），所以光靠 Column 的 crossAxisAlignment 不足以让它居中：
    // 盒子里的墨迹还要显式对齐。双栏档反过来贴着左侧栏。
    final inlineAlignment =
        widget.leftAligned ? TextAlign.start : TextAlign.center;
    return Padding(
      padding: EdgeInsets.only(top: widget.topPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            widget.leftAligned
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
        children: [
          Text(
            eyebrow.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: inlineAlignment,
            style: const TextStyle(
              color: MobileEnvColors.inkFaint,
              fontSize: AppTypography.labelMicro,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.65,
            ),
          ),
          const SizedBox(height: 2),
          LayoutBuilder(
            builder: (context, constraints) {
              final scale = (constraints.maxWidth * 0.24).clamp(
                72.0,
                widget.heroMaxFontSize,
              );
              // 衬线大时钟是氛围元素，字号已由视口宽度推导（原型
              // clamp(72,24vw,108)）；再叠加无障碍字号会在 1.6x 下把
              // 时间块撑到视口外，故此处不随 textScaler 二次放大。
              return MediaQuery.withNoTextScaling(
                child: Text(
                  timeOfDay,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: inlineAlignment,
                  style: TextStyle(
                    color: MobileEnvColors.ink,
                    fontFamily: AppTypography.serifFamily,
                    fontFamilyFallback: AppTypography.serifFamilyFallback,
                    fontSize: scale,
                    height: 1.0,
                    letterSpacing: -4,
                    shadows: const [
                      Shadow(color: Colors.black54, blurRadius: 18),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          weather.when(
            data: (value) {
              final location =
                  value.locationName.isNotEmpty ? ' ${value.locationName}' : '';
              return _WeatherLinePill(
                onTap: () => showWeatherDetailSheet(context, weather: value),
                semanticLabel: AppLocalizations.of(context).portalWeatherTitle,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OmniIcon(
                      icon: OmniIcons.weatherFor(
                        int.tryParse(value.icon) ?? -1,
                      ),
                      size: 19,
                      color: MobileEnvColors.white78,
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        '${value.temp}°',
                        style: const TextStyle(
                          color: MobileEnvColors.white78,
                          fontSize: AppTypography.bodyMedium,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 3,
                      height: 3,
                      decoration: const BoxDecoration(
                        color: Color(0x8CFFFFFF),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '${value.text}$location',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: MobileEnvColors.white78,
                          fontSize: AppTypography.bodyMedium,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const OmniIcon(
                      icon: OmniIcons.chevron,
                      size: 15,
                      color: MobileEnvColors.white52,
                    ),
                  ],
                ),
              );
            },
            loading: () => const MobileSkeletonBlock(width: 168, height: 16),
            error:
                (_, _) => MobilePressable(
                  semanticLabel: AppLocalizations.of(context).coreRetry,
                  onTap:
                      () => unawaited(
                        ref
                            .read(portalDashboardActionsProvider)
                            .retry(PortalDashboardSection.weather),
                      ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const OmniIcon(
                        icon: OmniIcons.cloud,
                        size: 18,
                        color: MobileEnvColors.white78,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        AppLocalizations.of(context).portalWeatherDisconnected,
                        style: const TextStyle(
                          color: MobileEnvColors.white78,
                          fontSize: AppTypography.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
          ),
        ],
      ),
    );
  }
}

/// 天气胶囊（原型 weather-line）：常态透明，悬停浮现白 7% 玻璃底 +
/// blur(10)；几何取原型（min-height 42 / radius 21 / 横向 10 内边距）。
class _WeatherLinePill extends StatefulWidget {
  const _WeatherLinePill({
    required this.child,
    required this.onTap,
    required this.semanticLabel,
  });

  final Widget child;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  State<_WeatherLinePill> createState() => _WeatherLinePillState();
}

class _WeatherLinePillState extends State<_WeatherLinePill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    // blur 层常驻（sigma 随悬停切换）：BackdropFilter 取样区取决于子树
    // 边界，若按悬停插拔会只模糊到内容行而非整颗胶囊。
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: MobilePressable(
        semanticLabel: widget.semanticLabel,
        onTap: widget.onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(21),
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: _hovered ? 10 : 0,
              sigmaY: _hovered ? 10 : 0,
            ),
            child: AnimatedContainer(
              duration:
                  reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              constraints: const BoxConstraints(minHeight: 42),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color:
                    _hovered
                        ? Colors.white.withValues(alpha: 0.07)
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(21),
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// 焦点续接卡：当前最重要的一个「继续」内容。
///
/// 优先级：正在播放 → 继续阅读 → 继续观看 → 推荐曲目（跳音乐模块）。
/// 眉标按一天中的时段措辞，与原型「CONTINUE YOUR EVENING」同语义。
class _SpatialFocusCard extends ConsumerWidget {
  const _SpatialFocusCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final music = ref.watch(portalMusicSnapshotProvider).asData?.value;
    final reader = ref.watch(portalReaderDashboardProvider).asData?.value;
    final movie = ref.watch(portalMovieDashboardProvider).asData?.value;

    final activeTrack = music?.activeTrack;
    final continueReading = reader?.continueReading.firstOrNull;
    final continueWatching = movie?.continueWatching.firstOrNull;

    Widget? card;
    if (activeTrack != null) {
      card = _SpatialFocusTile(
        eyebrow: _dayPartEyebrow(l10n),
        contextLine:
            activeTrack.albumTitle.isNotEmpty
                ? l10n.spatialPlayingFrom(activeTrack.albumTitle)
                : l10n.spatialNowPlaying,
        title: activeTrack.title,
        subtitle:
            activeTrack.artistName.isEmpty
                ? activeTrack.albumTitle
                : activeTrack.artistName,
        imageUrl: activeTrack.listCoverUrl ?? activeTrack.coverUrl,
        squareArt: true,
        actionIcon: music?.isPlaying == true ? OmniIcons.pause : OmniIcons.play,
        actionLabel: music?.isPlaying == true ? l10n.corePause : l10n.corePlay,
        onAction:
            () => unawaited(
              ref.read(portalMusicActionsProvider).togglePlayback(),
            ),
        onTap: () => context.push('/music/now-playing'),
      );
    } else if (continueReading != null) {
      final fraction = continueReading.progressPercent ?? 0;
      card = _SpatialFocusTile(
        eyebrow: _dayPartEyebrow(l10n),
        contextLine: l10n.readerSpaceContinueEyebrow,
        title: continueReading.title,
        subtitle:
            fraction > 0
                ? '${continueReading.authorName ?? ''} · ${(fraction * 100).round()}%'
                : (continueReading.authorName ?? ''),
        readerItemId: continueReading.hasCover ? continueReading.id : null,
        actionIcon: OmniIcons.arrow,
        actionLabel: l10n.spatialResume,
        onTap: () => context.push('/reader/items/${continueReading.id}'),
        progress: fraction,
      );
    } else if (continueWatching != null) {
      card = _SpatialFocusTile(
        eyebrow: _dayPartEyebrow(l10n),
        contextLine: l10n.libraryContinueWatchingTitle,
        title: continueWatching.title,
        subtitle: l10n.spatialFocusWatchingSub(
          continueWatching.progressPercent.round(),
        ),
        imageUrl: continueWatching.posterUrl,
        actionIcon: OmniIcons.play,
        actionLabel: l10n.corePlay,
        onTap: () => context.push(moviePlayRoute(continueWatching.id)),
        progress: continueWatching.progressPercent / 100,
      );
    } else if (music?.featuredTrack != null) {
      final featured = music!.featuredTrack!;
      card = _SpatialFocusTile(
        eyebrow: _dayPartEyebrow(l10n),
        contextLine: l10n.spatialNowPlaying,
        title: featured.title,
        subtitle: featured.artistName,
        imageUrl: featured.listCoverUrl ?? featured.coverUrl,
        squareArt: true,
        actionIcon: OmniIcons.play,
        actionLabel: l10n.corePlay,
        onTap: () => context.push('/music'),
      );
    } else {
      // 空库兜底：焦点栏目常驻（样例恒有 CONTINUE YOUR EVENING + 卡片）。
      card = _SpatialFocusTile(
        eyebrow: _dayPartEyebrow(l10n),
        contextLine: l10n.spatialStartListening,
        title: l10n.spatialStartTitle,
        subtitle: l10n.spatialStartSubtitle,
        squareArt: true,
        actionIcon: OmniIcons.play,
        actionLabel: l10n.corePlay,
        onTap: () => context.push('/music'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _dayPartEyebrow(l10n).toUpperCase(),
          style: const TextStyle(
            color: MobileEnvColors.inkFaint,
            fontSize: AppTypography.labelMicro,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.65,
          ),
        ),
        const SizedBox(height: 10),
        card,
      ],
    );
  }

  String _dayPartEyebrow(AppLocalizations l10n) {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return l10n.spatialFocusMorning;
    }
    if (hour < 18) {
      return l10n.spatialFocusAfternoon;
    }
    return l10n.spatialFocusEvening;
  }
}

class _SpatialFocusTile extends StatelessWidget {
  const _SpatialFocusTile({
    required this.eyebrow,
    required this.contextLine,
    required this.title,
    required this.subtitle,
    required this.actionIcon,
    required this.actionLabel,
    required this.onTap,
    this.imageUrl,
    this.readerItemId,
    this.squareArt = false,
    this.progress,
    this.onAction,
  });

  final String eyebrow;

  /// 标题上方的语境行（如「正在播放 Evening Drift」）。
  final String contextLine;
  final String title;
  final String subtitle;
  final String? imageUrl;

  /// 阅读条目封面（需鉴权下载）。
  final String? readerItemId;
  final bool squareArt;
  final OmniIconsData actionIcon;
  final String actionLabel;
  final VoidCallback onTap;

  /// 圆形主按钮的独立动作；缺省与整卡一致。
  final VoidCallback? onAction;

  /// 0-1 的进度；null 不显示。
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final artFallback = ColoredBox(
      color: Colors.white.withValues(alpha: 0.06),
      child: Center(
        child: OmniIcon(
          icon:
              readerItemId != null
                  ? OmniIcons.book
                  : squareArt
                  ? OmniIcons.music
                  : OmniIcons.film,
          size: 24,
          color: MobileEnvColors.white46,
        ),
      ),
    );
    Widget art;
    if (readerItemId != null) {
      art = AuthCoverImage(
        itemId: readerItemId!,
        fit: BoxFit.cover,
        fallback: artFallback,
      );
    } else if (imageUrl != null && imageUrl!.isNotEmpty) {
      art = PortalMediaThumbnail(
        imageUrl: imageUrl!,
        fit: BoxFit.cover,
        cacheHeight: 176,
        borderRadius: BorderRadius.zero,
        fallback: artFallback,
      );
    } else {
      art = artFallback;
    }
    return MobilePressable(
      semanticLabel: title,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  MobileEnvColors.focusGradientStart,
                  MobileEnvColors.focusGradientEnd,
                ],
              ),
              border: Border.all(color: MobileEnvColors.line15),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 35,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  SizedBox(
                    width: squareArt ? 68 : 56,
                    height: 68,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          art,
                          if (progress != null)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: LinearProgressIndicator(
                                value: progress!.clamp(0, 1),
                                minHeight: 3,
                                color: MobileEnvColors.accent,
                                backgroundColor: Colors.black45,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          contextLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: MobileEnvColors.inkMuted,
                            fontSize: AppTypography.labelMicro,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: MobileEnvColors.ink,
                            // ignore: font_size_whitelist
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: MobileEnvColors.white52,
                            fontSize: AppTypography.labelSmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  MobilePressable(
                    semanticLabel: actionLabel,
                    onTap: onAction ?? onTap,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: MobileEnvColors.accent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: MobileEnvColors.accent.withValues(
                              alpha: 0.35,
                            ),
                            blurRadius: 14,
                          ),
                        ],
                      ),
                      child: Center(
                        child: OmniIcon(
                          icon: actionIcon,
                          size: 21,
                          color: MobileEnvColors.onAccent,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 最近动态标题行：eyebrow + 「进入媒体库」文字动作。
class _SpatialRecentHeading extends StatelessWidget {
  const _SpatialRecentHeading();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            l10n.spatialRecentlyEyebrow.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: MobileEnvColors.inkFaint,
              fontSize: AppTypography.labelMicro,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.65,
            ),
          ),
        ),
        TextButton(
          onPressed: () => context.go('/library'),
          style: TextButton.styleFrom(
            foregroundColor: MobileEnvColors.white70,
            minimumSize: const Size(48, 40),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            textStyle: const TextStyle(fontSize: AppTypography.labelSmall),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.spatialViewLibrary),
              const SizedBox(width: 1),
              const OmniIcon(
                icon: OmniIcons.chevron,
                size: 16,
                color: MobileEnvColors.white70,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 最近动态条：照片 / 阅读 / 文件三张紧凑卡。
///
/// 手机与平板档沿用样例 `1.4fr : 1fr : 1fr`；≥980 双栏档按原型
/// `.recent-strip{repeat(3,1fr)}` 等分三列并抬高瓦片。
class _SpatialRecentStrip extends ConsumerWidget {
  const _SpatialRecentStrip({required this.tier});

  final PortalMobileTier tier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final photos = ref.watch(portalPhotoDashboardProvider).asData?.value;
    final reader = ref.watch(portalReaderDashboardProvider).asData?.value;
    final recentFiles = ref.watch(fileRecentEntriesProvider).asData?.value;
    final recentPhoto = photos?.recentPhotos.firstOrNull;
    final readingItem =
        reader?.continueReading.firstOrNull ?? reader?.recentItems.firstOrNull;
    final fileNode = recentFiles?.firstOrNull;

    final tiles = <Widget>[
      _SpatialRecentTile(
        label: l10n.spatialRecentPhotos,
        photo: recentPhoto,
        height: tier.recentTileHeight,
        photoSub: l10n.libraryBannerPhotoCount(
          photos?.recentPhotos.length ?? 0,
        ),
        onTap: () {
          final list = photos?.recentPhotos ?? const <PhotoItem>[];
          if (list.isEmpty) {
            context.push('/photos');
            return;
          }
          ref
              .read(photoBrowseScopeProvider.notifier)
              .set(list, PhotoBrowseSource.library);
          context.push('/photos/${list.first.id}');
        },
      ),
      _SpatialRecentTile(
        label: l10n.mobileNavReader,
        readerItem: readingItem,
        height: tier.recentTileHeight,
        onTap:
            readingItem == null
                ? () => context.go('/reader')
                : () => context.push('/reader/items/${readingItem.id}'),
      ),
      _SpatialRecentTile(
        label: l10n.spatialRecentFiles,
        fileNode: fileNode,
        height: tier.recentTileHeight,
        onTap: () => context.go('/files'),
      ),
    ];
    final photoFlex = tier.twoColumnHome ? 1 : 14;
    final otherFlex = tier.twoColumnHome ? 1 : 10;
    return Row(
      children: [
        for (var index = 0; index < tiles.length; index++) ...[
          if (index > 0) const SizedBox(width: 10),
          Expanded(
            flex: index == 0 ? photoFlex : otherFlex,
            child: tiles[index],
          ),
        ],
      ],
    );
  }
}

class _SpatialRecentTile extends StatelessWidget {
  const _SpatialRecentTile({
    required this.label,
    required this.height,
    required this.onTap,
    this.photo,
    this.photoSub,
    this.readerItem,
    this.fileNode,
  });

  final String label;

  /// 瓦片高度（样例 136，≥980 双栏档 150）。
  final double height;
  final PhotoItem? photo;

  /// 照片卡副文案（如新增张数）。
  final String? photoSub;
  final ReaderItem? readerItem;
  final FileNode? fileNode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    String title = label;
    String? subtitle;
    Widget? visual;
    if (photo != null) {
      title = photo!.title;
      subtitle = photoSub;
    } else if (readerItem != null) {
      title = readerItem!.title;
      visual = _BookMini(title: readerItem!.title);
      final fraction = readerItem!.progressPercent;
      final percent = fraction == null ? null : (fraction * 100).round();
      final chapter = readerItem!.currentChapterTitle;
      subtitle = [
        if (chapter?.isNotEmpty == true) chapter,
        if (percent != null && percent > 0) '$percent%',
      ].join(' · ');
    } else if (fileNode != null) {
      title = fileNode!.name;
      visual = Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: MobileEnvColors.folderGlyphBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: OmniIcon(
            icon: OmniIcons.folder,
            size: 24,
            color: MobileEnvColors.folderGlyph,
          ),
        ),
      );
      final updated = fileNode!.updatedAt;
      if (updated != null) {
        subtitle = localizations.formatShortDate(updated);
      }
    }
    Widget? image;
    if (photo != null) {
      image = PortalMediaThumbnail(
        imageUrl: photo!.coverUrl ?? '',
        cacheKey: photo!.coverCacheKey,
        cacheHeight: 320,
        fit: BoxFit.cover,
        borderRadius: BorderRadius.zero,
        fallback: const SizedBox.shrink(),
      );
    } else if (readerItem != null && readerItem!.hasCover) {
      image = AuthCoverImage(
        itemId: readerItem!.id,
        fit: BoxFit.cover,
        fallback: const SizedBox.shrink(),
      );
    }
    return MobilePressable(
      semanticLabel: label,
      onTap: onTap,
      child: SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: MobileEnvColors.surfaceRaised,
            borderRadius: BorderRadius.circular(19),
            border: Border.all(color: MobileEnvColors.line10),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(19),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (image != null)
                  Positioned.fill(child: image)
                else
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.white.withValues(alpha: 0.02),
                    ),
                  ),
                if (image != null)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.05),
                            Colors.black.withValues(alpha: 0.78),
                          ],
                          stops: const [0.35, 1],
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (visual != null) visual,
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: photo != null ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: MobileEnvColors.ink,
                              fontSize: AppTypography.bodySmall,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                            ),
                          ),
                          if (subtitle != null && subtitle.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: MobileEnvColors.inkMuted,
                                fontSize: AppTypography.labelMicro,
                              ),
                            ),
                          ],
                        ],
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

/// 书脊小卡：衬线首字母 + 左侧书脊描边（原型 book-mini）。
class _BookMini extends StatelessWidget {
  const _BookMini({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final letter =
        title.isNotEmpty ? title.characters.first.toUpperCase() : '?';
    return Container(
      width: 35,
      height: 48,
      decoration: const BoxDecoration(
        color: MobileEnvColors.bookMiniBg,
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(2),
          right: Radius.circular(7),
        ),
        boxShadow: [
          BoxShadow(
            color: MobileEnvColors.bookMiniSpine,
            offset: Offset(-3, 0),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: const TextStyle(
          color: MobileEnvColors.bookMiniFg,
          fontFamily: AppTypography.serifFamily,
          fontFamilyFallback: AppTypography.serifFamilyFallback,
          fontSize: AppTypography.titleLarge,
          height: 1,
        ),
      ),
    );
  }
}

/// 高频动作行：查找任何内容 / 添加媒体。
///
/// ≥980 双栏档按原型 `.quick-line{max-width:420}` 收成左对齐窄条，
/// 避免两枚按钮在跨列下摊满整幅。
class _SpatialQuickLine extends StatelessWidget {
  const _SpatialQuickLine({required this.tier});

  final PortalMobileTier tier;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget action(OmniIconsData icon, String label, VoidCallback onTap) {
      return Expanded(
        child: MobilePressable(
          semanticLabel: label,
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: MobileEnvColors.surfaceGlass,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: MobileEnvColors.line09),
                ),
                child: SizedBox(
                  height: MobileLayoutTokens.minimumTarget,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OmniIcon(
                        icon: icon,
                        size: 18,
                        color: MobileEnvColors.ink,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: MobileEnvColors.ink,
                            fontSize: AppTypography.labelSmall,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final row = Row(
      children: [
        action(OmniIcons.search, l10n.spatialActionFind, () {
          context.push('/search');
        }),
        const SizedBox(width: 9),
        action(OmniIcons.plus, l10n.spatialActionAddMedia, () {
          context.go('/files');
        }),
      ],
    );
    final maxWidth = tier.quickLineMaxWidth;
    if (maxWidth == null) {
      return row;
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: row,
      ),
    );
  }
}
