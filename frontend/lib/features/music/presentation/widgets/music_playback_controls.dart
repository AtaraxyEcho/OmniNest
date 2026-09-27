import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/music/application/music_audio_playback.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/core/widgets/app_slider.dart';
import 'package:omninest/app/theme/feature/music_chrome_colors.dart';

/// Music 播放按钮的视觉层级。
enum MusicPlaybackButtonSize { regular, compact, inline }

/// Music 模块统一使用的播放与暂停按钮。
class MusicPlaybackButton extends StatefulWidget {
  const MusicPlaybackButton({
    required this.isPlaying,
    required this.tooltip,
    required this.onPressed,
    this.buttonSize = MusicPlaybackButtonSize.regular,
    this.backgroundColor = MusicChromeColors.tealDeep,
    this.accentColor = MusicChromeColors.tealSoft,
    this.foregroundColor = MusicChromeColors.nearWhite,
    super.key,
  });

  final bool isPlaying;
  final String tooltip;
  final VoidCallback? onPressed;
  final MusicPlaybackButtonSize buttonSize;
  final Color backgroundColor;
  final Color accentColor;
  final Color foregroundColor;

  @override
  State<MusicPlaybackButton> createState() => _MusicPlaybackButtonState();
}

class _MusicPlaybackButtonState extends State<MusicPlaybackButton> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final viewport = MediaQuery.maybeSizeOf(context);
    final constrainedViewport =
        viewport != null && (viewport.width < 600 || viewport.height < 600);
    final diameter = switch (widget.buttonSize) {
      MusicPlaybackButtonSize.regular => constrainedViewport ? 38.0 : 40.0,
      MusicPlaybackButtonSize.compact => constrainedViewport ? 34.0 : 36.0,
      MusicPlaybackButtonSize.inline => constrainedViewport ? 26.0 : 28.0,
    };
    final scale = _pressed ? 0.95 : (_hovered && enabled ? 1.035 : 1.0);
    // 播放三角在视觉重心偏左，相对暂停/图标略微右移做光学居中。
    final iconSize = (diameter * 0.52).clamp(14.0, 22.0);
    final iconOffset =
        widget.isPlaying ? Offset.zero : Offset(iconSize * 0.1, 0);
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.tooltip,
      child: Tooltip(
        message: widget.tooltip,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit:
              (_) => setState(() {
                _hovered = false;
                _pressed = false;
              }),
          child: AnimatedScale(
            scale: scale,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              width: diameter,
              height: diameter,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // 无播放数据（禁用）时用扁平中性盘，避免亮色渐变盘误导可点性。
                gradient:
                    enabled
                        ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[
                            Color.lerp(
                              widget.backgroundColor,
                              widget.accentColor,
                              _hovered ? 0.34 : 0.20,
                            )!,
                            widget.backgroundColor,
                          ],
                        )
                        : null,
                color: enabled ? null : Colors.white.withValues(alpha: 0.06),
                border: Border.all(
                  color:
                      _focused
                          ? widget.foregroundColor.withValues(alpha: 0.90)
                          : enabled
                          ? widget.accentColor.withValues(
                            alpha: _hovered ? 0.68 : 0.42,
                          )
                          : Colors.white.withValues(alpha: 0.10),
                  width: _focused ? 1.8 : 1,
                ),
                boxShadow:
                    enabled
                        ? <BoxShadow>[
                          BoxShadow(
                            color: widget.accentColor.withValues(
                              alpha: _hovered ? 0.24 : 0.12,
                            ),
                            blurRadius: _hovered ? 18 : 11,
                            offset: const Offset(0, 4),
                          ),
                          BoxShadow(
                            color: const Color(
                              0xFF02070A,
                            ).withValues(alpha: 0.34),
                            blurRadius: 9,
                            offset: const Offset(0, 4),
                          ),
                        ]
                        : const <BoxShadow>[],
              ),
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: widget.onPressed,
                  onFocusChange: (value) => setState(() => _focused = value),
                  onHighlightChanged:
                      enabled
                          ? (value) => setState(() => _pressed = value)
                          : null,
                  splashColor: widget.foregroundColor.withValues(alpha: 0.16),
                  highlightColor: widget.foregroundColor.withValues(
                    alpha: 0.08,
                  ),
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      transitionBuilder:
                          (child, animation) => FadeTransition(
                            opacity: animation,
                            child: ScaleTransition(
                              scale: Tween<double>(
                                begin: 0.82,
                                end: 1,
                              ).animate(animation),
                              child: child,
                            ),
                          ),
                      child: Transform.translate(
                        key: ValueKey<bool>(widget.isPlaying),
                        offset: iconOffset,
                        child: Icon(
                          widget.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: iconSize,
                          color:
                              enabled
                                  ? widget.foregroundColor
                                  : widget.foregroundColor.withValues(
                                    alpha: 0.42,
                                  ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Music 模块统一使用的播放进度条。
///
/// 拖动期间用本地值呈现，避免展示层位置节流导致滑块回弹。
class MusicPlaybackProgressBar extends StatefulWidget {
  const MusicPlaybackProgressBar({
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
    this.activeColor = MusicChromeColors.tealSoft,
    this.inactiveColor = MusicChromeColors.inactiveTrack,
    this.thumbColor = MusicChromeColors.nearWhite,
    super.key,
  });

  final double value;
  final ValueChanged<double>? onChanged;
  final String semanticLabel;
  final Color activeColor;
  final Color inactiveColor;
  final Color thumbColor;

  @override
  State<MusicPlaybackProgressBar> createState() =>
      _MusicPlaybackProgressBarState();
}

class _MusicPlaybackProgressBarState extends State<MusicPlaybackProgressBar> {
  double? _dragValue;
  Timer? _dragReleaseTimer;

  @override
  void dispose() {
    _dragReleaseTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MusicPlaybackProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final drag = _dragValue;
    // 位置流追上拖动值后交还给外部状态，避免节流窗口内回弹。
    if (drag != null && (widget.value - drag).abs() < 0.002) {
      _dragReleaseTimer?.cancel();
      _dragValue = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = (_dragValue ?? widget.value).clamp(0.0, 1.0);
    return Semantics(
      label: widget.semanticLabel,
      slider: true,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 4,
          activeTrackColor: widget.activeColor,
          inactiveTrackColor: widget.inactiveColor,
          disabledActiveTrackColor: widget.activeColor.withValues(alpha: 0.32),
          disabledInactiveTrackColor: widget.inactiveColor.withValues(
            alpha: 0.54,
          ),
          thumbColor: widget.thumbColor,
          disabledThumbColor: widget.thumbColor.withValues(alpha: 0.42),
          overlayColor: widget.activeColor.withValues(alpha: 0.16),
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.5),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          trackShape: const RoundedRectSliderTrackShape(),
          showValueIndicator: ShowValueIndicator.never,
        ),
        child: AppSlider(
          value: value,
          onChangeStart:
              widget.onChanged == null
                  ? null
                  : (_) {
                    _dragReleaseTimer?.cancel();
                    setState(() => _dragValue = widget.value);
                  },
          onChanged:
              widget.onChanged == null
                  ? null
                  : (next) {
                    setState(() => _dragValue = next);
                    widget.onChanged!(next);
                  },
          onChangeEnd:
              widget.onChanged == null
                  ? null
                  : (next) {
                    // 保留拖动值至位置流追上；流停更时定时收回，避免滑块卡死。
                    setState(() => _dragValue = next);
                    widget.onChanged!(next);
                    _dragReleaseTimer?.cancel();
                    _dragReleaseTimer = Timer(
                      const Duration(milliseconds: 400),
                      () {
                        if (mounted && _dragValue != null) {
                          setState(() => _dragValue = null);
                        }
                      },
                    );
                  },
        ),
      ),
    );
  }
}

/// 播放模式轮换按钮：顺序播放 / 随机播放 / 单曲循环三态只更换图标与着色，
/// 点击后不保留选中底色（与主流播放器一致）。
class MusicPlayModeButton extends StatefulWidget {
  const MusicPlayModeButton({
    required this.playMode,
    required this.onTap,
    required this.idleColor,
    required this.activeColor,
    this.iconSize = 20,
    this.padding = 4,
    super.key,
  });

  final MusicPlayMode playMode;
  final VoidCallback? onTap;

  /// 顺序档（默认）的图标色；随机与单曲循环档用 [activeColor] 强调。
  final Color idleColor;
  final Color activeColor;
  final double iconSize;
  final double padding;

  /// 模式图标：三态互斥，每档一个图标。
  static IconData iconFor(MusicPlayMode playMode) {
    return switch (playMode) {
      MusicPlayMode.sequential => Icons.repeat_rounded,
      MusicPlayMode.shuffle => Icons.shuffle_rounded,
      MusicPlayMode.repeatOne => Icons.repeat_one_rounded,
    };
  }

  /// 模式文案：Tooltip 与读屏标签共用同一来源，避免两处措辞分叉。
  static String labelFor(AppLocalizations l10n, MusicPlayMode playMode) {
    return switch (playMode) {
      MusicPlayMode.sequential => l10n.musicPlayModeSequential,
      MusicPlayMode.shuffle => l10n.musicShuffle,
      MusicPlayMode.repeatOne => l10n.musicRepeatOne,
    };
  }

  @override
  State<MusicPlayModeButton> createState() => _MusicPlayModeButtonState();
}

class _MusicPlayModeButtonState extends State<MusicPlayModeButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final label = MusicPlayModeButton.labelFor(
      AppLocalizations.of(context),
      widget.playMode,
    );
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 160);
    final isActive = widget.playMode != MusicPlayMode.sequential;
    return Semantics(
      button: true,
      enabled: widget.onTap != null,
      label: label,
      child: Tooltip(
        message: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: widget.onTap,
          onHighlightChanged: (highlighted) {
            if (highlighted != _pressed) {
              setState(() => _pressed = highlighted);
            }
          },
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          child: AnimatedScale(
            scale: _pressed ? 0.88 : 1,
            duration: duration,
            curve: Curves.easeOutCubic,
            child: Padding(
              padding: EdgeInsets.all(widget.padding),
              child: AnimatedSwitcher(
                duration: duration,
                switchInCurve: Curves.easeOutCubic,
                child: Icon(
                  MusicPlayModeButton.iconFor(widget.playMode),
                  key: ValueKey<MusicPlayMode>(widget.playMode),
                  size: widget.iconSize,
                  color: isActive ? widget.activeColor : widget.idleColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 将播放位置流节流到约 8Hz 的展示构建器。
///
/// 原始位置流保持高频（歌词逐字填充依赖）；进度条与时间文本按展示节流重建。
/// 拖动中的值由进度条本地状态呈现，松手后跟流，避免节流导致回弹。
class MusicThrottledPositionBuilder extends StatefulWidget {
  const MusicThrottledPositionBuilder({
    required this.player,
    required this.builder,
    this.interval = const Duration(milliseconds: 120),
    super.key,
  });

  final MusicAudioPlayback player;
  final Duration interval;
  final Widget Function(BuildContext context, Duration position) builder;

  @override
  State<MusicThrottledPositionBuilder> createState() =>
      _MusicThrottledPositionBuilderState();
}

class _MusicThrottledPositionBuilderState
    extends State<MusicThrottledPositionBuilder> {
  StreamSubscription<Duration>? _positionSub;
  Timer? _trailingTimer;
  Duration _position = Duration.zero;
  Duration? _pending;
  DateTime _lastPaint = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _position = widget.player.state.position;
    _bind();
  }

  @override
  void didUpdateWidget(covariant MusicThrottledPositionBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.player, widget.player)) {
      _positionSub?.cancel();
      _trailingTimer?.cancel();
      _pending = null;
      _position = widget.player.state.position;
      _bind();
    }
  }

  @override
  void dispose() {
    _trailingTimer?.cancel();
    unawaited(_positionSub?.cancel());
    super.dispose();
  }

  void _bind() {
    _positionSub = widget.player.stream.position.listen(_onPosition);
  }

  void _onPosition(Duration position) {
    final now = DateTime.now();
    if (now.difference(_lastPaint) >= widget.interval) {
      _trailingTimer?.cancel();
      _trailingTimer = null;
      _pending = null;
      _lastPaint = now;
      if (mounted && position != _position) {
        setState(() => _position = position);
      } else {
        _position = position;
      }
      return;
    }
    _pending = position;
    _trailingTimer ??= Timer(widget.interval, _flushPending);
  }

  void _flushPending() {
    _trailingTimer = null;
    final pending = _pending;
    _pending = null;
    if (pending == null || !mounted) {
      return;
    }
    _lastPaint = DateTime.now();
    if (pending != _position) {
      setState(() => _position = pending);
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _position);
  }
}
