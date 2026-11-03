part of 'photo_slideshow_page.dart';

/// 幻灯片画面层：照片舞台与右侧信息面板。

/// 扩展成员不算 State 实例成员，改状态必须走 _updateState，不能直接调 setState。
extension _PhotoSlideshowPageChrome on _PhotoSlideshowPageState {
  /// 舞台内容（照片层、控件与面板）：由 build 挂入场扩缩之下。
  Widget _buildStage(BuildContext context, PhotoItem photo, bool showControls) {
    return Stack(
      fit: StackFit.expand,
      children: [
        switch (_phase) {
          SlideshowPhase.loading => SlideshowLoadingStage(photo: photo),
          SlideshowPhase.failed => SlideshowErrorRetry(
            onRetry: () => unawaited(_retryInitialLoad()),
          ),
          SlideshowPhase.ready => Stack(
            fit: StackFit.expand,
            children: [
              SlideshowBackdropLayers(
                transition: _transitionFade,
                transitioning: _transitioning,
                leavingFrame: _leavingFrame,
                enteringFrame: _currentFrame,
              ),
              SlideshowSlideLayers(
                transition: _transitionFade,
                transitioning: _transitioning,
                leavingFrame: _leavingFrame,
                enteringFrame: _currentFrame,
              ),
            ],
          ),
        },
        SlideshowGradients(visible: showControls),
        PhotoSlideshowTopBar(
          photo: photo,
          current: _current,
          total: _photos.length,
          visible: showControls,
          showInfo: _showInfo,
          showShare: _showShare,
          onClose: () => Navigator.of(context).maybePop(),
          onToggleFavorite: () => _toggleFavorite(photo),
          onToggleShare:
              () => _updateState(() {
                _showShare = !_showShare;
                if (_showShare) _showInfo = false;
              }),
          onDownload: () => unawaited(_downloadPhoto(photo)),
          onToggleInfo: () => _updateState(() => _showInfo = !_showInfo),
          onFullscreen: _toggleFullscreen,
        ),
        if (_photos.length > 1) ...[
          SlideshowArrow(right: false, visible: showControls, onTap: _goPrev),
          SlideshowArrow(right: true, visible: showControls, onTap: _goNext),
        ],
        SlideshowBottomArea(
          photo: photo,
          visible: showControls,
          isPlaying: _isPlaying,
          thumbnailsVisible: _thumbnailsVisible,
          onTogglePlay: _togglePlay,
          onToggleThumbnails:
              () =>
                  _updateState(() => _thumbnailsVisible = !_thumbnailsVisible),
          segments: SlideshowSegments(
            count: _photos.length,
            current: _current,
            isPlaying: _isPlaying,
            progress: _progressController,
            onTap: (index) => unawaited(_goTo(index)),
          ),
          thumbnailStrip: SlideshowThumbnailStrip(
            photos: _photos,
            current: _current,
            onTap: (index) => unawaited(_goTo(index)),
          ),
        ),
        // 面板 scrim 在侧栏之下（zIndex 语义），点击空白处同时收起。
        if (_showInfo || _showShare)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap:
                  () => _updateState(() {
                    _showInfo = false;
                    _showShare = false;
                  }),
            ),
          ),
        _buildInfoPanel(context, photo),
        PhotoSharePanel(
          visible: _showShare,
          photo: photo,
          onDone:
              () => _updateState(() {
                _showShare = false;
              }),
        ),
      ],
    );
  }

  // ─── Info 面板 ───

  Widget _buildInfoPanel(BuildContext context, PhotoItem photo) {
    return PhotoPanelHost(
      visible: _showInfo,
      onClose: () => _updateState(() => _showInfo = false),
      child: PhotoInfoPanel(
        photo: photo,
        onShare:
            () => _updateState(() {
              _showInfo = false;
              _showShare = true;
            }),
      ),
    );
  }
}
