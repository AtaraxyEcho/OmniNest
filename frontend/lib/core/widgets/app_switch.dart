import 'package:flutter/material.dart';
import 'package:omninest/core/theme/motion_token.dart';

/// 统一开关几何：36×20 胶囊轨道 + 14px 圆点。
///
/// 全产品只保留这一套尺寸，颜色由调用方给：工位取 `ColorScheme`，
/// 音乐沉浸取 glass 色板，移动环境取极性表。改造前同一产品里并存三种
/// 开关形状——工位 32×16 / 36×20 直角轨道 + 方形滑块、音乐 32×16 直角、
/// 移动 34×20 胶囊。方形滑块在暗色玻璃表面上辨识度低，状态边界只能靠
/// 1px 描边区分；胶囊轨道 + 圆形滑块是跨平台的主流心智模型，状态一眼可辨。
abstract final class AppSwitchGeometry {
  /// 轨道宽度。
  static const double trackWidth = 36;

  /// 轨道高度。
  static const double trackHeight = 20;

  /// 圆点直径。
  static const double thumbSize = 14;

  /// 圆点与轨道的水平内边距。
  static const double inset = (trackHeight - thumbSize) / 2;

  /// 桌面端热区边长：鼠标定位精确，32 足够且不撑高紧凑表单行。
  static const double desktopHitTarget = 32;

  /// 无障碍最小触控热区（移动端与独立开关使用）。
  static const double touchHitTarget = 44;
}

/// 开关轨道（纯视觉）：胶囊轨道 + 圆形滑块 + 150ms 位移。
///
/// 不含手势、焦点与语义：工位由 `WorkstationFocusTarget` 统一声明，
/// 移动壳层由 `Semantics` 包装，避免读屏重复播报同一个可点节点。
class AppSwitchTrack extends StatelessWidget {
  const AppSwitchTrack({
    required this.value,
    required this.trackOn,
    required this.trackOff,
    required this.thumbOn,
    required this.thumbOff,
    this.borderColor,
    this.thumbShadow,
    this.width = AppSwitchGeometry.trackWidth,
    this.height = AppSwitchGeometry.trackHeight,
    this.trackKey,
    super.key,
  });

  final bool value;

  final Color trackOn;
  final Color trackOff;
  final Color thumbOn;
  final Color thumbOff;

  /// 轨道描边；null 时不描边，开态轨道的实色本身即状态信号。
  final Color? borderColor;

  /// 圆点投影：浅色轨道上的白圆点需要投影分离，暗态通常不需要。
  final List<BoxShadow>? thumbShadow;

  final double width;
  final double height;

  /// 轨道容器自身的 key：测试与调用方据此取轨道几何与当前底色。
  ///
  /// 与 widget 自身的 [key] 分开，是因为 `find.byKey` 命中 key 所在的
  /// element，只有落在 `AnimatedContainer` 上才能直接读到它的 decoration。
  final Key? trackKey;

  @override
  Widget build(BuildContext context) {
    final duration = MotionToken.resolve(context, MotionToken.fast);
    // 圆点直径随轨道高度等比推导，调用方改尺寸时几何不会散。
    final thumbSize = height * (AppSwitchGeometry.thumbSize /
        AppSwitchGeometry.trackHeight);
    final inset = (height - thumbSize) / 2;
    return AnimatedContainer(
      key: trackKey,
      duration: duration,
      curve: MotionToken.curve,
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: value ? trackOn : trackOff,
        borderRadius: BorderRadius.circular(height / 2),
        border: borderColor == null ? null : Border.all(color: borderColor!),
      ),
      child: AnimatedAlign(
        duration: duration,
        curve: MotionToken.curve,
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: inset),
          child: AnimatedContainer(
            duration: duration,
            curve: MotionToken.curve,
            width: thumbSize,
            height: thumbSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: value ? thumbOn : thumbOff,
              boxShadow: thumbShadow,
            ),
          ),
        ),
      ),
    );
  }
}
