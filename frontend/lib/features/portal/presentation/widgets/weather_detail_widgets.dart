part of 'weather_detail_dialog.dart';

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
// 共用小组件
// ═══════════════════════════════════════════════════════════════════════════════

class _Panel extends StatelessWidget {
  const _Panel({
    required this.child,
    required this.padding,
    required this.radius,
    required this.background,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color background;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radius),
        border: borderColor == null ? null : Border.all(color: borderColor!),
      ),
      child: child,
    );
  }
}

class _SunMoment extends StatelessWidget {
  const _SunMoment({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.secondary,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final Color secondary;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: AppTypography.bodySmall,
            color: secondary,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: AppTypography.titleMedium,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({required this.item, required this.atm});

  final _DetailItem item;
  final _Atmosphere atm;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
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
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

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
