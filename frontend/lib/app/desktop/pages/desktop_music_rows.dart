part of 'desktop_music_page.dart';

class _TrackRows extends StatelessWidget {
  const _TrackRows({
    required this.tracks,
    required this.currentId,
    required this.playing,
    required this.onPlay,
  });

  final List<MusicTrack> tracks;
  final String? currentId;
  final bool playing;
  final ValueChanged<MusicTrack> onPlay;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Column(
      children: [
        _TrackHead(),
        for (var i = 0; i < tracks.length; i++)
          _TrackRow(
            index: i,
            track: tracks[i],
            current: tracks[i].id == currentId,
            playing: playing,
            onPlay: onPlay,
          ),
        const SizedBox(height: 8),
        Divider(height: 1, color: skin.line),
      ],
    );
  }
}

class _TrackHead extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final style = DesktopType.tableHead(skin.text3);
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: skin.line)),
      ),
      child: Row(
        children: [
          SizedBox(width: 52, child: Text('#', style: style)),
          Expanded(flex: 3, child: Text(l10n.desktopColTitle, style: style)),
          Expanded(flex: 2, child: Text(l10n.desktopColAlbum, style: style)),
          SizedBox(
            width: 70,
            child: Align(
              alignment: Alignment.centerRight,
              child: Icon(DesktopIcons.clock, size: 13, color: skin.text3),
            ),
          ),
          // 样例 `.t-head/.t-row` 的第五列 80px 是行内动作区，表头留空。
          const SizedBox(width: 80),
        ],
      ),
    );
  }
}

class _TrackRow extends ConsumerStatefulWidget {
  const _TrackRow({
    required this.index,
    required this.track,
    required this.current,
    required this.playing,
    required this.onPlay,
  });

  final int index;
  final MusicTrack track;
  final bool current;
  final bool playing;
  final ValueChanged<MusicTrack> onPlay;

  @override
  ConsumerState<_TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends ConsumerState<_TrackRow> {
  bool _hovered = false;

  Future<void> _toggleFavorite(MusicTrack track) async {
    try {
      await ref
          .read(musicCenterControllerProvider.notifier)
          .toggleFavorite(track);
    } on Object catch (error) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      showDesktopToast(
        context,
        failureToast(l10n, l10n.photosFavorite, error),
        kind: DesktopToastKind.error,
        icon: DesktopIcons.info,
      );
    }
  }

  void _openMore() {
    _openMoreAt();
  }

  void _openMoreAt([Offset? requestedPosition]) {
    final l10n = AppLocalizations.of(context);
    final track = widget.track;
    final box = context.findRenderObject();
    final position =
        requestedPosition ??
        (box is RenderBox
            ? box.localToGlobal(Offset(0, box.size.height))
            : Offset.zero);
    ref.read(desktopShellProvider.notifier).openMenu(position, [
      DesktopMenuItem(
        label: l10n.desktopPlay,
        icon: DesktopIcons.play,
        onPressed: () => widget.onPlay(track),
      ),
      DesktopMenuItem(
        label: l10n.musicAddToQueue,
        icon: DesktopIcons.queue,
        onPressed:
            () => ref
                .read(musicCenterControllerProvider.notifier)
                .enqueue(MusicPlayableItem.local(track)),
      ),
      const DesktopMenuItem.separator(),
      DesktopMenuItem(
        label: l10n.desktopOpenDetails,
        icon: DesktopIcons.info,
        onPressed: _openDetails,
      ),
      DesktopMenuItem(
        label: l10n.musicEditDetailsLyrics,
        icon: DesktopIcons.edit,
        onPressed:
            () =>
                showDesktopMusicMetadataDrawer(
                  context: context,
                  track: track,
                ).ignore(),
      ),
      const DesktopMenuItem.separator(),
      DesktopMenuItem(
        label: track.favorite ? l10n.photosUnfavorite : l10n.photosFavorite,
        icon: track.favorite ? DesktopIcons.heartFilled : DesktopIcons.heart,
        onPressed: () => _toggleFavorite(track).ignore(),
      ),
    ]);
  }

  void _openDetails() {
    final l10n = AppLocalizations.of(context);
    final track = widget.track;
    final duration = track.durationSeconds;
    ref
        .read(desktopShellProvider.notifier)
        .showDetail(
          DesktopDetailData(
            kind: 'track',
            title: track.title,
            subtitle: '${track.artistName} · ${track.albumTitle}',
            imageUrl: track.coverUrl ?? track.coverThumbUrl,
            squareArt: true,
            facts: [
              MapEntry(l10n.desktopColAlbum, track.albumTitle),
              MapEntry(
                l10n.musicFieldDuration,
                duration == null
                    ? '—'
                    : formatDesktopClock(Duration(seconds: duration)),
              ),
              MapEntry(l10n.musicFieldFormat, track.format),
            ],
            primary: DesktopDetailAction(
              label: l10n.desktopPlay,
              icon: DesktopIcons.play,
              onPressed: () => widget.onPlay(track),
            ),
          ),
        );
  }

  void _playFromRow() {
    if (widget.current && widget.playing) {
      ref.read(musicPortalActionsProvider).togglePlayback().ignore();
      return;
    }
    widget.onPlay(widget.track);
  }

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final track = widget.track;
    final duration = track.durationSeconds;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: _openDetails,
        onDoubleTap: () => widget.onPlay(track),
        onSecondaryTapDown: (details) => _openMoreAt(details.globalPosition),
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color:
                widget.current
                    ? skin.accentWash(0.10)
                    : _hovered
                    ? skin.raise
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(DesktopMetrics.radiusSmall),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 52,
                child: Center(
                  child: SizedBox(
                    width: 30,
                    height: 30,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AnimatedOpacity(
                          opacity: _hovered ? 0 : 1,
                          duration: DesktopMotion.fast,
                          child:
                              widget.current && widget.playing
                                  ? DesktopEqualizer(
                                    color: skin.accent,
                                    size: 13,
                                  )
                                  : Text(
                                    '${widget.index + 1}',
                                    style: DesktopType.numeric(skin.text3),
                                  ),
                        ),
                        IgnorePointer(
                          ignoring: !_hovered,
                          child: AnimatedScale(
                            scale: _hovered ? 1 : 0.72,
                            duration: DesktopMotion.fast,
                            curve: Curves.easeOutBack,
                            child: AnimatedOpacity(
                              opacity: _hovered ? 1 : 0,
                              duration: DesktopMotion.fast,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: _playFromRow,
                                child: Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    color: skin.text,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    widget.current && widget.playing
                                        ? DesktopIcons.pause
                                        : DesktopIcons.play,
                                    size: 13,
                                    color: skin.bg,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: DesktopCover(
                        url: track.coverUrl ?? track.coverThumbUrl,
                        kind: DesktopCoverKind.music,
                        fallbackIcon: DesktopIcons.music,
                        cacheKey: 'desktop-track-${track.id}',
                        iconSize: 14,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DesktopType.rowTitle(
                              widget.current ? skin.accent : skin.text,
                            ),
                          ),
                          Text(
                            track.artistName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DesktopType.caption(skin.text3),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  track.albumTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesktopType.caption(skin.text2),
                ),
              ),
              SizedBox(
                width: 70,
                child: Text(
                  duration == null
                      ? '—'
                      : formatDesktopClock(Duration(seconds: duration)),
                  textAlign: TextAlign.right,
                  style: DesktopType.numeric(skin.text3),
                ),
              ),
              SizedBox(
                width: 80,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _TrackAction(
                      icon:
                          track.favorite
                              ? DesktopIcons.heartFilled
                              : DesktopIcons.heart,
                      active: track.favorite,
                      tooltip:
                          track.favorite
                              ? l10n.photosUnfavorite
                              : l10n.photosFavorite,
                      onTap: () => _toggleFavorite(track).ignore(),
                    ),
                    _TrackAction(
                      icon: DesktopIcons.more,
                      tooltip: l10n.desktopMoreActions,
                      onTap: _openMore,
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
}

/// 行内动作按钮：子级手势消费点击，避免触发整行的播放（样例里的
/// `e.stopPropagation()`）。
class _TrackAction extends StatefulWidget {
  const _TrackAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  @override
  State<_TrackAction> createState() => _TrackActionState();
}

class _TrackActionState extends State<_TrackAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onDoubleTap: () {},
        child: Tooltip(
          message: widget.tooltip,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(
              widget.icon,
              size: 16,
              color:
                  widget.active
                      ? skin.accent
                      : _hovered
                      ? skin.text
                      : skin.text3,
            ),
          ),
        ),
      ),
    );
  }
}

class _QueueRows extends StatelessWidget {
  const _QueueRows({required this.state, required this.onPlayAt});

  final MusicCenterState? state;
  final ValueChanged<int> onPlayAt;

  @override
  Widget build(BuildContext context) {
    final items = state?.playbackItems.take(5).toList() ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TrackHead(),
        for (var i = 0; i < items.length; i++)
          _TrackRow(
            index: i,
            track: items[i].track,
            current: items[i].playableKey == state?.currentItem?.playableKey,
            playing: state?.isPlaying ?? false,
            onPlay: (_) => onPlayAt(i),
          ),
        const SizedBox(height: 8),
        Divider(height: 1, color: DesktopSkin.of(context).line),
      ],
    );
  }
}
