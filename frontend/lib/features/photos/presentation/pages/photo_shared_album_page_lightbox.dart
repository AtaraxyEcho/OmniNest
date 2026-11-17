part of 'photo_shared_album_page.dart';

/// 公开相册的页内全屏预览覆盖层：大图、左右翻页与下载，不改分享令牌语义。
class _SharedPhotoLightbox extends StatefulWidget {
  const _SharedPhotoLightbox({
    required this.photos,
    required this.index,
    required this.total,
    required this.onIndexChanged,
    required this.onClose,
  });

  final List<PhotoItem> photos;
  final int index;
  final int total;
  final ValueChanged<int> onIndexChanged;
  final VoidCallback onClose;

  @override
  State<_SharedPhotoLightbox> createState() => _SharedPhotoLightboxState();
}

class _SharedPhotoLightboxState extends State<_SharedPhotoLightbox> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.index;
    _controller = PageController(initialPage: _index);
  }

  @override
  void didUpdateWidget(covariant _SharedPhotoLightbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index == _index) {
      return;
    }
    _index = widget.index;
    if (!_controller.hasClients) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controller.hasClients) {
        _controller.jumpToPage(_index);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int next) {
    if (next < 0 || next >= widget.photos.length) {
      return;
    }
    _controller.animateToPage(
      next,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _goTo(_index - 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _goTo(_index + 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final total = widget.total > 0 ? widget.total : widget.photos.length;
    return Positioned.fill(
      child: Focus(
        autofocus: true,
        onKeyEvent: _handleKey,
        child: ColoredBox(
          color: FramePalette.sharedAlbumScrim,
          child: SafeArea(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          '${_index + 1} / $total',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip:
                          widget.photos[_index].sourceUrl == null
                              ? l10n.photosDownloadSourceUnavailable
                              : l10n.photosDownloadPhoto,
                      icon: const Icon(Icons.download_rounded),
                      color: Colors.white,
                      onPressed:
                          widget.photos[_index].sourceUrl == null
                              ? null
                              : () => _download(
                                context,
                                widget.photos[_index].sourceUrl!,
                                widget.photos[_index],
                              ),
                    ),
                    IconButton(
                      tooltip: l10n.corePrevious,
                      icon: const Icon(Icons.chevron_left_rounded),
                      color: Colors.white,
                      onPressed: _index > 0 ? () => _goTo(_index - 1) : null,
                    ),
                    IconButton(
                      tooltip: l10n.coreNext,
                      icon: const Icon(Icons.chevron_right_rounded),
                      color: Colors.white,
                      onPressed:
                          _index < widget.photos.length - 1
                              ? () => _goTo(_index + 1)
                              : null,
                    ),
                    IconButton(
                      tooltip: l10n.coreClose,
                      icon: const Icon(Icons.close_rounded),
                      color: Colors.white,
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: widget.photos.length,
                    onPageChanged: (next) {
                      setState(() => _index = next);
                      widget.onIndexChanged(next);
                    },
                    itemBuilder:
                        (context, photoIndex) =>
                            _buildPhoto(context, widget.photos[photoIndex]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhoto(BuildContext context, PhotoItem photo) {
    // 关闭原图质量时服务端不签发 sourceUrl：预览退回封面，下载入口隐藏。
    final displayUrl = photo.sourceUrl ?? photo.coverUrl;
    if (displayUrl == null || displayUrl.isEmpty) {
      return const Center(
        child: Icon(
          Icons.broken_image_outlined,
          size: 48,
          color: Colors.white54,
        ),
      );
    }
    return InteractiveViewer(
      child: Center(
        // 分享页大图同样按屏宽量化解码档位：手机浏览器直接解码
        // 高像素原图会卡住主线程并把位图堆满内存。
        child: CachedNetworkImage(
          imageUrl: displayUrl,
          fit: BoxFit.contain,
          memCacheWidth: quantizedDecodeWidth(
            logicalWidth: MediaQuery.sizeOf(context).width,
            devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
            step: 256,
            min: 512,
            max: 4096,
          ),
        ),
      ),
    );
  }

  /// 与文件夹分享同一口径：能开新标签就开，否则退回复制链接。
  Future<void> _download(
    BuildContext context,
    String url,
    PhotoItem photo,
  ) async {
    final l10n = AppLocalizations.of(context);
    if (openDownloadUrl(url)) {
      return;
    }
    final copied = await copyTextToClipboard(url);
    if (!context.mounted) {
      return;
    }
    showOmniFeedback(
      context,
      copied ? l10n.filesDownloadLinkCopied : l10n.clipboardCopyFailed,
      severity:
          copied ? OmniFeedbackSeverity.success : OmniFeedbackSeverity.error,
    );
  }
}
