part of 'desktop_now_playing_lyrics.dart';

class _VisualLineWordFillText extends StatelessWidget {
  const _VisualLineWordFillText({
    required this.text,
    required this.textStyle,
    required this.progress,
    required this.wordFill,
    required this.fillPaint,
    required this.basePaint,
    required this.baseOpacity,
    required this.glow,
  });

  final String text;
  final TextStyle textStyle;
  final double progress;
  final bool wordFill;
  final DesktopNpPaint fillPaint;
  final DesktopNpPaint basePaint;
  final double baseOpacity;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final glowShadows =
        glow
            ? <Shadow>[
              Shadow(
                color: fillPaint.primaryColor.withValues(alpha: 0.55),
                blurRadius: 28,
              ),
            ]
            : null;

    if (!wordFill) {
      return ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (rect) => fillPaint.createShader(rect),
        child: Text(text, style: textStyle.copyWith(shadows: glowShadows)),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final segments = _splitVisualLines(
          text: text,
          style: textStyle,
          maxWidth: maxWidth,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        );
        final totalLen = segments.fold<int>(0, (sum, s) => sum + s.length);
        final safeTotal = totalLen <= 0 ? 1 : totalLen;
        final currentChar = progress.clamp(0.0, 1.0) * safeTotal;

        var consumed = 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final segment in segments)
              Builder(
                builder: (context) {
                  final segLen = segment.isEmpty ? 1 : segment.length;
                  final segStart = consumed;
                  consumed += segment.length;
                  final lineFrac = ((currentChar - segStart) / segLen).clamp(
                    0.0,
                    1.0,
                  );

                  final baseLayer = ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback:
                        (rect) =>
                            basePaint.createShader(rect, opacity: baseOpacity),
                    child: Text(segment, style: textStyle, maxLines: 1),
                  );

                  if (lineFrac <= 0.001) {
                    return baseLayer;
                  }

                  final sungLayer = ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback: (rect) => fillPaint.createShader(rect),
                    child: Text(
                      segment,
                      style: textStyle.copyWith(shadows: glowShadows),
                      maxLines: 1,
                    ),
                  );

                  if (lineFrac >= 0.999) {
                    return sungLayer;
                  }

                  final softEdge = (lineFrac + 0.025).clamp(0.0, 1.0);
                  return Stack(
                    children: [
                      baseLayer,
                      ShaderMask(
                        blendMode: BlendMode.dstIn,
                        shaderCallback: (rect) {
                          return LinearGradient(
                            colors: const <Color>[
                              Colors.white,
                              Colors.white,
                              Colors.transparent,
                              Colors.transparent,
                            ],
                            stops: <double>[0.0, lineFrac, softEdge, 1.0],
                          ).createShader(rect);
                        },
                        child: sungLayer,
                      ),
                    ],
                  );
                },
              ),
          ],
        );
      },
    );
  }

  List<String> _splitVisualLines({
    required String text,
    required TextStyle style,
    required double maxWidth,
    required TextDirection textDirection,
    required TextScaler textScaler,
  }) {
    if (text.isEmpty || !maxWidth.isFinite || maxWidth <= 0) {
      return <String>[text];
    }
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: textDirection,
      textScaler: textScaler,
    )..layout(maxWidth: maxWidth);

    final metrics = painter.computeLineMetrics();
    if (metrics.length <= 1) {
      return <String>[text];
    }

    final result = <String>[];
    var start = 0;
    for (var i = 0; i < metrics.length; i++) {
      final metric = metrics[i];
      final y = metric.baseline - metric.ascent * 0.5;
      final endOffset =
          i == metrics.length - 1
              ? text.length
              : painter
                  .getPositionForOffset(Offset(maxWidth, y))
                  .offset
                  .clamp(start, text.length);
      if (endOffset > start) {
        result.add(text.substring(start, endOffset).trimRight());
        start = endOffset;
      }
    }
    if (start < text.length) {
      final tail = text.substring(start).trim();
      if (tail.isNotEmpty) result.add(tail);
    }
    return result.isEmpty ? <String>[text] : result;
  }
}
