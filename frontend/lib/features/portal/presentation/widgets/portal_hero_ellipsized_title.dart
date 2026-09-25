import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/residual_chrome_colors.dart';

/// Portal Hero 区域的单行省略标题。
class PortalHeroEllipsizedTitle extends StatelessWidget {
  const PortalHeroEllipsizedTitle(this.title, {required this.style, super.key});

  final String title;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final titleText = Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        );
        if (!constraints.maxWidth.isFinite) {
          return titleText;
        }
        final painter = TextPainter(
          text: TextSpan(text: title, style: style),
          maxLines: 1,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        if (!painter.didExceedMaxLines) {
          return titleText;
        }
        return Tooltip(
          message: title,
          waitDuration: const Duration(milliseconds: 320),
          showDuration: const Duration(seconds: 5),
          preferBelow: false,
          verticalOffset: 12,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: PortalHeroColors.titleBackdrop,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          textStyle: const TextStyle(
            color: Colors.white,
            fontSize: AppTypography.bodySmall,
            fontWeight: FontWeight.w600,
          ),
          child: titleText,
        );
      },
    );
  }
}
