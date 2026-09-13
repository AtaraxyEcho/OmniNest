import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/music/application/music_audio_playback.dart';

/// Music 音量按钮的呈现风格，与所在播放条的按钮语言对齐。
enum MusicVolumeButtonStyle { glass, flat }

/// Music 统一音量控件：圆形音量图标，悬停后在按钮上方展开竖向音量柱。
///
/// 交互对齐主流播放器：桌面端悬停即展开，拖动柱条调音量；触屏/点击
/// 仍可切换面板。Mini Player 与沉浸播放详情页共用同一交互与视觉语言。
class MusicVolumeButton extends StatefulWidget {
  const MusicVolumeButton({
    required this.player,
    required this.tooltip,
    this.style = MusicVolumeButtonStyle.glass,
    this.iconColor,
    this.mutedIconColor,
    this.activeColor,
    this.panelBackground = const Color(0xF00E151B),
    this.panelTextColor,
    this.buttonSize = 36,
    this.iconSize = 20,
    super.key,
  });

  final MusicAudioPlayback player;
  final String tooltip;
  final MusicVolumeButtonStyle style;
  final Color? iconColor;
  final Color? mutedIconColor;
  final Color? activeColor;
  final Color panelBackground;
  final Color? panelTextColor;
  final double buttonSize;
  final double iconSize;

  @override
  State<MusicVolumeButton> createState() => _MusicVolumeButtonState();
}

class _MusicVolumeButtonState extends State<MusicVolumeButton> {
  final LayerLink _link = LayerLink();
  final OverlayPortalController _portal = OverlayPortalController();
  StreamSubscription<double>? _volumeSub;
  Timer? _hideTimer;
  double _volume = 100;
  bool _hovered = false;
  bool _pointerOverPanel = false;

  static const _hideDelay = Duration(milliseconds: 160);

  @override
  void initState() {
    super.initState();
    _volume = widget.player.state.volume.clamp(0.0, 100.0).toDouble();
    _volumeSub = widget.player.stream.volume.listen((value) {
      if (mounted) {
        setState(() => _volume = value.clamp(0.0, 100.0).toDouble());
      }
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _volumeSub?.cancel();
    if (_portal.isShowing) {
      _portal.hide();
    }
    super.dispose();
  }

  void _cancelHide() {
    _hideTimer?.cancel();
    _hideTimer = null;
  }

  void _scheduleHide() {
    _cancelHide();
    _hideTimer = Timer(_hideDelay, () {
      if (!mounted) {
        return;
      }
      if (_hovered || _pointerOverPanel) {
        return;
      }
      _hidePanel();
    });
  }

  void _showPanel() {
    _cancelHide();
    if (!_portal.isShowing) {
      _portal.show();
    }
  }

  void _togglePanel() {
    if (_portal.isShowing) {
      _hidePanel();
    } else {
      _showPanel();
    }
  }

  void _hidePanel() {
    if (_portal.isShowing) {
      _portal.hide();
    }
  }

  void _setButtonHovered(bool value) {
    setState(() => _hovered = value);
    if (value) {
      _showPanel();
    } else {
      _scheduleHide();
    }
  }

  void _setPanelHovered(bool value) {
    _pointerOverPanel = value;
    if (value) {
      _showPanel();
    } else {
      _scheduleHide();
    }
  }

  void _setVolume(double value) {
    final next = value.clamp(0.0, 100.0).toDouble();
    widget.player.setVolume(next);
    setState(() => _volume = next);
  }

  void _toggleMute() {
    if (_volume <= 0) {
      _setVolume(50);
    } else {
      _setVolume(0);
    }
  }

  IconData get _volumeIcon {
    if (_volume <= 0) {
      return Icons.volume_off_rounded;
    }
    if (_volume < 50) {
      return Icons.volume_down_rounded;
    }
    return Icons.volume_up_rounded;
  }

  Color _resolveIconColor(BuildContext context) {
    if (_volume <= 0) {
      return widget.mutedIconColor ??
          (widget.iconColor ?? Theme.of(context).iconTheme.color)?.withValues(
            alpha: 0.55,
          ) ??
          Colors.white.withValues(alpha: 0.55);
    }
    if (_portal.isShowing && widget.activeColor != null) {
      return widget.activeColor!;
    }
    return widget.iconColor ??
        Theme.of(context).iconTheme.color ??
        Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = _resolveIconColor(context);
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (overlayContext) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _hidePanel,
              ),
            ),
            CompositedTransformFollower(
              link: _link,
              targetAnchor: Alignment.topCenter,
              followerAnchor: Alignment.bottomCenter,
              offset: const Offset(0, -10),
              child: MouseRegion(
                onEnter: (_) => _setPanelHovered(true),
                onExit: (_) => _setPanelHovered(false),
                child: _MusicVolumeColumn(
                  volume: _volume,
                  accentColor:
                      widget.activeColor ?? iconColor.withValues(alpha: 0.92),
                  background: widget.panelBackground,
                  textColor:
                      widget.panelTextColor ??
                      (widget.iconColor ?? Colors.white),
                  iconColor: iconColor,
                  onChanged: _setVolume,
                  onToggleMute: _toggleMute,
                ),
              ),
            ),
          ],
        );
      },
      child: CompositedTransformTarget(
        link: _link,
        child: _buildButton(context, iconColor: iconColor),
      ),
    );
  }

  Widget _buildButton(BuildContext context, {required Color iconColor}) {
    final message = widget.tooltip;
    final icon = Icon(_volumeIcon, size: widget.iconSize, color: iconColor);
    switch (widget.style) {
      case MusicVolumeButtonStyle.glass:
        return Tooltip(
          message: message,
          child: MouseRegion(
            onEnter: (_) => _setButtonHovered(true),
            onExit: (_) => _setButtonHovered(false),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: _togglePanel,
              child: SizedBox.square(
                dimension: widget.buttonSize,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(
                      alpha: _portal.isShowing || _hovered ? 0.14 : 0.08,
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(
                        alpha: _portal.isShowing ? 0.22 : 0.0,
                      ),
                    ),
                  ),
                  child: Center(child: icon),
                ),
              ),
            ),
          ),
        );
      case MusicVolumeButtonStyle.flat:
        return Tooltip(
          message: message,
          child: MouseRegion(
            onEnter: (_) => _setButtonHovered(true),
            onExit: (_) => _setButtonHovered(false),
            child: IconButton(
              onPressed: _togglePanel,
              style:
                  _portal.isShowing
                      ? IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.10),
                      )
                      : null,
              icon: icon,
            ),
          ),
        );
    }
  }
}

/// 竖向音量柱：底部为当前音量填充，顶部留白；底部附静音与百分比。
class _MusicVolumeColumn extends StatelessWidget {
  const _MusicVolumeColumn({
    required this.volume,
    required this.accentColor,
    required this.background,
    required this.textColor,
    required this.iconColor,
    required this.onChanged,
    required this.onToggleMute,
  });

  final double volume;
  final Color accentColor;
  final Color background;
  final Color textColor;
  final Color iconColor;
  final ValueChanged<double> onChanged;
  final VoidCallback onToggleMute;

  static const double _width = 40;
  static const double _trackHeight = 120;
  static const double _footerHeight = 36;
  static const double _trackWidth = 6;

  @override
  Widget build(BuildContext context) {
    final muted = volume <= 0;
    final normalized = (volume / 100).clamp(0.0, 1.0);
    return Material(
      color: Colors.transparent,
      child: Container(
        width: _width,
        height: _trackHeight + _footerHeight + 12,
        padding: const EdgeInsets.only(top: 10, bottom: 6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.36),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: _VerticalVolumeTrack(
                  value: normalized,
                  trackWidth: _trackWidth,
                  accentColor: accentColor,
                  trackColor: Colors.white.withValues(alpha: 0.16),
                  thumbColor: textColor,
                  onChanged: (next) => onChanged(next * 100),
                ),
              ),
            ),
            SizedBox(
              height: _footerHeight,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Tooltip(
                    message:
                        AppLocalizations.of(
                          context,
                        ).portalMusicVisualizerVolume,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: onToggleMute,
                      child: SizedBox.square(
                        dimension: 22,
                        child: Icon(
                          muted
                              ? Icons.volume_off_rounded
                              : Icons.volume_up_rounded,
                          size: 14,
                          color:
                              muted
                                  ? iconColor.withValues(alpha: 0.7)
                                  : iconColor,
                        ),
                      ),
                    ),
                  ),
                  Text(
                    volume.round().toString(),
                    style: TextStyle(
                      color: textColor.withValues(alpha: 0.80),
                      fontSize: 10,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 竖向拖动音量轨：从底部向上填充，与主流桌面播放器一致。
class _VerticalVolumeTrack extends StatelessWidget {
  const _VerticalVolumeTrack({
    required this.value,
    required this.trackWidth,
    required this.accentColor,
    required this.trackColor,
    required this.thumbColor,
    required this.onChanged,
  });

  final double value;
  final double trackWidth;
  final Color accentColor;
  final Color trackColor;
  final Color thumbColor;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final width = constraints.maxWidth;
        final fillHeight = height * value;
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: (details) {
              final next = (1 - (details.localPosition.dy / height)).clamp(
                0.0,
                1.0,
              );
              onChanged(next);
            },
            onTapDown: (details) {
              final next = (1 - (details.localPosition.dy / height)).clamp(
                0.0,
                1.0,
              );
              onChanged(next);
            },
            child: SizedBox(
              width: width,
              height: height,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: trackWidth,
                    height: height,
                    decoration: BoxDecoration(
                      color: trackColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    child: Container(
                      width: trackWidth,
                      height: fillHeight.clamp(0.0, height),
                      decoration: BoxDecoration(
                        color: accentColor,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: (fillHeight - 5).clamp(0.0, height - 10),
                    child: Container(
                      width: 12,
                      height: 10,
                      decoration: BoxDecoration(
                        color: thumbColor,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.28),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
