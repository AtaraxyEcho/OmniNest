import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/portal/application/weather_provider.dart';
import 'package:omninest/features/portal/presentation/widgets/portal_weather_profile.dart';
import 'package:omninest/features/portal/presentation/widgets/weather_detail_layout.dart';

part 'weather_detail_atmospheres.dart';
part 'weather_detail_painters.dart';
part 'weather_detail_widgets.dart';

/// 打开天气详情弹窗（玻璃拟态面板，对齐 Redesign Weather Detail UI 样例）。
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
    final atm = _Atmosphere.forScene(spec.scene, spec.profile);
    final effectsReady = _effectsReady && !_animationsDisabled;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: metrics.insetPadding,
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxW =
              constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : metrics.dialogWidth;
          final maxH =
              constraints.maxHeight.isFinite
                  ? constraints.maxHeight
                  : metrics.dialogHeight;
          final width = math.min(metrics.dialogWidth, maxW);
          final height = math.min(metrics.dialogHeight, maxH);

          return SizedBox(
            width: width,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: height),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(metrics.cornerRadius),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [atm.top, atm.mid, atm.bottom],
                    ),
                  ),
                  // 内容高度贴合，仅在超高时滚动，避免下方大段空白。
                  child: Stack(
                    children: [
                      if (effectsReady)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: AnimatedBuilder(
                              animation: _animCtrl,
                              builder:
                                  (_, _) => CustomPaint(
                                    key: const ValueKey(
                                      'weather-scene-effects',
                                    ),
                                    painter: _WeatherScenePainter(
                                      spec: spec,
                                      elapsed: _elapsedSeconds,
                                      particleColor: atm.particleColor,
                                    ),
                                  ),
                            ),
                          ),
                        ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0x8C0F2027),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                          borderRadius: BorderRadius.circular(
                            metrics.cornerRadius,
                          ),
                        ),
                        child: _buildPanel(context, metrics),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPanel(BuildContext context, WeatherDetailLayoutMetrics metrics) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHeader(context, metrics),
        Flexible(
          child: SingleChildScrollView(
            padding: metrics.contentPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeroSection(context, metrics),
                SizedBox(height: metrics.sectionGap),
                _buildAqiStrip(metrics),
                SizedBox(height: metrics.sectionGap),
                _buildMetricsCard(metrics),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─── 顶栏：提示 + 更新时间 + 关闭 ──────────────────────────────────────

  Widget _buildHeader(
    BuildContext context,
    WeatherDetailLayoutMetrics metrics,
  ) {
    final l10n = AppLocalizations.of(context);
    final w = widget.weather;
    final tip = _resolveTip(w, l10n);
    final updated =
        w.updateTime.isNotEmpty ? _formatUpdateTime(w.updateTime) : '';

    return Container(
      padding: EdgeInsets.fromLTRB(metrics.isMobile ? 14 : 18, 10, 8, 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
        ),
      ),
      child: Row(
        children: [
          if (tip != null) ...[
            Icon(
              tip.icon,
              size: 16,
              color: Colors.white.withValues(alpha: 0.70),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              tip?.text ?? w.text,
              style: TextStyle(
                fontSize: AppTypography.bodyMedium,
                color: Colors.white.withValues(alpha: 0.72),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (updated.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              updated,
              style: TextStyle(
                fontSize: AppTypography.bodySmall,
                color: Colors.white.withValues(alpha: 0.32),
              ),
            ),
          ],
          const SizedBox(width: 4),
          Semantics(
            button: true,
            label: l10n.coreClose,
            child: Tooltip(
              message: l10n.coreClose,
              child: IconButton(
                onPressed: _close,
                constraints: BoxConstraints.tightFor(
                  width: metrics.closeButtonSize,
                  height: metrics.closeButtonSize,
                ),
                padding: EdgeInsets.zero,
                iconSize: metrics.closeButtonSize * 0.45,
                icon: Icon(
                  Icons.close_rounded,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatUpdateTime(String raw) {
    // "2026-09-11T17:45+08:00" / "2026-09-11 17:45" → "17:45"
    final tIndex = raw.indexOf('T');
    final spaceIndex = raw.indexOf(' ');
    final start =
        tIndex >= 0 ? tIndex + 1 : (spaceIndex >= 0 ? spaceIndex + 1 : -1);
    if (start < 0 || start >= raw.length) {
      return raw.length > 16 ? raw.substring(raw.length - 16) : raw;
    }
    final rest = raw.substring(start);
    final plus = rest.indexOf('+');
    final cleaned = plus >= 0 ? rest.substring(0, plus) : rest;
    if (cleaned.length >= 5) {
      return cleaned.substring(0, 5);
    }
    return cleaned;
  }

  // ─── 英雄区 ────────────────────────────────────────────────────────────

  Widget _buildHeroSection(
    BuildContext context,
    WeatherDetailLayoutMetrics metrics,
  ) {
    final left = _buildCurrentCard(context, metrics);
    final right = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildDayNightCard(metrics),
        SizedBox(height: metrics.sectionGap * 0.75),
        _buildSunCard(metrics),
      ],
    );

    if (!metrics.useHeroSplit) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [left, SizedBox(height: metrics.sectionGap), right],
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 5, child: left),
          SizedBox(width: metrics.sectionGap),
          Expanded(flex: 6, child: right),
        ],
      ),
    );
  }

  Widget _buildCurrentCard(
    BuildContext context,
    WeatherDetailLayoutMetrics metrics,
  ) {
    final w = widget.weather;
    final hasRange = w.tempMax != 0 || w.tempMin != 0;
    final scaler = MediaQuery.textScalerOf(context);
    final tempStyle = TextStyle(
      fontSize: metrics.scaledTempSize(scaler),
      fontWeight: FontWeight.w300,
      color: Colors.white,
      height: 1.0,
      letterSpacing: -1.5,
    );

    return _GlassCard(
      radius: metrics.cornerRadius,
      padding: metrics.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(w.weatherIcon, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      w.text,
                      style: TextStyle(
                        fontSize: AppTypography.bodyLarge,
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${w.temp}°', style: tempStyle),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (hasRange)
                    Text(
                      '${w.tempMax}° / ${w.tempMin}°',
                      style: TextStyle(
                        fontSize: AppTypography.bodyMedium,
                        color: Colors.white.withValues(alpha: 0.60),
                      ),
                    ),
                  if (hasRange)
                    Container(
                      width: 1,
                      height: 12,
                      color: Colors.white.withValues(alpha: 0.20),
                    ),
                  Text(
                    AppLocalizations.of(
                      context,
                    ).portalWeatherFeelsLike(w.text, w.feelsLike),
                    style: TextStyle(
                      fontSize: AppTypography.bodyMedium,
                      color: Colors.white.withValues(alpha: 0.60),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDayNightCard(WeatherDetailLayoutMetrics metrics) {
    final l10n = AppLocalizations.of(context);
    final w = widget.weather;
    final dayLabel =
        w.textDay == '--' ? l10n.portalWeatherSunriseLabel : w.textDay;
    final nightLabel =
        w.textNight == '--' ? l10n.portalWeatherSunsetLabel : w.textNight;

    return _GlassCard(
      radius: metrics.cornerRadius,
      child: Row(
        children: [
          Expanded(
            child: _SplitMoment(
              icon: Icons.wb_sunny_outlined,
              label: dayLabel,
              value: w.tempMax != 0 ? '${w.tempMax}°' : '--',
            ),
          ),
          SizedBox(
            width: 1,
            height: 44,
            child: ColoredBox(color: Colors.white.withValues(alpha: 0.10)),
          ),
          Expanded(
            child: _SplitMoment(
              icon: Icons.nightlight_round,
              label: nightLabel,
              value: w.tempMin != 0 ? '${w.tempMin}°' : '--',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSunCard(WeatherDetailLayoutMetrics metrics) {
    final l10n = AppLocalizations.of(context);
    final w = widget.weather;

    return _GlassCard(
      radius: metrics.cornerRadius,
      child: Row(
        children: [
          Expanded(
            child: _SplitMoment(
              icon: Icons.wb_twilight,
              label: l10n.portalWeatherSunriseLabel,
              value: w.sunrise,
            ),
          ),
          SizedBox(
            width: 1,
            height: 44,
            child: ColoredBox(color: Colors.white.withValues(alpha: 0.10)),
          ),
          Expanded(
            child: _SplitMoment(
              icon: Icons.nightlight_round,
              label: l10n.portalWeatherSunsetLabel,
              value: w.sunset,
            ),
          ),
        ],
      ),
    );
  }

  // ─── AQI ───────────────────────────────────────────────────────────────

  Widget _buildAqiStrip(WeatherDetailLayoutMetrics metrics) {
    final w = widget.weather;
    final accent = w.aqiColorValue;
    return _GlassCard(
      radius: metrics.cornerRadius,
      tint: accent.withValues(alpha: 0.18),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.air, color: accent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'AQI ${w.aqi} · ${w.aqiCategory} · PM2.5 ${w.pm2p5} μg/m³',
              style: TextStyle(
                fontSize: AppTypography.bodyMedium,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.92),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ─── 指标 ──────────────────────────────────────────────────────────────

  Widget _buildMetricsCard(WeatherDetailLayoutMetrics metrics) {
    final l10n = AppLocalizations.of(context);
    final w = widget.weather;
    final windText =
        w.windScale != '--'
            ? '${w.windScale} ${w.windDir}'
            : '${w.windSpeed} ${w.windDir}';

    final cells = <Widget>[
      _MetricCell(
        icon: Icons.water_drop_outlined,
        label: l10n.portalWeatherHumidity,
        value: w.humidity,
      ),
      _MetricCell(
        icon: Icons.air,
        label: l10n.portalWeatherWind,
        value: windText,
      ),
      _MetricCell(
        icon: Icons.visibility_outlined,
        label: l10n.portalWeatherVisibility,
        value: w.visibility,
      ),
      _MetricCell(
        icon: Icons.compress,
        label: l10n.portalWeatherPressure,
        value: w.pressure,
      ),
      _MetricCell(
        icon: Icons.wb_sunny_outlined,
        label: l10n.portalWeatherUV,
        value: 'UV ${w.uvIndex}',
        trailing: _buildUvBar(w.uvIndex),
      ),
      _MetricCell(
        icon: Icons.water_outlined,
        label: l10n.portalWeatherPrecip,
        value: w.precip,
      ),
    ];

    return _GlassCard(
      radius: metrics.cornerRadius,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = metrics.metricColumns;
          final rows = (cells.length / columns).ceil();
          return Column(
            children: [
              for (var r = 0; r < rows; r++) ...[
                if (r > 0) _hDivider(),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var c = 0; c < columns; c++) ...[
                        if (c > 0) _vDivider(),
                        Expanded(
                          child:
                              r * columns + c < cells.length
                                  ? cells[r * columns + c]
                                  : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
