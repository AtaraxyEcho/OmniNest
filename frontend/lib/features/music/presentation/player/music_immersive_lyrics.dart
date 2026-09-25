import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui show Gradient;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/music/application/music_audio_playback.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_visualizer_preset.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_layout_spec.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_style.dart';

part 'music_immersive_lyric_line.dart';
part 'music_immersive_lyric_paint.dart';
part 'music_immersive_lyric_fill.dart';
part 'music_immersive_lyric_layout_helpers.dart';
part 'music_immersive_lyrics_layout.dart';
part 'music_immersive_lyric_follow.dart';
part 'music_immersive_lyric_position.dart';
part 'music_immersive_lyric_interaction.dart';
part 'music_immersive_lyric_chrome.dart';

/// 歌词区顶部/底部的渐隐高度（视口高度比例，并做上下限保护）。
const double _edgeFadeHeightRatio = 0.16;
const double _edgeFadeMinHeight = 18;
const double _edgeFadeMaxHeight = 76;

/// 逐行渐变遮罩的行数上限：超长歌词只保留纯色，避免大量离屏图层。
const int _gradientLineLimit = 300;

/// PageUp/PageDown 的跳转行数。
const int _pageStep = 5;

/// 歌词行菜单的动作值：复制歌词、歌词延后与提前。
const String _lineMenuCopy = 'copy';
const String _lineMenuDelayLater = 'delayLater';
const String _lineMenuAdvanceEarlier = 'advanceEarlier';

/// 在读行时间参考的显示格式：样例 `formatTimeDec` 的 `mm:ss.d`（十分之一秒）。
/// 分钟数不取模，与样例一致（超过 60 分钟仍读作 60+）。
String _formatLyricStamp(Duration position) {
  final minutes = position.inMinutes.toString().padLeft(2, '0');
  final seconds = position.inSeconds.remainder(60).toString().padLeft(2, '0');
  final deciseconds = (position.inMilliseconds % 1000) ~/ 100;
  return '$minutes:$seconds.$deciseconds';
}

/// 显示当前歌词及相邻歌词，并以固定周期驱动当前行呼吸效果。
class MusicImmersiveLyrics extends StatefulWidget {
  const MusicImmersiveLyrics({
    required this.palette,
    required this.player,
    required this.track,
    required this.lyrics,
    required this.scale,
    required this.textAlign,
    required this.blockAnchor,
    required this.onTogglePlayback,
    required this.onPrevious,
    required this.onNext,
    required this.onSeek,
    this.lyricSettings,
    this.lyricSpec,
    this.scrollMode = true,
    this.trackOffsetMs,
    this.onAdjustLyricOffset,
    super.key,
  });

  final MusicImmersivePalette palette;
  final MusicAudioPlayback player;

  /// 进度跳转必须经播放会话（`MusicPlaybackSessionController.seekTo`）：
  /// 直接对播放器 seek 会被切歌加载完成时的归零覆盖。
  final Future<void> Function(Duration position) onSeek;
  final MusicTrack? track;
  final List<MusicLyricLine> lyrics;
  final double scale;
  final PortalLyricVisualSettings? lyricSettings;

  /// 复刻参数（桌面沉浸舞台传入）：非 null 时字号、行距、上下渐隐与在读行
  final MusicLyricSpec? lyricSpec;

  /// 曲目级歌词延迟覆盖（设备本地，毫秒）：非 null 时优先于
  final int? trackOffsetMs;

  /// 歌词延迟微调回调（±100ms，由菜单触发）：宿主写入曲目级设备本地覆盖。
  final void Function(int deltaMs)? onAdjustLyricOffset;

  /// 滚动歌词形态在居中锚点下的文本排列：桌面沉浸舞台传 [TextAlign.left]，
  final TextAlign textAlign;

  /// 文字块锚点（随"歌词位置"设置取 centerLeft/center/centerRight）：
  final Alignment blockAnchor;

  /// 滚动歌词模式（设备级偏好，非跨端同步的视觉设置）：
  final bool scrollMode;
  final VoidCallback onTogglePlayback;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  State<MusicImmersiveLyrics> createState() => _MusicImmersiveLyricsState();
}

class _MusicImmersiveLyricsState extends State<MusicImmersiveLyrics>
    with TickerProviderStateMixin {
  /// 扩展方法使用的状态更新入口：mounted 检查后调用 setState。
  void _updateState(VoidCallback update) {
    if (mounted) {
      setState(update);
    }
  }

  StreamSubscription<Duration>? _positionSubscription;
  int _activeIndex = 0;
  int? _hoveredIndex;

  /// 滚动模式资源：连续列表控制器与「手动滚动暂停跟随」状态。
  final ScrollController _scrollController = ScrollController();
  bool _userScrolling = false;
  Timer? _followResumeTimer;
  static const Duration _followResumeDelay = Duration(seconds: 3);

  /// 拖动预览：手指/指针拖动列表时高亮并准备跳转到的行。
  int? _previewIndex;

  /// 跟随动画合并：动画进行中只保留最后一个目标，避免快速 seek 时排队。
  bool _followAnimating = false;
  double? _pendingFollowTarget;

  Duration _lastKnownPosition = Duration.zero;

  /// 词表是否含翻译行：行高预留据此决定（避免每帧扫描词表）。
  bool _hasTranslation = false;

  /// 逐字填充动画：0..1 的填充比例。位置事件逐帧重锚，事件之间按剩余
  late final AnimationController _fillController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1),
  );
  bool _fillActive = false;

  /// 排版度量器：实测整块宽度与最大折行数（含缓存），见 layout part。
  final _MusicLyricsLayout _layout = _MusicLyricsLayout();

  /// 滚动跟随几何：行槽高度、首端留白与焦点锚点（由每次构建写入）。
  double _slotHeight = 0;
  double _leadPadding = 0;
  double _focusAnchor = 0.5;

  @override
  void initState() {
    super.initState();
    _lastKnownPosition = widget.player.state.position;
    _activeIndex = _activeLyricIndex(_lastKnownPosition);
    _syncExtraLyrics();
    _bindPositionStream();
  }

  @override
  void didUpdateWidget(covariant MusicImmersiveLyrics oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.player, widget.player)) {
      _bindPositionStream();
    }
    final oldSettings =
        oldWidget.lyricSettings ?? PortalLyricVisualSettings.defaults;
    final settings = widget.lyricSettings ?? PortalLyricVisualSettings.defaults;
    if (oldWidget.track?.id != widget.track?.id ||
        _lyricsChanged(oldWidget.lyrics, widget.lyrics)) {
      _activeIndex = _activeLyricIndex(widget.player.state.position);
      _hoveredIndex = null;
      _previewIndex = null;
      _syncExtraLyrics();
      // 曲目或词表变化后旧填充数据全部失效，等待下一次位置事件重锚。
      if (_fillController.isAnimating) {
        _fillController.stop();
      }
      _syncFill(widget.player.state.position);
      return;
    }
    // 生效延迟变化（曲目级覆盖或全局校准）后当前行可能落到别的行上，
    if (_effectiveOffsetMs(
          oldSettings,
          trackOffsetMs: oldWidget.trackOffsetMs,
        ) !=
        _effectiveOffsetMs(settings, trackOffsetMs: widget.trackOffsetMs)) {
      _activeIndex = _activeLyricIndex(widget.player.state.position);
    }
    _syncFill(widget.player.state.position);
  }

  /// 词表是否含译文行（行高预留与附加行渲染据此决定）。
  void _syncExtraLyrics() {
    var hasTranslation = false;
    for (final line in widget.lyrics) {
      final translation = line.translation?.trim();
      if (translation != null && translation.isNotEmpty) {
        hasTranslation = true;
        break;
      }
    }
    _hasTranslation = hasTranslation;
  }

  /// 每行除原文外需要渲染的附加行数（当前只有译文）。
  int _extraLineCount(PortalLyricVisualSettings settings) {
    return settings.translationEnabled && _hasTranslation ? 1 : 0;
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _followResumeTimer?.cancel();
    _scrollController.dispose();
    _fillController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    if (track == null) {
      return Center(
        child: Text(
          AppLocalizations.of(context).musicNotPlaying,
          style: TextStyle(
            color: widget.palette.muted,
            fontSize: AppTypography.titleLarge * widget.scale,
          ),
        ),
      );
    }
    if (widget.lyrics.isEmpty) {
      return Center(
        child: Text(
          track.title,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: widget.palette.text,
            fontSize: AppTypography.displaySmall * widget.scale,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }
    final settings = widget.lyricSettings ?? PortalLyricVisualSettings.defaults;
    final spec = widget.lyricSpec;
    return Semantics(
      container: true,
      // 读屏用户只关心当前句：整个歌词区的语义收敛为一个节点，
      label: AppLocalizations.of(context).musicLyricSemanticsCurrent(
        widget.lyrics[_activeIndex.clamp(0, widget.lyrics.length - 1)].text,
      ),
      child: Focus(
        autofocus: false,
        onKeyEvent: (node, event) => _handleKeyEvent(event),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableHeight = math.max(1.0, constraints.maxHeight);
            // 排版度量必须先于行槽高度：行槽要按最长一行的折行数预留。
            _layout.syncMetrics(
              lyrics: widget.lyrics,
              availableWidth: constraints.maxWidth,
              scrollMode: widget.scrollMode,
              fontSizePx: settings.fontSizePx,
              currentFontSizePx: settings.currentFontSizePx,
              textDirection: Directionality.of(context),
              ambientStyle: DefaultTextStyle.of(context).style,
              textScaler: MediaQuery.textScalerOf(context),
              spec: spec,
            );
            // 行高由内容决定（基准文字行高 + 行距间隙），"行数"只属于
            final slotHeight = _layout.contentSlotHeight(
              settings,
              scrollMode: widget.scrollMode,
              extraLineCount: _extraLineCount(settings),
              spec: spec,
            );
            if (widget.scrollMode) {
              return _buildScrollLyrics(
                availableHeight: availableHeight,
                slotHeight: slotHeight,
                settings: settings,
              );
            }
            // 多行歌词形态：行数即每页行数，行高仍由内容决定，页内垂直居中。
            final requestedLines =
                (spec?.fixedWindowLines ?? 0) > 0
                    ? spec!.fixedWindowLines
                    : settings.visibleLines.clamp(1, 9).toInt();
            // 极矮窗口容不下单个行槽时，把行槽钳制到可用高度以内：
            // 行内容（文字盒）仍远小于行槽，只是留白被压缩，不会溢出。
            final effectiveSlot = math.min(slotHeight, availableHeight);
            final maxLinesByHeight = math.max(
              1,
              (availableHeight / effectiveSlot).floor(),
            );
            final resolvedVisibleLines =
                math.min(requestedLines, maxLinesByHeight).clamp(1, 9).toInt();
            return ExcludeSemantics(
              child: _LyricEdgeFade(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (
                        var offset = 0;
                        offset < resolvedVisibleLines;
                        offset++
                      )
                        _buildSlot(
                          _activeIndex - resolvedVisibleLines ~/ 2 + offset,
                          effectiveSlot,
                          settings,
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// 三端一致的滚动歌词：连续列表呈现全部歌词，当前行跟随焦点位；
  Widget _buildScrollLyrics({
    required double availableHeight,
    required double slotHeight,
    required PortalLyricVisualSettings settings,
  }) {
    // 首尾留白等于"焦点位到边缘的距离"：首行与末行同样能滚到焦点位。
    final anchor = settings.focusAnchor.clamp(0.35, 0.65).toDouble();
    final listPadding = math.max(
      8.0,
      availableHeight * anchor - slotHeight / 2,
    );
    _slotHeight = slotHeight;
    _leadPadding = listPadding;
    _focusAnchor = anchor;
    _scheduleFollowActive();
    return Stack(
      children: [
        // 渐隐遮罩只作用于歌词列表：回到当前按钮放在遮罩之外，不被压淡。
        _LyricEdgeFade(
          mask: widget.lyricSpec?.mask,
          child: ExcludeSemantics(
            // 滚动列表每帧增删行节点，会让 Windows 辅助功能桥持续报
            child: NotificationListener<ScrollNotification>(
              onNotification:
                  (notification) => _handleScrollNotification(
                    notification,
                    slotHeight: slotHeight,
                    leadPadding: listPadding,
                    anchor: anchor,
                  ),
              child: ScrollConfiguration(
                // 样例歌词滚动区是 `.no-scrollbar`：滚动条会压在最左/最右行的
                // 文字上，三端统一隐藏，滚动仍可用（滚轮、拖拽、键盘）。
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(scrollbars: false),
                child: ListView.builder(
                  controller: _scrollController,
                  physics: const ClampingScrollPhysics(),
                  padding: EdgeInsets.symmetric(vertical: listPadding),
                  itemCount: widget.lyrics.length,
                  // 行槽等高：给出固定 extent 让列表跳过逐项布局测量。
                  itemExtent: slotHeight,
                  itemBuilder:
                      (context, index) =>
                          _buildSlot(index, slotHeight, settings),
                ),
              ),
            ),
          ),
        ),
        if (_userScrolling)
          Positioned(
            right: 8,
            bottom: 20,
            child: _BackToCurrentButton(
              palette: widget.palette,
              tooltip: AppLocalizations.of(context).musicLyricBackToCurrent,
              onTap: _backToCurrent,
            ),
          ),
      ],
    );
  }

  Widget _buildSlot(
    int index,
    double height,
    PortalLyricVisualSettings settings,
  ) {
    if (index < 0 || index >= widget.lyrics.length) {
      return SizedBox(height: height);
    }
    final active = index == _activeIndex;
    final blockWidth = _layout.blockWidth;
    final line = widget.lyrics[index];
    final spec = widget.lyricSpec;
    final lyricLine = _MusicLyricLine(
      key: ValueKey<String>('music-lyric-${widget.track?.id}-$index'),
      line: line,
      active: active,
      hovered: index == _hoveredIndex,
      scale: widget.scale,
      spec: spec,
      // 在读行时间参考行的强调色（样例 text-primary）。
      accentColor: widget.palette.accent,
      // 与在读行的行号差：复刻形态据此取样例的不透明度档位。
      relativeIndex: index - _activeIndex,
      fontSize: _layout.lineFontSize(
        settings,
        active: false,
        scrollMode: widget.scrollMode,
        spec: spec,
      ),
      activeFontSize: _layout.lineFontSize(
        settings,
        active: true,
        scrollMode: widget.scrollMode,
        spec: spec,
      ),
      settings: settings,
      textAlign: widget.scrollMode ? _effectiveTextAlign : TextAlign.center,
      scrollMode: widget.scrollMode,
      // 拖动预览命中行轻放大；焦点带只挂在滚动形态的在读行上。
      preview: index == _previewIndex,
      // 复刻形态的在读行自带样例底衬，不再叠加焦点带。
      focusBand:
          spec == null &&
          widget.scrollMode &&
          settings.focusBandEnabled &&
          index == _activeIndex,
      // 超长歌词关闭逐行渐变遮罩，避免大量离屏图层。
      gradientAllowed: widget.lyrics.length <= _gradientLineLimit,
      // 逐字填充：滚动形态、开关开启且在读行可估算进度（词级数据或按
      // 行时长估算）时推进；数据缺失时由渲染层按行时长线性回退。
      fillAnimation:
          active
              ? _fillAnimationFor(line, settings, _lineDurationFor(index))
              : null,
      // 非居中锚点（居左/居右）时各行按同一块宽度渲染，共享同一侧基线。
      blockWidth: blockWidth,
      blockAnchor: widget.blockAnchor,
      onEnter: () => setState(() => _hoveredIndex = index),
      onExit: () {
        if (_hoveredIndex == index) {
          setState(() => _hoveredIndex = null);
        }
      },
      onTap: () => _seekTo(index),
      onMenu: (position) => _showLineMenu(index, position),
    );
    // 行状态切换（在读 ⇆ 非当前句）必须原地更新：逐字填充让两份文本
    // 视觉可区分（在读色 + 填充边界 vs 非当前句色），若走 AnimatedSwitcher
    // 交叉淡化，新旧两份同文异色副本会在淡化期间错位堆叠（"叠字"）。
    // 换行的滚动动效由跟随滚动动画承担，行内不再叠加二次动画。
    final lineContent = KeyedSubtree(
      key: ValueKey<String>(
        'music-lyric-slot-${widget.track?.id}-$index-$active',
      ),
      child: lyricLine,
    );
    // 行槽高度已包含内容裕量与行距；极矮窗口下由 multiline 分支把行槽
    // 钳制到可用高度以内，保证不产生 RenderFlex 溢出。
    return SizedBox(height: height, child: lineContent);
  }
}
