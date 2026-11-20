import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_reading_palette.dart';

/// 桌面端右侧毛玻璃悬浮抽屉（v3：统一右侧展开 + 加宽 + 显式关闭钮 + 暗色玻璃色板作用域）。
class DesktopReaderPopover extends StatelessWidget {
  const DesktopReaderPopover({
    required this.width,
    required this.eyebrow,
    required this.onDismissOutside,
    required this.child,
    this.alignLeft = false,
    super.key,
  });

  final bool alignLeft;
  final double width;
  final String eyebrow;
  final VoidCallback onDismissOutside;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final effectiveWidth = math.min(
      width,
      math.max(300.0, viewport.width - 40.0),
    );
    final maxH = math.max(280.0, viewport.height - 136.0);

    return Stack(
      fit: StackFit.expand,
      children: [
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
          width: effectiveWidth,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.46),
                    blurRadius: 36,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Material(
                    color: ReaderReadingPalette.desktopPopoverGlass,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: ReaderPanelSurfaceScope(
                      darkGlass: true,
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          brightness: Brightness.dark,
                          colorScheme: Theme.of(context).colorScheme.copyWith(
                            brightness: Brightness.dark,
                            onSurface:
                                ReaderReadingPalette.desktopPopoverOnSurface,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                14,
                                10,
                                10,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      eyebrow,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.78,
                                        ),
                                        fontSize: AppTypography.bodyLarge,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.6,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: onDismissOutside,
                                    visualDensity: VisualDensity.compact,
                                    splashRadius: 16,
                                    icon: Icon(
                                      Icons.close_rounded,
                                      size: 18,
                                      color: Colors.white.withValues(
                                        alpha: 0.68,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Divider(
                              height: 1,
                              thickness: 1,
                              color: Colors.white.withValues(alpha: 0.09),
                            ),
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
        ),
      ],
    );
  }
}
