import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_control_layout.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 阅读器目录、设置和辅助工具共用的面板框架。
class ReaderAdaptivePanelFrame extends StatelessWidget {
  const ReaderAdaptivePanelFrame({
    required this.title,
    required this.settings,
    required this.layout,
    required this.onClose,
    required this.child,
    this.headerAction,
    super.key,
  });

  final String title;
  final ReaderViewSettings settings;
  final ReaderControlLayout layout;
  final VoidCallback onClose;
  final Widget child;
  final Widget? headerAction;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: settings.controlSurfaceColor,
      elevation: layout.usesSidePanel ? 8 : 12,
      borderRadius:
          layout.usesSidePanel
              ? BorderRadius.circular(8)
              : const BorderRadius.vertical(top: Radius.circular(8)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: 56,
            child: Padding(
              padding: const EdgeInsets.only(left: 20, right: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: settings.onSurfaceColor,
                        fontSize: AppTypography.titleMedium,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (headerAction != null) headerAction!,
                  IconButton(
                    tooltip:
                        MaterialLocalizations.of(context).closeButtonTooltip,
                    onPressed: onClose,
                    icon: Icon(
                      Icons.close_rounded,
                      color: settings.onSurfaceVariantColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Divider(
            height: 1,
            color: settings.onSurfaceColor.withValues(alpha: 0.10),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// 阅读器共享的模态遮罩与响应式面板定位。
class ReaderAdaptivePanelOverlay extends StatelessWidget {
  const ReaderAdaptivePanelOverlay({
    required this.title,
    required this.settings,
    required this.layout,
    required this.onClose,
    required this.child,
    this.headerAction,
    super.key,
  });

  final String title;
  final ReaderViewSettings settings;
  final ReaderControlLayout layout;
  final VoidCallback onClose;
  final Widget child;
  final Widget? headerAction;

  @override
  Widget build(BuildContext context) {
    final panel = ReaderAdaptivePanelFrame(
      title: title,
      settings: settings,
      layout: layout,
      onClose: onClose,
      headerAction: headerAction,
      child: child,
    );
    final duration =
        MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 210);

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.34)),
          ),
        ),
        if (layout.usesSidePanel)
          Positioned(
            top: 72,
            right: 24,
            bottom: 24,
            width: layout.panelWidth,
            child: _ReaderPanelEntrance(
              horizontal: true,
              duration: duration,
              child: panel,
            ),
          )
        else
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: layout.panelMaxHeight,
            child: _ReaderPanelEntrance(
              horizontal: false,
              duration: duration,
              child: panel,
            ),
          ),
      ],
    );
  }
}

class _ReaderPanelEntrance extends StatelessWidget {
  const _ReaderPanelEntrance({
    required this.horizontal,
    required this.duration,
    required this.child,
  });

  final bool horizontal;
  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder:
          (context, value, child) => Transform.translate(
            offset:
                horizontal
                    ? Offset((1 - value) * 36, 0)
                    : Offset(0, (1 - value) * 36),
            child: Opacity(opacity: value, child: child),
          ),
      child: child,
    );
  }
}
