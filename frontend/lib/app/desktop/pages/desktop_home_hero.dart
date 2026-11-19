part of 'desktop_home_page.dart';

class _HeroSky extends StatelessWidget {
  const _HeroSky({
    required this.showSky,
    required this.contentLoading,
    required this.contentFailed,
    required this.retryLabel,
    required this.onRetryContent,
    required this.dateLabel,
    required this.greeting,
    required this.lead,
    required this.hour,
    required this.weather,
    required this.reduceMotion,
    required this.backdropActive,
    required this.listenLabel,
    required this.listenArtist,
    required this.onStartListening,
    this.listenArtUrl,
    this.resumeLabel,
    this.resumeTitle,
    this.resumeArtUrl,
    this.resumeProgress = 0,
    this.onResume,
  });

  /// 是否绘制实时天象；自定义壁纸在场时为 false。
  final bool showSky;
  final bool contentLoading;
  final bool contentFailed;
  final String retryLabel;
  final VoidCallback onRetryContent;

  final String dateLabel;
  final String greeting;
  final String lead;
  final double hour;
  final WeatherData? weather;
  final bool reduceMotion;
  final String listenLabel;
  final String listenArtist;
  final String? listenArtUrl;
  final VoidCallback onStartListening;
  final String? resumeLabel;
  final String? resumeTitle;
  final String? resumeArtUrl;
  final double resumeProgress;
  final VoidCallback? onResume;

  /// 自定义壁纸在场：样例 `.bd-on .hero-sky` 换成透明面 + 底部长渐变，
  /// 不再绘制实时天象与两层暗纱。
  final bool backdropActive;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    // 样例终值在 `polish.css:404`：clamp(380px, 46vh, 500px)，
    // 覆盖 `desktop.css:284` 的 340–460。
    final height = (MediaQuery.sizeOf(context).height * 0.46).clamp(
      380.0,
      500.0,
    );
    final isDay = hour >= 5.5 && hour < 20.5;
    final condition =
        weather == null
            ? DesktopSkyCondition.clear
            : desktopSkyConditionOf(
              iconCode: weather!.icon,
              text: weather!.text,
            );
    final showWeatherCard = width >= 1180;
    final skin = DesktopSkin.of(context);
    final inset = (width * 0.034).clamp(26.0, 44.0);
    final l10n = AppLocalizations.of(context);

    return Container(
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DesktopMetrics.radiusHero),
        // `extra.css:124`：`.bd-on .hero-sky` 的底是透明的，让壁纸透上来。
        color: backdropActive ? Colors.transparent : null,
        boxShadow: skin.shadow,
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DesktopMetrics.radiusHero),
        border: Border.all(
          color:
              backdropActive
                  ? const Color(0xFFFFFFFF).withValues(alpha: 0.2)
                  : skin.line2,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (showSky && !backdropActive)
            DesktopSky(
              condition: condition,
              hour: hour,
              isDay: isDay,
              reduceMotion: reduceMotion,
            ),
          if (backdropActive)
            // `extra.css:126`：壁纸态只留底部长渐变（55% → 60% 处透明）。
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0x8C050A12), Color(0x00050A12)],
                  stops: [0.0, 0.6],
                ),
              ),
            )
          else ...[
            // `polish.css:405`：径向暗角（左下 72% → 48% 处 28% → 72% 透明）
            // 叠一层顶部 28% 的线性压暗。
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.bottomLeft,
                  radius: 1.2,
                  colors: [
                    Color(0xB8040912),
                    Color(0x47040912),
                    Color(0x00040912),
                  ],
                  stops: [0.0, 0.48, 0.72],
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x47040912), Color(0x00040912)],
                  stops: [0.0, 0.32],
                ),
              ),
            ),
          ],
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.all(inset),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          dateLabel.toUpperCase(),
                          style: DesktopType.eyebrow(
                            DesktopPalette.onStage.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          greeting,
                          style: DesktopType.displayXl(
                            DesktopPalette.onStage,
                            width,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (contentLoading) ...[
                          const SizedBox(
                            width: 440,
                            child: DesktopSkeletonBox(height: 16, radius: 5),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              const DesktopSkeletonBox(
                                width: 214,
                                height: 66,
                                radius: 16,
                              ),
                              const SizedBox(width: 10),
                              const DesktopSkeletonBox(
                                width: 214,
                                height: 66,
                                radius: 16,
                              ),
                            ],
                          ),
                        ] else ...[
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 440),
                            child: Text(
                              lead,
                              style: DesktopType.medium(
                                DesktopPalette.onStage.withValues(alpha: 0.8),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          if (contentFailed)
                            DesktopButton(
                              label: retryLabel,
                              icon: DesktopIcons.retry,
                              variant: DesktopButtonVariant.glass,
                              large: true,
                              onPressed: onRetryContent,
                            )
                          else
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                if (resumeTitle != null)
                                  _HeroActionTile(
                                    artUrl: resumeArtUrl,
                                    icon: DesktopIcons.play,
                                    filledIcon: true,
                                    meta:
                                        resumeLabel == null
                                            ? null
                                            : l10n.desktopHeroResumeMeta(
                                              (100 - resumeProgress).round(),
                                            ),
                                    title: resumeTitle!,
                                    progress: resumeProgress,
                                    onTap: onResume,
                                  ),
                                _HeroActionTile(
                                  artUrl: listenArtUrl,
                                  icon: DesktopIcons.music,
                                  meta: l10n.desktopHeroPlayMeta(listenArtist),
                                  title: listenLabel,
                                  onTap: onStartListening,
                                ),
                              ],
                            ),
                        ],
                      ],
                    ),
                  ),
                  if (showWeatherCard) ...[
                    const SizedBox(width: 32),
                    Align(
                      alignment: Alignment.topRight,
                      child: SizedBox(
                        width: 264,
                        child: _WeatherCard(weather: weather, isDay: isDay),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 样例 `.hero-tile`：52px 封面 + 两行文案 + 底部 3px 进度条。
class _HeroActionTile extends StatefulWidget {
  const _HeroActionTile({
    required this.icon,
    required this.title,
    this.meta,
    this.artUrl,
    this.filledIcon = false,
    this.progress,
    this.onTap,
  });

  final IconData icon;
  final String? meta;
  final String title;
  final String? artUrl;
  final bool filledIcon;

  /// 0–100；null 表示不画进度条（样例第二块 tile 没有 `.ht-bar`）。
  final double? progress;
  final VoidCallback? onTap;

  @override
  State<_HeroActionTile> createState() => _HeroActionTileState();
}

class _HeroActionTileState extends State<_HeroActionTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final art = widget.artUrl;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: DesktopMotion.of(context, DesktopMotion.fast),
          curve: DesktopMotion.ease,
          // 样例 `.hero-tile { overflow: hidden }`：底部进度条被圆角裁掉。
          clipBehavior: Clip.antiAlias,
          transform: Matrix4.translationValues(0, _hovered ? -2 : 0, 0),
          constraints: const BoxConstraints(minWidth: 214),
          padding: const EdgeInsets.fromLTRB(7, 7, 18, 7),
          decoration: BoxDecoration(
            color: Color(0xFFFFFFFF).withValues(alpha: _hovered ? 0.2 : 0.13),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Color(0xFFFFFFFF).withValues(alpha: _hovered ? 0.34 : 0.2),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x80000000),
                blurRadius: 30,
                spreadRadius: -14,
                offset: Offset(0, 10),
              ),
              BoxShadow(
                color: Color(0x2EFFFFFF),
                blurRadius: 0,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Stack(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: SizedBox(
                      width: 52,
                      height: 52,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (art != null && art.isNotEmpty)
                            DesktopImage(
                              url: art,
                              cacheWidth: 156,
                              fallbackIcon: widget.icon,
                            )
                          else
                            ColoredBox(
                              color: const Color(0x33FFFFFF),
                              child: Icon(
                                widget.icon,
                                size: 20,
                                color: const Color(0xFFFFFFFF),
                              ),
                            ),
                          ColoredBox(
                            color: Color(
                              0x00000000,
                            ).withValues(alpha: _hovered ? 0.18 : 0.32),
                            child: Icon(
                              widget.icon,
                              size: 15,
                              color: const Color(0xFFFFFFFF),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 240),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.meta != null)
                          Text(
                            widget.meta!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DesktopType.caption(
                              const Color(0xFFFFFFFF).withValues(alpha: 0.72),
                            ),
                          ),
                        const SizedBox(height: 2),
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DesktopType.medium(
                            const Color(0xFFFFFFFF),
                          ).copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (widget.progress != null)
                Positioned(
                  left: -7,
                  right: -18,
                  bottom: -7,
                  child: SizedBox(
                    height: 3,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(
                          color: Color(0xFFFFFFFF).withValues(alpha: 0.18),
                        ),
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: ((widget.progress ?? 0) / 100).clamp(
                            0.0,
                            1.0,
                          ),
                          child: const ColoredBox(color: Color(0xFFFFFFFF)),
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

class _WeatherCard extends ConsumerWidget {
  const _WeatherCard({required this.weather, required this.isDay});

  final WeatherData? weather;
  final bool isDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final onGlass = DesktopPalette.onStage;
    final data = weather;
    final time = DateFormat.Hm(
      Localizations.localeOf(context).toString(),
    ).format(DesktopHomePage.clock());

    Widget body;
    if (data == null) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppLoading(),
          const SizedBox(height: 8),
          Text(
            l10n.desktopWeatherReading,
            style: DesktopType.caption(onGlass.withValues(alpha: 0.75)),
          ),
        ],
      );
    } else if (data.status != 'OK') {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(DesktopIcons.cloud, size: 22, color: onGlass),
          const SizedBox(height: 8),
          Text(
            l10n.desktopWeatherUnavailable,
            style: DesktopType.denseStrong(onGlass),
          ),
          const SizedBox(height: 8),
          DesktopButton(
            label: l10n.desktopWeatherRefresh,
            icon: DesktopIcons.retry,
            variant: DesktopButtonVariant.glass,
            onPressed: () => ref.invalidate(realtimeWeatherProvider),
          ),
        ],
      );
    } else {
      final live = !data.isDegraded;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(time, style: DesktopType.display(onGlass)),
                    const SizedBox(height: 4),
                    Text(
                      '${data.locationName} · ${data.text}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesktopType.caption(
                        onGlass.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
              Text('${data.temp}°', style: DesktopType.displaySm(onGlass)),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: onGlass.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(
                  isDay ? DesktopIcons.sun : DesktopIcons.moon,
                  size: 26,
                  color: onGlass,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.desktopWeatherHighLow(data.tempMax, data.tempMin),
                        style: DesktopType.denseStrong(onGlass),
                      ),
                      Text(
                        l10n.desktopWeatherFeels(data.feelsLike),
                        style: DesktopType.caption(
                          onGlass.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(DesktopIcons.wind, size: 14, color: onGlass),
              const SizedBox(width: 5),
              Text(
                l10n.desktopWeatherWind(data.windSpeed),
                style: DesktopType.caption(onGlass.withValues(alpha: 0.85)),
              ),
              const Spacer(),
              Icon(DesktopIcons.drop, size: 14, color: onGlass),
              const SizedBox(width: 5),
              Text(
                l10n.desktopWeatherHumidity(data.humidity),
                style: DesktopType.caption(onGlass.withValues(alpha: 0.85)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: onGlass.withValues(alpha: 0.16)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: live ? skin.ok : skin.warn,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    live ? l10n.desktopWeatherLive : l10n.desktopWeatherStale,
                    style: DesktopType.micro(onGlass.withValues(alpha: 0.8)),
                  ),
                ),
                DesktopIconButton(
                  icon: DesktopIcons.retry,
                  size: 24,
                  iconSize: 12,
                  color: onGlass,
                  tooltip: l10n.desktopWeatherRefresh,
                  onPressed: () => ref.invalidate(realtimeWeatherProvider),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Container(
      width: 270,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: onGlass.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: onGlass.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 50,
            offset: const Offset(0, 20),
            spreadRadius: -20,
          ),
        ],
      ),
      child: body,
    );
  }
}
