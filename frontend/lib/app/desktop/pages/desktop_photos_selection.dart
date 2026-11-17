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
            thumbColor: skin.accent,
            trackFill: false,
            thumbAlwaysVisible: true,
            thumbGlow: true,
            growTrackOnActive: false,
            thumbRadius: 7,
            thumbInset: 7,
            keyboardStep: 1,
          ),
        ),
        const SizedBox(width: 10),
        Icon(DesktopIcons.zoomIn, size: 14, color: skin.text3),
      ],
    );
  }
}

/// 缩略图（样例 `.ph`）：选中时圆角收到 16、整体 scale(.94)、外描一圈主色。
class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.photo,
    required this.height,
    this.onTap,
    this.onToggleSelect,
    this.selected = false,
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
        final radius = selected ? 16.0 : 10.0;
        return AnimatedScale(
          scale: selected ? 0.94 : 1,
          duration: DesktopMotion.of(context, DesktopMotion.lift),
          curve: DesktopMotion.spring,
          child: AnimatedContainer(
            duration: DesktopMotion.of(context, DesktopMotion.soft),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              boxShadow:
                  selected
                      ? [
                        BoxShadow(
                          color: skin.accent,
                          blurRadius: 0,
                          spreadRadius: 3,
                        ),
                      ]
                      : const <BoxShadow>[],
            ),
            child: DesktopTilt(
              maxDegrees: 4,
              radius: radius,
              onTap: onTap == null ? null : () => onTap!(photo),
              child: SizedBox(
                height: height,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DesktopCover(
                      url: photo.coverUrl,
                      kind: DesktopCoverKind.network,
                      fallbackIcon: DesktopIcons.image,
                      cacheKey: 'desktop-photo-${photo.id}',
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0x59000000)],
                          stops: [0.62, 1.0],
                        ),
                      ),
                    ),
                    if (showCaption)
                      Positioned(
                        left: 10,
                        right: 10,
                        bottom: 8,
                        child: Text(
                          photo.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DesktopType.caption(Colors.white),
                        ),
                      ),
                    if (showFavorite && photo.favorite)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Icon(
                          DesktopIcons.heart,
                          size: 15,
                          color: skin.liked,
                        ),
                      ),
                    if (showSelectionControls)
                      Positioned(
                        top: 9,
                        left: 9,
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
        );
      },
    );
  }
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
              width: 24,
              height: 24,
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

class _AlbumShelf extends StatelessWidget {
  const _AlbumShelf({
    required this.albums,
    required this.onOpen,
    required this.onCreate,
  });

  final List<PhotoAlbum> albums;
  final ValueChanged<PhotoAlbum> onOpen;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // desktop.css:346：minmax(220px,1fr) + gap26，246 为两者之和。
        final available = constraints.maxWidth;
        final columns = ((available + 26) / 246).floor().clamp(2, 7);
        final width = (available - (columns - 1) * 26) / columns;
        return Wrap(
          spacing: 26,
          runSpacing: 26,
          children: [
            SizedBox(width: width, child: _CreateAlbumCard(onCreate: onCreate)),
            for (var i = 0; i < albums.length; i++)
              SizedBox(
                width: width,
                child: DesktopStagger(
                  index: i,
                  child: _AlbumCard(album: albums[i], onOpen: onOpen),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.album, required this.onOpen});

  final PhotoAlbum album;
  final ValueChanged<PhotoAlbum> onOpen;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DesktopTilt(
          maxDegrees: 5,
          onTap: () => onOpen(album),
          child: AspectRatio(
            aspectRatio: 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                DesktopCover(
                  url: album.coverUrl,
                  kind: DesktopCoverKind.network,
                  fallbackIcon: DesktopIcons.image,
                  cacheKey: 'desktop-album-${album.id}',
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0x4D000000)],
                      stops: [0.70, 1.0],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          album.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DesktopType.bodyStrong(skin.text),
        ),
        const SizedBox(height: 2),
        Text(
          l10n.desktopItemCount(album.photoCount),
          style: DesktopType.caption(skin.text3),
        ),
      ],
    );
  }
}

class _CreateAlbumCard extends StatelessWidget {
  const _CreateAlbumCard({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DesktopTilt(
          maxDegrees: 2,
          onTap: onCreate,
          child: AspectRatio(
            aspectRatio: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: skin.raise,
                borderRadius: BorderRadius.circular(DesktopMetrics.radiusCard),
                border: Border.all(color: skin.line2),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(DesktopIcons.plus, size: 28, color: skin.accent),
                  const SizedBox(height: 10),
                  Text(
                    l10n.photosNewAlbum,
                    style: DesktopType.bodyStrong(skin.text),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NewAlbumDrawer extends StatefulWidget {
  const _NewAlbumDrawer({required this.takenNames});

  final List<String> takenNames;

  @override
  State<_NewAlbumDrawer> createState() => _NewAlbumDrawerState();
}

class _NewAlbumDrawerState extends State<_NewAlbumDrawer> {
  final TextEditingController _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final name = _name.text.trim();
    final duplicate = widget.takenNames.any(
      (taken) => taken.toLowerCase() == name.toLowerCase(),
    );
    return DesktopDrawerFrame(
      eyebrow: l10n.modulePhotosTitle,
      title: l10n.photosNewAlbum,
      footer: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DesktopButton(
            label: l10n.filesCancel,
            onPressed: () => closeDesktopModal(context),
          ),
          const SizedBox(width: 8),
          DesktopButton(
            label: l10n.photosNewAlbum,
            icon: DesktopIcons.plus,
            variant: DesktopButtonVariant.primary,
            onPressed:
                name.isEmpty || duplicate
                    ? null
                    : () => closeDesktopModal(context, name),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.photosAlbumName, style: DesktopType.fieldLabel(skin.text2)),
          const SizedBox(height: 7),
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: 60,
            onChanged: (_) => setState(() {}),
            style: DesktopType.body(skin.text),
            decoration: InputDecoration(
              counterText: '',
              hintText: l10n.photosAlbumNameHint,
              hintStyle: DesktopType.body(skin.text3),
            ),
          ),
          if (duplicate)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.desktopPhotosAlbumDuplicate,
                style: DesktopType.caption(DesktopPalette.danger),
              ),
            ),
          const SizedBox(height: 14),
          Text(
            l10n.desktopPhotosAlbumCollectionNote,
            style: DesktopType.caption(skin.text3),
          ),
        ],
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
