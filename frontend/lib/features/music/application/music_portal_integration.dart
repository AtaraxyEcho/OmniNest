import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/music/application/music_audio_playback.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_playback_session.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';

/// Portal 展示所需的歌词行快照。
class MusicPortalLyricLine {
  const MusicPortalLyricLine({
    required this.position,
    required this.text,
    this.translation,
  });

  final Duration position;
  final String text;
  final String? translation;
}

/// Portal 展示所需的曲目快照。
class MusicPortalTrack {
  const MusicPortalTrack({
    required this.id,
    required this.title,
    required this.artistName,
    required this.albumTitle,
    required this.lyrics,
    this.coverUrl,
  });

  final String id;
  final String title;
  final String artistName;
  final String albumTitle;
  final String? coverUrl;
  final List<MusicPortalLyricLine> lyrics;
}

/// Portal 展示所需的专辑快照。
class MusicPortalAlbum {
  const MusicPortalAlbum({
    required this.title,
    required this.artistName,
    this.coverUrl,
  });

  final String title;
  final String artistName;
  final String? coverUrl;
}

/// Portal 使用的有界音乐状态投影。
class MusicPortalSnapshot {
  const MusicPortalSnapshot({
    required this.featuredTrack,
    required this.featuredAlbum,
    required this.activeTrack,
    required this.queuePreview,
    required this.recentTracks,
    required this.recentPlayCount,
    required this.isPlaying,
  });

  final MusicPortalTrack? featuredTrack;
  final MusicPortalAlbum? featuredAlbum;
  final MusicPortalTrack? activeTrack;
  final List<MusicPortalTrack> queuePreview;
  final List<MusicPortalTrack> recentTracks;
  final int recentPlayCount;
  final bool isPlaying;
}

/// Portal 沉浸歌词只需要的播放时间轴。
abstract interface class MusicPortalPlaybackTimeline {
  Stream<Duration> get positionStream;

  Duration get position;

  Future<void> seek(Duration position);
}

/// Portal 可执行的音乐命令集合。
class MusicPortalActions {
  const MusicPortalActions._(this._ref);

  final Ref _ref;

  Future<void> refresh() {
    return _ref.read(musicCenterControllerProvider.notifier).refresh();
  }

  Future<void> togglePlayback() {
    return _ref.read(musicCenterControllerProvider.notifier).togglePlayback();
  }

  Future<void> previousTrack() {
    return _ref.read(musicCenterControllerProvider.notifier).previousTrack();
  }

  Future<void> nextTrack() {
    return _ref.read(musicCenterControllerProvider.notifier).nextTrack();
  }

  /// 从最近列表的指定曲目开始播放（与音乐页最近列表同语义：以完整
  /// 最近列表为队列、点击项为起点）。供 Portal 卡片就地切歌，不导航
  /// 离开门户；曲目不在最近列表中时静默忽略。
  Future<void> playRecentTrack(String trackId) {
    final recent =
        _ref.read(musicCenterControllerProvider).asData?.value.recentItems ??
        const <MusicPlayableItem>[];
    final startIndex = recentItemsIndexOf(recent, trackId);
    if (startIndex < 0) {
      return Future<void>.value();
    }
    return _ref
        .read(musicCenterControllerProvider.notifier)
        .playItems(recent, startIndex: startIndex);
  }

  /// 在最近列表中定位曲目下标；不存在返回 -1。
  @visibleForTesting
  static int recentItemsIndexOf(
    List<MusicPlayableItem> recent,
    String trackId,
  ) {
    for (var i = 0; i < recent.length; i++) {
      if (recent[i].track.id == trackId) {
        return i;
      }
    }
    return -1;
  }

  /// 从播放队列的指定位置开始播放（供 Portal 队列卡就地切歌）；
  /// 下标越界时静默忽略。
  Future<void> playQueueAt(int index) {
    final queue =
        _ref.read(musicCenterControllerProvider).asData?.value.playbackItems ??
        const <MusicPlayableItem>[];
    if (index < 0 || index >= queue.length) {
      return Future<void>.value();
    }
    return _ref
        .read(musicCenterControllerProvider.notifier)
        .playItems(queue, startIndex: index);
  }

  Future<void> syncPlayback() {
    return _ref
        .read(musicPlaybackSessionProvider.notifier)
        .syncFromCenterState();
  }
}

/// Portal 使用的只读音乐状态。
final musicPortalSnapshotProvider = Provider<AsyncValue<MusicPortalSnapshot>>((
  ref,
) {
  return ref
      .watch(musicCenterControllerProvider)
      .whenData(projectMusicPortalSnapshot);
});

/// Portal 沉浸歌词使用的播放时间轴。
final musicPortalPlaybackTimelineProvider =
    Provider<MusicPortalPlaybackTimeline>((ref) {
      final player = ref.watch(
        musicPlaybackSessionProvider.select((session) => session.player),
      );
      return _MusicPortalPlaybackTimeline(player);
    });

/// Portal 使用的音乐命令入口。
final musicPortalActionsProvider = Provider<MusicPortalActions>((ref) {
  return MusicPortalActions._(ref);
});

class _MusicPortalPlaybackTimeline implements MusicPortalPlaybackTimeline {
  const _MusicPortalPlaybackTimeline(this._player);

  final MusicAudioPlayback _player;

  @override
  Duration get position => _player.state.position;

  @override
  Stream<Duration> get positionStream => _player.stream.position;

  @override
  Future<void> seek(Duration position) => _player.seek(position);
}

/// 将音乐中心状态压缩为 Portal 所需的有界快照。
@visibleForTesting
MusicPortalSnapshot projectMusicPortalSnapshot(MusicCenterState center) {
  final primaryItem = _resolvePrimaryItem(center);
  final dashboardTrack =
      center.dashboard.recentTracks.isEmpty
          ? null
          : center.dashboard.recentTracks.first;
  final dashboardAlbum =
      center.dashboard.recentAlbums.isEmpty
          ? null
          : center.dashboard.recentAlbums.first;
  return MusicPortalSnapshot(
    featuredTrack: _projectTrack(primaryItem?.track ?? dashboardTrack),
    featuredAlbum: _projectAlbum(dashboardAlbum),
    activeTrack: _projectTrack(center.currentTrack),
    queuePreview: _projectQueuePreview(center),
    recentTracks: List<MusicPortalTrack>.unmodifiable(
      center.recentItems.take(5).map((item) => _projectTrack(item.track)!),
    ),
    recentPlayCount: center.recentItems.length,
    isPlaying: center.isPlaying && center.currentTrack != null,
  );
}

MusicPlayableItem? _resolvePrimaryItem(MusicCenterState center) {
  final current = center.currentItem;
  if (current != null) {
    return current;
  }
  final index = center.playbackIndex;
  if (index >= 0 && index < center.playbackItems.length) {
    return center.playbackItems[index];
  }
  if (center.playbackItems.isNotEmpty) {
    return center.playbackItems.first;
  }
  if (center.recentItems.isNotEmpty) {
    return center.recentItems.first;
  }
  return null;
}

List<MusicPortalTrack> _projectQueuePreview(MusicCenterState center) {
  final source =
      center.playbackItems.isNotEmpty
          ? center.playbackItems
          : <MusicPlayableItem>[
            if (center.currentItem != null) center.currentItem!,
            ...center.recentItems,
          ];
  final seen = <String>{};
  final tracks = <MusicPortalTrack>[];
  for (final item in source) {
    if (!seen.add(item.playableKey)) {
      continue;
    }
    tracks.add(_projectTrack(item.track)!);
    if (tracks.length >= 6) {
      break;
    }
  }
  return List<MusicPortalTrack>.unmodifiable(tracks);
}

MusicPortalTrack? _projectTrack(MusicTrack? track) {
  if (track == null) {
    return null;
  }
  return MusicPortalTrack(
    id: track.id,
    title: track.title,
    artistName: track.artistName,
    albumTitle: track.albumTitle,
    coverUrl: track.listCoverUrl,
    lyrics: List<MusicPortalLyricLine>.unmodifiable(
      track.lyricLines.map(
        (line) => MusicPortalLyricLine(
          position: line.position,
          text: line.text,
          translation: line.translation,
        ),
      ),
    ),
  );
}

MusicPortalAlbum? _projectAlbum(MusicAlbum? album) {
  if (album == null) {
    return null;
  }
  return MusicPortalAlbum(
    title: album.title,
    artistName: album.artistName,
    coverUrl: album.listCoverUrl,
  );
}
