import 'package:flutter/widgets.dart';

/// 通用单击检测器：以 260ms / 12px 阈值区分点击与拖动。
///
/// 阅读器内容区用它把 Pointer 事件收敛为语义化点击回调，
/// 避免各阅读器 State 内散落手势判定的位移与时间戳样板。
class ReaderTapDetector extends StatefulWidget {
  const ReaderTapDetector({
    required this.onTap,
    required this.child,
    super.key,
  });

  /// 命中单击时回调，参数为按下位置的本地坐标。
  final void Function(Offset localPosition) onTap;
  final Widget child;

  @override
  State<ReaderTapDetector> createState() => _ReaderTapDetectorState();
}

class _ReaderTapDetectorState extends State<ReaderTapDetector> {
  static const _tapMaxDuration = Duration(milliseconds: 260);
  static const _tapMaxDistance = 12.0;

  Offset? _startPosition;
  DateTime? _startedAt;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _startPosition = event.localPosition;
        _startedAt = DateTime.now();
      },
      onPointerUp: (event) {
        final start = _startPosition;
        final startedAt = _startedAt;
        _startPosition = null;
        _startedAt = null;
        if (start == null || startedAt == null) {
          return;
        }
        final duration = DateTime.now().difference(startedAt);
        final distance = (event.localPosition - start).distance;
        if (duration <= _tapMaxDuration && distance <= _tapMaxDistance) {
          widget.onTap(event.localPosition);
        }
      },
      onPointerCancel: (_) {
        _startPosition = null;
        _startedAt = null;
      },
      child: widget.child,
    );
  }
}
