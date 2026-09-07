import 'package:flutter/material.dart';
import 'package:omninest/features/video/presentation/theme/movie_redesign_theme.dart';

/// 新版细进度条：2px 高，海报纸底部与继续观看卡片共用。
class MovieRedesignProgressBar extends StatelessWidget {
  const MovieRedesignProgressBar({
    required this.value,
    this.trackColor = const Color(0x66000000),
    super.key,
  });

  /// 进度 0.0 - 1.0。
  final double value;

  /// 轨道底色。
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.movieRedesign;
    return SizedBox(
      height: 2,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: trackColor),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value.clamp(0.0, 1.0),
            child: ColoredBox(color: palette.primary),
          ),
        ],
      ),
    );
  }
}
