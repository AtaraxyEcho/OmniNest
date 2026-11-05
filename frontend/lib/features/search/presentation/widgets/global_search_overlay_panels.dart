part of 'global_search_overlay.dart';

Widget _buildFilterBar(
  CommandPaletteColors p,
  AppLocalizations l10n, {
  required _PaletteTab selected,
  required ValueChanged<_PaletteTab> onSelect,
}) {
  final tabs = <(_PaletteTab, String, String)>[
    (_PaletteTab.all, l10n.searchScopeAll, 'Alt+1'),
    (_PaletteTab.video, l10n.searchGroupVideo, 'Alt+2'),
    (_PaletteTab.music, l10n.searchGroupMusic, 'Alt+3'),
    (_PaletteTab.book, l10n.searchGroupBook, 'Alt+4'),
    (_PaletteTab.photo, l10n.searchGroupPhoto, 'Alt+5'),
    (_PaletteTab.file, l10n.searchGroupFile, 'Alt+6'),
    (_PaletteTab.command, l10n.searchGroupCommand, 'Alt+7'),
  ];
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    decoration: BoxDecoration(
      color: p.isDark ? p.surface : p.surfaceSub,
      border: Border(bottom: BorderSide(color: p.hairline)),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (tab, label, key) in tabs)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _TabChip(
                label: label,
                shortcut: key,
                selected: selected == tab,
                p: p,
                onTap: () => onSelect(tab),
              ),
            ),
        ],
      ),
    ),
  );
}

Widget _buildEmptyState(
  CommandPaletteColors p,
  AppLocalizations l10n,
  String query,
) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 48),
    child: Center(
      child: Text(
        query.isEmpty ? l10n.searchEmptyQuery : l10n.searchEmptyResult,
        style: TextStyle(color: p.inkMuted, fontSize: AppTypography.bodyMedium),
      ),
    ),
  );
}

Widget _buildListRow(
  BuildContext context,
  CommandPaletteColors p,
  _Hit hit, {
  required bool selected,
  required VoidCallback onTap,
}) {
  return TweenAnimationBuilder<Color?>(
    tween: ColorTween(end: selected ? p.surfaceMuted : Colors.transparent),
    duration: MotionToken.reduced(context, const Duration(milliseconds: 100)),
    curve: MotionToken.curve,
    builder: (context, color, child) => Material(color: color, child: child),
    child: InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: p.hairline.withValues(alpha: 0.5)),
          ),
        ),
        child: Row(
          children: [
            Icon(_iconForHitType(hit.type), size: 18, color: p.inkMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                hit.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppTypography.bodyMedium,
                  fontWeight: FontWeight.w500,
                  color: p.ink,
                ),
              ),
            ),
            if (hit.subtitle.isNotEmpty) ...[
              const SizedBox(width: 10),
              Text(
                hit.subtitle,
                style: TextStyle(
                  fontSize: AppTypography.labelSmall,
                  color: p.inkMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _HitThumbnail extends ConsumerWidget {
  const _HitThumbnail({required this.hit, required this.p});

  final _Hit hit;
  final CommandPaletteColors p;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fallback = ColoredBox(
      color: p.surfaceMuted,
      child: Icon(Icons.movie_outlined, size: 18, color: p.inkMuted),
    );
    final readerItemId = hit.readerItemId;
    if (readerItemId != null && readerItemId.isNotEmpty) {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final cacheWidth = quantizedDecodeWidth(
        logicalWidth: 116,
        devicePixelRatio: dpr,
      );
      return ref
          .watch(coverBytesProvider(readerItemId))
          .when(
            data:
                (bytes) =>
                    bytes == null || bytes.isEmpty
                        ? fallback
                        : Image.memory(
                          bytes,
                          fit: BoxFit.cover,
                          cacheWidth: cacheWidth,
                          errorBuilder: (_, _, _) => fallback,
                        ),
            loading: () => fallback,
            error: (_, _) => fallback,
          );
    }
    final url = hit.thumbnailUrl;
    if (url == null || url.isEmpty) {
      return fallback;
    }
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Image.network(
      url,
      fit: BoxFit.cover,
      cacheWidth: quantizedDecodeWidth(
        logicalWidth: 116,
        devicePixelRatio: dpr,
      ),
      cacheHeight: quantizedDecodeWidth(
        logicalWidth: 68,
        devicePixelRatio: dpr,
      ),
      errorBuilder: (_, _, _) => fallback,
    );
  }
}

Widget _buildMediaCard(
  BuildContext context,
  CommandPaletteColors p,
  _Hit hit, {
  required bool selected,
  required VoidCallback onTap,
}) {
  final progress = hit.progress ?? 0;
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: p.surface,
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: MotionToken.reduced(
            context,
            const Duration(milliseconds: 100),
          ),
          curve: MotionToken.curve,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? p.surfaceMuted : p.surface,
            border: Border.all(color: selected ? p.border : p.hairline),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: SizedBox(
                  width: 116,
                  height: 68,
                  child: _HitThumbnail(hit: hit, p: p),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hit.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppTypography.bodySmall,
                        fontWeight: FontWeight.w600,
                        color: p.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hit.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppTypography.labelSmall,
                        color: p.inkMuted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 3,
                              backgroundColor: p.surfaceActive,
                              valueColor: AlwaysStoppedAnimation(p.accent),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${(progress * 100).round()}%',
                          style: TextStyle(
                            fontSize: AppTypography.labelMicro,
                            color: p.inkMuted,
                            fontFeatures: const [],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _buildPaletteFooter(CommandPaletteColors p, AppLocalizations l10n) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    decoration: BoxDecoration(
      color: p.surface,
      border: Border(top: BorderSide(color: p.hairline)),
    ),
    child: Row(
      children: [
        _buildFooterHint(p, '↑↓', l10n.searchFooterNavigate),
        const SizedBox(width: 14),
        _buildFooterHint(p, '↵', l10n.searchFooterSelect),
        const SizedBox(width: 14),
        _buildFooterHint(p, 'Tab', l10n.searchFooterFilter),
        const SizedBox(width: 14),
        _buildFooterHint(p, 'Esc', l10n.searchFooterClose),
        const Spacer(),
        Container(width: 6, height: 6, color: p.statusOk),
        const SizedBox(width: 8),
        Text(
          'OmniNest',
          style: TextStyle(
            fontSize: AppTypography.labelSmall,
            color: p.inkMuted,
          ),
        ),
      ],
    ),
  );
}

Widget _buildFooterHint(CommandPaletteColors p, String key, String label) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _Kbd(label: key, p: p),
      const SizedBox(width: 6),
      Text(
        label,
        style: TextStyle(fontSize: AppTypography.labelSmall, color: p.inkMuted),
      ),
    ],
  );
}

IconData _iconForHitType(String type) {
  return switch (type) {
    'file' => Icons.insert_drive_file_outlined,
    'book' => Icons.menu_book_outlined,
    'video' => Icons.movie_outlined,
    'photo' => Icons.photo_outlined,
    'music' => Icons.music_note_outlined,
    'command' => Icons.bolt_outlined,
    _ => Icons.search_rounded,
  };
}

class _Kbd extends StatelessWidget {
  const _Kbd({required this.label, required this.p, this.muted = false});

  final String label;
  final CommandPaletteColors p;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: muted ? p.surfaceMuted : p.kbdBg,
        border: Border.all(color: muted ? p.hairline : p.kbdBorder),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: AppTypography.labelSmall,
          height: 1.0,
          color: muted ? p.inkMuted : p.ink,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.08,
        ),
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.shortcut,
    required this.selected,
    required this.p,
    required this.onTap,
  });

  final String label;
  final String shortcut;
  final bool selected;
  final CommandPaletteColors p;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? p.surfaceActive : Colors.transparent,
          border: Border.all(color: selected ? p.border : Colors.transparent),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected && p.isDark) ...[
              Container(width: 5, height: 5, color: p.accent),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: AppTypography.labelSmall,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? p.ink : p.inkMuted,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              shortcut,
              style: TextStyle(
                fontSize: AppTypography.labelMicro,
                color: selected ? p.inkMuted : p.inkPlaceholder,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
