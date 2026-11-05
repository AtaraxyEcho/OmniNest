part of 'photo_detail_page.dart';

extension _PhotoDetailStage on _PhotoDetailBodyState {
  Widget _buildPhotoStage(
    BuildContext context,
    PhotoItem photo,
    int index,
    int total, {
    required EdgeInsets stagePadding,
    required double badgeBottom,
    required double imageRadius,
    required bool hosted,
  }) {
    final imageUrl = photo.sourceUrl ?? photo.coverUrl;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final viewBackground =
        hosted
            ? photoViewerHostedStageColor
            : isDark
            ? FramePalette.viewerBg
            : context.photosColors.surfaceContainerLow;
    return ColoredBox(
      // 托管态取样例 photo-viewer 实底，工位暗色取设计稿查看器底色，
      // 亮色跟随主题浅色底。
      color: viewBackground,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              // 动态照片：长按快速预览运动视频，松手回到静态帧。
              onLongPressStart:
                  photo.isMotionReady ? (_) => _setMotionHold(true) : null,
              onLongPressEnd:
                  photo.isMotionReady ? (_) => _setMotionHold(false) : null,
              onLongPressCancel:
                  photo.isMotionReady ? () => _setMotionHold(false) : null,
              child: Padding(
                // 舞台留白由调用方按形态给定：工位四周 40/56/40/24，
                // 托管按样例 photo-stage 窄留白并避开横幅与动作行。
                padding: stagePadding,
                child: Center(
                  child: AnimatedScale(
                    scale: _motionHoldPlaying ? 1.02 : 1.0,
                    duration: MotionToken.reduced(
                      context,
                      MotionToken.pageSwitch,
                    ),
                    curve: MotionToken.curve,
                    child:
                        imageUrl != null && imageUrl.isNotEmpty
                            ? Hero(
                              tag: 'photo-cover-${photo.id}',
                              // Default Material flight + InteractiveViewer
                              // Transform can leave a diagonal white seam.
                              // Fly the destination child without extra chrome.
                              flightShuttleBuilder:
                                  (
                                    flightContext,
                                    animation,
                                    flightDirection,
                                    fromHeroContext,
                                    toHeroContext,
                                  ) => (toHeroContext.widget as Hero).child,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  imageRadius,
                                ),
                                clipBehavior: Clip.hardEdge,
                                child: InteractiveViewer(
                                  minScale: 1,
                                  maxScale: 5,
                                  clipBehavior: Clip.hardEdge,
                                  child: SizedBox.expand(
                                    child: _ProgressivePhotoImage(photo: photo),
                                  ),
                                ),
                              ),
                            )
                            : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.photo_outlined,
                                  color: context.photosColors.onSurfaceVariant
                                      .withValues(alpha: 0.4),
                                  size: 64,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  photo.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color:
                                        context.photosColors.onSurfaceVariant,
                                    fontSize: AppTypography.titleMedium,
                                  ),
                                ),
                              ],
                            ),
                  ),
                ),
              ),
            ),
          ),
          // 动态照片：运动视频播放层（长按或点按徽标触发），盖在照片上方、箭头之下。
          if (photo.isMotionReady &&
              (_motionHoldPlaying || _motionPinnedPlaying))
            Positioned.fill(
              child: GestureDetector(
                onTap: () => _setMotionPinned(false),
                child: PhotoMotionPlayer(
                  key: ValueKey('motion-${photo.id}'),
                  url: photo.motionVideoUrl!,
                  onError: _handleMotionPlayError,
                ),
              ),
            ),
          // LIVE 徽标：常驻播放开关。
          if (photo.isMotionReady)
            Positioned(
              left: hosted ? 16 : 24,
              bottom: badgeBottom,
              child: _MotionBadge(
                active: _motionPinnedPlaying,
                label: AppLocalizations.of(context).photosLiveBadge,
                tooltip: AppLocalizations.of(context).photosLiveBadgeTooltip,
                onTap: () => _setMotionPinned(!_motionPinnedPlaying),
              ),
            ),
          // 圆形翻页钮（样例 photo-nav）：各宽度档常驻，仅首尾页隐藏。
          if (index > 0)
            PhotoViewerArrowButton(
              icon: Icons.chevron_left_rounded,
              tooltip: AppLocalizations.of(context).photosPrevPhoto,
              alignRight: false,
              onTap: () => _goToPage(index - 1),
            ),
          if (index < total - 1)
            PhotoViewerArrowButton(
              icon: Icons.chevron_right_rounded,
              tooltip: AppLocalizations.of(context).photosNextPhoto,
              alignRight: true,
              onTap: () => _goToPage(index + 1),
            ),
        ],
      ),
    );
  }
}
