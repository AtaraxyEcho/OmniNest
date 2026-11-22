part of 'desktop_now_playing_page.dart';

class _SidePanel extends ConsumerWidget {
  const _SidePanel({
    required this.track,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.format,
    required this.bitrate,
    required this.sampleRate,
    required this.fileSize,
    required this.position,
    required this.positionStream,
    required this.playing,
    required this.hueColor,
    required this.tab,
    required this.onTab,
    required this.showTranslation,
    required this.onToggleTranslation,
    required this.onSeek,
    required this.queue,
    required this.currentKey,
    required this.onPickQueue,
    required this.onToggleFavorite,
    required this.onBrowseMusic,
    required this.onEdit,
  });

  final MusicTrack track;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final String? format;
  final int? bitrate;
  final int? sampleRate;
  final int? fileSize;
  final Duration position;
  final Stream<Duration> positionStream;
  final bool playing;
  final Color hueColor;
  final int tab;
  final ValueChanged<int> onTab;
  final bool showTranslation;
  final VoidCallback onToggleTranslation;
  final ValueChanged<Duration> onSeek;
  final List<MusicPlayableItem> queue;
  final String? currentKey;
  final ValueChanged<int> onPickQueue;
  final VoidCallback onToggleFavorite;
  final VoidCallback onBrowseMusic;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isZh = Localizations.localeOf(
      context,
    ).languageCode.toLowerCase().startsWith('zh');
    final skin = DesktopSkin.of(context);
    final style = ref.watch(desktopNpStyleProvider);
    final timedLyrics = track.lyricLines;
    final plainLyrics =
        timedLyrics.isEmpty
            ? _plainLyricLines(track.lyricsRaw)
            : const <String>[];
    final hasTranslation = timedLyrics.any((line) => line.hasTranslation);
    final activeColor = style.effectiveFillPaint(hueColor).primaryColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              fit: FlexFit.loose,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    artist.isEmpty ? l10n.musicNowPlayingEyebrow : artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DesktopType.eyebrow(
                      Colors.white.withValues(alpha: 0.6),
                    ).copyWith(letterSpacing: 1.6),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: DesktopType.displayXl(
                      Colors.white,
                      MediaQuery.sizeOf(context).width,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    [
                      if (album.isNotEmpty) album,
                      formatDesktopClock(duration),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DesktopType.medium(
                      Colors.white.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            DesktopIconButton(
              key: const ValueKey('desktop-np-favorite'),
              icon:
                  track.favorite
                      ? DesktopIcons.heartFilled
                      : DesktopIcons.heart,
              size: 40,
              iconSize: 22,
              color:
                  track.favorite
                      ? skin.liked
                      : Colors.white.withValues(alpha: 0.78),
              tooltip: l10n.desktopFavorite,
              onPressed: onToggleFavorite,
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            DesktopSeg<int>(
              options: const [0, 1, 2],
              value: tab,
              labelOf:
                  (value) => switch (value) {
                    0 => l10n.musicNowPlayingLyrics,
                    1 => l10n.musicQueueTitle,
                    _ => l10n.musicNowPlayingAbout,
                  },
              small: true,
              onChanged: onTab,
            ),
            if (tab == 0 && hasTranslation) ...[
              const SizedBox(width: 10),
              _TranslationToggleChip(
                active: showTranslation,
                accent: skin.accent,
                isZh: isZh,
                onTap: onToggleTranslation,
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child:
              tab == 0
                  ? DesktopNowPlayingLyrics(
                    lines: timedLyrics,
                    plainLines: plainLyrics,
                    position: position,
                    positionStream: positionStream,
                    duration: duration,
                    playing: playing,
                    style: style,
                    hueColor: hueColor,
                    showTranslation: showTranslation,
                    onSeek: onSeek,
                    onEdit: onEdit,
                  )
                  : tab == 1
                  ? (queue.isEmpty
                      ? Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 320),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                DesktopIcons.queue,
                                size: 32,
                                color: Colors.white.withValues(alpha: 0.35),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                l10n.musicQueueEmpty,
                                textAlign: TextAlign.center,
                                style: DesktopType.medium(
                                  Colors.white.withValues(alpha: 0.78),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                isZh
                                    ? '从曲库中选择曲目加入队列，编排接下来要听的歌。'
                                    : 'Add tracks from your library to line up what plays next.',
                                textAlign: TextAlign.center,
                                style: DesktopType.dense(
                                  Colors.white.withValues(alpha: 0.5),
                                ),
                              ),
                              const SizedBox(height: 16),
                              DesktopButton(
                                key: const ValueKey('desktop-np-queue-browse'),
                                label: isZh ? '浏览音乐' : 'Browse music',
                                icon: DesktopIcons.music,
                                variant: DesktopButtonVariant.glass,
                                foregroundOverride: Colors.white,
                                onPressed: onBrowseMusic,
                              ),
                            ],
                          ),
                        ),
                      )
                      : _NowPlayingQueueList(
                        queue: queue,
                        currentKey: currentKey,
                        playing: playing,
                        accentColor: skin.accent,
                        onPickQueue: onPickQueue,
                      ))
                  : _NowPlayingAbout(
                    playing: playing,
                    color: activeColor,
                    artist: artist,
                    album: album,
                    duration: duration,
                    format: format,
                    bitrate: bitrate,
                    sampleRate: sampleRate,
                    fileSize: fileSize,
                    onEdit: onEdit,
                  ),
        ),
      ],
    );
  }
}

/// 正在播放队列列表：切入时自动滚中当前曲目，左侧展示 1-based 序号与三柱动态均衡器。
class _NowPlayingQueueList extends StatefulWidget {
  const _NowPlayingQueueList({
    required this.queue,
    required this.currentKey,
    required this.playing,
    required this.accentColor,
    required this.onPickQueue,
  });

  final List<MusicPlayableItem> queue;
  final String? currentKey;
  final bool playing;
  final Color accentColor;
  final ValueChanged<int> onPickQueue;

  @override
  State<_NowPlayingQueueList> createState() => _NowPlayingQueueListState();
}

class _NowPlayingQueueListState extends State<_NowPlayingQueueList> {
  static const double _itemExtent = 66.0;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCurrent(animate: false);
    });
  }

  @override
  void didUpdateWidget(_NowPlayingQueueList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentKey != widget.currentKey ||
        oldWidget.queue.length != widget.queue.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToCurrent(animate: true);
      });
    }
  }

  void _scrollToCurrent({required bool animate}) {
    if (!mounted ||
        !_scrollController.hasClients ||
        widget.currentKey == null) {
      return;
    }
    final activeIndex = widget.queue.indexWhere(
      (entry) => entry.playableKey == widget.currentKey,
    );
    if (activeIndex < 0) return;
    final position = _scrollController.position;
    final viewport = position.viewportDimension;
    final rawTarget =
        activeIndex * _itemExtent - (viewport / 2) + (_itemExtent / 2);
    final target = rawTarget.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!animate || reduceMotion) {
      _scrollController.jumpTo(target);
    } else {
      unawaited(
        _scrollController.animateTo(
          target,
          duration: MotionToken.reduced(context, DesktopMotion.fast),
          curve: DesktopMotion.ease,
        ),
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _scrollController,
      itemExtent: _itemExtent,
      itemCount: widget.queue.length,
      itemBuilder: (context, index) {
        final item = widget.queue[index];
        final active = item.playableKey == widget.currentKey;
        return GestureDetector(
          onTap: () => widget.onPickQueue(index),
          behavior: HitTestBehavior.opaque,
          child: Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color:
                  active
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(DesktopMetrics.radiusSmall),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Center(
                    child:
                        active
                            ? _QueueEqualizer(
                              color: widget.accentColor,
                              playing: widget.playing,
                            )
                            : Text(
                              '${index + 1}',
                              style: DesktopType.numeric(
                                Colors.white.withValues(alpha: 0.45),
                              ),
                            ),
                  ),
                ),
                const SizedBox(width: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: DesktopImage(
                      url: item.track.coverUrl,
                      borderRadius: BorderRadius.circular(7),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DesktopType.dense(
                          active
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.82),
                        ),
                      ),
                      Text(
                        item.track.artistName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DesktopType.nano(
                          Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _queueDuration(item.track.durationSeconds),
                  style: DesktopType.numeric(
                    Colors.white.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 队列当前曲目的三柱动态均衡器。
class _QueueEqualizer extends StatefulWidget {
  const _QueueEqualizer({required this.color, required this.playing});

  final Color color;
  final bool playing;

  @override
  State<_QueueEqualizer> createState() => _QueueEqualizerState();
}

class _QueueEqualizerState extends State<_QueueEqualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: MotionToken.resolveForPlatform(DesktopMotion.equalizerPulse),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_QueueEqualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.playing && !reduceMotion) {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    } else if (_controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      height: 14,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final phase = _controller.value * 2 * math.pi;
          const offsets = [0.0, 2.1, 4.2];
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < 3; i++)
                Container(
                  width: 3,
                  height:
                      widget.playing
                          ? 4.0 +
                              10.0 * (0.5 + 0.5 * math.sin(phase + offsets[i]))
                          : 4.0 + i * 2.0,
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _NowPlayingAbout extends StatelessWidget {
  const _NowPlayingAbout({
    required this.playing,
    required this.color,
    required this.artist,
    required this.album,
    required this.duration,
    required this.format,
    required this.bitrate,
    required this.sampleRate,
    required this.fileSize,
    required this.onEdit,
  });

  final bool playing;
  final Color color;
  final String artist;
  final String album;
  final Duration duration;
  final String? format;
  final int? bitrate;
  final int? sampleRate;
  final int? fileSize;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rows = <MapEntry<String, String>>[
      MapEntry(l10n.musicFieldArtist, artist),
      MapEntry(l10n.musicFieldAlbum, album),
      MapEntry(l10n.musicFieldDuration, formatDesktopClock(duration)),
      MapEntry(l10n.musicFieldFormat, format?.toUpperCase() ?? '—'),
      MapEntry(l10n.musicFieldBitrate, bitrate == null ? '—' : '$bitrate kbps'),
      MapEntry(
        l10n.musicFieldSampleRate,
        sampleRate == null
            ? '—'
            : '${(sampleRate! / 1000).toStringAsFixed(1)} kHz',
      ),
      MapEntry(
        l10n.musicFieldFileSize,
        fileSize == null ? '—' : formatFileSize(fileSize!),
      ),
    ];
    final skin = DesktopSkin.of(context);
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: DesktopButton(
            label: l10n.musicEditDetailsLyrics,
            icon: DesktopIcons.edit,
            variant: DesktopButtonVariant.glass,
            foregroundOverride: Colors.white,
            onPressed: onEdit,
          ),
        ),
        const SizedBox(height: 18),
        for (var index = 0; index < rows.length; index++) ...[
          if (index > 0)
            Container(height: 1, color: Colors.white.withValues(alpha: 0.10)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 4,
                  child: Text(
                    rows[index].key,
                    style: DesktopType.caption(
                      Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  flex: 6,
                  child: Text(
                    rows[index].value.isEmpty ? '—' : rows[index].value,
                    textAlign: TextAlign.right,
                    style: DesktopType.dense(skin.onStage),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        SizedBox(
          height: 90,
          child: Opacity(
            opacity: 0.85,
            child: DesktopVisualizer(
              playing: playing,
              color: color,
              bars: 64,
              seed: 5,
            ),
          ),
        ),
      ],
    );
  }
}

/// 歌词双语翻译切换按钮：32px 与 `DesktopSeg(small: true)` 齐平，
/// 圆角 `DesktopMetrics.radiusIconButton`（9px），强调色半透底+描边，
/// 具备悬停反馈、指针手型、Tooltip、语义状态与中英文光学居中。
class _TranslationToggleChip extends StatelessWidget {
  const _TranslationToggleChip({
    required this.active,
    required this.accent,
    required this.isZh,
    required this.onTap,
  });

  final bool active;
  final Color accent;
  final bool isZh;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tooltip =
        isZh
            ? (active ? '隐藏歌词翻译' : '显示歌词翻译')
            : (active ? 'Hide translation' : 'Show translation');
    return Semantics(
      button: true,
      toggled: active,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: DesktopHover(
          cursor: SystemMouseCursors.click,
          builder: (context, hovered) {
            final bgColor =
                active
                    ? accent.withValues(alpha: hovered ? 0.24 : 0.18)
                    : Colors.white.withValues(alpha: hovered ? 0.14 : 0.08);
            final borderColor =
                active
                    ? accent.withValues(alpha: hovered ? 0.72 : 0.55)
                    : Colors.white.withValues(alpha: hovered ? 0.28 : 0.16);
            final fgColor =
                active
                    ? accent
                    : Colors.white.withValues(alpha: hovered ? 0.92 : 0.72);
            return GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: DesktopMotion.of(context, DesktopMotion.fast),
                curve: DesktopMotion.ease,
                height: 32,
                constraints: const BoxConstraints(minWidth: 32),
                padding: EdgeInsets.symmetric(horizontal: isZh ? 9 : 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(
                    DesktopMetrics.radiusIconButton,
                  ),
                  border: Border.all(color: borderColor),
                ),
                child: Text(
                  isZh ? '译' : 'TR',
                  textHeightBehavior: const TextHeightBehavior(
                    applyHeightToFirstAscent: false,
                    applyHeightToLastDescent: false,
                  ),
                  style: DesktopType.chip(fgColor).copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.0,
                    letterSpacing: isZh ? 0.0 : 0.4,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
