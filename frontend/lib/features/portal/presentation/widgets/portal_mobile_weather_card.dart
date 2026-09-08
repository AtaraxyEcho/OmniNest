part of 'portal_mobile_shell.dart';

// ─── 天气卡片 ────────────────────────────────────────────────────────────────

class _WeatherCard extends ConsumerStatefulWidget {
  const _WeatherCard();

  @override
  ConsumerState<_WeatherCard> createState() => _WeatherCardState();
}

class _WeatherCardState extends ConsumerState<_WeatherCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  bool _animationsDisabled = false;
  double _elapsed = 0;
  DateTime? _lastTick;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );
    _animCtrl.addListener(_tick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animationsDisabled =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_animationsDisabled) {
      _animCtrl.stop();
      _animCtrl.value = 0;
      _elapsed = 0;
      _lastTick = null;
      return;
    }
    if (!_animCtrl.isAnimating) {
      _animCtrl.repeat(reverse: false);
    }
  }

  void _tick() {
    if (_animationsDisabled) {
      return;
    }
    final now = DateTime.now();
    if (_lastTick != null) {
      _elapsed += now.difference(_lastTick!).inMicroseconds / 1e6;
    }
    _lastTick = now;
  }

  @override
  void dispose() {
    _animCtrl.removeListener(_tick);
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final weatherAsync = ref.watch(realtimeWeatherProvider);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: weatherAsync.whenOrNull(
          data:
              (weather) =>
                  () => showWeatherDetailDialog(context, weather: weather),
        ),
        child: ClipRect(
          child: Stack(
            children: [
              // 粒子背景层
              if (weatherAsync.hasValue)
                Positioned.fill(
                  child:
                      _animationsDisabled
                          ? CustomPaint(
                            painter: _CardParticlePainter(
                              weather: weatherAsync.value!,
                              elapsed: 0,
                            ),
                          )
                          : AnimatedBuilder(
                            animation: _animCtrl,
                            builder:
                                (_, _) => CustomPaint(
                                  painter: _CardParticlePainter(
                                    weather: weatherAsync.value!,
                                    elapsed: _elapsed,
                                  ),
                                ),
                          ),
                ),
              // 内容层
              Padding(
                padding: const EdgeInsets.all(12),
                child: weatherAsync.when(
                  data: (weather) => _WeatherContent(weather: weather),
                  loading: () => const _WeatherLoading(),
                  error:
                      (_, _) => _WeatherError(
                        onRetry:
                            () => unawaited(
                              ref
                                  .read(portalDashboardActionsProvider)
                                  .retry(PortalDashboardSection.weather),
                            ),
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

class _WeatherContent extends StatelessWidget {
  const _WeatherContent({required this.weather});

  final WeatherData weather;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final detailIconSize = (screenWidth * 0.035).clamp(12.0, 16.0);

    final aqiColor = weather.aqiColorValue;

    final scheme = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.labelSmall;
    final detailColor = scheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              weather.weatherIcon,
              style: const TextStyle(fontSize: AppTypography.titleLarge),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.portalWeatherTitle,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    weather.updateTime.isNotEmpty
                        ? l10n.portalWeatherUpdated
                        : l10n.portalWeatherDisconnected,
                    style: labelStyle?.copyWith(color: detailColor),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${weather.temp}°',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  l10n.portalWeatherFeelsLike(weather.text, weather.feelsLike),
                  style: labelStyle?.copyWith(color: detailColor),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: aqiColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.air, size: detailIconSize, color: aqiColor),
              const SizedBox(width: 6),
              Text(
                'AQI ${weather.aqi} · PM2.5 ${weather.pm2p5} · ${weather.aqiCategory}',
                style: TextStyle(
                  fontSize: AppTypography.bodySmall,
                  color: aqiColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _WeatherDetail(
              icon: Icons.water_drop_outlined,
              label: weather.humidity,
              iconSize: detailIconSize,
            ),
            const SizedBox(width: 16),
            _WeatherDetail(
              icon: Icons.air,
              label: '${weather.windSpeed} ${weather.windDir}',
              iconSize: detailIconSize,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(
              Icons.wb_twilight,
              size: detailIconSize,
              color: scheme.tertiary,
            ),
            const SizedBox(width: 4),
            Text(l10n.portalWeatherSunrise(weather.sunrise), style: labelStyle),
            const SizedBox(width: 16),
            Icon(
              Icons.nightlight_round,
              size: detailIconSize,
              color: scheme.primary,
            ),
            const SizedBox(width: 4),
            Text(l10n.portalWeatherSunset(weather.sunset), style: labelStyle),
          ],
        ),
      ],
    );
  }
}

class _WeatherLoading extends StatelessWidget {
  const _WeatherLoading();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.wb_sunny_outlined,
              size: 18,
              color: Theme.of(context).colorScheme.tertiary,
            ),
            const SizedBox(width: 8),
            Text(
              l10n.portalWeatherTitle,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ],
    );
  }
}

class _WeatherError extends StatelessWidget {
  const _WeatherError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.wb_sunny_outlined, size: 18, color: scheme.tertiary),
            const SizedBox(width: 8),
            Text(
              l10n.portalWeatherTitle,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          l10n.portalWeatherConfigApiKey,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(onPressed: onRetry, child: Text(l10n.coreRetry)),
        ),
      ],
    );
  }
}

class _WeatherDetail extends StatelessWidget {
  const _WeatherDetail({
    required this.icon,
    required this.label,
    required this.iconSize,
  });

  final IconData icon;
  final String label;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: iconSize,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

// ─── 本周统计卡片（数字计数动画）──────────────────────────────────────────────
