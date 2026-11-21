part of 'desktop_reader_page.dart';

class _Shelf extends StatelessWidget {
  const _Shelf({required this.items, required this.onOpen});

  final List<ReaderItem> items;
  final ValueChanged<ReaderItem> onOpen;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final target = (MediaQuery.sizeOf(context).width * 0.12).clamp(
          150.0,
          190.0,
        );
        final columns = ((constraints.maxWidth + 26) / (target + 26))
            .floor()
            .clamp(2, 8);
        final width = (constraints.maxWidth - (columns - 1) * 26) / columns;
        return Wrap(
          spacing: 26,
          runSpacing: 30,
          children: [
            for (var i = 0; i < items.length; i++)
              SizedBox(
                width: width,
                child: DesktopStagger(
                  index: i,
                  child: _BookCard(
                    item: items[i],
                    onTap: () => onOpen(items[i]),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _BookCard extends StatelessWidget {
  const _BookCard({required this.item, required this.onTap});

  final ReaderItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final progress = (item.progressPercent ?? 0).clamp(0, 100);
    return DesktopHover(
      builder: (context, hovered) {
        return AnimatedContainer(
          key: ValueKey<String>('desktop-reader-book-card-${item.id}'),
          duration: MotionToken.reduced(
            context,
            const Duration(milliseconds: 220),
          ),
          curve: Curves.easeOutCubic,
          transformAlignment: Alignment.center,
          transform:
              Matrix4.identity()
                ..translateByDouble(0.0, hovered ? -10.0 : 0.0, 0, 1)
                ..scaleByDouble(
                  hovered ? 1.022 : 1.0,
                  hovered ? 1.022 : 1.0,
                  1.0,
                  1.0,
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                button: true,
                label: item.title,
                child: GestureDetector(
                  onTap: onTap,
                  child: AspectRatio(
                    aspectRatio: 168 / 240,
                    child: _BookCover(item: item, hoveredOverride: hovered),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DesktopType.rowTitle(skin.text),
              ),
              const SizedBox(height: 2),
              Text(
                item.authorName ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DesktopType.caption(skin.text3),
              ),
              if (progress > 0) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: SizedBox(
                    height: 3,
                    child: LinearProgressIndicator(
                      value: progress / 100,
                      backgroundColor: skin.raise3,
                      valueColor: AlwaysStoppedAnimation<Color>(skin.accent),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _BookCover extends StatelessWidget {
  const _BookCover({
    required this.item,
    this.large = false,
    this.hoveredOverride,
  });

  final ReaderItem item;
  final bool large;
  final bool? hoveredOverride;

  @override
  Widget build(BuildContext context) {
    return DesktopReaderBookCover(
      itemId: item.id,
      title: item.title,
      author: item.authorName ?? '',
      coverUrl: item.coverUrl,
      isComic: item.isDisplayedAsComic,
      readerType: item.readerType,
      volumeNumber: item.volumeNumber,
      large: large,
      hoveredOverride: hoveredOverride,
    );
  }
}
