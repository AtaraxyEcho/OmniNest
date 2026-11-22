part of 'desktop_photo_viewer_page.dart';

/// 底部胶片条与幻灯片底部栏融合组件：
/// - 72×48 缩略图（圆角 4px、当前项 100% + 2px 白色高亮框、非当前项 45%）
/// - `ScrollController` 自动居中当前项
/// - 内置「隐藏/显示」折叠切换（`AnimatedSize`）与左下精简元信息
/// - 幻灯片态展示大号轻字重标题、地点/日期元信息、播放/暂停与分段进度条
class _Filmstrip extends StatefulWidget {
  const _Filmstrip({
    required this.photos,
    required this.currentPhoto,
    required this.currentIndex,
    required this.slideshow,
    required this.thumbnailsVisible,
    required this.slideProgress,
    required this.onPick,
    required this.onToggleSlideshow,
    required this.onToggleThumbnails,
  });

  final List<PhotoItem> photos;
  final PhotoItem currentPhoto;
  final int currentIndex;
  final bool slideshow;
  final bool thumbnailsVisible;
  final ValueListenable<double> slideProgress;
  final ValueChanged<String> onPick;
  final VoidCallback onToggleSlideshow;
  final VoidCallback onToggleThumbnails;

  @override
  State<_Filmstrip> createState() => _FilmstripState();
}

class _FilmstripState extends State<_Filmstrip> {
  static const double _thumbWidth = 72;
  static const double _thumbHeight = 48;
  static const double _thumbGap = 8;
  static const double _itemExtent = _thumbWidth + _thumbGap;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerCurrent(animate: false);
    });
  }

  @override
  void didUpdateWidget(covariant _Filmstrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentChanged =
        oldWidget.currentIndex != widget.currentIndex ||
        oldWidget.currentPhoto.id != widget.currentPhoto.id;
    final reopened = !oldWidget.thumbnailsVisible && widget.thumbnailsVisible;
    if (currentChanged || reopened) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _centerCurrent(animate: !reopened);
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _centerCurrent({required bool animate}) {
    if (!mounted || !_scrollController.hasClients || widget.photos.isEmpty) {
      return;
    }
    final position = _scrollController.position;
    if (!position.hasViewportDimension || position.maxScrollExtent <= 0) {
      return;
    }
    final clampedIndex = widget.currentIndex.clamp(0, widget.photos.length - 1);
    final itemCenter = clampedIndex * _itemExtent + _thumbWidth / 2;
    final target = (itemCenter - position.viewportDimension / 2).clamp(
      0.0,
      position.maxScrollExtent,
    );
    if ((position.pixels - target).abs() < 1) {
      return;
    }
    if (!animate) {
      _scrollController.jumpTo(target);
      return;
    }
    final duration = DesktopMotion.of(context, DesktopMotion.soft);
    if (duration == Duration.zero) {
      _scrollController.jumpTo(target);
      return;
    }
    unawaited(
      _scrollController.animateTo(
        target,
        duration: duration,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  String _metaLine(PhotoItem photo, bool preferZh) {
    final location =
        photo.locationDisplay(preferZh: preferZh) ?? _placeLabel(photo);
    final date = photo.dateTaken ?? photo.createdAt;
    final dateText =
        date == null
            ? null
            : '${date.year}-${date.month.toString().padLeft(2, '0')}-'
                '${date.day.toString().padLeft(2, '0')}';
    return [
      location,
      dateText,
    ].whereType<String>().where((part) => part.isNotEmpty).join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final preferZh = Localizations.localeOf(context).languageCode == 'zh';
    final meta = _metaLine(widget.currentPhoto, preferZh);
    final hasMultiple = widget.photos.length > 1;
    final toggleButton =
        hasMultiple
            ? TextButton(
              onPressed: widget.onToggleThumbnails,
              child: Text(
                widget.thumbnailsVisible
                    ? l10n.photosStripHide
                    : l10n.photosStripShow,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: AppTypography.labelSmall,
                  letterSpacing: 0.08,
                ),
              ),
            )
            : const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.slideshow) ...[
            Text(
              widget.currentPhoto.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: AppTypography.headlineSmall,
                fontWeight: FontWeight.w300,
                letterSpacing: -0.01,
              ),
            ),
            if (meta.isNotEmpty)
              Text(
                meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: AppTypography.bodySmall,
                  letterSpacing: 0.06,
                  fontWeight: FontWeight.w300,
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                IconButton(
                  tooltip: l10n.photosPause,
                  onPressed: widget.onToggleSlideshow,
                  icon: Icon(
                    Icons.pause_rounded,
                    color: Colors.white.withValues(alpha: 0.85),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SlideshowSegments(
                    count: widget.photos.length,
                    current: widget.currentIndex,
                    isPlaying: widget.slideshow,
                    progress: widget.slideProgress,
                    onTap: (index) {
                      if (index >= 0 && index < widget.photos.length) {
                        widget.onPick(widget.photos[index].id);
                      }
                    },
                  ),
                ),
                if (hasMultiple) ...[const SizedBox(width: 12), toggleButton],
              ],
            ),
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.currentPhoto.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.90),
                          fontSize: AppTypography.bodyMedium,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      if (meta.isNotEmpty)
                        Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.48),
                            fontSize: AppTypography.bodySmall,
                            letterSpacing: 0.04,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                    ],
                  ),
                ),
                if (hasMultiple) ...[const SizedBox(width: 12), toggleButton],
              ],
            ),
          ],
          if (hasMultiple)
            AnimatedSize(
              duration: DesktopMotion.of(
                context,
                const Duration(milliseconds: 320),
              ),
              curve: Curves.easeOutCubic,
              alignment: Alignment.bottomCenter,
              child:
                  widget.thumbnailsVisible
                      ? Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: SizedBox(
                          height: _thumbHeight,
                          child: ListView.separated(
                            controller: _scrollController,
                            scrollDirection: Axis.horizontal,
                            itemCount: widget.photos.length,
                            separatorBuilder:
                                (_, _) => const SizedBox(width: _thumbGap),
                            itemBuilder: (context, i) {
                              final item = widget.photos[i];
                              final active = item.id == widget.currentPhoto.id;
                              return Opacity(
                                opacity: active ? 1 : 0.45,
                                alwaysIncludeSemantics: true,
                                child: GestureDetector(
                                  key: ValueKey<String>(
                                    'viewer-thumb-${item.id}',
                                  ),
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => widget.onPick(item.id),
                                  child: Container(
                                    width: _thumbWidth,
                                    height: _thumbHeight,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color:
                                            active
                                                ? Colors.white.withValues(
                                                  alpha: 0.90,
                                                )
                                                : Colors.transparent,
                                        width: 2,
                                      ),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(2),
                                      child: DesktopImage(
                                        url: item.coverUrl,
                                        cacheWidth: 256,
                                        fallbackIcon: DesktopIcons.image,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      )
                      : const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }
}
