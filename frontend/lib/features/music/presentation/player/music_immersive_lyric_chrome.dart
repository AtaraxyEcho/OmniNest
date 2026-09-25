part of 'music_immersive_lyrics.dart';

/// "回到当前播放"按钮：手动滚动暂停跟随后浮出，点击恢复跟随并滚回焦点行。
class _BackToCurrentButton extends StatelessWidget {
  const _BackToCurrentButton({
    required this.palette,
    required this.tooltip,
    required this.onTap,
  });

  final MusicImmersivePalette palette;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Material(
          color: palette.surfaceStrong,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.my_location_rounded,
                    size: 15,
                    color: palette.text.withValues(alpha: 0.86),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    tooltip,
                    style: TextStyle(
                      color: palette.text.withValues(alpha: 0.86),
                      fontSize: AppTypography.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 歌词区顶部/底部的渐隐遮罩。
class _LyricEdgeFade extends StatelessWidget {
  const _LyricEdgeFade({required this.child, this.mask});

  final Widget child;

  /// 复刻形态的渐隐区间（视口高度比例，起点与终点）：样例三布局各自不同，
  final (double, double)? mask;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        if (!height.isFinite || height <= 0) {
          return child;
        }
        final resolvedMask = mask;
        final double stop;
        final double end;
        if (resolvedMask != null) {
          stop = resolvedMask.$1.clamp(0.0, 0.5).toDouble();
          end = resolvedMask.$2.clamp(0.5, 1.0).toDouble();
        } else {
          final extent =
              (height * _edgeFadeHeightRatio)
                  .clamp(
                    _edgeFadeMinHeight,
                    _edgeFadeMaxHeight,
                  )
                  .toDouble();
          stop = (extent / height).clamp(0.0, 0.45).toDouble();
          end = 1 - stop;
        }
        return ShaderMask(
          key: const ValueKey('music-lyric-edge-fade'),
          blendMode: BlendMode.dstIn,
          shaderCallback:
              (bounds) => LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: const <Color>[
                  kMusicLyricFadeClearWhite,
                  kMusicLyricActiveTextColor,
                  kMusicLyricActiveTextColor,
                  kMusicLyricFadeClearWhite,
                ],
                stops: <double>[0, stop, end, 1],
              ).createShader(bounds),
          child: child,
        );
      },
    );
  }
}
