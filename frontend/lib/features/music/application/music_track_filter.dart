import 'package:omninest/features/music/domain/music_models.dart';

/// 曲库内按标题/歌手/专辑过滤的同一套判据。
///
/// 甲板搜索与全局搜索共用：两处各写一份 contains 条件迟早会漂移。
List<MusicTrack> filterLoadedTracks(List<MusicTrack> tracks, String query) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) {
    return const <MusicTrack>[];
  }
  return tracks
      .where(
        (track) =>
            track.title.toLowerCase().contains(normalized) ||
            track.artistName.toLowerCase().contains(normalized) ||
            track.albumTitle.toLowerCase().contains(normalized),
      )
      .toList(growable: false);
}
