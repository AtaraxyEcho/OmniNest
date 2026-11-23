part of 'desktop_home_sections.dart';

/// 在读卡（样例 `.reading-card`）。
class DesktopReadingCard extends ConsumerWidget {
  const DesktopReadingCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final dashboardAsync = ref.watch(readerDashboardProvider);
    final dashboard = dashboardAsync.asData?.value;
    final book =
        (dashboard?.continueReading.isNotEmpty ?? false)
            ? dashboard!.continueReading.first
            : (dashboard?.recentItems.isNotEmpty ?? false)
            ? dashboard!.recentItems.first
            : null;
    if (book == null && dashboardAsync.hasError) {
      return DesktopErrorView(
        message: errorReason(dashboardAsync.error!, l10n),
        onRetry: () => ref.invalidate(readerDashboardProvider),
        minHeightFactor: 0.22,
      );
    }
    final skeleton = Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: skin.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: skin.line),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 116,
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: DesktopSkeletonBox(radius: 8),
            ),
          ),
          SizedBox(width: 22),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                DesktopSkeletonBox(width: 120, height: 10),
                SizedBox(height: 10),
                DesktopSkeletonBox(width: 210, height: 22),
                SizedBox(height: 8),
                DesktopSkeletonBox(width: 130, height: 12),
                SizedBox(height: 16),
                DesktopSkeletonBox(height: 5, radius: 3),
                SizedBox(height: 18),
                DesktopSkeletonBox(width: 104, height: 34),
              ],
            ),
          ),
        ],
      ),
    );
    final Widget content;
    if (book == null) {
      content = DesktopEmpty(
        message: l10n.desktopHomeEmptyBook,
        icon: DesktopIcons.book,
        actionLabel: l10n.desktopOpenReader,
        onAction: () => context.go(DesktopRoutes.reader),
      );
    } else {
      final progress = (book.progressPercent ?? 0) / 100;
      final tone = DesktopPalette.bookToneFor(book.id);
      content = DesktopHover(
        builder:
            (context, hovered) => GestureDetector(
              onTap: () => context.push(DesktopRoutes.bookDetail(book.id)),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: MotionToken.reduced(context, MotionToken.normal),
                curve: MotionToken.curve,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: skin.panel,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: hovered ? skin.line2 : skin.line),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 116,
                      child: AspectRatio(
                        aspectRatio: 2 / 3,
                        child:
                            book.hasCover
                                ? DesktopCover(
                                  url: book.coverUrl,
                                  kind: DesktopCoverKind.reader,
                                  readerItemId: book.id,
                                  fallbackIcon: DesktopIcons.book,
                                  borderRadius: const BorderRadius.horizontal(
                                    left: Radius.circular(4),
                                    right: Radius.circular(10),
                                  ),
                                )
                                : DesktopPaperCover(
                                  title: book.title,
                                  author: book.authorName ?? '',
                                  tone: tone.tone,
                                  ink: tone.ink,
                                  compact: true,
                                ),
                      ),
                    ),
                    const SizedBox(width: 22),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if ((book.currentChapterTitle ?? '').isNotEmpty)
                            DesktopEyebrow(
                              l10n.desktopChapterLabel(
                                book.currentChapterTitle!,
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              book.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: DesktopType.displaySm(skin.text),
                            ),
                          ),
                          if ((book.authorName ?? '').isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                book.authorName!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: DesktopType.dense(skin.text2),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(top: 14, bottom: 16),
                            child: DesktopProgress(
                              fraction: progress,
                              label: l10n.desktopProgressPercent(
                                (progress * 100).round(),
                              ),
                            ),
                          ),
                          DesktopButton(
                            label: l10n.desktopContinue,
                            icon: DesktopIcons.book,
                            variant: DesktopButtonVariant.soft,
                            onPressed:
                                () => context.push(
                                  DesktopRoutes.bookDetail(book.id),
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
      );
    }
    return DesktopSkeletonSwitcher(
      regionId: 'home-reading-card',
      hasData: dashboard != null,
      loading: book == null && dashboardAsync.isLoading,
      skeleton: skeleton,
      child: content,
    );
  }
}
