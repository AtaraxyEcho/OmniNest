import 'package:flutter/widgets.dart';

/// 分段区跟手横滑：内容随手指平移，松手按位移与速度落页。
///
/// 与媒体库分段的观感同一条水准（原生 PageView + 分段点选带动画落页）。
/// 组件是**受控**的：当前分段由外部传入，点选分段条与横滑共用同一条回流，
/// 因为各调用方的分段真相分别住在自己的 Controller 或父级 State 里，组件
/// 自己再存一份就会出现两份状态互相覆盖。
///
/// 横向轨道（海报/专辑轨）与分页同轴，落在轨道上的手势仍由轨道消费——
/// 与横滑检测器时代的取舍一致，不是本次改动引入的回归。
class MobileSegmentPager<T> extends StatefulWidget {
  const MobileSegmentPager({
    required this.sections,
    required this.current,
    required this.onChanged,
    required this.pageBuilder,
    this.controller,
    this.interactionEnabled = true,
    super.key,
  });

  /// 分段次序，顺序即横滑方向。
  final List<T> sections;

  /// 当前分段：唯一真相，来自调用方的状态。
  final T current;

  /// 横滑落定或外部改选后的目标分段。
  final ValueChanged<T> onChanged;

  /// 按分段构建该页内容。相邻分段只在拖动起手时才构建。
  final Widget Function(BuildContext context, T section) pageBuilder;

  /// 宿主自己持有的分页控制器：分段滑块要读**连续**页码（媒体库的跟手滑块就是
  /// 这样画的），组件内部的控制器对外不可见，所以这里开一个注入口。
  /// 传入时由宿主负责 dispose。
  final PageController? controller;

  /// 关掉横滑本身（例如多选进行中：分段条已隐藏，误划会悄悄换掉视图）。
  /// 关闭只换分页物理，页内纵向滚动与滚动位置都不受影响。
  final bool interactionEnabled;

  @override
  State<MobileSegmentPager<T>> createState() => _MobileSegmentPagerState<T>();
}

class _MobileSegmentPagerState<T> extends State<MobileSegmentPager<T>> {
  /// 仅在宿主没有传控制器时创建；宿主传进来的由宿主自己 dispose。
  PageController? _ownedController;

  PageController get _controller => widget.controller ?? _ownedController!;

  /// 上一次由本组件发起或确认的页码，用于区分「内部落页」与「外部改选」。
  /// 初值必须在 initState 里取：`late` 的初始化式推迟到首次读取，而首次
  /// 读取发生在 didUpdateWidget 里，那时 `widget` 已经换成新配置，初值会直接
  /// 等于目标页码，外部改选因此被当成回声而不再落页。
  late int _lastReported;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _ownedController = PageController(initialPage: _targetIndex);
    }
    _lastReported = _targetIndex;
  }

  int get _targetIndex {
    final index = widget.sections.indexOf(widget.current);
    // 调用方必须保证 current 在 sections 里：不在就没有「邻位内容」可画，
    // 画首段等于把别的分段内容顶掉。这种视图应当直接渲染、不挂分页器
    //（照片的 Tags、影视的管理分区就是这么处理的），这里的归零只是兜底。
    return index < 0 ? 0 : index;
  }

  @override
  void didUpdateWidget(covariant MobileSegmentPager<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = _targetIndex;
    if (_lastReported == target) {
      // 落页由本组件发起，调用方只是把同一个值回灌：不再动画，避免回声。
      return;
    }
    _lastReported = target;
    if (!_controller.hasClients) {
      return;
    }
    if ((_controller.page ?? target.toDouble()).round() == target) {
      return;
    }
    _controller.animateToPage(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _ownedController?.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    final section = widget.sections[index];
    _lastReported = index;
    widget.onChanged(section);
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _controller,
      physics:
          widget.interactionEnabled
              ? null
              : const NeverScrollableScrollPhysics(),
      itemCount: widget.sections.length,
      onPageChanged: _onPageChanged,
      itemBuilder:
          (context, index) =>
              widget.pageBuilder(context, widget.sections[index]),
    );
  }
}
