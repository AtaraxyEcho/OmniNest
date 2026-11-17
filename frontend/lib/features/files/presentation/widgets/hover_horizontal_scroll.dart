import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 悬停横滚容器：鼠标悬停在区域内时，纵向滚轮直接驱动横向滚动。
///
/// 桌面工位的横向条（筛选 chips 等）在窄窗口会被截断，而 Flutter 默认
/// 不把纵向滚轮映射到横向轴；本组件在悬停期间消费 PointerScrollEvent，
/// 把滚轮增量转换为水平偏移。内容未溢出时不拦截，事件照常冒泡。
class HoverHorizontalScroll extends StatefulWidget {
  const HoverHorizontalScroll({required this.child, super.key});

  final Widget child;

  @override
  State<HoverHorizontalScroll> createState() => _HoverHorizontalScrollState();
}

class _HoverHorizontalScrollState extends State<HoverHorizontalScroll> {
  final ScrollController _controller = ScrollController();
  bool _hovering = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleScroll(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_controller.hasClients) {
      return;
    }
    final position = _controller.position;
    if (position.maxScrollExtent <= 0) {
      return;
    }
    var delta = event.scrollDelta.dy;
    if (delta == 0) {
      delta = event.scrollDelta.dx;
    }
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target == position.pixels) {
      return;
    }
    position.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Listener(
        onPointerSignal: _hovering ? _handleScroll : null,
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: SingleChildScrollView(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
