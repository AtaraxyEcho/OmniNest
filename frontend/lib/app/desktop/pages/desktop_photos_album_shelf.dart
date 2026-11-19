part of 'desktop_photos_page.dart';

class _AlbumShelf extends StatelessWidget {
  const _AlbumShelf({
    required this.albums,
    required this.loading,
    required this.onOpen,
    required this.onCreate,
  });

  final List<PhotoAlbum> albums;
  final bool loading;
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
            if (loading)
              for (var i = 0; i < 5; i++)
                SizedBox(
                  width: width,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AspectRatio(
                        aspectRatio: 4 / 3,
                        child: DesktopSkeletonBox(
                          radius: DesktopMetrics.radius,
                          index: i * 3,
                        ),
                      ),
                      const SizedBox(height: 10),
                      FractionallySizedBox(
                        widthFactor: 0.58,
                        alignment: Alignment.centerLeft,
                        child: DesktopSkeletonBox(height: 14, index: i * 3 + 1),
                      ),
                      const SizedBox(height: 6),
                      FractionallySizedBox(
                        widthFactor: 0.34,
                        alignment: Alignment.centerLeft,
                        child: DesktopSkeletonBox(height: 11, index: i * 3 + 2),
                      ),
                    ],
                  ),
                ),
            for (var i = 0; i < albums.length; i++)
              SizedBox(
                width: width,
                child: DesktopStagger(
                  index: i,
                  child: _AlbumCard(album: albums[i], onOpen: onOpen),
                ),
              ),
            SizedBox(width: width, child: _CreateAlbumCard(onCreate: onCreate)),
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
        DesktopHoverLift(
          onTap: () => onOpen(album),
          child: AspectRatio(
            aspectRatio: 4 / 3,
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

class _CreateAlbumCard extends StatefulWidget {
  const _CreateAlbumCard({required this.onCreate});

  final VoidCallback onCreate;

  @override
  State<_CreateAlbumCard> createState() => _CreateAlbumCardState();
}

class _CreateAlbumCardState extends State<_CreateAlbumCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final color = _hovered ? skin.accent : skin.text3;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onCreate,
            behavior: HitTestBehavior.opaque,
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: CustomPaint(
                painter: _CreateAlbumBorder(color: color),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(DesktopIcons.plus, size: 22, color: color),
                      const SizedBox(height: 10),
                      Text(
                        l10n.photosNewAlbum,
                        style: DesktopType.bodyStrong(color),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 样例新建相册卡只在悬停时强调虚线与文字颜色，不使用图片卡的光效。
class _CreateAlbumBorder extends CustomPainter {
  const _CreateAlbumBorder({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = 0.5;
    final path =
        Path()..addRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              inset,
              inset,
              size.width - inset * 2,
              size.height - inset * 2,
            ),
            const Radius.circular(DesktopMetrics.radiusSmall),
          ),
        );
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
    final dashed = Path();
    for (final metric in path.computeMetrics()) {
      for (var distance = 0.0; distance < metric.length; distance += 8) {
        dashed.addPath(
          metric.extractPath(
            distance,
            (distance + 4).clamp(0.0, metric.length),
          ),
          Offset.zero,
        );
      }
    }
    canvas.drawPath(dashed, paint);
  }

  @override
  bool shouldRepaint(_CreateAlbumBorder oldDelegate) =>
      oldDelegate.color != color;
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
          DesktopTextField(
            controller: _name,
            label: l10n.photosAlbumName,
            helper: l10n.desktopPhotosAlbumCollectionNote,
            error: duplicate ? l10n.desktopPhotosAlbumDuplicate : null,
            autofocus: true,
            maxLength: 60,
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }
}
