part of 'desktop_photos_page.dart';

/// 缩略图行高滑杆（样例 `.zoom`）：150–320，默认 210。
class _DensitySlider extends StatelessWidget {
  const _DensitySlider({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Row(
      children: [
        Icon(DesktopIcons.zoomOut, size: 14, color: skin.text3),
        const SizedBox(width: 10),
        SizedBox(
          width: 120,
          child: DesktopSlider(
            value: value,
            min: 150,
            max: 320,
            onChanged: (next) => onChanged(next.clamp(150, 320)),
            keyboardStep: 1,
          ),
        ),
        const SizedBox(width: 10),
        Icon(DesktopIcons.zoomIn, size: 14, color: skin.text3),
      ],
    );
  }
}

/// 缩略图（样例 `.ph`）：选中双内环，按压缩放整张 tile，悬停缩放内层图片。
class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    super.key,
    required this.photo,
    required this.height,
    this.onTap,
    this.onToggleSelect,
    this.selected = false,
    this.pressing = false,
    this.dragging = false,
    this.reordering = false,
    this.landed = false,
    this.selectionActive = false,
    this.showCaption = true,
    this.showFavorite = true,
    this.showSelectionControls = true,
  });

  final PhotoItem photo;
  final double height;
  final ValueChanged<PhotoItem>? onTap;
  final ValueChanged<PhotoItem>? onToggleSelect;
  final bool selected;
  final bool pressing;
  final bool dragging;
  final bool reordering;
  final bool landed;

  /// 已有选中项：所有缩略图的勾选圈一起显形（样例 `.justified:has(.sel)`）。
  final bool selectionActive;
  final bool showCaption;
  final bool showFavorite;
  final bool showSelectionControls;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return DesktopHover(
      builder: (context, hovered) {
        final radius = selected || dragging ? 12.0 : 10.0;
        final content = AnimatedContainer(
          duration: DesktopMotion.of(context, DesktopMotion.soft),
          decoration: BoxDecoration(
            color:
                selected
                    ? skin.raise2
                    : dragging
                    ? Color.lerp(skin.raise2, skin.accent, 0.16)
                    : skin.raise2,
            borderRadius: BorderRadius.circular(radius),
            border:
                dragging
                    ? Border.all(
                      color: skin.accent.withValues(alpha: 0.5),
                      width: 1.5,
                    )
                    : null,
            boxShadow:
                pressing
                    ? [
                      BoxShadow(
                        color: skin.accent.withValues(alpha: 0.7),
                        blurRadius: 0,
                        spreadRadius: 3,
                      ),
                    ]
                    : !selected && hovered && !dragging
                    ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.55),
                        offset: const Offset(0, 14),
                        blurRadius: 32,
                        spreadRadius: -14,
                      ),
                    ]
                    : const <BoxShadow>[],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: AnimatedScale(
              scale:
                  pressing ? (selected && selectionActive ? 0.955 : 0.975) : 1,
              duration: DesktopMotion.of(
                context,
                DesktopMotion.photoReorderPressScale,
              ),
              curve: DesktopMotion.photoReorderPressCurve,
              child: GestureDetector(
                onTap: onTap == null ? null : () => onTap!(photo),
                child: SizedBox(
                  height: height,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      AnimatedOpacity(
                        opacity: dragging ? 0.22 : 1,
                        duration: DesktopMotion.of(
                          context,
                          DesktopMotion.photoReorderSourceFade,
                        ),
                        child: AnimatedScale(
                          scale:
                              pressing
                                  ? 1
                                  : dragging
                                  ? 1
                                  : selected
                                  ? 1
                                  : reordering
                                  ? 0.97
                                  : hovered
                                  ? (selectionActive ? 1.03 : 1.05)
                                  : 1,
                          duration: DesktopMotion.of(
                            context,
                            pressing
                                ? DesktopMotion.photoReorderPressScale
                                : DesktopMotion.photoTileImageHover,
                          ),
                          curve:
                              pressing
                                  ? DesktopMotion.photoReorderPressCurve
                                  : DesktopMotion.ease,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              selected ? 12 : 10,
                            ),
                            child: ColorFiltered(
                              colorFilter: ColorFilter.matrix(
                                desktopColorMatrix(
                                  brightness: pressing ? 1.06 : 1,
                                ),
                              ),
                              child: DesktopCover(
                                url: photo.coverUrl,
                                kind: DesktopCoverKind.network,
                                fallbackIcon: DesktopIcons.image,
                                cacheKey: 'desktop-photo-${photo.id}',
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (!dragging)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: AnimatedOpacity(
                              opacity: selected || hovered ? 1 : 0,
                              duration: DesktopMotion.of(
                                context,
                                DesktopMotion.soft,
                              ),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient:
                                      selected
                                          ? LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Color.lerp(
                                                Colors.black.withValues(
                                                  alpha: 0.28,
                                                ),
                                                skin.accent,
                                                0.22,
                                              )!,
                                              Colors.transparent,
                                            ],
                                            stops: const [0, 0.38],
                                          )
                                          : const LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Color(0x59000000),
                                              Colors.transparent,
                                              Colors.transparent,
                                              Color(0x80000000),
                                            ],
                                            stops: [0, 0.35, 0.65, 1],
                                          ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (showCaption && !dragging)
                        // 样例 `.ph-cap`：标题只在悬停时淡入，右下留给收藏心。
                        Positioned(
                          left: 12,
                          right: 36,
                          bottom: 10,
                          child: AnimatedOpacity(
                            duration: DesktopMotion.of(
                              context,
                              DesktopMotion.soft,
                            ),
                            opacity: hovered ? 1 : 0,
                            child: Text(
                              photo.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DesktopType.caption(Colors.white),
                            ),
                          ),
                        ),
                      if (showFavorite && photo.favorite && !dragging)
                        // 样例 `.ph .fav`：右下角白色心形。
                        Positioned(
                          right: 10,
                          bottom: 10,
                          child: Icon(
                            DesktopIcons.heart,
                            size: 15,
                            color: Colors.white,
                          ),
                        ),
                      if (selected && !dragging)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              key: ValueKey<String>(
                                'desktop-photo-selected-ring-${photo.id}',
                              ),
                              painter: _PhotoSelectionRingPainter(
                                accent: skin.accent,
                              ),
                            ),
                          ),
                        ),
                      if (showSelectionControls && !dragging)
                        Positioned(
                          top: 10,
                          left: 10,
                          child: _SelectCheck(
                            selected: selected,
                            visible: hovered || selected || selectionActive,
                            onTap:
                                onToggleSelect == null
                                    ? null
                                    : () => onToggleSelect!(photo),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        return TweenAnimationBuilder<double>(
          key: ValueKey<bool>(landed),
          tween: Tween<double>(begin: landed ? 0.82 : 1, end: 1),
          duration: DesktopMotion.of(context, DesktopMotion.photoReorderSettle),
          curve: DesktopMotion.riseCurve,
          child: content,
          builder:
              (context, scale, child) => Transform.scale(
                scale: pressing ? 1 : scale,
                child: Opacity(
                  opacity: landed ? ((scale - 0.82) / 0.18).clamp(0.0, 1.0) : 1,
                  child: child,
                ),
              ),
        );
      },
    );
  }
}

class _PhotoSelectionRingPainter extends CustomPainter {
  const _PhotoSelectionRingPainter({required this.accent});

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(12);
    final accentRect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(accentRect.deflate(1.5), radius),
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(accentRect.deflate(5), radius),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_PhotoSelectionRingPainter oldDelegate) =>
      accent != oldDelegate.accent;
}

/// 缩略图左上角的勾选圈（样例 `.check`）：24 圆环，悬停/选中才显形，
/// 选中态换成主色实心并放大到 1.1。
class _SelectCheck extends StatelessWidget {
  const _SelectCheck({
    required this.selected,
    required this.visible,
    required this.onTap,
  });

  final bool selected;
  final bool visible;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: DesktopMotion.of(context, DesktopMotion.soft),
      child: AnimatedScale(
        scale: selected ? 1.1 : 1,
        duration: DesktopMotion.of(context, DesktopMotion.soft),
        curve: DesktopMotion.spring,
        child: Semantics(
          button: true,
          selected: selected,
          label: l10n.desktopPhotosSelect,
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? skin.accent : const Color(0x26000000),
                border: Border.all(
                  color:
                      selected
                          ? skin.accent
                          : Colors.white.withValues(alpha: 0.85),
                  width: 1.8,
                ),
              ),
              child: Icon(
                DesktopIcons.check,
                size: 14,
                color: selected ? skin.accentInk : Colors.transparent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 选中后的动作条（样例 `.sel-bar`）：计数 + 收藏 + 删除 + 取消。
/// 底部居中的多选操作条（样例 `.sel-bar`）。
///
/// 它是浮层而不是页面流的一段：样例用 `position:absolute; left:50%;
/// bottom:90px` 把它钉在播放条上方，选中变化时 `translate(-50%,30px) → 0`
/// 弹入。放进流里会把下面的相片墙整体推下去，选一张就跳一次版。
class _PhotoSelectionOverlay extends StatelessWidget {
  const _PhotoSelectionOverlay({
    required this.count,
    required this.busy,
    required this.onFavorite,
    required this.onAlbum,
    required this.onDownload,
    required this.onDelete,
    required this.onClear,
  });

  final int count;
  final bool busy;
  final VoidCallback onFavorite;
  final VoidCallback onAlbum;
  final VoidCallback onDownload;
  final VoidCallback onDelete;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final visible = count > 0;
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        // 操作条约 52px 高，0.58 的相对位移对应样例的 30px 入场距离。
        offset: visible ? Offset.zero : const Offset(0, 0.58),
        duration: DesktopMotion.of(context, DesktopMotion.pane),
        curve: DesktopMotion.spring,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: DesktopMotion.of(context, DesktopMotion.pane),
          curve: DesktopMotion.ease,
          child: Center(
            child: _PhotoSelectionBar(
              count: count,
              busy: busy,
              onFavorite: onFavorite,
              onAlbum: onAlbum,
              onDownload: onDownload,
              onDelete: onDelete,
              onClear: onClear,
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoSelectionBar extends StatelessWidget {
  const _PhotoSelectionBar({
    required this.count,
    required this.busy,
    required this.onFavorite,
    required this.onAlbum,
    required this.onDownload,
    required this.onDelete,
    required this.onClear,
  });

  final int count;
  final bool busy;
  final VoidCallback onFavorite;
  final VoidCallback onAlbum;
  final VoidCallback onDownload;
  final VoidCallback onDelete;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 8, 10, 8),
          decoration: BoxDecoration(
            color: skin.pop,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: skin.line2),
            boxShadow: skin.shadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.filesSelectedCount(count),
                style: DesktopType.denseStrong(
                  skin.text,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 10),
              DesktopButton(
                label: l10n.photosFavorite,
                icon: DesktopIcons.heart,
                variant: DesktopButtonVariant.ghost,
                onPressed: busy ? null : onFavorite,
              ),
              const SizedBox(width: 4),
              DesktopButton(
                label: l10n.photosAddToAlbum,
                icon: DesktopIcons.album,
                variant: DesktopButtonVariant.ghost,
                onPressed: busy ? null : onAlbum,
              ),
              const SizedBox(width: 4),
              DesktopButton(
                label: l10n.photosDownload,
                icon: DesktopIcons.download,
                variant: DesktopButtonVariant.ghost,
                onPressed: busy ? null : onDownload,
              ),
              const SizedBox(width: 4),
              DesktopButton(
                label: l10n.photosDelete,
                icon: DesktopIcons.trash,
                variant: DesktopButtonVariant.ghost,
                onPressed: busy ? null : onDelete,
              ),
              const SizedBox(width: 4),
              DesktopIconButton(
                icon: DesktopIcons.close,
                tooltip: l10n.desktopPhotosClearSelection,
                onPressed: onClear,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 选中项的批量动作（加入相册、下载）。
///
/// 写成 part 里的 extension 而不是塞进 State：主页面的行数已经贴着源码
/// 棘轮（`source_size_baseline.dart`），动作逻辑又只依赖 `_selection` /
/// `ref` / `setState`，放这里语义一样、文件不再膨胀。
extension _PhotoSelectionActions on _DesktopPhotosPageState {
  /// 逐张下载选中照片（样例 `.sel-bar` 的 Download 动作）。
  ///
  /// 每张走系统保存对话框（桌面口径），用户取消即停并按已保存数量收尾。
  /// 列表数据未必带原图地址：`sourceUrl` 为空时直接提示先打开照片，
  /// 而不是拿缩略图地址糊一张降级图下来。
  Future<void> _downloadSelected(void Function(VoidCallback) setState) async {
    final l10n = AppLocalizations.of(context);
    final ids = _selection.toList(growable: false);
    final visible = <String, PhotoItem>{
      for (final photo
          in ref.read(photoFavoritesProvider).asData?.value.items ??
              const <PhotoItem>[])
        photo.id: photo,
      for (final photo
          in ref.read(photoListProvider).asData?.value.items ??
              const <PhotoItem>[])
        photo.id: photo,
    };
    final photos = ids
        .map((id) => visible[id])
        .whereType<PhotoItem>()
        .where((photo) => (photo.sourceUrl?.isNotEmpty ?? false))
        .toList(growable: false);
    if (photos.isEmpty) {
      showDesktopToast(
        context,
        l10n.photosDownloadNeedsOriginal,
        kind: DesktopToastKind.warn,
        icon: DesktopIcons.download,
      );
      return;
    }
    setState(() => _selectionBusy = true);
    var saved = 0;
    try {
      for (final photo in photos) {
        final ext = photo.format.isEmpty ? 'jpg' : photo.format.toLowerCase();
        final name = '${photo.title}.$ext';
        final path = await resolvePhotoExportPath(suggestedName: name);
        if (path == null) {
          break;
        }
        await ref
            .read(photoRepositoryProvider)
            .downloadPhotoFile(
              url: photo.sourceUrl!,
              sizeBytes: photo.fileSize,
              destinationPath: path,
            );
        await deliverPhotoExport(path: path, fileName: name);
        saved++;
      }
      if (!mounted) {
        return;
      }
      if (saved > 0) {
        showDesktopToast(
          context,
          l10n.photosSavedCount(saved),
          icon: DesktopIcons.check,
        );
        setState(_selection.clear);
      }
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      showDesktopToast(
        context,
        userFacingErrorText(error),
        kind: DesktopToastKind.error,
      );
    } finally {
      if (mounted) {
        setState(() => _selectionBusy = false);
      }
    }
  }
}
