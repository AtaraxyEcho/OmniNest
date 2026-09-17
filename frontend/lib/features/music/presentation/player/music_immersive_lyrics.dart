import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/music/application/music_audio_playback.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_visualizer_preset.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_style.dart';

/// 显示当前歌词及相邻歌词，并以固定周期驱动当前行呼吸效果。
class MusicImmersiveLyrics extends StatefulWidget {
  const MusicImmersiveLyrics({
    required this.palette,
    required this.player,
    required this.track,
    required this.lyrics,
    required this.scale,
    required this.onTogglePlayback,
    required this.onPrevious,
    required this.onNext,
    this.lyricSettings,
    super.key,
  });

  final MusicImmersivePalette palette;
  final MusicAudioPlayback player;
  final MusicTrack? track;
  final List<MusicLyricLine> lyrics;
  final double scale;
  final PortalLyricVisualSettings? lyricSettings;
  final VoidCallback onTogglePlayback;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  State<MusicImmersiveLyrics> createState() => _MusicImmersiveLyricsState();
}

class _MusicImmersiveLyricsState extends State<MusicImmersiveLyrics> {
  StreamSubscription<Duration>? _positionSubscription;
  int _activeIndex = 0;
  int? _hoveredIndex;

  @override
  void initState() {
    super.initState();
    _activeIndex = _activeLyricIndex(widget.player.state.position);
    _bindPositionStream();
  }

  @override
  void didUpdateWidget(covariant MusicImmersiveLyrics oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.player, widget.player)) {
      _bindPositionStream();
    }
    if (oldWidget.track?.id != widget.track?.id ||
        _lyricsChanged(oldWidget.lyrics, widget.lyrics)) {
      _activeIndex = _activeLyricIndex(widget.player.state.position);
      _hoveredIndex = null;
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
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
    return Focus(
      autofocus: false,
      onKeyEvent: (node, event) => _handleKeyEvent(event),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableHeight = math.max(1.0, constraints.maxHeight);
          final requestedLines = settings.visibleLines.clamp(1, 9).toInt();
          final minimumSlotHeight = 76 * widget.scale * settings.lineSpacing;
          final rawMaxLinesByHeight = math.max(
            1,
            (availableHeight / minimumSlotHeight).floor(),
          );
          final maxLinesByHeight =
              rawMaxLinesByHeight == 2 ? 1 : rawMaxLinesByHeight;
          final resolvedVisibleLines =
              math.min(requestedLines, maxLinesByHeight).clamp(1, 9).toInt();
          final targetHeight =
              resolvedVisibleLines == 1
                  ? (176 * widget.scale).clamp(128.0, 208.0).toDouble()
                  : (104 * widget.scale * settings.lineSpacing)
                      .clamp(72.0, 156.0)
                      .toDouble();
          final slotHeight =
              math
                  .min(availableHeight / resolvedVisibleLines, targetHeight)
                  .clamp(1.0, targetHeight)
                  .toDouble();
          return Center(
            child: SizedBox(
              height: slotHeight * resolvedVisibleLines,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var offset = 0; offset < resolvedVisibleLines; offset++)
                    _buildSlot(
                      _activeIndex - resolvedVisibleLines ~/ 2 + offset,
                      slotHeight,
                      settings,
                    ),
                ],
              ),
            ),
          );
        },
      ),
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
    final line = _MusicLyricLine(
      key: ValueKey<String>('music-lyric-${widget.track?.id}-$index'),
      palette: widget.palette,
      line: widget.lyrics[index],
      active: active,
      read: index < _activeIndex,
      hovered: index == _hoveredIndex,
      scale: widget.scale,
      settings: settings,
      onEnter: () => setState(() => _hoveredIndex = index),
      onExit: () {
        if (_hoveredIndex == index) {
          setState(() => _hoveredIndex = null);
        }
      },
      onTap: () => _seekTo(index),
    );
    return SizedBox(
      height: height,
      child: AnimatedSwitcher(
        duration: MusicImmersiveMotion.duration(
          context,
          const Duration(milliseconds: 240),
        ),
        reverseDuration: MusicImmersiveMotion.duration(
          context,
          const Duration(milliseconds: 160),
        ),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (currentChild, previousChildren) {
          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              ...previousChildren,
              if (currentChild != null) currentChild,
            ],
          );
        },
        transitionBuilder: (child, animation) {
          final slide = Tween<Offset>(
            begin: const Offset(0, 0.16),
            end: Offset.zero,
          ).animate(animation);
          final scale = Tween<double>(begin: 0.96, end: 1).animate(animation);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: slide,
              child: ScaleTransition(scale: scale, child: child),
            ),
          );
        },
        child: KeyedSubtree(
          key: ValueKey<String>(
            'music-lyric-slot-${widget.track?.id}-$index-$active',
          ),
          child: line,
        ),
      ),
    );
  }

  void _bindPositionStream() {
    _positionSubscription?.cancel();
    _positionSubscription = widget.player.stream.position.listen(
      _handlePosition,
    );
  }

  void _handlePosition(Duration position) {
    if (!mounted) {
      return;
    }
    final nextIndex = _activeLyricIndex(position);
    if (nextIndex != _activeIndex) {
      setState(() => _activeIndex = nextIndex);
    }
  }

  int _activeLyricIndex(Duration position) {
    if (widget.lyrics.isEmpty) {
      return 0;
    }
    var low = 0;
    var high = widget.lyrics.length - 1;
    var candidate = 0;
    while (low <= high) {
      final middle = (low + high) >> 1;
      if (widget.lyrics[middle].position <= position) {
        candidate = middle;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return candidate;
  }

  bool _lyricsChanged(
    List<MusicLyricLine> previous,
    List<MusicLyricLine> next,
  ) {
    if (identical(previous, next)) {
      return false;
    }
    if (previous.length != next.length) {
      return true;
    }
    for (var index = 0; index < previous.length; index++) {
      if (previous[index].position != next[index].position ||
          previous[index].text != next[index].text) {
        return true;
      }
    }
    return false;
  }

  void _seekTo(int index) {
    if (index < 0 || index >= widget.lyrics.length) {
      return;
    }
    final position = widget.lyrics[index].position;
    if (_activeIndex != index) {
      setState(() => _activeIndex = index);
    }
    unawaited(widget.player.seek(position));
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.space) {
      widget.onTogglePlayback();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      widget.onPrevious();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      widget.onNext();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _seekTo((_activeIndex - 1).clamp(0, widget.lyrics.length - 1));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _seekTo((_activeIndex + 1).clamp(0, widget.lyrics.length - 1));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}

class _MusicLyricLine extends StatefulWidget {
  const _MusicLyricLine({
    required this.palette,
    required this.line,
    required this.active,
    required this.read,
    required this.hovered,
    required this.scale,
    required this.settings,
    required this.onEnter,
    required this.onExit,
    required this.onTap,
    super.key,
  });

  final MusicImmersivePalette palette;
  final MusicLyricLine line;
  final bool active;
  final bool read;
  final bool hovered;
  final double scale;
  final PortalLyricVisualSettings settings;
  final VoidCallback onEnter;
  final VoidCallback onExit;
  final VoidCallback onTap;

  @override
  State<_MusicLyricLine> createState() => _MusicLyricLineState();
}

class _MusicLyricLineState extends State<_MusicLyricLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breathingController;
  bool _motionDisabled = false;

  @override
  void initState() {
    super.initState();
    _breathingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
      value: 0.25,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motionDisabled = MediaQuery.disableAnimationsOf(context);
    _syncBreathing();
  }

  @override
  void didUpdateWidget(covariant _MusicLyricLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active ||
        oldWidget.settings.breathingEnabled !=
            widget.settings.breathingEnabled) {
      _syncBreathing();
    }
  }

  @override
  void dispose() {
    _breathingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active || !widget.settings.breathingEnabled) {
      return _buildLine(0);
    }
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _breathingController,
        builder: (context, _) {
          final breathing =
              _motionDisabled
                  ? 0.5
                  : Curves.easeInOutSine.transform(_breathingController.value);
          return _buildLine(breathing);
        },
      ),
    );
  }

  Widget _buildLine(double breathing) {
    final activeTextColor = Color(widget.settings.activeColorValue);
    final inactiveTextColor = Color(
      widget.read
          ? widget.settings.readColorValue
          : widget.settings.unreadColorValue,
    );
    final glowColor = Color(widget.settings.glowColorValue);
    final glowIntensity =
        widget.settings.glowIntensity.clamp(0.0, 2.0).toDouble();
    final activeColor =
        Color.lerp(
          activeTextColor,
          Colors.white,
          widget.settings.breathingEnabled ? breathing * 0.08 : 0,
        )!;
    final textStyle = TextStyle(
      color:
          widget.active
              ? activeColor
              : Color.lerp(
                inactiveTextColor.withValues(
                  alpha: widget.settings.inactiveOpacity,
                ),
                inactiveTextColor,
                widget.hovered ? 0.34 : 0,
              ),
      fontSize: (widget.active ? 31.0 : 19.5) * widget.scale,
      height: 1.18,
      fontWeight: widget.active ? FontWeight.w800 : FontWeight.w500,
      shadows:
          widget.settings.shadowEnabled && widget.active
              ? <Shadow>[
                Shadow(
                  color: activeTextColor.withValues(
                    alpha: (0.12 + breathing * 0.08) * glowIntensity,
                  ),
                  blurRadius: (1.5 + breathing * 1.5) * glowIntensity,
                ),
                Shadow(
                  color: glowColor.withValues(
                    alpha: (0.12 + breathing * 0.16) * glowIntensity,
                  ),
                  blurRadius: (8 + breathing * 10) * glowIntensity,
                ),
                Shadow(
                  color: glowColor.withValues(
                    alpha: (0.06 + breathing * 0.12) * glowIntensity,
                  ),
                  blurRadius: (18 + breathing * 20) * glowIntensity,
                ),
              ]
              : null,
    );
    final text = Text(
      widget.line.text,
      key: widget.active ? const ValueKey('music-lyric-active') : null,
      maxLines: 3,
      overflow: TextOverflow.visible,
      textAlign: TextAlign.center,
      style: textStyle,
    );
    final translation = widget.line.translation?.trim();
    final hasTranslation = translation != null && translation.isNotEmpty;
    final content =
        hasTranslation
            ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                text,
                const SizedBox(height: 4),
                Text(
                  translation,
                  maxLines: 2,
                  overflow: TextOverflow.visible,
                  textAlign: TextAlign.center,
                  style: textStyle.copyWith(
                    fontSize: textStyle.fontSize! * 0.52,
                    fontWeight:
                        widget.active ? FontWeight.w600 : FontWeight.w400,
                    height: 1.2,
                  ),
                ),
              ],
            )
            : text;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => widget.onEnter(),
      onExit: (_) => widget.onExit(),
      child: Semantics(
        button: true,
        selected: widget.active,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: widget.onTap,
          child: Center(
            child: Transform.translate(
              key:
                  widget.active
                      ? const ValueKey('music-lyric-reactive-motion')
                      : null,
              offset:
                  widget.active
                      ? Offset(
                        0,
                        -2.4 *
                            breathing *
                            widget.scale *
                            (widget.settings.breathingEnabled ? 1 : 0),
                      )
                      : Offset.zero,
              child: Transform.scale(
                key:
                    widget.active
                        ? const ValueKey('music-lyric-reactive-transform')
                        : null,
                scale:
                    widget.active
                        ? widget.settings.currentFontScale *
                            (widget.settings.breathingEnabled
                                ? 0.985 + breathing * 0.055
                                : 1)
                        : widget.hovered
                        ? 1.025
                        : 1,
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _syncBreathing() {
    if (!widget.active ||
        !widget.settings.breathingEnabled ||
        _motionDisabled) {
      _breathingController.stop();
      return;
    }
    if (!_breathingController.isAnimating) {
      _breathingController.repeat(reverse: true);
    }
  }
}
