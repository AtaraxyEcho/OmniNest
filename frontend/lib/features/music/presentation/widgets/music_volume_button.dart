import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/widgets/app_slider.dart';
import 'package:omninest/features/music/application/music_audio_playback.dart';

/// Music 音量按钮的呈现风格，与所在播放条的按钮语言对齐。
enum MusicVolumeButtonStyle { glass, flat }

/// Music 统一音量控件：圆形音量图标，点击后在按钮上方展开控制条。
///
/// 控制条为横向玻璃胶囊：静音切换 + 滑条 + 百分比。Mini Player 与
/// 沉浸播放详情页共用同一交互与视觉语言。
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
  double _volume = 100;
  bool _hovered = false;

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
    _volumeSub?.cancel();
    if (_portal.isShowing) {
      _portal.hide();
    }
    super.dispose();
  }

  void _togglePanel() {
    if (_portal.isShowing) {
      _portal.hide();
    } else {
      _portal.show();
    }
  }

  void _hidePanel() {
    if (_portal.isShowing) {
      _portal.hide();
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
              child: _MusicVolumeControlPanel(
                volume: _volume,
                accentColor:
                    widget.activeColor ?? iconColor.withValues(alpha: 0.92),
                background: widget.panelBackground,
                textColor:
                    widget.panelTextColor ?? (widget.iconColor ?? Colors.white),
                iconColor: iconColor,
                onChanged: _setVolume,
                onToggleMute: _toggleMute,
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
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
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
        return IconButton(
          tooltip: message,
          onPressed: _togglePanel,
          style:
              _portal.isShowing
                  ? IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.10),
                  )
                  : null,
          icon: icon,
        );
    }
  }
}

/// 音量展开控制条：静音切换 + 横向滑条 + 百分比。
class _MusicVolumeControlPanel extends StatelessWidget {
  const _MusicVolumeControlPanel({
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

  @override
  Widget build(BuildContext context) {
    final muted = volume <= 0;
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 208,
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.36),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Tooltip(
              message: AppLocalizations.of(context).portalMusicVisualizerVolume,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: onToggleMute,
                child: SizedBox.square(
                  dimension: 32,
                  child: Icon(
                    muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    size: 18,
                    color: muted ? iconColor.withValues(alpha: 0.7) : iconColor,
                  ),
                ),
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3.5,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 5.5,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 11,
                  ),
                  activeTrackColor: accentColor,
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.16),
                  thumbColor: textColor,
                  overlayColor: accentColor.withValues(alpha: 0.14),
                  showValueIndicator: ShowValueIndicator.never,
                ),
                child: AppSlider(
                  value: (volume / 100).clamp(0.0, 1.0),
                  onChanged: (next) => onChanged(next * 100),
                ),
              ),
            ),
            SizedBox(
              width: 32,
              child: Text(
                volume.round().toString(),
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: textColor.withValues(alpha: 0.88),
                  fontSize: AppTypography.labelSmall,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
