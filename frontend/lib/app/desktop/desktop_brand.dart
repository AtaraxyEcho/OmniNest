import 'package:material_ui/material_ui.dart';

import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';

/// 品牌标记（样例 `.mark`）：三根不等高的强调色竖条。
///
/// 与应用图标同源语义，但这里是矢量绘制，跟随强调色档位实时变化，
/// 不是一张固定 PNG——换 accent 时品牌也跟着变，这是样例的行为。
class DesktopBrandMark extends StatelessWidget {
  const DesktopBrandMark({this.height = 18, this.color, super.key});

  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final tint = color ?? skin.accent;
    final barWidth = height * (5 / 18);
    final gap = height * (2 / 18);
    final radius = Radius.circular(height * (3 / 18));
    Widget bar(double ratio, double opacity) => Container(
      width: barWidth,
      height: height * ratio,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: opacity),
        borderRadius: BorderRadius.all(radius),
      ),
    );
    return SizedBox(
      height: height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          bar(0.5, 0.6),
          SizedBox(width: gap),
          bar(1, 1),
          SizedBox(width: gap),
          bar(13 / 18, 0.8),
        ],
      ),
    );
  }
}

/// 品牌锁定组合：标记 + 衬线字标。
class DesktopBrandLockup extends StatelessWidget {
  const DesktopBrandLockup({
    this.markHeight = 18,
    this.color,
    this.showLabel = true,
    super.key,
  });

  final double markHeight;
  final Color? color;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DesktopBrandMark(height: markHeight, color: color),
        if (showLabel) ...[
          const SizedBox(width: 9),
          Text('OmniNest', style: DesktopType.brand(color ?? skin.text)),
        ],
      ],
    );
  }
}
