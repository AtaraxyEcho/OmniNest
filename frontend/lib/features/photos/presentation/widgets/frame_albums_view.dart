import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/photos/domain/photo_album.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_palette.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_thumb_image.dart';

/// Frame 影集视图：衬线标题 + 黑色新建按钮 + 相册封面卡网格。
///
/// 封面卡 aspect 1.4、圆角 4、底色 #EAE7E0，悬停放大 1.05；
/// 网格 2 列（md 3 列、lg 4 列），间距 16px。
class FrameAlbumsView extends StatelessWidget {
  const FrameAlbumsView({
    required this.albums,
    required this.onOpenAlbum,
    required this.onDeleteAlbum,
    required this.onCreateAlbum,
    super.key,
  });

  final List<PhotoAlbum> albums;
  final ValueChanged<PhotoAlbum> onOpenAlbum;
  final ValueChanged<PhotoAlbum> onDeleteAlbum;
  final VoidCallback onCreateAlbum;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.frameColors;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverLayoutBuilder(
          builder: (context, constraints) {
            final padding = _paddingFor(constraints.crossAxisExtent);
            final columns = _columnCountFor(constraints.crossAxisExtent);
            return SliverPadding(
              padding: EdgeInsets.all(padding),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Row(
                    children: [
                      Text(
                        l10n.photosAlbums,
                        style: TextStyle(
                          fontFamily: FramePalette.serifFamily,
                          fontFamilyFallback: FramePalette.serifFallback,
                          color: colors.ink,
                          fontSize: 24,
                        ),
                      ),
                      const Spacer(),
                      _NewAlbumButton(onTap: onCreateAlbum),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (albums.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        l10n.photosNoAlbums,
                        style: TextStyle(color: colors.muted, fontSize: 13),
                      ),
                    )
                  else
                    LayoutBuilder(
                      builder: (context, gridConstraints) {
                        final itemWidth =
                            (gridConstraints.maxWidth - (columns - 1) * 16) /
                            columns;
                        return Wrap(
                          spacing: 16,
                          runSpacing: 20,
                          children: [
                            for (final album in albums)
                              SizedBox(
                                width: itemWidth,
                                child: _FrameAlbumCard(
                                  album: album,
                                  onOpen: () => onOpenAlbum(album),
                                  onLongPress: () => onDeleteAlbum(album),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                ]),
              ),
            );
          },
        ),
      ],
    );
  }

  double _paddingFor(double width) => width > 768 ? 24.0 : 16.0;

  int _columnCountFor(double width) {
    if (width >= 1024) return 4;
    if (width >= 768) return 3;
    return 2;
  }
}

/// 新建影集按钮：黑底白字圆角 8，加号 15px。
class _NewAlbumButton extends StatelessWidget {
  const _NewAlbumButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.frameColors;
    return Semantics(
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colors.btnBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, size: 15, color: colors.onBtn),
                const SizedBox(width: 8),
                Text(
                  AppLocalizations.of(context).photosNewAlbum,
                  style: TextStyle(color: colors.onBtn, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Frame 相册封面卡：1.4 封面 + 名称 + 计数与创建日期。
class _FrameAlbumCard extends StatefulWidget {
  const _FrameAlbumCard({
    required this.album,
    required this.onOpen,
    required this.onLongPress,
  });

  final PhotoAlbum album;
  final VoidCallback onOpen;
  final VoidCallback onLongPress;

  @override
  State<_FrameAlbumCard> createState() => _FrameAlbumCardState();
}

class _FrameAlbumCardState extends State<_FrameAlbumCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final album = widget.album;
    final created = album.createdAt;
    final meta = l10n.photosAlbumPhotoCountLabel(album.photoCount);
    final metaText =
        created == null
            ? meta
            : '$meta · ${DateFormat.yMMMMd(Localizations.localeOf(context).toString()).format(created)}';

    return Semantics(
      button: true,
      label: album.name,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: widget.onOpen,
          onLongPress: widget.onLongPress,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: AspectRatio(
                  aspectRatio: 1.4,
                  child: Container(
                    color: context.frameColors.card,
                    child: AnimatedScale(
                      scale: _hovering ? 1.05 : 1,
                      duration:
                          MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 300),
                      child:
                          album.hasCover
                              ? PhotoThumbImage(
                                imageUrl: album.coverUrl!,
                                fadeInDuration: const Duration(
                                  milliseconds: 500,
                                ),
                                fadeOutDuration: const Duration(
                                  milliseconds: 1000,
                                ),
                              )
                              : const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                album.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color:
                      _hovering
                          ? context.frameColors.accent
                          : context.frameColors.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                metaText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.frameColors.muted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
