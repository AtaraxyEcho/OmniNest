import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/portal/application/weather_provider.dart';
import 'package:omninest/features/portal/presentation/widgets/portal_weather_profile.dart';
import 'package:omninest/features/portal/presentation/widgets/weather_detail_layout.dart';

part 'weather_detail_atmospheres.dart';
part 'weather_detail_painters.dart';
part 'weather_detail_widgets.dart';

/// 打开沉浸式天气详情弹窗。
Future<void> showWeatherDetailDialog(
  BuildContext context, {
  required WeatherData weather,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (_) => _WeatherDetailDialog(weather: weather),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// 弹窗主体
// ═══════════════════════════════════════════════════════════════════════════════

class _WeatherDetailDialog extends StatefulWidget {
  const _WeatherDetailDialog({required this.weather});
  final WeatherData weather;

  @override
  State<_WeatherDetailDialog> createState() => _WeatherDetailDialogState();
}

class _WeatherDetailDialogState extends State<_WeatherDetailDialog>
    with SingleTickerProviderStateMixin {
  static const _effectsWarmUpDelay = Duration(milliseconds: 160);

  late final AnimationController _animCtrl;
  bool _animationsDisabled = false;
  bool _effectsReady = false;
  bool _effectsScheduled = false;
  double _elapsedSeconds = 0;
  DateTime? _lastTick;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );
    _animCtrl.addListener(_trackElapsed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animationsDisabled =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_animationsDisabled) {
      _effectsReady = false;
      _effectsScheduled = false;
      _syncAnimationController();
      return;
    }
    _scheduleEffectsWarmUp();
    _syncAnimationController();
  }

  void _scheduleEffectsWarmUp() {
    if (_effectsReady || _effectsScheduled) {
      return;
    }
    _effectsScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(
        Future<void>.delayed(_effectsWarmUpDelay, () {
          if (!mounted || _animationsDisabled) {
            return;
          }
          setState(() {
            _effectsReady = true;
            _elapsedSeconds = 0;
            _lastTick = null;
          });
          _syncAnimationController();
        }),
      );
    });
  }

  void _syncAnimationController() {
    final shouldAnimate = _effectsReady && !_animationsDisabled;
    if (shouldAnimate) {
      if (!_animCtrl.isAnimating) {
        _animCtrl.repeat(reverse: false);
      }
      return;
    }
    _animCtrl.stop();
    _animCtrl.value = 0;
    _elapsedSeconds = 0;
    _lastTick = null;
  }

  void _trackElapsed() {
    if (_animationsDisabled) {
      return;
    }
    final now = DateTime.now();
    if (_lastTick != null) {
      _elapsedSeconds += now.difference(_lastTick!).inMicroseconds / 1e6;
    }
    _lastTick = now;
  }

  @override
  void dispose() {
    _animCtrl.removeListener(_trackElapsed);
    _animCtrl.dispose();
    super.dispose();
  }

  void _close() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final metrics = WeatherDetailLayoutMetrics.resolve(viewport);
    final spec = WeatherSceneSpec.from(widget.weather);
    final profile = spec.profile;
    final atm = _Atmosphere.forScene(spec.scene, profile);
    final effectsReady = _effectsReady && !_animationsDisabled;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: metrics.insetPadding,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: metrics.dialogWidth,
        height: metrics.dialogHeight,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(metrics.cornerRadius),
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [atm.top, atm.mid, atm.bottom],
                    ),
                  ),
                ),
              ),
              // 背景粒子在首帧后延迟启动，避免弹窗点击路径阻塞。
              if (effectsReady)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _animCtrl,
                      builder:
                          (_, _) => CustomPaint(
                            key: const ValueKey('weather-scene-effects'),
                            painter: _WeatherScenePainter(
                              spec: spec,
                              elapsed: _elapsedSeconds,
                              particleColor: atm.particleColor,
                            ),
                          ),
                    ),
                  ),
                ),
              // 内容层与关闭按钮分层，天气效果不参与命中测试。
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        atm.bottom.withValues(alpha: 0.45),
                        atm.bottom.withValues(alpha: 0.88),
                      ],
                      stops: const [0.0, 0.4, 0.72],
                    ),
                  ),
                  child: SingleChildScrollView(
                    padding: metrics.contentPadding,
                    child: _buildBody(context, atm, metrics),
                  ),
                ),
              ),
              Positioned(
                top: metrics.isMobile ? 6 : 10,
                right: metrics.isMobile ? 6 : 10,
                child: _buildCloseButton(atm, metrics),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    _Atmosphere atm,
    WeatherDetailLayoutMetrics metrics,
  ) {
    if (metrics.useTwoColumn) {
      return _buildTwoColumnBody(context, atm, metrics);
    }
    return _buildStackedBody(context, atm, metrics);
  }

  // ─── 布局：单列（手机 / 窄平板 / 矮窗口）──────────────────────────────

  Widget _buildStackedBody(
    BuildContext context,
    _Atmosphere atm,
    WeatherDetailLayoutMetrics metrics,
  ) {
    final gap = SizedBox(height: metrics.sectionGap);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 关闭按钮悬浮层外的顶部留白。
        SizedBox(height: metrics.closeButtonSize * 0.55),
        _buildHeroPanel(context, atm, metrics, panelized: !metrics.isMobile),
        gap,
        _buildTipCard(atm, metrics),
        gap,
        _buildAqiCard(metrics),
        gap,
        _buildAdviceCard(atm, metrics),
        gap,
        _buildDayNightCard(atm, metrics),
        gap,
        _buildSunCard(atm, metrics),
        gap,
        _buildMetricsGrid(atm, metrics),
      ],
    );
  }

  // ─── 布局：双列（平板 / 桌面 / 宽屏）──────────────────────────────────

  Widget _buildTwoColumnBody(
    BuildContext context,
    _Atmosphere atm,
    WeatherDetailLayoutMetrics metrics,
  ) {
    final gap = SizedBox(height: metrics.sectionGap);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: metrics.closeButtonSize * 0.55),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: metrics.heroFlex,
              child: _buildHeroPanel(context, atm, metrics, panelized: true),
            ),
            SizedBox(width: metrics.sectionGap),
            Expanded(
              flex: metrics.sideFlex,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTipCard(atm, metrics),
                  gap,
                  _buildAqiCard(metrics),
                  gap,
                  _buildAdviceCard(atm, metrics),
                  gap,
                  _buildDayNightCard(atm, metrics),
                  gap,
                  _buildSunCard(atm, metrics),
                ],
              ),
            ),
          ],
        ),
        gap,
        _buildMetricsGrid(atm, metrics),
      ],
    );
  }

  // ─── 组件 ──────────────────────────────────────────────────────────────

  Widget _buildCloseButton(
    _Atmosphere atm,
    WeatherDetailLayoutMetrics metrics,
  ) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: l10n.coreClose,
      child: Tooltip(
        message: l10n.coreClose,
        child: IconButton(
          onPressed: _close,
          iconSize: metrics.closeButtonSize * 0.5,
          constraints: BoxConstraints.tightFor(
            width: metrics.closeButtonSize,
            height: metrics.closeButtonSize,
          ),
          padding: EdgeInsets.zero,
          icon: Icon(Icons.close_rounded, color: atm.textColor),
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroPanel(
    BuildContext context,
    _Atmosphere atm,
    WeatherDetailLayoutMetrics metrics, {
    required bool panelized,
  }) {
    final child = _buildSummary(context, atm, metrics);
    if (!panelized) {
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 8,
          vertical: metrics.sectionGap / 2,
        ),
        child: child,
      );
    }
    return Container(
      constraints: BoxConstraints(minHeight: metrics.heroMinHeight),
      padding: metrics.heroPanelPadding,
      decoration: BoxDecoration(
        color: atm.panelBg,
        borderRadius: BorderRadius.circular(metrics.cornerRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: child,
    );
  }

  Widget _buildSummary(
    BuildContext context,
    _Atmosphere atm,
    WeatherDetailLayoutMetrics metrics,
  ) {
    final w = widget.weather;
    final hasRange = w.tempMax != 0 || w.tempMin != 0;
    final scaler = MediaQuery.textScalerOf(context);
    final tempStyle = TextStyle(
      fontSize: metrics.scaledTempSize(scaler),
      height: 1.0,
      fontWeight: FontWeight.w800,
      color: atm.textColor,
      letterSpacing: -1.2,
    );

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${w.temp}°', style: tempStyle),
          if (hasRange)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${w.tempMax}° / ${w.tempMin}°',
                style: TextStyle(
                  fontSize: AppTypography.bodyLarge,
                  color: atm.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            AppLocalizations.of(
              context,
            ).portalWeatherFeelsLike(w.text, w.feelsLike),
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: atm.textSecondary),
            textAlign: TextAlign.center,
          ),
          if (w.updateTime.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              w.updateTime,
              style: TextStyle(
                fontSize: AppTypography.bodySmall,
                color: atm.textSecondary.withValues(alpha: 0.85),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTipCard(_Atmosphere atm, WeatherDetailLayoutMetrics metrics) {
    final l10n = AppLocalizations.of(context);
    final tip = _resolveTip(widget.weather, l10n);
    if (tip == null) {
      return const SizedBox.shrink();
    }

    return _Panel(
      padding: metrics.cardPadding,
      radius: metrics.cornerRadius,
      background: Colors.white.withValues(alpha: 0.18),
      borderColor: Colors.white.withValues(alpha: 0.12),
      child: Row(
        children: [
          Icon(tip.icon, color: atm.textColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tip.text,
              style: TextStyle(
                fontSize: AppTypography.bodyMedium,
                color: atm.textColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdviceCard(_Atmosphere atm, WeatherDetailLayoutMetrics metrics) {
    final advice = widget.weather.healthAdvice;
    if (advice.isEmpty) {
      return const SizedBox.shrink();
    }
    return _Panel(
      padding: metrics.cardPadding,
      radius: metrics.cornerRadius,
      background: Colors.white.withValues(alpha: 0.12),
      borderColor: Colors.white.withValues(alpha: 0.08),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.medical_information_outlined,
            color: atm.textColor,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              advice,
              style: TextStyle(
                fontSize: AppTypography.bodySmall,
                color: atm.textColor,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAqiCard(WeatherDetailLayoutMetrics metrics) {
    final c = widget.weather.aqiColorValue;
    return _Panel(
      padding: metrics.cardPadding,
      radius: metrics.cornerRadius,
      background: c.withValues(alpha: 0.16),
      child: Row(
        children: [
          Icon(Icons.air, color: c, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AQI ${widget.weather.aqi} · ${widget.weather.aqiCategory}',
                  style: TextStyle(
                    color: c,
                    fontWeight: FontWeight.w700,
                    fontSize: AppTypography.bodyLarge,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'PM2.5 ${widget.weather.pm2p5} μg/m³',
                  style: TextStyle(
                    color: c.withValues(alpha: 0.85),
                    fontSize: AppTypography.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayNightCard(
    _Atmosphere atm,
    WeatherDetailLayoutMetrics metrics,
  ) {
    final l10n = AppLocalizations.of(context);
    final w = widget.weather;
    final hasDayNight = w.textDay != '--' || w.textNight != '--';
    if (!hasDayNight) {
      return const SizedBox.shrink();
    }

    return _Panel(
      padding: metrics.cardPadding,
      radius: metrics.cornerRadius,
      background: atm.panelBg,
      borderColor: Colors.white.withValues(alpha: 0.08),
      child: Row(
        children: [
          Expanded(
            child: _SunMoment(
              icon: Icons.wb_sunny_outlined,
              label:
                  w.textDay == '--'
                      ? l10n.portalWeatherSunriseLabel
                      : w.textDay,
              value: w.tempMax != 0 ? '${w.tempMax}°' : '--',
              color: atm.textColor,
              secondary: atm.textSecondary,
            ),
          ),
          Container(
            width: 1,
            height: metrics.compactHeight ? 40 : 48,
            color: atm.textColor.withValues(alpha: 0.15),
          ),
          Expanded(
            child: _SunMoment(
              icon: Icons.nightlight_round,
              label:
                  w.textNight == '--'
                      ? l10n.portalWeatherSunsetLabel
                      : w.textNight,
              value: w.tempMin != 0 ? '${w.tempMin}°' : '--',
              color: atm.textColor,
              secondary: atm.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSunCard(_Atmosphere atm, WeatherDetailLayoutMetrics metrics) {
    final l10n = AppLocalizations.of(context);
    final w = widget.weather;
    final hasSun = w.sunrise != '--' || w.sunset != '--';

    return _Panel(
      padding: metrics.cardPadding,
      radius: metrics.cornerRadius,
      background: atm.panelBg,
      borderColor: Colors.white.withValues(alpha: 0.08),
      child: Row(
        children: [
          Expanded(
            child: _SunMoment(
              icon: Icons.wb_twilight,
              label: l10n.portalWeatherSunriseLabel,
              value: hasSun ? w.sunrise : '--',
              color: atm.textColor,
              secondary: atm.textSecondary,
            ),
          ),
          Container(
            width: 1,
            height: metrics.compactHeight ? 36 : 44,
            color: atm.textColor.withValues(alpha: 0.15),
          ),
          Expanded(
            child: _SunMoment(
              icon: Icons.nightlight_round,
              label: l10n.portalWeatherSunsetLabel,
              value: hasSun ? w.sunset : '--',
              color: atm.textColor,
              secondary: atm.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // ─── 参数网格 ─────────────────────────────────────────────────────────

  Widget _buildMetricsGrid(
    _Atmosphere atm,
    WeatherDetailLayoutMetrics metrics,
  ) {
    final l10n = AppLocalizations.of(context);
    final w = widget.weather;
    final windText =
        w.windScale != '--'
            ? '${w.windScale} ${w.windDir}'
            : '${w.windSpeed} ${w.windDir}';
    final items = [
      _DetailItem(
        icon: Icons.water_drop_outlined,
        label: l10n.portalWeatherHumidity,
        value: w.humidity,
      ),
      _DetailItem(
        icon: Icons.air,
        label: l10n.portalWeatherWind,
        value: windText,
      ),
      _DetailItem(
        icon: Icons.visibility_outlined,
        label: l10n.portalWeatherVisibility,
        value: w.visibility,
      ),
      _DetailItem(
        icon: Icons.compress,
        label: l10n.portalWeatherPressure,
        value: w.pressure,
      ),
      _DetailItem(
        icon: Icons.wb_sunny_outlined,
        label: l10n.portalWeatherUV,
        value: 'UV ${w.uvIndex}',
      ),
      _DetailItem(
        icon: Icons.water_outlined,
        label: l10n.portalWeatherPrecip,
        value: w.precip,
      ),
    ];

    return _Panel(
      padding: EdgeInsets.all(metrics.compactHeight ? 12 : 14),
      radius: metrics.cornerRadius,
      background: atm.panelBg,
      borderColor: Colors.white.withValues(alpha: 0.08),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = metrics.gridColumns;
          final aspect = metrics.gridChildAspectRatio;
          final tileWidth =
              (constraints.maxWidth - (columns - 1) * 12) / columns;
          final tileHeight = math.max(56.0, tileWidth / aspect);
          return Wrap(
            spacing: 12,
            runSpacing: metrics.compactHeight ? 12 : 16,
            children: [
              for (final item in items)
                SizedBox(
                  width: tileWidth,
                  height: tileHeight,
                  child: _MetricCell(item: item, atm: atm),
                ),
            ],
          );
        },
      ),
    );
  }
}
