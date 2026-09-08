import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/music_colors.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_primitives.dart';

/// Music Deck 封面内容模型。
class MusicDeckCoverItem {
  const MusicDeckCoverItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.imageUrl,
    this.platform = MusicPlatform.local,
    this.overlayPlatformBadge = false,
    this.icon = Icons.album_rounded,
    this.actions = const <MusicDeckCoverAction>[],
  });

  final String id;
  final String title;
  final String subtitle;
  final String? imageUrl;
  final MusicPlatform platform;
  final bool overlayPlatformBadge;
  final IconData icon;
  final List<MusicDeckCoverAction> actions;
  final VoidCallback onTap;
}

/// 封面卡片提供的上下文操作。
class MusicDeckCoverAction {
  const MusicDeckCoverAction({
    required this.label,
    required this.icon,
    required this.onSelected,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onSelected;
  final bool destructive;
}

/// 使用稳定正方形封面的自适应内容网格。
class MusicDeckCoverGrid extends StatelessWidget {
  const MusicDeckCoverGrid({
    required this.items,
    this.minTileWidth = 142,
    this.maxTileWidth = 196,
    super.key,
  });

  final List<MusicDeckCoverItem> items;
  final double minTileWidth;
  final double maxTileWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 800.0;
        final columns = (width / (minTileWidth + 18)).floor().clamp(1, 8);
        final tileWidth = ((width - (columns - 1) * 18) / columns).clamp(
          minTileWidth,
          maxTileWidth,
        );
        return GridView.builder(
          padding: const EdgeInsets.only(bottom: 112),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 18,
            mainAxisSpacing: 22,
            childAspectRatio: tileWidth / (tileWidth + 48),
          ),
          itemCount: items.length,
          itemBuilder:
              (context, index) => _MusicDeckCoverTile(item: items[index]),
        );
      },
    );
  }
}

/// 横向浏览少量封面内容的内容架。
class MusicDeckCoverShelf extends StatelessWidget {
  const MusicDeckCoverShelf({
    required this.items,
    this.itemWidth = 142,
    super.key,
  });

  final List<MusicDeckCoverItem> items;
  final double itemWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: itemWidth + 54,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (context, index) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          return SizedBox(
            width: itemWidth,
            child: _MusicDeckCoverTile(item: items[index]),
          );
        },
      ),
    );
  }
}

class _MusicDeckCoverTile extends StatefulWidget {
  const _MusicDeckCoverTile({required this.item});

  final MusicDeckCoverItem item;

  @override
  State<_MusicDeckCoverTile> createState() => _MusicDeckCoverTileState();
}

class _MusicDeckCoverTileState extends State<_MusicDeckCoverTile> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final platform = Theme.of(context).platform;
    final mobile =
        platform == TargetPlatform.android || platform == TargetPlatform.iOS;
    final actionsVisible = !mobile && item.actions.isNotEmpty;
    final sourceLabel =
        item.platform == MusicPlatform.local
            ? ''
            : musicDeckSourceLabel(AppLocalizations.of(context), item.platform);
    return Semantics(
      button: true,
      label: [
        item.title,
        item.subtitle,
        if (item.platform != MusicPlatform.local) sourceLabel,
      ].join(', '),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: item.onTap,
          onLongPress:
              mobile && item.actions.isNotEmpty
                  ? () => _showMobileActions(context)
                  : null,
          onFocusChange: (value) => setState(() => _focused = value),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AnimatedScale(
                  scale: _hovered ? 1.018 : 1,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MusicDeckArtwork(
                        title: item.title,
                        imageUrl: item.imageUrl,
                        icon: item.icon,
                      ),
                      if (item.overlayPlatformBadge &&
                          item.platform != MusicPlatform.local)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: MusicDeckSourceBadge(
                            platform: item.platform,
                            overlay: true,
                          ),
                        ),
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: AnimatedOpacity(
                          opacity: _hovered ? 1 : 0,
                          duration: const Duration(milliseconds: 150),
                          child: DecoratedBox(
                            decoration: const BoxDecoration(
                              color: Color(0xE6F4D77E),
                              shape: BoxShape.circle,
                            ),
                            child: const SizedBox.square(
                              dimension: 34,
                              child: Icon(
                                Icons.arrow_forward_rounded,
                                size: 17,
                                color: Color(0xFF11171B),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (actionsVisible)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: IgnorePointer(
                            ignoring: !_hovered && !_focused,
                            child: AnimatedOpacity(
                              opacity: _hovered || _focused ? 1 : 0,
                              duration: const Duration(milliseconds: 140),
                              child: _buildDesktopActions(context),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 9),
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.musicColors.onSurface,
                  fontSize: AppTypography.bodyMedium,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.musicColors.onSurfaceVariant,
                        fontSize: AppTypography.labelSmall,
                      ),
                    ),
                  ),
                  if (item.platform != MusicPlatform.local &&
                      !item.overlayPlatformBadge) ...[
                    const SizedBox(width: 6),
                    MusicDeckSourceBadge(platform: item.platform),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopActions(BuildContext context) {
    final l10n = MaterialLocalizations.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.musicColors.surfaceContainerHigh,
        shape: BoxShape.circle,
        border: Border.all(color: context.musicColors.outline),
      ),
      child: PopupMenuButton<int>(
        tooltip: l10n.showMenuTooltip,
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.more_horiz_rounded, size: 19),
        onSelected: (index) => widget.item.actions[index].onSelected(),
        itemBuilder:
            (context) => [
              for (var index = 0; index < widget.item.actions.length; index++)
                PopupMenuItem<int>(
                  value: index,
                  child: _ActionLabel(action: widget.item.actions[index]),
                ),
            ],
      ),
    );
  }

  Future<void> _showMobileActions(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.musicColors.surfaceContainer,
      showDragHandle: true,
      builder:
          (sheetContext) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
                    child: Text(
                      widget.item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.musicColors.onSurface,
                        fontSize: AppTypography.titleMedium,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  for (final action in widget.item.actions)
                    ListTile(
                      leading: Icon(
                        action.icon,
                        color:
                            action.destructive
                                ? const Color(0xFFFF8F91)
                                : context.musicColors.onSurface,
                      ),
                      title: Text(
                        action.label,
                        style: TextStyle(
                          color:
                              action.destructive
                                  ? const Color(0xFFFF8F91)
                                  : context.musicColors.onSurface,
                        ),
                      ),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        action.onSelected();
                      },
                    ),
                ],
              ),
            ),
          ),
    );
  }
}

class _ActionLabel extends StatelessWidget {
  const _ActionLabel({required this.action});

  final MusicDeckCoverAction action;

  @override
  Widget build(BuildContext context) {
    final color =
        action.destructive ? const Color(0xFFC8353D) : const Color(0xFF1D252A);
    return Row(
      children: [
        Icon(action.icon, size: 18, color: color),
        const SizedBox(width: 10),
        Text(action.label, style: TextStyle(color: color)),
      ],
    );
  }
}
