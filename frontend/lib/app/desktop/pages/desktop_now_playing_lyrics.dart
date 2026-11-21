import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_np_style.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/features/music/domain/music_models.dart';

/// 双语对照副行字号（样例译文按原文 `0.62×` 呈现，11.5 是 18.5px 原文的对齐值）。
const _translationSize = 11.5;

/// 桌面播放页歌词组件（对齐新版样例 `Music.tsx:197-244` 与 `npstyle.css:9-17, 86-98`）：
/// - 60fps `positionStream` + 帧间 `Ticker` 插值驱动；
/// - 换句平滑居中滚动 + 手动滚屏暂停跟随 3s 与「回到当前」胶囊按钮；
/// - 上下 `style.lyricFade%` 渐隐与隐藏滚动条；
/// - 单行 `RepaintBoundary` + 仅对 `1 <= d <= 3` 近邻行施加 `ImageFiltered(d * 0.7)` 景深模糊；
/// - 双层 `Paint` 与可视行切片逐字填充共存（支持折行逐行扫过 + 上下分色/渐变）；
/// - 悬停非当前行去模糊并浮现 `▶ mm:ss` 跳转胶囊，点击精准 `seekTo`；
/// - 双语对照译文渲染（`0.62×` 字号，当前行整行提亮）。
class DesktopNowPlayingLyrics extends StatefulWidget {
  const DesktopNowPlayingLyrics({
    required this.lines,
    required this.plainLines,
    required this.position,
    required this.positionStream,
    required this.duration,
    required this.playing,
    required this.style,
    required this.hueColor,
    required this.showTranslation,
    required this.onSeek,
    super.key,
  });

  final List<MusicLyricLine> lines;
  final List<String> plainLines;
  final Duration position;
  final Stream<Duration> positionStream;
  final Duration duration;
  final bool playing;
  final DesktopNpStyle style;
  final Color hueColor;
  final bool showTranslation;
  final ValueChanged<Duration> onSeek;

  @override
  State<DesktopNowPlayingLyrics> createState() =>
      _DesktopNowPlayingLyricsState();
}

class _DesktopNowPlayingLyricsState extends State<DesktopNowPlayingLyrics>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _lineKeys = <int, GlobalKey>{};
  final ValueNotifier<double> _activeLineProgress = ValueNotifier<double>(0.0);

  StreamSubscription<Duration>? _positionSub;
  late final Ticker _ticker;
  final Stopwatch _sampleWatch = Stopwatch();

  Duration _samplePosition = Duration.zero;
  int _activeIndex = -1;
  int? _hoveredIndex;
  bool _userScrolling = false;
  Timer? _resumeFollowTimer;

  @override
  void initState() {
    super.initState();
    _samplePosition = widget.position;
    _sampleWatch.start();
    _ticker = createTicker(_onTick);
    _subscribeStream();
    _syncPosition(_samplePosition, scrollIfChanged: false);
    _syncTicker();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _activeIndex >= 0) {
        _scrollToIndex(_activeIndex, animate: false);
      }
    });
  }

  @override
  void didUpdateWidget(DesktopNowPlayingLyrics oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.positionStream != widget.positionStream) {
      _subscribeStream();
    }
    if (oldWidget.lines != widget.lines) {
      _lineKeys.clear();
      _hoveredIndex = null;
      _userScrolling = false;
      _resumeFollowTimer?.cancel();
      _samplePosition = widget.position;
      _sampleWatch
        ..reset()
        ..start();
      _syncPosition(_samplePosition, scrollIfChanged: false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _activeIndex >= 0) {
          _scrollToIndex(_activeIndex, animate: false);
        }
      });
    } else if (oldWidget.position != widget.position &&
        (widget.position - _currentInterpolatedPosition()).abs() >
            const Duration(milliseconds: 220)) {
      _samplePosition = widget.position;
      _sampleWatch
        ..reset()
        ..start();
      _syncPosition(_samplePosition, scrollIfChanged: true);
    }
    if (oldWidget.playing != widget.playing) {
      _samplePosition = _currentInterpolatedPosition();
      _sampleWatch
        ..reset()
        ..start();
      _syncTicker();
    }
  }

  void _subscribeStream() {
    _positionSub?.cancel();
    _positionSub = widget.positionStream.listen((pos) {
      if (!mounted) return;
      _samplePosition = pos;
      _sampleWatch
        ..reset()
        ..start();
      _syncPosition(pos, scrollIfChanged: true);
    });
  }

  void _syncTicker() {
    final shouldTick = widget.playing && widget.lines.isNotEmpty;
    if (shouldTick && !_ticker.isActive) {
      _ticker.start();
    } else if (!shouldTick && _ticker.isActive) {
      _ticker.stop();
    }
  }

  Duration _currentInterpolatedPosition() {
    if (!widget.playing) return _samplePosition;
    final elapsed = _sampleWatch.elapsed;
    final next = _samplePosition + elapsed;
    if (widget.duration > Duration.zero && next > widget.duration) {
      return widget.duration;
    }
    return next;
  }

  void _onTick(Duration _) {
    if (!mounted || widget.lines.isEmpty) return;
    _syncPosition(_currentInterpolatedPosition(), scrollIfChanged: true);
  }

  void _syncPosition(Duration pos, {required bool scrollIfChanged}) {
    final lines = widget.lines;
    if (lines.isEmpty) {
      if (_activeIndex != -1) {
        setState(() => _activeIndex = -1);
      }
      _activeLineProgress.value = 0.0;
      return;
    }

    final index = _binarySearchActiveIndex(lines, pos);
    if (index >= 0) {
      final line = lines[index];
      final nextPos =
          index + 1 < lines.length
              ? lines[index + 1].position
              : (widget.duration > line.position
                  ? widget.duration
                  : line.position + const Duration(seconds: 4));
      final span = nextPos - line.position;
      final within = pos - line.position;
      final frac = line.progressAt(within, lineSpan: span);
      if ((frac - _activeLineProgress.value).abs() > 0.002) {
        _activeLineProgress.value = frac;
      }
    } else {
      _activeLineProgress.value = 0.0;
    }

    if (index != _activeIndex) {
      setState(() => _activeIndex = index);
      if (scrollIfChanged && !_userScrolling && index >= 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_userScrolling && _activeIndex == index) {
            _scrollToIndex(index, animate: true);
          }
        });
      }
    }
  }

  int _binarySearchActiveIndex(List<MusicLyricLine> lines, Duration pos) {
    if (lines.isEmpty || pos < lines.first.position) {
      return -1;
    }
    var low = 0;
    var high = lines.length - 1;
    var result = 0;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (lines[mid].position <= pos) {
        result = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return result;
  }

  void _scrollToIndex(int index, {required bool animate}) {
    if (!_scrollController.hasClients) return;
    final key = _lineKeys[index];
    final itemContext = key?.currentContext;
    if (itemContext == null || !itemContext.mounted) return;
    final itemBox = itemContext.findRenderObject();
    final viewportBox = context.findRenderObject();
    if (itemBox is! RenderBox ||
        viewportBox is! RenderBox ||
        !itemBox.hasSize ||
        !viewportBox.hasSize) {
      return;
    }
    final itemTop =
        itemBox.localToGlobal(Offset.zero, ancestor: viewportBox).dy;
    final itemCenter = itemTop + itemBox.size.height / 2;
    final viewportCenter = viewportBox.size.height * 0.44;
    final targetOffset =
        (_scrollController.offset + (itemCenter - viewportCenter)).clamp(
          _scrollController.position.minScrollExtent,
          _scrollController.position.maxScrollExtent,
        );
    if (!animate) {
      _scrollController.jumpTo(targetOffset);
      return;
    }
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      _scrollController.jumpTo(targetOffset);
      return;
    }
    unawaited(
      _scrollController.animateTo(
        targetOffset,
        duration: DesktopMotion.of(context, DesktopMotion.lyricsFollow),
        curve: const Cubic(0.22, 0.7, 0.2, 1),
      ),
    );
  }

  void _onUserScroll() {
    if (!_userScrolling && mounted) {
      setState(() => _userScrolling = true);
    }
    _resumeFollowTimer?.cancel();
    _resumeFollowTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _userScrolling = false);
      if (_activeIndex >= 0) {
        _scrollToIndex(_activeIndex, animate: true);
      }
    });
  }

  void _jumpBackToCurrent() {
    _resumeFollowTimer?.cancel();
    setState(() => _userScrolling = false);
    if (_activeIndex >= 0) {
      _scrollToIndex(_activeIndex, animate: true);
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _resumeFollowTimer?.cancel();
    _ticker.dispose();
    _scrollController.dispose();
    _activeLineProgress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isZh = Localizations.localeOf(
      context,
    ).languageCode.toLowerCase().startsWith('zh');
    final timed = widget.lines;
    final plain = widget.plainLines;
    if (timed.isEmpty && plain.isEmpty) {
      return Center(
        child: Text(
          l10n.musicNoLyrics,
          style: DesktopType.dense(Colors.white.withValues(alpha: 0.55)),
        ),
      );
    }

    final style = widget.style;
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final lyricSize =
        (viewportWidth * 0.024).clamp(24.0, 36.0) * style.lyricScale;
    final fadeFrac = (style.lyricFade / 100.0).clamp(0.0, 0.45);
    final fillPaint = style.effectiveFillPaint(widget.hueColor);
    final baseOp = (style.baseOpacity / 100.0).clamp(0.08, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final padY = (constraints.maxHeight * 0.36).clamp(64.0, 220.0);

        Widget listContent;
        if (timed.isEmpty) {
          listContent = ListView.builder(
            controller: _scrollController,
            padding: EdgeInsets.symmetric(vertical: padY * 0.4),
            itemCount: plain.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback:
                      (rect) =>
                          style.basePaint.createShader(rect, opacity: 0.78),
                  child: Text(
                    plain[index],
                    style: DesktopType.sectionTitle(
                      Colors.white,
                    ).copyWith(fontSize: lyricSize, height: 1.32),
                  ),
                ),
              );
            },
          );
        } else {
          listContent = NotificationListener<UserScrollNotification>(
            onNotification: (notification) {
              _onUserScroll();
              return false;
            },
            child: ListView.builder(
              controller: _scrollController,
              padding: EdgeInsets.symmetric(vertical: padY),
              itemCount: timed.length,
              itemBuilder: (context, index) {
                final line = timed[index];
                final isCurrent = index == _activeIndex;
                final isHovered = index == _hoveredIndex;
                final distance =
                    _activeIndex < 0 ? 0 : (index - _activeIndex).abs();
                final lineKey = _lineKeys.putIfAbsent(index, GlobalKey.new);

                return RepaintBoundary(
                  key: lineKey,
                  child: _LyricRowItem(
                    line: line,
                    isCurrent: isCurrent,
                    isHovered: isHovered,
                    distance: distance,
                    lyricSize: lyricSize,
                    style: style,
                    fillPaint: fillPaint,
                    baseOpacity: baseOp,
                    showTranslation: widget.showTranslation,
                    activeProgress: _activeLineProgress,
                    onHoverChanged: (hovering) {
                      if (hovering) {
                        if (_hoveredIndex != index) {
                          setState(() => _hoveredIndex = index);
                        }
                      } else if (_hoveredIndex == index) {
                        setState(() => _hoveredIndex = null);
                      }
                    },
                    onSeek: () {
                      _resumeFollowTimer?.cancel();
                      if (_userScrolling) {
                        setState(() => _userScrolling = false);
                      }
                      widget.onSeek(line.position);
                    },
                  ),
                );
              },
            ),
          );
        }

        final masked =
            fadeFrac > 0.005
                ? ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (rect) {
                    return LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: const <Color>[
                        Colors.transparent,
                        Colors.white,
                        Colors.white,
                        Colors.transparent,
                      ],
                      stops: <double>[0.0, fadeFrac, 1.0 - fadeFrac, 1.0],
                    ).createShader(rect);
                  },
                  child: listContent,
                )
                : listContent;

        return Stack(
          fit: StackFit.expand,
          children: [
            ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              child: masked,
            ),
            if (_userScrolling && timed.isNotEmpty && _activeIndex >= 0)
              Positioned(
                right: 8,
                bottom: 14,
                child: GestureDetector(
                  onTap: _jumpBackToCurrent,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xCC12161B),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.22),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          DesktopIcons.play,
                          size: 13,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          isZh ? '回到当前' : 'Current',
                          style: DesktopType.chip(Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _LyricRowItem extends StatelessWidget {
  const _LyricRowItem({
    required this.line,
    required this.isCurrent,
    required this.isHovered,
    required this.distance,
    required this.lyricSize,
    required this.style,
    required this.fillPaint,
    required this.baseOpacity,
    required this.showTranslation,
    required this.activeProgress,
    required this.onHoverChanged,
    required this.onSeek,
  });

  final MusicLyricLine line;
  final bool isCurrent;
  final bool isHovered;
  final int distance;
  final double lyricSize;
  final DesktopNpStyle style;
  final DesktopNpPaint fillPaint;
  final double baseOpacity;
  final bool showTranslation;
  final ValueNotifier<double> activeProgress;
  final ValueChanged<bool> onHoverChanged;
  final VoidCallback onSeek;

  @override
  Widget build(BuildContext context) {
    final textStyle = DesktopType.sectionTitle(Colors.white).copyWith(
      fontSize: lyricSize,
      height: 1.28,
      fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
    );

    final effectiveBaseOp =
        isHovered
            ? (baseOpacity + 0.35).clamp(0.45, 0.92)
            : (distance >= 4
                ? (baseOpacity * 0.65).clamp(0.08, 1.0)
                : baseOpacity);

    Widget lyricBody;
    if (isCurrent) {
      lyricBody = ValueListenableBuilder<double>(
        valueListenable: activeProgress,
        builder: (context, progress, _) {
          return _VisualLineWordFillText(
            text: line.text,
            textStyle: textStyle,
            progress: style.wordFill ? progress : 1.0,
            wordFill: style.wordFill,
            fillPaint: fillPaint,
            basePaint: style.basePaint,
            baseOpacity: baseOpacity,
            glow: style.glow,
          );
        },
      );
    } else {
      lyricBody = ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback:
            (rect) =>
                style.basePaint.createShader(rect, opacity: effectiveBaseOp),
        child: Text(line.text, style: textStyle),
      );
    }

    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        lyricBody,
        if (showTranslation && line.hasTranslation) ...[
          const SizedBox(height: 5),
          Text(
            line.translation!,
            style: DesktopType.dense(
              Colors.white.withValues(
                alpha: isCurrent ? 0.78 : (isHovered ? 0.62 : 0.34),
              ),
            ).copyWith(fontSize: lyricSize * 0.62, height: 1.35),
          ),
        ],
      ],
    );

    // 仅对 1 <= d <= 3 的非悬停近邻行施加焦外模糊（d >= 4 免除 ImageFiltered 防止 saveLayer 掉帧）。
    final blurSigma =
        (!isCurrent && !isHovered && distance >= 1 && distance <= 3)
            ? distance * 0.7
            : 0.0;
    if (blurSigma > 0) {
      content = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: content,
      );
    }

    // 当前行轻度放大 1.06×（左对齐原点）。
    content = AnimatedScale(
      scale: isCurrent ? 1.06 : 1.0,
      alignment: Alignment.centerLeft,
      duration: DesktopMotion.of(context, DesktopMotion.lyricLineScale),
      curve: DesktopMotion.ease,
      child: content,
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHoverChanged(true),
      onExit: (_) => onHoverChanged(false),
      child: GestureDetector(
        onTap: onSeek,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: DesktopMotion.of(context, DesktopMotion.fast),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color:
                isHovered && !isCurrent
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: content),
              if (isHovered && !isCurrent) ...[
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        DesktopIcons.play,
                        size: 11,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatTimestamp(line.position),
                        style: DesktopType.numeric(
                          Colors.white,
                        ).copyWith(fontSize: _translationSize),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(Duration value) {
    final totalSec = value.inSeconds < 0 ? 0 : value.inSeconds;
    final minutes = (totalSec ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSec % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

/// 可视行切片双层渲染组件：将折行后的文本拆成独立可视行，
/// 底层绘 `basePaint`（含 `baseOpacity`），顶层按 `fillPaint` 结合
/// `BlendMode.dstIn` 做水平逐字裁切，实现上下分色/渐变与折行逐字填充完美共存。
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
