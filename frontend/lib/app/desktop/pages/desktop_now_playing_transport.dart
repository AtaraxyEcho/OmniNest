part of 'desktop_now_playing_page.dart';

class _Transport extends StatelessWidget {
  const _Transport({
    required this.trackId,
    required this.playing,
    required this.playMode,
    required this.queueLength,
    required this.queueIndex,
    required this.queueActive,
    required this.position,
    required this.positionStream,
    required this.duration,
    required this.dragging,
    required this.dragValue,
    required this.volumeStream,
    required this.initialVolume,
    required this.onSeek,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onCyclePlayMode,
    required this.onPrevious,
    required this.onToggle,
    required this.onNext,
    required this.onToggleQueue,
    required this.onToggleMute,
    required this.onVolumeChanged,
  });

  final String trackId;
  final bool playing;
  final MusicPlayMode playMode;
  final int queueLength;
  final int queueIndex;
  final bool queueActive;
  final Duration position;
  final Stream<Duration> positionStream;
  final Duration duration;
  final bool dragging;
  final double? dragValue;
  final Stream<double> volumeStream;
  final double initialVolume;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onCyclePlayMode;
  final VoidCallback onPrevious;
  final VoidCallback onToggle;
  final VoidCallback onNext;
  final VoidCallback onToggleQueue;
  final VoidCallback onToggleMute;
  final ValueChanged<double> onVolumeChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final maxMs =
        duration.inMilliseconds <= 0 ? 1.0 : duration.inMilliseconds.toDouble();
    final modeIcon = switch (playMode) {
      MusicPlayMode.sequential => DesktopIcons.listOrder,
      MusicPlayMode.shuffle => DesktopIcons.shuffle,
      MusicPlayMode.repeatOne => DesktopIcons.repeatOne,
    };
    final modeLabel = switch (playMode) {
      MusicPlayMode.sequential => l10n.desktopPlayInOrder,
      MusicPlayMode.shuffle => l10n.desktopShuffle,
      MusicPlayMode.repeatOne => l10n.desktopRepeatOne,
    };
    final modeActive = playMode != MusicPlayMode.sequential;

    final controlsRow = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        DesktopIconButton(
          key: const ValueKey('desktop-np-mode'),
          icon: modeIcon,
          size: 40,
          iconSize: 20,
          active: modeActive,
          color:
              modeActive ? skin.accent : Colors.white.withValues(alpha: 0.78),
          tooltip: '$modeLabel — ${l10n.desktopClickToSwitch}',
          onPressed: onCyclePlayMode,
        ),
        const SizedBox(width: 10),
        DesktopIconButton(
          key: const ValueKey('desktop-np-previous'),
          icon: DesktopIcons.previous,
          size: 44,
          iconSize: 24,
          color: Colors.white.withValues(alpha: 0.9),
          tooltip: l10n.desktopPrevious,
          onPressed: onPrevious,
        ),
        const SizedBox(width: 14),
        Tooltip(
          message: playing ? l10n.desktopPause : l10n.desktopPlay,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              key: const ValueKey('desktop-np-play'),
              onTap: onToggle,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    playing ? DesktopIcons.pause : DesktopIcons.play,
                    size: 30,
                    color: const Color(0xFF07090B),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        DesktopIconButton(
          key: const ValueKey('desktop-np-next'),
          icon: DesktopIcons.next,
          size: 44,
          iconSize: 24,
          color: Colors.white.withValues(alpha: 0.9),
          tooltip: l10n.desktopNext,
          onPressed: onNext,
        ),
        const SizedBox(width: 10),
        Tooltip(
          message:
              queueLength > 0
                  ? '${l10n.musicQueueTitle} · $queueIndex/$queueLength'
                  : l10n.musicQueueTitle,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              key: const ValueKey('desktop-np-queue-pill'),
              onTap: onToggleQueue,
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: DesktopMotion.of(context, DesktopMotion.fast),
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color:
                      queueActive
                          ? skin.accentWash(0.18)
                          : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color:
                        queueActive
                            ? skin.accent.withValues(alpha: 0.55)
                            : Colors.white.withValues(alpha: 0.14),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      DesktopIcons.queue,
                      size: 17,
                      color:
                          queueActive
                              ? skin.accent
                              : Colors.white.withValues(alpha: 0.86),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$queueLength',
                      style: DesktopType.numeric(
                        queueActive
                            ? skin.accent
                            : Colors.white.withValues(alpha: 0.86),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );

    final volumeCluster = StreamBuilder<double>(
      stream: volumeStream,
      initialData: initialVolume,
      builder: (context, snapshot) {
        final vol = (snapshot.data ?? initialVolume).clamp(0.0, 100.0);
        final muted = vol <= 0;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DesktopIconButton(
              key: const ValueKey('desktop-np-mute'),
              icon: muted ? DesktopIcons.mute : DesktopIcons.volume,
              size: 36,
              iconSize: 20,
              color: Colors.white.withValues(alpha: muted ? 0.55 : 0.88),
              tooltip: l10n.desktopMute,
              onPressed: onToggleMute,
            ),
            const SizedBox(width: 8),
            DesktopSlider(
              key: const ValueKey('desktop-np-volume'),
              width: 120,
              value: vol,
              max: 100,
              trackColor: Colors.white.withValues(alpha: 0.2),
              fillColor: Colors.white.withValues(alpha: 0.92),
              thumbColor: Colors.white,
              onChanged: onVolumeChanged,
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 38,
              child: Text(
                '${vol.round()}%',
                textAlign: TextAlign.right,
                style: DesktopType.numeric(
                  Colors.white.withValues(alpha: 0.72),
                ),
              ),
            ),
          ],
        );
      },
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StreamBuilder<Duration>(
              stream: positionStream,
              initialData: position,
              builder: (context, snapshot) {
                final liveMs = (snapshot.data ?? position).inMilliseconds
                    .toDouble()
                    .clamp(0.0, maxMs);
                final shownMs =
                    dragging && dragValue != null
                        ? dragValue!.clamp(0.0, maxMs)
                        : liveMs;
                final shownDuration = Duration(milliseconds: shownMs.round());
                final remaining =
                    duration > shownDuration
                        ? duration - shownDuration
                        : Duration.zero;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 48),
                      child: Text(
                        formatDesktopClock(shownDuration),
                        style: DesktopType.numeric(
                          Colors.white.withValues(alpha: 0.65),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _WaveSeek(
                        trackId: trackId,
                        position: shownDuration,
                        duration: duration,
                        onDragStart: onDragStart,
                        onDragUpdate:
                            (value) =>
                                onDragUpdate(value.inMilliseconds.toDouble()),
                        onCommit: (value) {
                          onDragEnd();
                          onSeek(value);
                        },
                        onDragCancel: onDragEnd,
                      ),
                    ),
                    const SizedBox(width: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 48),
                      child: Text(
                        '-${formatDesktopClock(remaining)}',
                        textAlign: TextAlign.right,
                        style: DesktopType.numeric(
                          Colors.white.withValues(alpha: 0.65),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 760) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      controlsRow,
                      const SizedBox(height: 10),
                      volumeCluster,
                    ],
                  );
                }
                if (constraints.maxWidth < 860) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [controlsRow, volumeCluster],
                  );
                }
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    controlsRow,
                    Align(
                      alignment: Alignment.centerRight,
                      child: volumeCluster,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 纯文本歌词回退：仅在无任何时间轴时按行展示。
List<String> _plainLyricLines(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return const <String>[];
  }
  final tag = RegExp(r'\[\d{1,2}:\d{2}(?:[.:]\d{1,3})?\]');
  return raw
      .split('\n')
      .map((line) => line.replaceAll(tag, '').trim())
      .where(
        (line) =>
            line.isNotEmpty &&
            !line.startsWith('[') &&
            !line.startsWith('{"t"') &&
            !line.startsWith('{"c"'),
      )
      .toList(growable: false);
}

/// 队列行的时长（样例 `.q-row time`）：秒数缺失时留空而不是显示 0:00。
String _queueDuration(int? seconds) {
  if (seconds == null || seconds <= 0) {
    return '';
  }
  return formatDesktopClock(Duration(seconds: seconds));
}
