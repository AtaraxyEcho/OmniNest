import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/video_colors.dart';
import 'package:omninest/core/widgets/app_slider.dart';

/// 显示播放、缓冲和拖动位置，并在指针悬停时提供时间预览。
class MoviePlayerProgressBar extends StatefulWidget {
  const MoviePlayerProgressBar({
    required this.polledPosition,
    required this.durationSeconds,
    required this.playerDuration,
    required this.bufferProgress,
    required this.isSeeking,
    required this.seekValue,
    required this.onSeekStart,
    required this.onSeeking,
    required this.onSeekEnd,
    required this.onMouseActivity,
    required this.formatDuration,
    super.key,
  });

  final ValueNotifier<Duration> polledPosition;
  final int durationSeconds;
  final Duration playerDuration;
  final ValueListenable<double> bufferProgress;
  final bool isSeeking;
  final double seekValue;
  final void Function(double) onSeekStart;
  final void Function(double) onSeeking;
  final void Function(double) onSeekEnd;
  final VoidCallback onMouseActivity;
  final String Function(Duration) formatDuration;

  @override
  State<MoviePlayerProgressBar> createState() => _MoviePlayerProgressBarState();
}

class _MoviePlayerProgressBarState extends State<MoviePlayerProgressBar> {
  double? _hoverFraction;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Duration>(
      valueListenable: widget.polledPosition,
      builder: (context, polledPosition, _) {
        final duration =
            widget.durationSeconds > 0
                ? Duration(seconds: widget.durationSeconds)
                : widget.playerDuration;
        final position =
            widget.isSeeking
                ? Duration(
                  milliseconds:
                      (widget.seekValue * duration.inMilliseconds).round(),
                )
                : polledPosition;
        final streamProgress =
            duration.inMilliseconds > 0
                ? (position.inMilliseconds / duration.inMilliseconds).clamp(
                  0.0,
                  1.0,
                )
                : 0.0;
        final displayValue =
            widget.isSeeking ? widget.seekValue : streamProgress;
        return LayoutBuilder(
          builder: (context, constraints) {
            final previewFraction =
                widget.isSeeking ? widget.seekValue : _hoverFraction;
            return MouseRegion(
              onHover: (event) {
                final fraction = (event.localPosition.dx / constraints.maxWidth)
                    .clamp(0.0, 1.0);
                if (_hoverFraction != fraction) {
                  setState(() => _hoverFraction = fraction);
                }
                widget.onMouseActivity();
              },
              onExit: (_) => setState(() => _hoverFraction = null),
              child: SizedBox(
                height: 34,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.bottomLeft,
                  children: [
                    _TimelineTrack(
                      displayValue: displayValue,
                      bufferProgress: widget.bufferProgress,
                      isActive: widget.isSeeking || _hoverFraction != null,
                      onSeekStart: widget.onSeekStart,
                      onSeeking: widget.onSeeking,
                      onSeekEnd: widget.onSeekEnd,
                      onMouseActivity: widget.onMouseActivity,
                    ),
                    if (previewFraction != null && duration.inMilliseconds > 0)
                      _TimePreview(
                        fraction: previewFraction,
                        availableWidth: constraints.maxWidth,
                        label: widget.formatDuration(
                          Duration(
                            milliseconds:
                                (duration.inMilliseconds * previewFraction)
                                    .round(),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _TimelineTrack extends StatelessWidget {
  const _TimelineTrack({
    required this.displayValue,
    required this.bufferProgress,
    required this.isActive,
    required this.onSeekStart,
    required this.onSeeking,
    required this.onSeekEnd,
    required this.onMouseActivity,
  });

  final double displayValue;
  final ValueListenable<double> bufferProgress;
  final bool isActive;
  final void Function(double) onSeekStart;
  final void Function(double) onSeeking;
  final void Function(double) onSeekEnd;
  final VoidCallback onMouseActivity;

  @override
  Widget build(BuildContext context) {
    final colors = context.videoColors;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final animDuration =
        reducedMotion ? Duration.zero : const Duration(milliseconds: 180);
    final trackHeight = isActive ? 7.0 : 4.0;
    final trackRadius = trackHeight / 2;
    final clampedValue = displayValue.clamp(0.0, 1.0);
    return SizedBox(
      height: 24,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          final thumbLeft = (maxWidth * clampedValue - 7.0).clamp(
            0.0,
            (maxWidth - 14.0).clamp(0.0, double.infinity),
          );
          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.centerLeft,
            children: [
              // 轨道底色：hover / drag 时 4px → 7px 平滑增高。
              AnimatedContainer(
                duration: animDuration,
                curve: Curves.easeOutCubic,
                height: trackHeight,
                decoration: BoxDecoration(
                  color: colors.playerTimelineInactive,
                  borderRadius: BorderRadius.circular(trackRadius),
                ),
              ),
              // 缓冲轨道：同步 4px → 7px 增高。
              ValueListenableBuilder<double>(
                valueListenable: bufferProgress,
                builder: (context, progress, _) {
                  return AnimatedContainer(
                    duration: animDuration,
                    curve: Curves.easeOutCubic,
                    height: trackHeight,
                    width: maxWidth * progress.clamp(0.0, 1.0),
                    decoration: BoxDecoration(
                      color: colors.playerTimelineBuffered,
                      borderRadius: BorderRadius.circular(trackRadius),
                    ),
                  );
                },
              ),
              // 已播放轨道：同步 4px → 7px 增高。
              AnimatedContainer(
                duration: animDuration,
                curve: Curves.easeOutCubic,
                height: trackHeight,
                width: maxWidth * clampedValue,
                decoration: BoxDecoration(
                  color: colors.playerTimelinePlayed,
                  borderRadius: BorderRadius.circular(trackRadius),
                ),
              ),
              // 交互与无障碍由 AppSlider 承接，视觉轨道与弹簧圆点由自定义层渲染。
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: trackHeight,
                  thumbShape: SliderComponentShape.noThumb,
                  overlayShape: SliderComponentShape.noOverlay,
                  activeTrackColor: Colors.transparent,
                  inactiveTrackColor: Colors.transparent,
                ),
                child: AppSlider(
                  value: clampedValue,
                  onChangeStart: onSeekStart,
                  onChanged: (value) {
                    onSeeking(value);
                    onMouseActivity();
                  },
                  onChangeEnd: onSeekEnd,
                ),
              ),
              // 14px 弹簧圆点滑块：默认 scale(0)，hover/drag 弹至 scale(1)。
              Positioned(
                left: thumbLeft,
                child: IgnorePointer(
                  child: AnimatedScale(
                    scale: isActive ? 1.0 : 0.0,
                    duration:
                        reducedMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 220),
                    curve: isActive ? Curves.easeOutBack : Curves.easeInCubic,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: colors.playerControlForeground,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.45),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TimePreview extends StatelessWidget {
  const _TimePreview({
    required this.fraction,
    required this.availableWidth,
    required this.label,
  });

  final double fraction;
  final double availableWidth;
  final String label;

  @override
  Widget build(BuildContext context) {
    const previewWidth = 62.0;
    final rawLeft = availableWidth * fraction - previewWidth / 2;
    final left = rawLeft.clamp(0.0, availableWidth - previewWidth);
    return Positioned(
      left: left,
      top: -4,
      width: previewWidth,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.videoColors.playerPanelSurface,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            style: TextStyle(
              color: context.videoColors.playerControlForeground,
              fontSize: AppTypography.labelSmall,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}
