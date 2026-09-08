import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/photos_colors.dart';

/// 幻灯片控制覆盖层
class SlideshowControls extends StatelessWidget {
  const SlideshowControls({
    required this.isPlaying,
    required this.currentIndex,
    required this.totalCount,
    required this.speedSeconds,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
    required this.onSpeedChanged,
    required this.onClose,
    super.key,
  });

  final bool isPlaying;
  final int currentIndex;
  final int totalCount;
  final int speedSeconds;
  final VoidCallback onPlayPause;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<int> onSpeedChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 顶部关闭按钮：与查看器箭头一致的描边方块
        Positioned(
          top: 16,
          right: 16,
          child: Material(
            color: Colors.black.withValues(alpha: 0.45),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.24)),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onClose,
              child: Tooltip(
                message: AppLocalizations.of(context).coreClose,
                child: SizedBox(
                  width: 42,
                  height: 42,
                  child: Icon(
                    Icons.close_rounded,
                    size: 22,
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                ),
              ),
            ),
          ),
        ),
        // 底部控制栏
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [context.photosColors.overlay, Colors.transparent],
              ),
            ),
            child: Row(
              children: [
                // 上一张
                IconButton(
                  tooltip: AppLocalizations.of(context).corePrevious,
                  onPressed: onPrevious,
                  icon: Icon(
                    Icons.skip_previous_rounded,
                    color: context.photosColors.slideshowText,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 8),
                // 播放/暂停
                IconButton(
                  tooltip:
                      isPlaying
                          ? AppLocalizations.of(context).corePause
                          : AppLocalizations.of(context).corePlay,
                  onPressed: onPlayPause,
                  icon: Icon(
                    isPlaying
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_filled_rounded,
                    color: context.photosColors.slideshowText,
                    size: 48,
                  ),
                ),
                const SizedBox(width: 8),
                // 下一张
                IconButton(
                  tooltip: AppLocalizations.of(context).coreNext,
                  onPressed: onNext,
                  icon: Icon(
                    Icons.skip_next_rounded,
                    color: context.photosColors.slideshowText,
                    size: 32,
                  ),
                ),
                const Spacer(),
                // 页码
                Text(
                  '${currentIndex + 1} / $totalCount',
                  style: TextStyle(
                    color: context.photosColors.slideshowText,
                    fontSize: AppTypography.bodyLarge,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 16),
                // 速度选择
                DropdownButton<int>(
                  value: speedSeconds,
                  dropdownColor: context.photosColors.overlay,
                  underline: const SizedBox.shrink(),
                  icon: Icon(
                    Icons.speed_rounded,
                    color: context.photosColors.slideshowMuted,
                    size: 20,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 3,
                      child: Text(
                        AppLocalizations.of(context).photosSlideshow3s,
                        style: TextStyle(
                          color: context.photosColors.slideshowText,
                          fontSize: AppTypography.bodyMedium,
                        ),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 5,
                      child: Text(
                        AppLocalizations.of(context).photosSlideshow5s,
                        style: TextStyle(
                          color: context.photosColors.slideshowText,
                          fontSize: AppTypography.bodyMedium,
                        ),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 10,
                      child: Text(
                        AppLocalizations.of(context).photosSlideshow10s,
                        style: TextStyle(
                          color: context.photosColors.slideshowText,
                          fontSize: AppTypography.bodyMedium,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) onSpeedChanged(v);
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
