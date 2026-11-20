part of 'desktop_music_page.dart';

/// 当前播放主视觉（样例 `.focus`）：模糊封面打底、唱片随播放转、右侧频谱。
class _FocusHero extends StatelessWidget {
  const _FocusHero({required this.state, required this.onTogglePlayback});

  final MusicCenterState? state;
  final VoidCallback onTogglePlayback;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final item = state?.currentItem;
    final track = item?.track;
    final playing = state?.isPlaying ?? false;
    // Hero 使用列表封面地址优先：本地封面会走鉴权缩略图，平台封面会走平台
    // 提供的方形缩放图。这样大图不会在固定唱片容器里被按矩形拉伸。
    final cover = _firstMusicCover(track?.listCoverUrl, track?.coverUrl);
    // 样例 `.focus::before` 的 `color-mix(--hue 30%, rgba(5,8,10,.55))`：
    // 曲目色相混进深色底，切曲时按 1s 补间，不是硬切。
    final tint =
        Color.lerp(
          desktopTrackHue(track?.hue, skin.accent),
          const Color(0xFF05080A),
          0.70,
        )!;

    return Container(
      // 样例 min-height 340；内容实际高 = 封面 280 + 上下 34 = 348。
      height: 348,
      margin: const EdgeInsets.only(bottom: 40),
      // 样例 `.focus` 是 `border-radius:26 + overflow:hidden + border + shadow`。
      // 边框必须走 foregroundDecoration：写在 decoration 里会被紧随其后的
      // 模糊封面层整片盖住，圆角处只剩抗锯齿的半像素，看起来像缺了一圈。
      decoration: BoxDecoration(
        color: skin.raise,
        borderRadius: BorderRadius.circular(DesktopMetrics.radiusHero),
        boxShadow: skin.shadow,
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DesktopMetrics.radiusHero),
        border: Border.all(color: skin.line2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (cover != null)
            RepaintBoundary(
              child: ImageFiltered(
                imageFilter: desktopGlassFilter(
                  blur: 42,
                  saturation: 1.6,
                  brightness: 0.7,
                ),
                child: Transform.scale(
                  scale: 1.2,
                  child: DesktopCover(
                    url: cover,
                    kind: DesktopCoverKind.music,
                    cacheKey:
                        'desktop-music-focus-background-${track?.id ?? 'empty'}',
                    fallback: const SizedBox.shrink(),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: AnimatedContainer(
              duration: DesktopMotion.colorFade,
              curve: DesktopMotion.ease,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    tint.withValues(alpha: 0.55),
                    skin.bg.withValues(alpha: 0.42),
                    skin.bg.withValues(alpha: 0.72),
                  ],
                ),
              ),
            ),
          ),
          // 样例 `.f-viz`：贴底通栏 90px、白色 56 柱、整体 55% 不透明度，
          // 只作氛围，不接指针。
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 90,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.55,
                child: DesktopVisualizer(
                  playing: playing,
                  color: Colors.white,
                  bars: 56,
                  seed: 3,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 34, 40, 34),
            child: Row(
              children: [
                if (cover != null)
                  _SpinningCover(
                    url: cover,
                    playing: playing,
                    size: 280,
                    cacheKey: 'desktop-music-focus-${track?.id ?? cover}',
                    onTap: () => desktopPush(context, DesktopRoutes.nowPlaying),
                  ),
                const SizedBox(width: 40),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _heroEyebrow(l10n, playing, track),
                        style: DesktopType.eyebrow(
                          Colors.white.withValues(alpha: 0.70),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        track?.title ?? l10n.desktopNothingPlaying,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DesktopType.displayXl(
                          Colors.white,
                          MediaQuery.sizeOf(context).width,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        track == null
                            ? l10n.desktopNothingPlayingHint
                            : '${track.artistName} · ${track.albumTitle}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DesktopType.dense(
                          Colors.white.withValues(alpha: 0.78),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          DesktopButton(
                            label:
                                playing ? l10n.desktopPause : l10n.desktopPlay,
                            icon:
                                playing
                                    ? DesktopIcons.pause
                                    : DesktopIcons.play,
                            variant: DesktopButtonVariant.primary,
                            large: true,
                            onPressed: track == null ? null : onTogglePlayback,
                          ),
                          const SizedBox(width: 10),
                          DesktopButton(
                            label: l10n.desktopOpenNowPlaying,
                            icon: DesktopIcons.expand,
                            variant: DesktopButtonVariant.glass,
                            large: true,
                            onPressed:
                                () => desktopPush(
                                  context,
                                  DesktopRoutes.nowPlaying,
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
        ],
      ),
    );
  }
}

/// 封面字段在在线曲目里可能以空字符串表示缺失，不能只用 `??` 判断。
/// Hero 与唱片封面必须共享同一回退顺序，避免背景有图而前景落占位图。
String? _firstMusicCover(String? primary, String? fallback) {
  final primaryValue = primary?.trim() ?? '';
  if (primaryValue.isNotEmpty) {
    return primaryValue;
  }
  final fallbackValue = fallback?.trim() ?? '';
  return fallbackValue.isEmpty ? null : fallbackValue;
}

/// 样例 `.f-copy .eyebrow`：Playing from {album} / Paused · {album}。
String _heroEyebrow(AppLocalizations l10n, bool playing, MusicTrack? track) {
  final label =
      playing ? l10n.desktopMusicPlayingFrom : l10n.desktopMusicPaused;
  final album = track?.albumTitle.trim() ?? '';
  if (album.isEmpty) {
    return label.toUpperCase();
  }
  return (playing ? '$label $album' : '$label · $album').toUpperCase();
}

class _SpinningCover extends StatefulWidget {
  const _SpinningCover({
    required this.url,
    required this.playing,
    required this.onTap,
    required this.cacheKey,
    this.size = 280,
  });

  final String url;
  final bool playing;
  final VoidCallback onTap;
  final String cacheKey;
  final double size;

  @override
  State<_SpinningCover> createState() => _SpinningCoverState();
}

class _SpinningCoverState extends State<_SpinningCover>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: DesktopMotion.vinylSpinFull,
  );

  bool _started = false;

  // MediaQuery 在 initState 阶段还不可依赖。
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) {
      return;
    }
    _started = true;
    _sync();
  }

  @override
  void didUpdateWidget(_SpinningCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final animate =
        widget.playing &&
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    if (animate) {
      if (!_spin.isAnimating) {
        _spin.repeat();
      }
    } else {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    // 样例 `.f-art`：暂停时是 18 圆角封面，播放时收成圆形唱片并加中心轴孔。
    final radius =
        widget.playing ? widget.size / 2 : DesktopMetrics.radiusLarge;
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: DesktopMotion.of(context, DesktopMotion.soft),
        curve: DesktopMotion.ease,
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 40,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            RotationTransition(
              turns: _spin,
              child: AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius),
                  child: DesktopCover(
                    url: widget.url,
                    kind: DesktopCoverKind.music,
                    fallbackIcon: DesktopIcons.music,
                    cacheKey: widget.cacheKey,
                    fit: BoxFit.cover,
                    cacheWidth: (widget.size * 2).round(),
                    cacheHeight: (widget.size * 2).round(),
                    iconSize: 32,
                  ),
                ),
              ),
            ),
            if (widget.playing)
              Center(
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: skin.bg,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.24),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AlbumRail extends StatelessWidget {
  const _AlbumRail({required this.albums, required this.onOpen});

  final List<MusicAlbum> albums;
  final ValueChanged<MusicAlbum> onOpen;

  @override
  Widget build(BuildContext context) {
    // 样例 `.album-row.big .album`：宽度 clamp(168px, 14vw, 210px)，gap 20。
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth * 0.14).clamp(168.0, 210.0);
        return SizedBox(
          height: width + 70,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            itemCount: albums.length,
            separatorBuilder: (_, _) => const SizedBox(width: 20),
            itemBuilder:
                (context, index) => SizedBox(
                  width: width,
                  child: DesktopStagger(
                    index: index,
                    child: _AlbumCard(
                      album: albums[index],
                      onTap: () => onOpen(albums[index]),
                    ),
                  ),
                ),
          ),
        );
      },
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({required this.playlist, required this.onOpen});

  final MusicPlaylist playlist;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    return DesktopHoverLift(
      onTap: onOpen,
      tooltip: l10n.musicOpenPlaylist,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              // 样例歌单卡是 `.album`，没有 `.tilt`：只有封面静态描边 +
              // 14px 圆角，hover 只上移 4px。此前套 DesktopTilt 会多出
              // 指针柔光和大块投影，已按源码移除。
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.6),
                      blurRadius: 30,
                      offset: const Offset(0, 14),
                      spreadRadius: -12,
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: DesktopCover(
                      url: playlist.listCoverUrl,
                      kind: DesktopCoverKind.music,
                      fallbackIcon: DesktopIcons.queue,
                      cacheKey: 'desktop-playlist-${playlist.id}',
                      iconSize: 28,
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: skin.bg.withValues(alpha: 0.72),
                    shape: BoxShape.circle,
                    border: Border.all(color: skin.line2),
                  ),
                  child: Icon(DesktopIcons.play, size: 16, color: skin.text),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            playlist.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DesktopType.bodyStrong(skin.text),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.musicDeckTrackCount(playlist.trackCount),
            style: DesktopType.caption(skin.text3),
          ),
        ],
      ),
    );
  }
}

class _NewPlaylistCard extends StatelessWidget {
  const _NewPlaylistCard({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    return DesktopHoverLift(
      onTap: onCreate,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: skin.raise,
                borderRadius: BorderRadius.circular(DesktopMetrics.radiusCard),
                border: Border.all(color: skin.line2),
              ),
              child: Center(
                child: Icon(DesktopIcons.plus, size: 28, color: skin.accent),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            l10n.musicCreatePlaylist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DesktopType.bodyStrong(skin.text),
          ),
        ],
      ),
    );
  }
}

class _PlaylistDetail extends StatelessWidget {
  const _PlaylistDetail({
    required this.playlist,
    required this.tracks,
    required this.loadingMore,
    required this.currentId,
    required this.playing,
    required this.onBack,
    required this.onPlay,
    required this.onShuffle,
    required this.onAddToQueue,
    required this.onEdit,
    required this.onDelete,
    required this.onTrackPlay,
  });

  final MusicPlaylist playlist;
  final List<MusicTrack> tracks;
  final bool loadingMore;
  final String? currentId;
  final bool playing;
  final VoidCallback onBack;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;
  final VoidCallback onAddToQueue;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<MusicTrack> onTrackPlay;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: DesktopButton(
            label: l10n.musicDeckPlaylists,
            icon: DesktopIcons.left,
            variant: DesktopButtonVariant.ghost,
            onPressed: onBack,
          ),
        ),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              width: 190,
              height: 190,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(DesktopMetrics.radiusCard),
                child: DesktopCover(
                  url: playlist.listCoverUrl,
                  kind: DesktopCoverKind.music,
                  fallbackIcon: DesktopIcons.queue,
                  cacheKey: 'desktop-playlist-detail-${playlist.id}',
                  iconSize: 36,
                ),
              ),
            ),
            const SizedBox(width: 28),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DesktopEyebrow(l10n.musicDeckPlaylists.toUpperCase()),
                  const SizedBox(height: 8),
                  Text(
                    playlist.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: DesktopType.displayXl(
                      skin.text,
                      MediaQuery.sizeOf(context).width,
                    ),
                  ),
                  if ((playlist.description ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      playlist.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: DesktopType.dense(skin.text2),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    l10n.musicDeckTrackCount(playlist.trackCount),
                    style: DesktopType.caption(skin.text3),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      DesktopButton(
                        label: l10n.musicPlay,
                        icon: DesktopIcons.play,
                        variant: DesktopButtonVariant.primary,
                        large: true,
                        onPressed: tracks.isEmpty ? null : onPlay,
                      ),
                      DesktopButton(
                        label: l10n.musicShuffle,
                        icon: DesktopIcons.shuffle,
                        variant: DesktopButtonVariant.soft,
                        large: true,
                        onPressed: tracks.isEmpty ? null : onShuffle,
                      ),
                      DesktopButton(
                        label: l10n.musicAddToQueue,
                        icon: DesktopIcons.queue,
                        variant: DesktopButtonVariant.ghost,
                        large: true,
                        onPressed: tracks.isEmpty ? null : onAddToQueue,
                      ),
                      DesktopButton(
                        label: l10n.musicEditPlaylist,
                        icon: DesktopIcons.edit,
                        variant: DesktopButtonVariant.ghost,
                        large: true,
                        onPressed: onEdit,
                      ),
                      DesktopButton(
                        label: l10n.musicDeletePlaylist,
                        icon: DesktopIcons.trash,
                        variant: DesktopButtonVariant.ghost,
                        large: true,
                        onPressed: onDelete,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        if (tracks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 50),
            child: Center(
              child: Text(
                l10n.musicPlaylistEmptyHint,
                style: DesktopType.medium(skin.text3),
              ),
            ),
          )
        else
          _TrackRows(
            tracks: tracks,
            currentId: currentId,
            playing: playing,
            onPlay: onTrackPlay,
          ),
        if (loadingMore)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 22),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
      ],
    );
  }
}

class _PlaylistEditor extends StatefulWidget {
  const _PlaylistEditor({required this.playlist, required this.takenNames});

  final MusicPlaylist? playlist;
  final Set<String> takenNames;

  @override
  State<_PlaylistEditor> createState() => _PlaylistEditorState();
}

class _PlaylistEditorState extends State<_PlaylistEditor> {
  late final TextEditingController _name = TextEditingController(
    text: widget.playlist?.name ?? '',
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.playlist?.description ?? '',
  );

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final name = _name.text.trim();
    final duplicate =
        name.isNotEmpty && widget.takenNames.contains(name.toLowerCase());
    final canSave = name.isNotEmpty && !duplicate;
    return DesktopDrawerFrame(
      eyebrow: l10n.musicDeckPlaylists,
      title:
          widget.playlist == null
              ? l10n.musicCreatePlaylist
              : l10n.musicEditPlaylist,
      footer: Wrap(
        spacing: 8,
        children: [
          DesktopButton(
            label: l10n.filesCancel,
            onPressed: () => closeDesktopModal(context),
          ),
          DesktopButton(
            label: widget.playlist == null ? l10n.musicCreate : l10n.musicSave,
            variant: DesktopButtonVariant.primary,
            onPressed:
                canSave
                    ? () => closeDesktopModal(context, (
                      name,
                      _description.text.trim(),
                    ))
                    : null,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DesktopTextField(
            keyName: 'desktop-playlist-name',
            controller: _name,
            label: l10n.musicPlaylistName,
            hint: l10n.musicPlaylistName,
            required: true,
            maxLength: 48,
            autofocus: true,
            error: duplicate ? l10n.musicPlaylistNameDuplicate : null,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 18),
          DesktopTextField(
            keyName: 'desktop-playlist-description',
            controller: _description,
            label: l10n.musicPlaylistDescription,
            hint: l10n.musicPlaylistDescription,
            maxLength: 160,
            maxLines: 3,
            height: 96,
            onChanged: (_) => setState(() {}),
          ),
          if (duplicate) ...[
            const SizedBox(height: 8),
            Text(
              l10n.musicPlaylistNameDuplicate,
              style: DesktopType.caption(skin.bad),
            ),
          ],
        ],
      ),
    );
  }
}

class _AlbumGrid extends StatelessWidget {
  const _AlbumGrid({
    required this.albums,
    required this.emptyLabel,
    required this.onOpen,
    this.onlineTracks = const <OnlineTrack>[],
    this.currentId,
    this.playing = false,
    this.onPlayOnline,
  });

  final List<MusicAlbum> albums;
  final String emptyLabel;
  final ValueChanged<MusicAlbum> onOpen;
  final List<OnlineTrack> onlineTracks;
  final String? currentId;
  final bool playing;
  final ValueChanged<List<OnlineTrack>>? onPlayOnline;

  @override
  Widget build(BuildContext context) {
    final onlineAlbums = _onlineAlbumGroups(onlineTracks);
    if (albums.isEmpty && onlineAlbums.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 80),
        child: Center(
          child: Text(
            emptyLabel,
            style: DesktopType.medium(DesktopSkin.of(context).text3),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 200).floor().clamp(2, 8);
        final width = (constraints.maxWidth - (columns - 1) * 18) / columns;
        return Wrap(
          spacing: 18,
          runSpacing: 24,
          children: [
            for (var i = 0; i < albums.length; i++)
              SizedBox(
                width: width,
                child: DesktopStagger(
                  index: i,
                  child: _AlbumCard(
                    album: albums[i],
                    onTap: () => onOpen(albums[i]),
                  ),
                ),
              ),
            if (onPlayOnline != null)
              for (var i = 0; i < onlineAlbums.length; i++)
                SizedBox(
                  width: width,
                  child: DesktopStagger(
                    index: albums.length + i,
                    child: _DesktopOnlineAlbumCard(
                      tracks: onlineAlbums[i],
                      currentId: currentId,
                      playing: playing,
                      onPlay: () => onPlayOnline!(onlineAlbums[i]),
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.album, required this.onTap});

  final MusicAlbum album;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return DesktopHover(
      builder:
          (context, hovered) => GestureDetector(
            key: ValueKey<String>('desktop-music-album-${album.id}'),
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: DesktopMotion.springHover,
              curve: DesktopMotion.spring,
              transform: Matrix4.translationValues(0, hovered ? -4 : 0, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 样例 `.album .cover` 只有静态 14px 圆角 + 柔和投影，没有
                  // `.tilt/.shine` 的指针柔光；这里不再用 DesktopTilt，避免 hover 光晕。
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.6),
                          blurRadius: 30,
                          offset: const Offset(0, 14),
                          spreadRadius: -12,
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: DesktopCover(
                          url: album.coverUrl,
                          kind: DesktopCoverKind.music,
                          fallbackIcon: DesktopIcons.music,
                          cacheKey: 'desktop-album-${album.id}',
                          iconSize: 28,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    album.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DesktopType.bodyStrong(skin.text),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    album.artistName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DesktopType.caption(skin.text3),
                  ),
                ],
              ),
            ),
          ),
    );
  }
}

enum _MusicTrackSort { title, artist, album, duration }

class _TracksView extends StatefulWidget {
  const _TracksView({
    required this.tracks,
    required this.search,
    required this.onPlay,
    required this.currentId,
    required this.playing,
    this.showControls = true,
  });

  final List<MusicTrack> tracks;
  final TextEditingController search;
  final ValueChanged<MusicTrack> onPlay;
  final String? currentId;
  final bool playing;
  final bool showControls;

  @override
  State<_TracksView> createState() => _TracksViewState();
}

class _TracksViewState extends State<_TracksView> {
  bool _favoritesOnly = false;
  _MusicTrackSort _sort = _MusicTrackSort.title;
  int _page = 0;
  int _pageSize = 20;

  List<MusicTrack> _filteredTracks() {
    final query = widget.search.text.trim().toLowerCase();
    final tracks =
        widget.tracks.where((track) {
          if (widget.showControls && _favoritesOnly && !track.favorite) {
            return false;
          }
          if (!widget.showControls || query.isEmpty) {
            return true;
          }
          return '${track.title} ${track.artistName} ${track.albumTitle}'
              .toLowerCase()
              .contains(query);
        }).toList();
    if (widget.showControls) {
      tracks.sort((a, b) {
        return switch (_sort) {
          _MusicTrackSort.title => a.title.toLowerCase().compareTo(
            b.title.toLowerCase(),
          ),
          _MusicTrackSort.artist => a.artistName.toLowerCase().compareTo(
            b.artistName.toLowerCase(),
          ),
          _MusicTrackSort.album => a.albumTitle.toLowerCase().compareTo(
            b.albumTitle.toLowerCase(),
          ),
          _MusicTrackSort.duration => (a.durationSeconds ?? 0).compareTo(
            b.durationSeconds ?? 0,
          ),
        };
      });
    }
    return tracks;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final filtered = _filteredTracks();
    final totalPages = (filtered.length / _pageSize).ceil().clamp(1, 1 << 30);
    final page = _page.clamp(0, totalPages - 1);
    final start = page * _pageSize;
    final visible =
        widget.showControls
            ? filtered.skip(start).take(_pageSize).toList(growable: false)
            : filtered;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showControls)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 18,
              runSpacing: 12,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      width: 320,
                      child: DesktopTextField(
                        key: const ValueKey<String>('desktop-music-search'),
                        controller: widget.search,
                        onChanged: (value) {
                          setState(() => _page = 0);
                        },
                        hint: l10n.desktopMusicSearchHint,
                        prefixIcon: DesktopIcons.search,
                        height: 36,
                      ),
                    ),
                    DesktopChipButton(
                      label: l10n.desktopFilterAll,
                      selected: !_favoritesOnly,
                      count: widget.tracks.length,
                      onTap:
                          () => setState(() {
                            _favoritesOnly = false;
                            _page = 0;
                          }),
                    ),
                    DesktopChipButton(
                      label: l10n.desktopPinnedFavorites,
                      selected: _favoritesOnly,
                      count:
                          widget.tracks.where((track) => track.favorite).length,
                      onTap:
                          () => setState(() {
                            _favoritesOnly = true;
                            _page = 0;
                          }),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.desktopReaderSortLabel,
                      style: DesktopType.caption(skin.text3),
                    ),
                    const SizedBox(width: 8),
                    DesktopSelect<_MusicTrackSort>(
                      value: _sort,
                      variant: DesktopSelectVariant.small,
                      width: 158,
                      options: [
                        DesktopSelectOption(
                          value: _MusicTrackSort.title,
                          label: l10n.desktopSortTitle,
                        ),
                        DesktopSelectOption(
                          value: _MusicTrackSort.artist,
                          label: l10n.musicFieldArtist,
                        ),
                        DesktopSelectOption(
                          value: _MusicTrackSort.album,
                          label: l10n.desktopColAlbum,
                        ),
                        DesktopSelectOption(
                          value: _MusicTrackSort.duration,
                          label: l10n.musicFieldDuration,
                        ),
                      ],
                      onChanged:
                          (value) => setState(() {
                            _sort = value;
                            _page = 0;
                          }),
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (visible.isEmpty)
          DesktopEmpty(
            message:
                widget.showControls
                    ? l10n.desktopMusicNoTracks
                    : l10n.musicNoFavoritesYet,
            icon:
                widget.showControls ? DesktopIcons.search : DesktopIcons.heart,
            description: widget.showControls ? null : l10n.musicNoFavoritesHint,
            actionLabel:
                widget.showControls &&
                        (widget.search.text.isNotEmpty || _favoritesOnly)
                    ? l10n.desktopReaderClearFilters
                    : null,
            onAction:
                widget.showControls &&
                        (widget.search.text.isNotEmpty || _favoritesOnly)
                    ? () {
                      widget.search.clear();
                      setState(() {
                        _favoritesOnly = false;
                        _page = 0;
                      });
                    }
                    : null,
            large: !widget.showControls,
          )
        else
          _TrackRows(
            tracks: visible,
            currentId: widget.currentId,
            playing: widget.playing,
            onPlay: widget.onPlay,
          ),
        if (widget.showControls)
          DesktopPager(
            page: page,
            totalPages: totalPages,
            onPageChanged: (value) => setState(() => _page = value),
            pageSize: _pageSize,
            pageSizeOptions: const [20, 50, 100],
            onPageSizeChanged:
                (value) => setState(() {
                  _pageSize = value;
                  _page = 0;
                }),
          ),
      ],
    );
  }
}
