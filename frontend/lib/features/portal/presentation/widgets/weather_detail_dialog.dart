import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/portal/application/weather_provider.dart';
import 'package:omninest/features/portal/presentation/widgets/portal_weather_profile.dart';

part 'weather_detail_atmospheres.dart';
part 'weather_detail_painters.dart';

/// 天气详情弹窗 — 沉浸式天气场景，粒子与 UI 卡片交互
Future<void> showWeatherDetailDialog(
  BuildContext context, {
  required WeatherData weather,
}) {
  return showDialog(
    context: context,
    barrierColor: Colors.black54,
    builder: (_) => _WeatherDetailDialog(weather: weather),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// 提示卡片逻辑
// ═══════════════════════════════════════════════════════════════════════════════

class _TipData {
  const _TipData(this.icon, this.text);
  final IconData icon;
  final String text;
}

_TipData? _resolveTip(WeatherData w, AppLocalizations l10n) {
  if (w.aqi > 100) {
    return _TipData(Icons.masks_outlined, l10n.portalWeatherTipMask);
  }
  final code = int.tryParse(w.icon) ?? 999;
  if (code >= 300 && code < 400) {
    return _TipData(Icons.umbrella_outlined, l10n.portalWeatherTipRain);
  }
  if (code >= 400 && code < 500) {
    return _TipData(Icons.ac_unit_outlined, l10n.portalWeatherTipIce);
  }
  if (w.uvIndex >= 6) {
    return _TipData(Icons.wb_sunny_outlined, l10n.portalWeatherTipUV);
  }
  if (w.feelsLike <= 5) {
    return _TipData(Icons.checkroom_outlined, l10n.portalWeatherTipCold);
  }
  if (w.feelsLike >= 35) {
    return _TipData(Icons.local_drink_outlined, l10n.portalWeatherTipHot);
  }
  if (code >= 500) {
    return _TipData(Icons.directions_car_outlined, l10n.portalWeatherTipFog);
  }
  return _TipData(
    Icons.sentiment_satisfied_outlined,
    l10n.portalWeatherTipNice,
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

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.sizeOf(context);
    final desktop = mq.width >= 900;
    final horizontalInset = desktop ? 32.0 : 16.0;
    final verticalInset = desktop ? 28.0 : 24.0;
    final availableWidth = math.max(280.0, mq.width - horizontalInset * 2);
    final availableHeight = math.max(360.0, mq.height - verticalInset * 2);
    final w =
        desktop
            ? math.min(1320.0, availableWidth)
            : math.min(520.0, availableWidth);
    final h =
        desktop
            ? math.min(860.0, availableHeight)
            : math.min(680.0, availableHeight);

    final spec = WeatherSceneSpec.from(widget.weather);
    final profile = spec.profile;
    final atm = _Atmosphere.forScene(spec.scene, profile);
    final effectsReady = _effectsReady && !_animationsDisabled;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: horizontalInset,
        vertical: verticalInset,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: w,
          height: h,
          child: Stack(
            children: [
              // [0] 氛围渐变
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
              // 内容层保持独立，天气效果不会参与交互命中测试。
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        atm.bottom.withValues(alpha: 0.5),
                        atm.bottom.withValues(alpha: 0.85),
                      ],
                      stops: const [0.0, 0.35, 0.65],
                    ),
                  ),
                  child: SingleChildScrollView(
                    padding:
                        desktop
                            ? const EdgeInsets.fromLTRB(28, 22, 28, 28)
                            : const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    child:
                        desktop
                            ? _buildDesktopContent(context, atm)
                            : _buildMobileContent(context, atm),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── 关闭按钮 ──────────────────────────────────────────────────────────

  Widget _buildMobileContent(BuildContext context, _Atmosphere atm) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCloseButton(atm),
        _buildSummary(context, atm),
        const SizedBox(height: 16),
        _buildTipCard(atm),
        const SizedBox(height: 16),
        _buildAqiCard(),
        const SizedBox(height: 20),
        _buildGrid(atm),
        const SizedBox(height: 20),
        _buildSunRow(atm),
      ],
    );
  }

  Widget _buildDesktopContent(BuildContext context, _Atmosphere atm) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCloseButton(atm),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 4,
              child: Container(
                constraints: const BoxConstraints(minHeight: 214),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 28,
                ),
                decoration: BoxDecoration(
                  color: atm.panelBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: _buildSummary(context, atm, desktop: true),
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              flex: 7,
              child: Column(
                children: [
                  _buildTipCard(atm),
                  const SizedBox(height: 14),
                  _buildAqiCard(),
                  const SizedBox(height: 14),
                  _buildSunRow(atm),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _buildGrid(atm, desktop: true),
      ],
    );
  }

  Widget _buildCloseButton(_Atmosphere atm) => Align(
    alignment: Alignment.topRight,
    child: IconButton(
      onPressed: () => Navigator.of(context).pop(),
      icon: Icon(Icons.close_rounded, color: atm.textColor),
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
  );

  // ─── 温度摘要（无 emoji）──────────────────────────────────────────────

  Widget _buildSummary(
    BuildContext ctx,
    _Atmosphere atm, {
    bool desktop = false,
  }) {
    final w = widget.weather;
    final hasRange = w.tempMax != 0 && w.tempMin != 0;
    return Center(
      child: Column(
        children: [
          Text(
            '${w.temp}°',
            style: (desktop
                    ? Theme.of(ctx).textTheme.displayLarge
                    : Theme.of(ctx).textTheme.displaySmall)
                ?.copyWith(fontWeight: FontWeight.w800, color: atm.textColor),
          ),
          if (hasRange)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${w.tempMax}° / ${w.tempMin}°',
                style: TextStyle(
                  fontSize: AppTypography.bodyLarge,
                  color: atm.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          const SizedBox(height: 4),
          Text(
            AppLocalizations.of(
              ctx,
            ).portalWeatherFeelsLike(w.text, w.feelsLike),
            style: Theme.of(
              ctx,
            ).textTheme.bodyLarge?.copyWith(color: atm.textSecondary),
          ),
        ],
      ),
    );
  }

  // ─── 温馨提示卡片 ─────────────────────────────────────────────────────

  Widget _buildTipCard(_Atmosphere atm) {
    final l10n = AppLocalizations.of(context);
    final tip = _resolveTip(widget.weather, l10n);
    if (tip == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
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
          // 如果有后端健康建议，显示在右侧
          if (widget.weather.healthAdvice.isNotEmpty)
            Tooltip(
              message: widget.weather.healthAdvice,
              child: Icon(
                Icons.info_outline,
                color: atm.textSecondary,
                size: 16,
              ),
            ),
        ],
      ),
    );
  }

  // ─── AQI 卡片 ─────────────────────────────────────────────────────────

  Widget _buildAqiCard() {
    final c = widget.weather.aqiColorValue;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
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
                Text(
                  'PM2.5 ${widget.weather.pm2p5} μg/m³',
                  style: TextStyle(
                    color: c.withValues(alpha: 0.8),
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

  // ─── 参数网格（居中 GridView + 建议）─────────────────────────────────

  Widget _buildGrid(_Atmosphere atm, {bool desktop = false}) {
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
      if (w.healthAdvice.isNotEmpty)
        _DetailItem(
          icon: Icons.medical_information_outlined,
          label: l10n.portalWeatherAdvice,
          value: widget.weather.healthAdvice,
        ),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: atm.panelBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: GridView.count(
        crossAxisCount: desktop ? 4 : 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: desktop ? 18 : 14,
        crossAxisSpacing: desktop ? 18 : 20,
        childAspectRatio: desktop ? 2.35 : 2.2,
        children:
            items
                .map(
                  (item) => Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(item.icon, size: 16, color: atm.textSecondary),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              item.label,
                              style: TextStyle(
                                fontSize: AppTypography.labelSmall,
                                color: atm.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.value,
                        style: TextStyle(
                          fontSize: AppTypography.bodyLarge,
                          fontWeight: FontWeight.w600,
                          color: atm.textColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ),
                )
                .toList(),
      ),
    );
  }

  // ─── 全天概览（日/夜天气 + 日出日落）────────────────────────────────

  Widget _buildSunRow(_Atmosphere atm) {
    final l10n = AppLocalizations.of(context);
    final w = widget.weather;
    final hasDayNight = w.textDay != '--' || w.textNight != '--';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: atm.panelBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          // 日间
          Expanded(
            child: Column(
              children: [
                Icon(Icons.wb_sunny_outlined, color: atm.textColor, size: 20),
                const SizedBox(height: 4),
                Text(
                  hasDayNight ? w.textDay : l10n.portalWeatherSunriseLabel,
                  style: TextStyle(
                    fontSize: AppTypography.bodySmall,
                    color: atm.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
                Text(
                  hasDayNight ? '${w.tempMax}°' : w.sunrise,
                  style: TextStyle(
                    fontSize: AppTypography.titleMedium,
                    fontWeight: FontWeight.w600,
                    color: atm.textColor,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 36,
            color: atm.textColor.withValues(alpha: 0.15),
          ),
          // 夜间
          Expanded(
            child: Column(
              children: [
                Icon(Icons.nightlight_round, color: atm.textColor, size: 20),
                const SizedBox(height: 4),
                Text(
                  hasDayNight ? w.textNight : l10n.portalWeatherSunsetLabel,
                  style: TextStyle(
                    fontSize: AppTypography.bodySmall,
                    color: atm.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
                Text(
                  hasDayNight ? '${w.tempMin}°' : w.sunset,
                  style: TextStyle(
                    fontSize: AppTypography.titleMedium,
                    fontWeight: FontWeight.w600,
                    color: atm.textColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 背景粒子 Painter
// ═══════════════════════════════════════════════════════════════════════════════

class _DetailItem {
  const _DetailItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;
}
