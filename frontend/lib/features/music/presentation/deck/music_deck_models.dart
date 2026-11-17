import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';

/// Music Deck 一级内容意图。
///
/// 不提供「离线内容/离线下载」分区（产品决策 D7：版权原因暂不提供离线下载）。
enum MusicDeckSection {
  home(Icons.home_outlined, Icons.home_rounded),
  library(Icons.library_music_outlined, Icons.library_music_rounded),
  playlists(Icons.queue_music_outlined, Icons.queue_music_rounded),
  favorites(Icons.favorite_border_rounded, Icons.favorite_rounded),
  recent(Icons.history_rounded, Icons.history_toggle_off_rounded),
  localManagement(Icons.tune_rounded, Icons.library_music_rounded);

  const MusicDeckSection(this.icon, this.selectedIcon);

  final IconData icon;
  final IconData selectedIcon;

  String label(AppLocalizations l10n) => switch (this) {
    MusicDeckSection.home => l10n.musicDeckHome,
    MusicDeckSection.library => l10n.musicDeckLibrary,
    MusicDeckSection.playlists => l10n.musicDeckPlaylists,
    MusicDeckSection.favorites => l10n.musicDeckFavorites,
    MusicDeckSection.recent => l10n.musicDeckRecent,
    MusicDeckSection.localManagement => l10n.musicDeckLocalManagement,
  };
}

/// 曲库内部视图。
enum MusicDeckLibraryView { tracks, albums, artists, genres }

/// Music Deck 当前打开的集合。
sealed class MusicDeckCollectionSelection {
  const MusicDeckCollectionSelection();
}

/// 本地歌单集合。
final class LocalMusicDeckCollection extends MusicDeckCollectionSelection {
  const LocalMusicDeckCollection(this.playlist);

  final MusicPlaylist playlist;
}

/// 在线平台歌单集合。
final class OnlineMusicDeckCollection extends MusicDeckCollectionSelection {
  const OnlineMusicDeckCollection(this.playlist);

  final OnlinePlaylist playlist;
}

/// 外部平台每日推荐歌曲集合。
final class DailyRecommendationMusicDeckCollection
    extends MusicDeckCollectionSelection {
  const DailyRecommendationMusicDeckCollection(this.recommendation);

  final DailyRecommendedTracks recommendation;
}

/// 本地专辑集合。
final class AlbumMusicDeckCollection extends MusicDeckCollectionSelection {
  const AlbumMusicDeckCollection(this.album);

  final MusicAlbum album;
}

/// 本地艺术家集合。
final class ArtistMusicDeckCollection extends MusicDeckCollectionSelection {
  const ArtistMusicDeckCollection(this.artist);

  final MusicArtist artist;
}

/// 外部平台专辑集合。
final class OnlineAlbumMusicDeckCollection
    extends MusicDeckCollectionSelection {
  const OnlineAlbumMusicDeckCollection({
    required this.platform,
    required this.title,
    required this.artistName,
    required this.coverUrl,
    required this.tracks,
  });

  final MusicPlatform platform;
  final String title;
  final String artistName;
  final String coverUrl;
  final List<OnlineTrack> tracks;
}

/// 外部平台艺人集合。
final class OnlineArtistMusicDeckCollection
    extends MusicDeckCollectionSelection {
  const OnlineArtistMusicDeckCollection({
    required this.platform,
    required this.name,
    required this.coverUrl,
    required this.tracks,
  });

  final MusicPlatform platform;
  final String name;
  final String coverUrl;
  final List<OnlineTrack> tracks;
}
