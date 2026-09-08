import 'package:flutter/material.dart';

/// 锚定浮层：在锚点控件下方右对齐弹出面板，点击浮层外部关闭。
///
/// 对应 Reader 重构原型 Popover 的定位语义（absolute top-full mt-2
/// right-0）。使用根 Overlay 直插面板而非 MenuAnchor：定位精确可控，
/// 且避免桌面端菜单语义树更新触发的引擎无障碍报错。
class AnchoredPopover {
  AnchoredPopover({this.gap = 8});

  /// 面板与锚点底边的间距，原型为 mt-2（8px）。
  final double gap;

  OverlayEntry? _entry;

  bool get isOpen => _entry != null;

  /// 在 [anchorContext] 对应控件下方右对齐打开 [panelBuilder] 面板。
  /// [onChanged] 在打开与关闭时回调，供宿主刷新入口态样式。
  void open(
    BuildContext anchorContext,
    WidgetBuilder panelBuilder, {
    VoidCallback? onChanged,
  }) {
    if (isOpen) {
      return;
    }
    final RenderBox box = anchorContext.findRenderObject()! as RenderBox;
    final OverlayState overlay = Overlay.of(anchorContext, rootOverlay: true);
    final RenderBox overlayBox =
        overlay.context.findRenderObject()! as RenderBox;
    final Offset anchorTopLeft = box.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final double right = (overlayBox.size.width -
            anchorTopLeft.dx -
            box.size.width)
        .clamp(8.0, double.infinity);
    final double top = anchorTopLeft.dy + box.size.height + gap;

    void close() {
      _entry?.remove();
      _entry = null;
      onChanged?.call();
    }

    final OverlayEntry entry = OverlayEntry(
      builder:
          (context) => Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: close,
                  child: const SizedBox.expand(),
                ),
              ),
              Positioned(top: top, right: right, child: panelBuilder(context)),
            ],
          ),
    );
    _entry = entry;
    overlay.insert(entry);
    onChanged?.call();
  }

  /// 关闭当前浮层，未打开时为空操作。
  void close({VoidCallback? onChanged}) {
    if (_entry == null) {
      return;
    }
    _entry!.remove();
    _entry = null;
    onChanged?.call();
  }
}
