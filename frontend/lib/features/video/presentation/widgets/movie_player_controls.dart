import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/video_colors.dart';
import 'package:omninest/core/utils/platform_helper.dart';

/// 播放器控制层使用的统一图标按钮。
class MoviePlayerIconButton extends StatelessWidget {
  const MoviePlayerIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size,
    this.iconSize = 24,
    this.selected = false,
    this.filled = false,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double? size;
  final double iconSize;
  final bool selected;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final colors = context.videoColors;
    final targetSize = size ?? (isMobilePlatform ? 48.0 : 44.0);
    return Tooltip(
      message: tooltip ?? '',
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: iconSize),
        constraints: BoxConstraints.tightFor(
          width: targetSize,
          height: targetSize,
        ),
        padding: EdgeInsets.zero,
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return colors.playerControlMuted.withValues(alpha: 0.38);
            }
            return selected
                ? colors.playerControlForeground
                : colors.playerControlMuted;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return colors.playerControlHover.withValues(alpha: 0.90);
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused) ||
                selected ||
                filled) {
              return colors.playerControlHover;
            }
            return Colors.transparent;
          }),
          overlayColor: WidgetStatePropertyAll(
            colors.playerControlForeground.withValues(alpha: 0.08),
          ),
          shape: const WidgetStatePropertyAll(CircleBorder()),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return BorderSide(color: colors.playerFocusRing, width: 1.5);
            }
            return BorderSide.none;
          }),
        ),
      ),
    );
  }
}

class SpeedButton extends StatelessWidget {
  const SpeedButton({required this.speed, required this.onTap, super.key});

  final double speed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.videoColors;
    return Tooltip(
      message: AppLocalizations.of(context).videoPlaybackSpeed,
      child: TextButton(
        onPressed: onTap,
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(48, 44)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 10),
          ),
          foregroundColor: WidgetStatePropertyAll(
            colors.playerControlForeground,
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused) ||
                states.contains(WidgetState.pressed)) {
              return colors.playerControlHover;
            }
            return Colors.transparent;
          }),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
        ),
        child: Text(
          '${speed.toStringAsFixed(speed == speed.roundToDouble() ? 0 : 2)}x',
          style: TextStyle(
            color: colors.playerControlForeground,
            fontSize: AppTypography.bodySmall,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.videoColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: TextStyle(
                color: colors.playerControlMuted.withValues(alpha: 0.72),
                fontSize: AppTypography.bodyMedium,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: colors.playerControlForeground,
                fontSize: AppTypography.bodyMedium,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AspectRatioOption {
  const AspectRatioOption({
    required this.label,
    required this.ratio,
    required this.icon,
    this.isFill = false,
  });

  final String label;
  final double? ratio;
  final IconData icon;
  final bool isFill;

  static List<AspectRatioOption> options(BuildContext context) => [
    AspectRatioOption(
      label: AppLocalizations.of(context).videoOriginalAspectRatio,
      ratio: null,
      icon: Icons.aspect_ratio_rounded,
    ),
    const AspectRatioOption(
      label: '16:9',
      ratio: 16 / 9,
      icon: Icons.crop_landscape_rounded,
    ),
    const AspectRatioOption(
      label: '21:9',
      ratio: 21 / 9,
      icon: Icons.crop_free_rounded,
    ),
    const AspectRatioOption(
      label: '4:3',
      ratio: 4 / 3,
      icon: Icons.crop_portrait_rounded,
    ),
    AspectRatioOption(
      label: AppLocalizations.of(context).videoFillScreen,
      ratio: null,
      icon: Icons.fit_screen_rounded,
      isFill: true,
    ),
  ];
}
