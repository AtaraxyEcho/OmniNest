import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_control_layout.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 阅读器目录、设置和辅助工具共用的面板框架。
///
/// 底部形态（移动壳层）按稿子 `.bottom-sheet` 画，几何全部取自
/// [ReaderSheetSpec]：glass-solid 实底、r28、--line 描边（窄屏底边贴屏不画）、
/// 投影 0 -20 60、38×4 手柄，头部是 9pt 强调色眉标 + 25pt 衬线面板名。
/// 侧栏形态（桌面宽窗）保持工位直角框架。
class ReaderAdaptivePanelFrame extends StatelessWidget {
  const ReaderAdaptivePanelFrame({
    required this.title,
    required this.settings,
    required this.layout,
    required this.onClose,
    required this.child,
    this.headerAction,
    this.eyebrow,
    super.key,
  });

  final String title;
  final ReaderViewSettings settings;
  final ReaderControlLayout layout;
  final VoidCallback onClose;
  final Widget child;
  final Widget? headerAction;

  /// 稿子 `.sheet-header small`：面板上方的上下文眉标（阅读器里是书名）。
  final String? eyebrow;

  @override
  Widget build(BuildContext context) {
    if (!layout.usesSidePanel) {
      return _bottomSheet(context);
    }
    return Material(
      color: settings.controlSurfaceColor,
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _headerRow(context, compact: true),
          Divider(
            height: 1,
            color: settings.onSurfaceColor.withValues(alpha: 0.10),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _bottomSheet(BuildContext context) {
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final sheetRadius = ReaderSheetSpec.borderRadiusFor(viewportWidth);
    return Container(
      // 描边挂在 Container 上：Border 会把子节点按线宽内缩，
      // 画在 Material 自己那层会被实底内容盖掉。
      decoration: BoxDecoration(
        borderRadius: sheetRadius,
        border: ReaderSheetSpec.borderFor(viewportWidth, settings.lineColor),
        boxShadow: [
          BoxShadow(
            color: settings.shadowColor,
            blurRadius: ReaderSheetSpec.shadowBlurRadius,
            offset: ReaderSheetSpec.shadowOffset,
          ),
        ],
      ),
      child: Material(
        color: settings.glassSolidColor,
        borderRadius: sheetRadius,
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(
                top: ReaderSheetSpec.handleTopPadding,
              ),
              child: Center(
                child: Container(
                  width: ReaderSheetSpec.handleWidth,
                  height: ReaderSheetSpec.handleHeight,
                  decoration: BoxDecoration(
                    color: settings.onSurfaceColor.withValues(
                      alpha: ReaderSheetSpec.handleOpacity,
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
            _headerRow(context, compact: false),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }

  Widget _headerRow(BuildContext context, {required bool compact}) {
    final eyebrowText = eyebrow;
    final closeChip = _CloseChip(onClose: onClose, settings: settings);
    final header = Row(
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!compact && eyebrowText != null && eyebrowText.isNotEmpty)
                Text(
                  eyebrowText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: settings.accentColor,
                    fontSize: AppTypography.labelNano,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.08,
                  ),
                ),
              Padding(
                padding: EdgeInsets.only(
                  top: compact ? 0 : ReaderSheetSpec.headerTitleGap,
                ),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: compact ? null : AppTypography.serifFamily,
                    fontFamilyFallback:
                        compact ? null : AppTypography.serifFamilyFallback,
                    color: settings.onSurfaceColor,
                    fontSize:
                        compact
                            ? AppTypography.titleMedium
                            : ReaderSheetSpec.headerTitleFontSize,
                    fontWeight: compact ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (headerAction != null) headerAction!,
        closeChip,
      ],
    );
    if (compact) {
      return SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.only(left: 20, right: 8),
          child: header,
        ),
      );
    }
    return Padding(padding: ReaderSheetSpec.headerPadding, child: header);
  }
}

/// 稿子 `.icon-button`：44×44 圆形、`--page-elevated` 72% 底、1px --line 描边、
/// 投影 0 5 18。本项目把关闭这类逃生控件的触控下限定在 48dp，所以取
/// [ReaderSheetSpec.closeTargetSize]；描边和底色照稿子。
class _CloseChip extends StatelessWidget {
  const _CloseChip({required this.onClose, required this.settings});

  final VoidCallback onClose;
  final ReaderViewSettings settings;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: ReaderSheetSpec.closeTargetSize,
      height: ReaderSheetSpec.closeTargetSize,
      child: IconButton(
        tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
        onPressed: onClose,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          backgroundColor: settings.elevatedColor.withValues(alpha: 0.72),
          shape: CircleBorder(side: BorderSide(color: settings.lineColor)),
        ),
        iconSize: ReaderSheetSpec.closeIconSize,
        color: settings.onSurfaceColor,
        icon: const Icon(Icons.close_rounded),
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
    this.eyebrow,
    super.key,
  });

  final String title;
  final ReaderViewSettings settings;
  final ReaderControlLayout layout;
  final VoidCallback onClose;
  final Widget child;
  final Widget? headerAction;

  /// 见 [ReaderAdaptivePanelFrame.eyebrow]。
  final String? eyebrow;

  @override
  Widget build(BuildContext context) {
    final panel = ReaderAdaptivePanelFrame(
      title: title,
      settings: settings,
      layout: layout,
      onClose: onClose,
      headerAction: headerAction,
      eyebrow: eyebrow,
      child: child,
    );
    final duration =
        MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : ReaderSheetSpec.entranceDuration;

    return LayoutBuilder(
      builder: (context, constraints) {
        // 稿子 `@media (min-width:720px)` 让抽屉离屏幕底边抬起 18px 并补上
        // 底边描边；键盘弹出后 Scaffold body 变矮，面板高度按实际可用高收敛，
        // 并保留一条遮罩带供点外关闭，否则标题与关闭钮会被 Stack 裁到可视区外。
        final sheetBottomMargin =
            layout.usesSidePanel ||
                    !ReaderSheetSpec.isWide(constraints.maxWidth)
                ? 0.0
                : ReaderSheetSpec.wideBottomMargin;
        final availableHeight = math.max(
          0.0,
          constraints.maxHeight - 24 - sheetBottomMargin,
        );
        final panelHeight = math.min(layout.panelMaxHeight, availableHeight);
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClose,
                child: const ColoredBox(color: ReaderSheetSpec.scrimColor),
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
                bottom: sheetBottomMargin,
                height: panelHeight,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  // `.bottom-sheet` 的 width: min(100%, 680px) + margin: 0 auto。
                  child: SizedBox(
                    width: math.min(
                      ReaderSheetSpec.maxWidth,
                      constraints.maxWidth,
                    ),
                    height: panelHeight,
                    child: _ReaderPanelEntrance(
                      horizontal: false,
                      duration: duration,
                      child: panel,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
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
      curve: ReaderSheetSpec.entranceCurve,
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
