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
// 玻璃卡片
// ═══════════════════════════════════════════════════════════════════════════════

/// 样例 GlassCard：rounded-2xl + white/10 + blur。
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
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tint ?? Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
        ),
      ),
    );
  }
}

/// 样例 MetricItem：p-4，标签 xs，数值 xl。
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: Colors.white.withValues(alpha: 0.45)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: AppTypography.labelSmall,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: AppTypography.titleMedium,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              height: 1.05,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          if (trailing != null) ...[const SizedBox(height: 8), trailing!],
        ],
      ),
    );
  }
}

/// 样例 UvBar。
Widget _buildUvBar(int value) {
  final pct = (value / 11).clamp(0.0, 1.0);
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
        fit: StackFit.expand,
        children: [
          ColoredBox(color: Colors.white.withValues(alpha: 0.15)),
          FractionallySizedBox(
            widthFactor: pct,
            alignment: Alignment.centerLeft,
            child: ColoredBox(color: color),
          ),
        ],
      ),
    ),
  );
}

/// 样例昼夜/日出单元：py-4 px-3，图标 2xl，数值 xl/base。
class _SplitMoment extends StatelessWidget {
  const _SplitMoment({
    required this.icon,
    required this.label,
    required this.value,
    this.valueSize = AppTypography.titleMedium,
  });

  final IconData icon;
  final String label;
  final String value;
  final double valueSize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 24, color: Colors.white.withValues(alpha: 0.92)),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: AppTypography.bodySmall,
              color: Colors.white.withValues(alpha: 0.40),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: valueSize,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

Widget _vDivider() => SizedBox(
  width: 1,
  child: ColoredBox(color: Colors.white.withValues(alpha: 0.10)),
);

Widget _hDivider() => Divider(
  height: 1,
  thickness: 1,
  color: Colors.white.withValues(alpha: 0.08),
);

/// 样例预报分段控件。
class _ForecastTab extends StatelessWidget {
  const _ForecastTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color:
          selected ? Colors.white.withValues(alpha: 0.20) : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: AppTypography.bodySmall,
              fontWeight: FontWeight.w600,
              color:
                  selected
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.40),
            ),
          ),
        ),
      ),
    );
  }
}
