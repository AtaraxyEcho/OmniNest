part of 'desktop_reader_page.dart';

/// 书架卡片与它的右键菜单/侧栏详情入口：卡片本体与详情坞数据同住一处，
/// 避免阅读页主文件继续膨胀。
Future<void> _openBookReadingFromDock(
  BuildContext ctx,
  WidgetRef r,
  ReaderItem item,
) async {
  if (item.id.isEmpty) {
    return;
  }
  r
      .read(desktopAmbientHintProvider.notifier)
      .rememberReaderBook(
        item.coverUrl,
        DesktopPalette.bookToneFor(item.id).tone,
      );
  final encodedId = Uri.encodeComponent(item.id);
  if (item.isComic) {
    desktopPush(ctx, '/reader/comics/$encodedId/read');
    return;
  }
  if (item.itemType.toUpperCase() == 'PDF') {
    desktopPush(ctx, '/reader/pdfs/$encodedId/read');
    return;
  }
  try {
    final detail = await r
        .read(readerItemDetailProvider(item.id).future)
        .timeout(const Duration(milliseconds: 500));
    if (!ctx.mounted) {
      return;
    }
    final chapterId = detail.progress?.chapterId;
    if (chapterId == null || chapterId.isEmpty) {
      desktopPush(ctx, DesktopRoutes.bookDetail(item.id));
      return;
    }
    desktopPush(
      ctx,
      '/reader/items/$encodedId/chapters/${Uri.encodeComponent(chapterId)}',
    );
  } on Exception {
    if (ctx.mounted) {
      desktopPush(ctx, DesktopRoutes.bookDetail(item.id));
    }
  }
}

void _showBookQuickLook(WidgetRef ref, AppLocalizations l10n, ReaderItem item) {
  final progress = (item.progressPercent ?? 0).clamp(0.0, 100.0);
  final hasCover = item.coverUrl != null && item.coverUrl!.trim().isNotEmpty;
  final paper = hasCover ? null : DesktopPalette.bookToneFor(item.id);
  final readingLabel =
      progress > 0 && progress < 90
          ? l10n.desktopReaderContinueAction
          : l10n.desktopStartReading;
  final facts = <MapEntry<String, String>>[
    if ((item.authorName ?? '').trim().isNotEmpty)
      MapEntry(l10n.desktopBookAuthor, item.authorName!.trim()),
    MapEntry(l10n.desktopBookFormat, item.itemType),
    MapEntry(l10n.desktopBookProgress, '${progress.round()}%'),
  ];
  ref
      .read(desktopShellProvider.notifier)
      .showDetail(
        DesktopDetailData(
          id: 'book:${item.id}',
          kind: 'book',
          title: item.title,
          subtitle: item.authorName ?? item.itemType,
          imageUrl: hasCover ? item.coverUrl : null,
          paperCover: paper,
          squareArt: true,
          about: item.description,
          progress: progress > 0 ? progress / 100 : null,
          chips: (item.genres ?? const <String>[]).take(6).toList(),
          chipsLabel: l10n.desktopBookTags,
          factsLabel: l10n.desktopBookDetails,
          facts: facts,
          primary: DesktopDetailAction(
            label: readingLabel,
            icon: DesktopIcons.book,
            onPressed:
                (ctx, r) => unawaited(_openBookReadingFromDock(ctx, r, item)),
          ),
          secondary: DesktopDetailAction(
            label: l10n.desktopReaderBookPage,
            icon: DesktopIcons.info,
            onPressed:
                (ctx, r) => desktopPush(ctx, DesktopRoutes.bookDetail(item.id)),
          ),
        ),
      );
}

void _openBookContextMenu({
  required BuildContext context,
  required WidgetRef ref,
  required ReaderItem item,
  required Offset position,
  required VoidCallback onOpen,
  required VoidCallback onRead,
}) {
  final l10n = AppLocalizations.of(context);
  final progress = (item.progressPercent ?? 0).clamp(0.0, 100.0);
  final readLabel =
      progress > 0 && progress < 90
          ? l10n.desktopReaderContinueAction
          : l10n.desktopStartReading;
  ref.read(desktopShellProvider.notifier).openMenu(position, [
    DesktopMenuItem(
      label: readLabel,
      icon: DesktopIcons.book,
      onPressed: onRead,
    ),
    DesktopMenuItem(
      label: l10n.desktopQuickLook,
      icon: DesktopIcons.panel,
      onPressed: () => _showBookQuickLook(ref, l10n, item),
    ),
    DesktopMenuItem(
      label: l10n.desktopReaderBookPage,
      icon: DesktopIcons.info,
      onPressed: onOpen,
    ),
  ]);
}

class _BookCard extends ConsumerWidget {
  const _BookCard({
    required this.item,
    required this.onTap,
    required this.onRead,
  });

  final ReaderItem item;
  final VoidCallback onTap;
  final VoidCallback onRead;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                ..translateByDouble(0.0, hovered ? -14.0 : 0.0, 0, 1)
                ..rotateZ(hovered ? -1.2 * math.pi / 180.0 : 0.0)
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
                  onSecondaryTapDown:
                      (details) => _openBookContextMenu(
                        context: context,
                        ref: ref,
                        item: item,
                        position: details.globalPosition,
                        onOpen: onTap,
                        onRead: onRead,
                      ),
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
