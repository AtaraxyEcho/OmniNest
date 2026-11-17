part of 'music_immersive_lyrics.dart';

/// 歌词行填充排版缓存载体与焦点带。
/// 折行填充的逐行度量：可视行子串、行盒几何与行宽权重。
///
/// [cacheKey] 覆盖文本、样式与宽度约束，命中时跳过重新排版。
class _FillLineLayout {
  const _FillLineLayout({
    required this.cacheKey,
    required this.lines,
    required this.tops,
    required this.heights,
    required this.widths,
    required this.consumed,
    required this.totalWidth,
    required this.widest,
    required this.timeWeights,
    required this.totalTime,
    required this.consumedTime,
  });

  final Object cacheKey;

  /// 每个可视行的裁剪后子串。
  final List<String> lines;

  /// 每行行盒相对首行顶部的纵向偏移。
  final List<double> tops;

  /// 每行行盒高度（strut 强制一致）。
  final List<double> heights;

  /// 每行实测字形宽度。
  final List<double> widths;

  /// 每行之前所有行的字形宽度累计，用于把整段填充比例换算到本行。
  final List<double> consumed;

  /// 全部可视行的字形宽度合计。
  final double totalWidth;

  /// 最宽可视行的宽度（行盒宽度）。
  final double widest;

  /// 每个可视行的词级时长权重（毫秒）；无词级数据或匹配失败时为 null，
  /// 行间衔接回退按行宽加权。
  final List<double>? timeWeights;

  /// 词级时长权重合计（毫秒）；[timeWeights] 为 null 时为 0。
  final double totalTime;

  /// 每行之前所有行的词级时长累计（毫秒）；[timeWeights] 为 null 时为 null。
  final List<double>? consumedTime;
}

/// 焦点带：在读行背后的一层低强度横向提亮，向两端淡出。
class _LyricFocusBand extends StatelessWidget {
  const _LyricFocusBand();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: <Color>[
                kMusicLyricFadeClearWhite,
                Colors.white.withValues(alpha: 0.07),
                Colors.white.withValues(alpha: 0.07),
                kMusicLyricFadeClearWhite,
              ],
              stops: const <double>[0, 0.18, 0.82, 1],
            ),
          ),
        ),
      ),
    );
  }
}
