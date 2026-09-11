part of 'weather_detail_dialog.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// 提示文案
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
// 玻璃卡片与指标
// ═══════════════════════════════════════════════════════════════════════════════

/// 样例中的 GlassCard：半透明白底 + 描边 + 模糊。
class _GlassCard extends StatelessWidget {
  const _GlassCard({
    required this.child,
    required this.radius,
    this.padding,
    this.tint,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius - 8),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tint ?? Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(radius - 8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
        ),
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.45)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: AppTypography.labelSmall,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.45),
                    letterSpacing: 0.4,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: AppTypography.titleMedium,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    height: 1.0,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (trailing != null) ...[const SizedBox(height: 8), trailing!],
        ],
      ),
    );
  }
}

/// UV 色带，对齐样例 UvBar。
Widget _buildUvBar(int value) {
  const maxUv = 11;
  final pct = (value / maxUv).clamp(0.0, 1.0);
  final color = switch (value) {
    <= 2 => const Color(0xFF4ADE80),
    <= 5 => const Color(0xFFFACC15),
    <= 7 => const Color(0xFFFB923C),
    _ => const Color(0xFFEF4444),
  };
  return SizedBox(
    height: 6,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Stack(
        children: [
          ColoredBox(color: Colors.white.withValues(alpha: 0.15)),
          FractionallySizedBox(
            widthFactor: pct,
            child: ColoredBox(color: color),
          ),
        ],
      ),
    ),
  );
}

class _SplitMoment extends StatelessWidget {
  const _SplitMoment({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 22, color: Colors.white.withValues(alpha: 0.9)),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: AppTypography.labelSmall,
              color: Colors.white.withValues(alpha: 0.40),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: AppTypography.titleMedium,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

Widget _vDivider() => ColoredBox(
  color: Colors.white.withValues(alpha: 0.10),
  child: const SizedBox(width: 1, height: double.infinity),
);

Widget _hDivider() => Divider(
  height: 1,
  thickness: 1,
  color: Colors.white.withValues(alpha: 0.10),
);
