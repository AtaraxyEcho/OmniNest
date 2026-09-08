import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_palette.dart';

/// Frame 风格视图空态：线性图标 + 主提示 + 弱化说明，居中展示。
class FrameEmptyView extends StatelessWidget {
  const FrameEmptyView({
    required this.icon,
    required this.message,
    this.hint,
    super.key,
  });

  final IconData icon;
  final String message;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final colors = context.frameColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: colors.muted),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.sub,
                fontSize: AppTypography.bodyLarge,
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.muted,
                  fontSize: AppTypography.bodySmall,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
