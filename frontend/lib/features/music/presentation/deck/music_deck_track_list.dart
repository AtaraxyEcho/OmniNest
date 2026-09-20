import 'package:flutter/material.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/music_colors.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_primitives.dart';

/// 支持来源标识、键盘激活和局部悬停反馈的歌曲列表。
class MusicDeckTrackList extends StatefulWidget {
  const MusicDeckTrackList({
    required this.items,
    required this.onPlay,
    this.currentPlayableKey,
    this.onToggleFavorite,
    this.onDelete,
    this.onEnqueue,
    this.onAddToPlaylist,
    this.emptyTitle,
    this.emptyMessage,
    this.scrollable = true,
    this.onReachEnd,
    this.footer,
    this.onLongPress,
    this.selectedIds,
    super.key,
  });

  final List<MusicPlayableItem> items;
  final String? currentPlayableKey;
  final ValueChanged<int> onPlay;
  final ValueChanged<MusicPlayableItem>? onToggleFavorite;
  final ValueChanged<MusicPlayableItem>? onDelete;
  final ValueChanged<MusicPlayableItem>? onEnqueue;
  final ValueChanged<MusicPlayableItem>? onAddToPlaylist;
  final String? emptyTitle;
  final String? emptyMessage;
  final bool scrollable;
  final VoidCallback? onReachEnd;
  final Widget? footer;
  final VoidCallback? onLongPress;
  final Set<String>? selectedIds;

  @override
  State<MusicDeckTrackList> createState() => _MusicDeckTrackListState();
}

class _MusicDeckTrackListState extends State<MusicDeckTrackList> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    final onReachEnd = widget.onReachEnd;
    if (onReachEnd == null || !_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    if (position.maxScrollExtent - position.pixels <= 480) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        onReachEnd();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      final l10n = AppLocalizations.of(context);
      return _MusicDeckEmptyState(
        title: widget.emptyTitle ?? l10n.musicNoTracks,
        message: widget.emptyMessage ?? l10n.musicTracksHint,
      );
    }
    if (!widget.scrollable) {
      return Column(
        children: [
          for (var index = 0; index < widget.items.length; index++)
            SizedBox(height: 66, child: _buildTrackRow(index)),
        ],
      );
    }
    final footer = widget.footer;
    return Scrollbar(
      controller: _scrollController,
      interactive: true,
      child: ListView.builder(
        controller: _scrollController,
        primary: false,
        // 桌面态卡片已带 80px 播放条避让（_playerOverlayInset），
        // 这里仅保留小余量；紧凑态播放条在布局流内，保留完整避让。
        padding: EdgeInsets.only(
          bottom:
              MobileShellScope.isHosted(context) ||
                      MediaQuery.sizeOf(context).width < 760
                  ? 108
                  : 24,
        ),
        itemCount: widget.items.length + (footer == null ? 0 : 1),
        itemExtent: 66,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        itemBuilder: (context, index) {
          if (footer != null && index == widget.items.length) {
            return SizedBox(height: 66, child: Center(child: footer));
          }
          return _buildTrackRow(index);
        },
      ),
    );
  }

  Widget _buildTrackRow(int index) {
    final item = widget.items[index];
    return _MusicDeckTrackRow(
      item: item,
      index: index,
      selected: widget.currentPlayableKey == item.playableKey,
      onTap: () => widget.onPlay(index),
      onToggleFavorite:
          widget.onToggleFavorite == null || item.ref is! LocalMusicRef
              ? null
              : () => widget.onToggleFavorite!(item),
      onDelete:
          widget.onDelete == null || item.ref is! LocalMusicRef
              ? null
              : () => widget.onDelete!(item),
      onEnqueue:
          widget.onEnqueue == null ? null : () => widget.onEnqueue!(item),
      onAddToPlaylist:
          widget.onAddToPlaylist == null || item.ref is! LocalMusicRef
              ? null
              : () => widget.onAddToPlaylist!(item),
      onLongPress: widget.onLongPress,
      checked: widget.selectedIds?.contains(item.track.id),
    );
  }
}

class _MusicDeckTrackRow extends StatefulWidget {
  const _MusicDeckTrackRow({
    required this.item,
    required this.index,
    required this.selected,
    required this.onTap,
    this.onToggleFavorite,
    this.onDelete,
    this.onEnqueue,
    this.onAddToPlaylist,
    this.onLongPress,
    this.checked,
  });

  final MusicPlayableItem item;
  final int index;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onDelete;
  final VoidCallback? onEnqueue;
  final VoidCallback? onAddToPlaylist;
  final VoidCallback? onLongPress;
  final bool? checked;

  @override
  State<_MusicDeckTrackRow> createState() => _MusicDeckTrackRowState();
}

class _MusicDeckTrackRowState extends State<_MusicDeckTrackRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.musicColors;
    final track = widget.item.track;
    final platform = switch (widget.item.ref) {
      LocalMusicRef() => MusicPlatform.local,
      OnlineMusicRef(:final platform) => platform,
    };
    final mobile = MediaQuery.sizeOf(context).width < 600;
    final foreground = widget.selected ? colors.primary : colors.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Semantics(
        button: true,
        selected: widget.selected,
        label: '${track.title}, ${track.artistName}',
        child: Material(
          // 播放行为持久激活态、悬停为瞬态反馈：hoverBg 弱于 playingRowBg，
          // selected 分支优先于悬停，播放行不再被悬停实底冲淡。
          color:
              widget.selected
                  ? colors.playingRowBg
                  : _hovered
                  ? colors.hoverBg
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onHover: (value) => setState(() => _hovered = value),
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  if (widget.checked != null)
                    Checkbox(
                      value: widget.checked,
                      onChanged: (_) => widget.onTap(),
                    )
                  else
                    SizedBox.square(
                      dimension: 40,
                      child: MusicDeckArtwork(
                        title: track.title,
                        imageUrl: track.coverUrl,
                        borderRadius: 5,
                      ),
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 5,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: foreground,
                            fontSize: AppTypography.bodyLarge,
                            fontWeight:
                                widget.selected
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          track.artistName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: AppTypography.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (MediaQuery.sizeOf(context).width >= 900) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: Text(
                        track.albumTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: AppTypography.bodySmall,
                        ),
                      ),
                    ),
                  ],
                  if (!mobile) ...[
                    const SizedBox(width: 12),
                    MusicDeckSourceBadge(platform: platform),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 42,
                      child: Text(
                        track.durationText,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: AppTypography.labelSmall,
                        ),
                      ),
                    ),
                  ] else if (widget.selected) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.graphic_eq_rounded,
                      size: 18,
                      color: colors.primary,
                    ),
                  ],
                  if (widget.onToggleFavorite != null) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip:
                          track.favorite
                              ? AppLocalizations.of(context).musicUnfavorite
                              : AppLocalizations.of(context).musicFavorite,
                      onPressed: widget.onToggleFavorite,
                      icon: Icon(
                        track.favorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 18,
                        color:
                            track.favorite
                                ? const Color(0xFFF28C9A)
                                : colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (widget.onEnqueue != null ||
                      widget.onAddToPlaylist != null ||
                      widget.onDelete != null)
                    PopupMenuButton<String>(
                      tooltip: AppLocalizations.of(context).coreMore,
                      icon: Icon(
                        Icons.more_vert_rounded,
                        size: 18,
                        color: colors.onSurfaceVariant,
                      ),
                      onSelected: (value) {
                        if (value == 'enqueue') {
                          widget.onEnqueue?.call();
                        } else if (value == 'addToPlaylist') {
                          widget.onAddToPlaylist?.call();
                        } else if (value == 'delete') {
                          widget.onDelete?.call();
                        }
                      },
                      itemBuilder:
                          (context) => [
                            if (widget.onEnqueue != null)
                              PopupMenuItem(
                                value: 'enqueue',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.queue_music_rounded,
                                      size: 20,
                                      color: colors.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      AppLocalizations.of(
                                        context,
                                      ).musicPlayNext,
                                    ),
                                  ],
                                ),
                              ),
                            if (widget.onAddToPlaylist != null)
                              PopupMenuItem(
                                value: 'addToPlaylist',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.playlist_add_rounded,
                                      size: 20,
                                      color: colors.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      AppLocalizations.of(
                                        context,
                                      ).musicAddToPlaylist,
                                    ),
                                  ],
                                ),
                              ),
                            if (widget.onDelete != null)
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.delete_outline_rounded,
                                      color:
                                          Theme.of(context).colorScheme.error,
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      AppLocalizations.of(
                                        context,
                                      ).musicDeleteLocalTrack,
                                    ),
                                  ],
                                ),
                              ),
                          ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MusicDeckEmptyState extends StatelessWidget {
  const _MusicDeckEmptyState({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.musicColors;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.library_music_outlined,
              size: 42,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.onSurface,
                fontSize: AppTypography.titleLarge,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.onSurfaceVariant,
                fontSize: AppTypography.bodyMedium,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
