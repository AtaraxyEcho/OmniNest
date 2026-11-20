import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_reading_palette.dart';

/// 桌面端毛玻璃悬浮面板（1:1 对齐样例 `.bk-pop`）：
/// - 无全屏暗色 scrim，不压暗正文阅读区；
/// - 目录（TOC）靠左 `left: 20, width: 280`，其余面板靠右 `right: 20, width: 300-340`；
/// - 受控 `BackdropFilter(sigma: 18)` 兼顾毛玻璃质感与高刷 GPU 帧率，关闭即卸载。
class DesktopReaderPopover extends StatelessWidget {
  const DesktopReaderPopover({
    required this.alignLeft,
    required this.width,
    required this.eyebrow,
    required this.onDismissOutside,
    required this.child,
    super.key,
  });

  final bool alignLeft;
  final double width;
  final String eyebrow;
  final VoidCallback onDismissOutside;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final maxH = math.max(240.0, MediaQuery.sizeOf(context).height - 140.0);
    return Stack(
      fit: StackFit.expand,
      children: [
        // 透明点击穿透吸收层：点击正文区收起面板，不叠暗色黑幕。
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onDismissOutside,
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          top: 64,
          left: alignLeft ? 20 : null,
          right: alignLeft ? null : 20,
          width: width,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Material(
                  color: ReaderReadingPalette.desktopPopoverGlass,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  elevation: 16,
                  shadowColor: Colors.black.withValues(alpha: 0.48),
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      brightness: Brightness.dark,
                      colorScheme: Theme.of(context).colorScheme.copyWith(
                        brightness: Brightness.dark,
                        onSurface: ReaderReadingPalette.dark.bookDeskText,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            eyebrow.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.50),
                              fontSize: AppTypography.labelSmall,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Flexible(child: child),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
