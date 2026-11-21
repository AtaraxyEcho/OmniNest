import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_window_frame.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/core/window/window_chrome_controller.dart';

enum _WindowControlGlyph { minimize, maximize, restore, close }

/// 样例 `.win-ctl`：46px 见方三键，关闭键悬停转红底白字。
///
/// 标题栏与登录/首启/启动页共用同一份，避免前置页另写一套尺寸与配色。
class DesktopWindowControls extends ConsumerWidget {
  const DesktopWindowControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final chrome = ref.read(windowChromeControllerProvider.notifier);
    // 样例 `.win-ctl` 中键按 `win === "max"` 在 maximize / restore 之间换字形。
    final maximized = ref.watch(
      windowChromeControllerProvider.select((state) => state.isMaximized),
    );
    Widget control({
      required _WindowControlGlyph glyph,
      required String label,
      required VoidCallback onTap,
      bool danger = false,
      Key? key,
    }) {
      return DesktopHover(
        builder:
            (context, hovered) => GestureDetector(
              key: key,
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: Semantics(
                button: true,
                label: label,
                child: Container(
                  width: 46,
                  height: DesktopMetrics.titleBarHeight,
                  color:
                      hovered
                          ? (danger ? const Color(0xFFC4423B) : skin.raise2)
                          : Colors.transparent,
                  child: Center(
                    child: _WindowControlIcon(
                      glyph: glyph,
                      size:
                          glyph == _WindowControlGlyph.maximize ||
                                  glyph == _WindowControlGlyph.restore
                              ? 14
                              : 15,
                      color: hovered && danger ? skin.onStage : skin.text2,
                    ),
                  ),
                ),
              ),
            ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        control(
          glyph: _WindowControlGlyph.minimize,
          label: l10n.desktopMinimize,
          onTap: () => chrome.minimize(),
        ),
        control(
          glyph:
              maximized
                  ? _WindowControlGlyph.restore
                  : _WindowControlGlyph.maximize,
          label: l10n.desktopMaximize,
          // 字形由 CustomPainter 绘制，测试按 key 区分最大化/还原。
          key: ValueKey<String>(
            maximized ? 'window-control-restore' : 'window-control-maximize',
          ),
          onTap: () => chrome.toggleMaximize(),
        ),
        control(
          glyph: _WindowControlGlyph.close,
          label: l10n.desktopCloseWindow,
          danger: true,
          onTap: () => chrome.close(),
        ),
      ],
    );
  }
}

class _WindowControlIcon extends StatelessWidget {
  const _WindowControlIcon({
    required this.glyph,
    required this.size,
    required this.color,
  });

  final _WindowControlGlyph glyph;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _WindowControlPainter(glyph: glyph, color: color),
    );
  }
}

class _WindowControlPainter extends CustomPainter {
  const _WindowControlPainter({required this.glyph, required this.color});

  final _WindowControlGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    canvas.save();
    canvas.scale(scale);
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    switch (glyph) {
      case _WindowControlGlyph.minimize:
        canvas.drawLine(const Offset(5, 12), const Offset(19, 12), paint);
        break;
      case _WindowControlGlyph.maximize:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(5, 5, 14, 14),
            const Radius.circular(1.5),
          ),
          paint,
        );
        break;
      case _WindowControlGlyph.restore:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(5, 9, 10, 10),
            const Radius.circular(1.5),
          ),
          paint,
        );
        final path =
            Path()
              ..moveTo(9, 9)
              ..lineTo(9, 6.5)
              ..arcToPoint(
                const Offset(10.5, 5),
                radius: const Radius.circular(1.5),
              )
              ..lineTo(17.5, 5)
              ..arcToPoint(
                const Offset(19, 6.5),
                radius: const Radius.circular(1.5),
              )
              ..lineTo(19, 13.5)
              ..arcToPoint(
                const Offset(17.5, 15),
                radius: const Radius.circular(1.5),
              )
              ..lineTo(15, 15);
        canvas.drawPath(path, paint);
        break;
      case _WindowControlGlyph.close:
        canvas
          ..drawLine(const Offset(5, 5), const Offset(19, 19), paint)
          ..drawLine(const Offset(19, 5), const Offset(5, 19), paint);
        break;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WindowControlPainter oldDelegate) =>
      oldDelegate.glyph != glyph || oldDelegate.color != color;
}

/// 无标题栏页面（登录 / 首启向导 / 启动页）的窗口 chrome。
///
/// 这些页面在样例里是 `.window` 之外的独立幕，本身没有 `.titlebar`；但原生
/// 窗口是固定无边框的，缺了拖拽区与三键就无法移动、最大化或关闭。这里只在
/// 顶部叠一条 46px 的透明命中带（样例 `.titlebar` 同高），不改页面自身布局：
/// 登录卡与向导卡都居中且顶部留白大于 46px，启动页更是纯居中。
class DesktopWindowChrome extends ConsumerWidget {
  const DesktopWindowChrome({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isDesktopPlatform) {
      return child;
    }
    final chrome = ref.read(windowChromeControllerProvider.notifier);
    return DesktopWindowFrame(
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: DesktopMetrics.titleBarHeight,
            // translucent：命中带只认领拖拽与双击，单击仍穿透到下层内容。
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => chrome.startDragging(),
              onDoubleTap: () => chrome.toggleMaximize(),
              child: const Align(
                alignment: Alignment.topRight,
                child: DesktopWindowControls(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 沉浸页顶栏空白处通用窗口拖拽区：拖动移动窗口，双击切换最大化，
/// 子按钮的单击事件不受影响（HitTestBehavior.translucent）。
class DesktopWindowDragRegion extends ConsumerWidget {
  const DesktopWindowDragRegion({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isDesktopPlatform) return child;
    final chrome = ref.read(windowChromeControllerProvider.notifier);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => chrome.startDragging(),
      onDoubleTap: () => chrome.toggleMaximize(),
      child: child,
    );
  }
}
