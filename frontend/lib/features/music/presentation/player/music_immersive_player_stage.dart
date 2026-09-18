part of 'music_immersive_player.dart';

class _MusicImmersivePlayerStage extends ConsumerStatefulWidget {
  const _MusicImmersivePlayerStage({
    required this.palette,
    required this.reservedTopInset,
  });

  final MusicImmersivePalette palette;
  final double reservedTopInset;

  @override
  ConsumerState<_MusicImmersivePlayerStage> createState() =>
      _MusicImmersivePlayerStageState();
}

class _MusicImmersivePlayerStageState
    extends ConsumerState<_MusicImmersivePlayerStage> {
  int _deckIndex = 0;
  bool _syncScheduled = false;
  bool _deckExpanded = false;
  bool _visualEditorOpen = false;
  PortalMusicVisualizerSettings? _previewVisual;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _schedulePlaybackSync();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(musicCenterControllerProvider, (previous, next) {
      _schedulePlaybackSync();
    });
    final center = ref.watch(musicCenterControllerProvider);
    final session = ref.watch(musicPlaybackSessionProvider);
    final spectrumFeed = ref.watch(musicSpectrumFeedProvider);
    final preferences =
        ref.watch(musicVisualizerPreferencesProvider).asData?.value ??
        const PortalMusicVisualizerPreferences();
    final savedVisual = preferences.visual;
    final visual = _previewVisual ?? savedVisual;
    final state = center.asData?.value;
    final track = state?.currentTrack ?? state?.activeTrack;
    final lyrics = track?.lyricLines ?? const <MusicLyricLine>[];
    final isPlaying = state?.isPlaying == true && track != null;
    final deckTracks = _resolveDeckTracks(state, track);
    _syncDeckIndex(track, deckTracks);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTap: () => setState(() => _deckExpanded = !_deckExpanded),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          if (!width.isFinite ||
              !height.isFinite ||
              width <= 0 ||
              height <= 0) {
            return const SizedBox.shrink();
          }
          final scale = (width / 1680).clamp(0.84, 1.14).toDouble();
          final horizontalInset = (width * 0.045).clamp(28.0, 104.0).toDouble();
          final baseHeaderTop = (height * 0.020).clamp(12.0, 26.0).toDouble();
          final headerTop =
              math
                  .max(baseHeaderTop, widget.reservedTopInset + 12 * scale)
                  .toDouble();
          final headerHeight = (height * 0.105).clamp(72.0, 104.0).toDouble();
          final lyricTop =
              headerTop +
              headerHeight +
              (height * 0.024).clamp(10.0, 26.0).toDouble();
          final deckVisible = width >= 980;
          final coverDeckWidth =
              _deckExpanded
                  ? (width * 0.28).clamp(300.0, 480.0).toDouble()
                  : (width * 0.17).clamp(200.0, 300.0).toDouble();
          final coverDeckHeight =
              (height * 0.82).clamp(420.0, 760.0).toDouble();
          final deckOnLeft =
              visual.lyrics.position == PortalLyricPosition.right;
          final (lyricLeft, lyricWidth) = _resolveLyricGeometry(
            width: width,
            horizontalInset: horizontalInset,
            coverDeckWidth: coverDeckWidth,
            deckVisible: deckVisible,
            position: visual.lyrics.position,
            scale: scale,
          );
          final lyricBottom = (height * 0.10).clamp(42.0, 96.0).toDouble();
          final controlsHeight = (height * 0.082).clamp(58.0, 74.0).toDouble();
          final controlsBottom = (height * 0.042).clamp(24.0, 48.0).toDouble();
          final controlsAvailable =
              math.max(280.0, width - horizontalInset * 2).toDouble();
          final controlsWidth =
              math
                  .min(controlsAvailable, (width * 0.62).clamp(460.0, 980.0))
                  .toDouble();
          final controlsLeft =
              ((width - controlsWidth) / 2)
                  .clamp(
                    horizontalInset,
                    width - horizontalInset - controlsWidth,
                  )
                  .toDouble();
          final audioBarHeight = (52 * scale).clamp(44.0, 62.0).toDouble();
          final audioBarBottom =
              visual.player.enabled
                  ? controlsBottom + controlsHeight + 10 * scale
                  : controlsBottom;
          final visualControlsTop =
              visual.player.audioBarEnabled
                  ? audioBarBottom + audioBarHeight + 12 * scale
                  : visual.player.enabled
                  ? controlsBottom + controlsHeight + 18 * scale
                  : lyricBottom;
          final resolvedLyricBottom = math.max(lyricBottom, visualControlsTop);
          final contentHeight =
              math
                  .max(120.0, height - lyricTop - resolvedLyricBottom)
                  .toDouble();
          final viewportShortSide = math.min(width, height).toDouble();
          final coverTargetByViewport =
              (viewportShortSide * (width >= 1920 ? 0.70 : 0.62))
                  .clamp(360.0, 1480.0)
                  .toDouble();
          final coverMaxByViewport =
              math
                  .min(width * (deckVisible ? 0.46 : 0.72), height * 0.78)
                  .toDouble();
          final coverMinByViewport =
              math
                  .min(width * 0.34, height * 0.42)
                  .clamp(190.0, 380.0)
                  .toDouble();
          final coverFieldSize =
              math
                  .min(
                    math.min(coverTargetByViewport, contentHeight),
                    coverMaxByViewport,
                  )
                  .clamp(coverMinByViewport, coverMaxByViewport)
                  .toDouble();
          final coverCenter = Offset(width / 2, lyricTop + contentHeight / 2);
          return Stack(
            fit: StackFit.expand,
            children: [
              if (visual.coverElements.originalCoverEnabled)
                Positioned.fill(
                  child: ExcludeSemantics(
                    child: _DigitalImmersiveCoverPlane(
                      palette: widget.palette,
                      track: track,
                      spectrum: spectrumFeed,
                      visual: visual,
                      size: coverFieldSize,
                      center: coverCenter,
                      scale: scale,
                    ),
                  ),
                ),
              if (visual.lyrics.enabled)
                Positioned(
                  left: lyricLeft,
                  top: lyricTop,
                  width: lyricWidth,
                  bottom: resolvedLyricBottom,
                  child: _ImmersiveLyrics(
                    palette: widget.palette,
                    player: session.player,
                    track: track,
                    lyrics: lyrics,
                    scale: scale,
                    lyricSettings: visual.lyrics,
                    onPrevious: () {},
                    onTogglePlayback:
                        () => _runPlaybackCommand(
                          () =>
                              ref
                                  .read(musicCenterControllerProvider.notifier)
                                  .togglePlayback(),
                        ),
                    onNext: () {},
                  ),
                ),
              if (visual.player.audioBarEnabled)
                Positioned(
                  left: controlsLeft,
                  width: controlsWidth,
                  bottom: audioBarBottom,
                  height: audioBarHeight,
                  child: _MusicImmersiveAudioBar(
                    palette: widget.palette,
                    spectrum: spectrumFeed,
                    settings: visual.spectrum,
                    style: visual.player.audioBarStyle,
                  ),
                ),
              if (visual.player.enabled)
                Positioned(
                  left: controlsLeft,
                  width: controlsWidth,
                  bottom: controlsBottom,
                  height: controlsHeight,
                  child: _DigitalImmersiveGlassPlayerControls(
                    palette: widget.palette,
                    player: session.player,
                    track: track,
                    isPlaying: isPlaying,
                    settings: visual.player,
                    scale: scale,
                    onPrevious:
                        () => _runPlaybackCommand(
                          () =>
                              ref
                                  .read(musicCenterControllerProvider.notifier)
                                  .previousTrack(),
                        ),
                    onTogglePlayback:
                        () => _runPlaybackCommand(
                          () =>
                              ref
                                  .read(musicCenterControllerProvider.notifier)
                                  .togglePlayback(),
                        ),
                    onNext:
                        () => _runPlaybackCommand(
                          () =>
                              ref
                                  .read(musicCenterControllerProvider.notifier)
                                  .nextTrack(),
                        ),
                  ),
                ),
              Positioned(
                top: headerTop,
                left: horizontalInset,
                right: horizontalInset,
                height: headerHeight,
                child: _DigitalImmersiveTrackHeader(
                  palette: widget.palette,
                  track: track,
                  scale: scale,
                ),
              ),
              if (!_visualEditorOpen)
                Positioned(
                  top: headerTop + 8,
                  right: horizontalInset,
                  child: _GlassIconButton(
                    palette: widget.palette,
                    tooltip:
                        AppLocalizations.of(context).portalMusicVisualizerEdit,
                    icon: Icons.tune_rounded,
                    onTap: _openVisualEditor,
                  ),
                ),
              if (deckVisible)
                Positioned(
                  left: deckOnLeft ? horizontalInset : null,
                  right: deckOnLeft ? null : horizontalInset,
                  top: (height - coverDeckHeight) / 2,
                  width: coverDeckWidth,
                  height: coverDeckHeight,
                  child: MusicImmersiveCoverDeck(
                    palette: widget.palette,
                    tracks: deckTracks,
                    selectedIndex: _deckIndex,
                    currentTrack: track,
                    expanded: _deckExpanded,
                    scale: scale,
                    onSelected: (index) => _selectDeckTrack(deckTracks, index),
                    onStep: (delta) => _stepDeck(deckTracks, delta),
                  ),
                ),
              if (_visualEditorOpen)
                Positioned(
                  key: const ValueKey('music-visual-editor-positioned'),
                  top: headerTop,
                  right: horizontalInset,
                  bottom: controlsBottom,
                  width:
                      math
                          .min(
                            width - horizontalInset * 2,
                            (width * 0.34).clamp(360.0, 520.0),
                          )
                          .toDouble(),
                  child: _MusicVisualizerEditor(
                    key: const ValueKey('music-visual-editor'),
                    palette: widget.palette,
                    source: savedVisual,
                    onChanged: _previewVisualizerSettings,
                    onSave: _saveVisualizerSettings,
                    onClose: _closeVisualizerEditor,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _openVisualEditor() {
    setState(() {
      _previewVisual = null;
      _visualEditorOpen = true;
    });
  }

  void _previewVisualizerSettings(PortalMusicVisualizerSettings visual) {
    setState(() => _previewVisual = visual);
  }

  Future<void> _saveVisualizerSettings(
    PortalMusicVisualizerSettings visual,
  ) async {
    await ref
        .read(musicVisualizerPreferencesProvider.notifier)
        .saveVisual(visual);
    if (!mounted) {
      return;
    }
    setState(() {
      _previewVisual = null;
      _visualEditorOpen = false;
    });
  }

  void _closeVisualizerEditor() {
    setState(() {
      _previewVisual = null;
      _visualEditorOpen = false;
    });
  }

  void _schedulePlaybackSync() {
    if (_syncScheduled) {
      return;
    }
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted) {
        return;
      }
      unawaited(
        ref.read(musicPlaybackSessionProvider.notifier).syncFromCenterState(),
      );
    });
  }

  void _runPlaybackCommand(Future<void> Function() command) {
    unawaited(() async {
      try {
        await command();
        _schedulePlaybackSync();
      } on Exception catch (error) {
        if (kDebugMode) {
          final message = describeUserFacingError(error).message;
          devLog('Music 沉浸播放命令失败: $message');
        }
      }
    }());
  }

  (double, double) _resolveLyricGeometry({
    required double width,
    required double horizontalInset,
    required double coverDeckWidth,
    required bool deckVisible,
    required PortalLyricPosition position,
    required double scale,
  }) {
    final deckReserve = deckVisible ? coverDeckWidth + 18 * scale : 0.0;
    if (position == PortalLyricPosition.center) {
      final sideReserve = horizontalInset + deckReserve;
      final lyricWidth =
          math
              .min(width - sideReserve * 2, (width * 0.72).clamp(480.0, 1360.0))
              .clamp(280.0, 1360.0)
              .toDouble();
      return ((width - lyricWidth) / 2, lyricWidth);
    }
    final availableWidth = width - horizontalInset * 2 - deckReserve;
    final lyricWidth =
        math
            .min(availableWidth, (width * 0.46).clamp(420.0, 760.0))
            .clamp(280.0, 760.0)
            .toDouble();
    final lyricLeft =
        position == PortalLyricPosition.left
            ? horizontalInset
            : width - horizontalInset - lyricWidth;
    return (lyricLeft, lyricWidth);
  }

  List<MusicTrack> _resolveDeckTracks(
    MusicCenterState? state,
    MusicTrack? track,
  ) {
    final source =
        state?.playbackQueue.isNotEmpty == true
            ? state!.playbackQueue
            : state?.tracks ?? const <MusicTrack>[];
    if (track == null) {
      return List<MusicTrack>.unmodifiable(source);
    }
    final seen = <String>{};
    final tracks = <MusicTrack>[];
    for (final item in source) {
      if (seen.add(item.id)) {
        tracks.add(item.id == track.id ? track : item);
      }
    }
    if (seen.add(track.id)) {
      tracks.add(track);
    }
    return List<MusicTrack>.unmodifiable(tracks);
  }

  void _syncDeckIndex(MusicTrack? track, List<MusicTrack> tracks) {
    final trackId = track?.id;
    if (trackId == null) {
      return;
    }
    final index = tracks.indexWhere((item) => item.id == trackId);
    if (index < 0 || _deckIndex == index) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _deckIndex != index) {
        setState(() => _deckIndex = index);
      }
    });
  }

  void _stepDeck(List<MusicTrack> tracks, int delta) {
    if (tracks.isEmpty) {
      return;
    }
    final nextIndex = (_deckIndex + delta).clamp(0, tracks.length - 1);
    if (nextIndex == _deckIndex) {
      return;
    }
    _selectDeckTrack(tracks, nextIndex);
  }

  void _selectDeckTrack(List<MusicTrack> tracks, int index) {
    if (index < 0 || index >= tracks.length) {
      return;
    }
    setState(() => _deckIndex = index);
    _runPlaybackCommand(
      () => ref
          .read(musicCenterControllerProvider.notifier)
          .playTrack(tracks[index]),
    );
  }
}
