import 'package:omninest/features/music/domain/music_cover_paths.dart';

part 'music_models_lyric_parser.dart';
part 'music_models_lyrics.dart';
part 'music_models_playback.dart';
part 'music_models_platform.dart';

class MusicTrack {
  const MusicTrack({
    required this.id,
    required this.fileNodeId,
    required this.title,
    required this.artistName,
    required this.albumTitle,
    required this.format,
    required this.favorite,
    this.durationSeconds,
    this.bitrate,
    this.sampleRate,
    this.fileSize,
    this.lyricsRaw,
    this.lyricsTranslation,
    this.lyricsWords,
    this.genre,
    this.coverUrl,
    this.coverThumbUrl,
    this.updatedAt,
  });

  factory MusicTrack.fromJson(Map<String, dynamic> json) {
    return MusicTrack(
      id: json['id']?.toString() ?? '',
      fileNodeId: json['fileNodeId']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Untitled Track',
      artistName: json['artistName']?.toString() ?? 'Unknown Artist',
      albumTitle: json['albumTitle']?.toString() ?? 'Unknown Album',
      durationSeconds: _nullableInt(json['durationSeconds']),
      format: json['format']?.toString() ?? 'AUDIO',
      bitrate: _nullableInt(json['bitrate']),
      sampleRate: _nullableInt(json['sampleRate']),
      fileSize: _nullableInt(json['fileSize']),
      lyricsRaw: json['lyricsRaw']?.toString(),
      lyricsTranslation: json['lyricsTranslation']?.toString(),
      genre: json['genre']?.toString(),
      coverUrl: json['coverUrl']?.toString(),
      favorite: _asBool(json['favorite']),
      updatedAt: _parseDateTime(json['updatedAt']),
    );
  }

  final String id;
  final String fileNodeId;
  final String title;
  final String artistName;
  final String albumTitle;
  final int? durationSeconds;
  final String format;
  final int? bitrate;
  final int? sampleRate;
  final int? fileSize;
  final String? lyricsRaw;

  /// 歌词译文（独立于原文的 LRC 或纯文本），由在线平台提供。
  final String? lyricsTranslation;

  /// 逐字歌词载荷（网易云 `yrc`），由在线平台提供。
  ///
  /// 只在内存中随曲目对象流转：本地曲库与后端 DTO 都没有该字段，
  /// 换曲或重启后重新按需拉取。
  final String? lyricsWords;
  final String? genre;
  final String? coverUrl;

  /// 图片来源平台提供的缩略位地址；本地曲库走派生缩略图端点，见 [listCoverUrl]。
  final String? coverThumbUrl;
  final bool favorite;
  final DateTime? updatedAt;

  /// 列表与封面格子用的展示地址：优先平台缩放图，其次本地派生缩略图，缺省回退原图。
  String? get listCoverUrl {
    final thumb = coverThumbUrl?.trim() ?? '';
    if (thumb.isNotEmpty) {
      return thumb;
    }
    return musicCoverThumbnailPath(coverUrl);
  }

  String get durationText {
    final total = durationSeconds ?? 0;
    if (total <= 0) return '--:--';
    final minutes = total ~/ 60;
    final seconds = total % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String get qualityText {
    final parts = <String>[];
    if (sampleRate != null && sampleRate! > 0) {
      final khz = sampleRate! / 1000;
      parts.add(
        '${khz.toStringAsFixed(khz.truncateToDouble() == khz ? 0 : 1)}kHz',
      );
    }
    if (bitrate != null && bitrate! > 0) parts.add('${bitrate}kbps');
    return parts.isEmpty ? format.toUpperCase() : parts.join(' / ');
  }

  List<MusicLyricLine> get lyricLines => parseMusicLyrics(
    lyricsRaw,
    translation: lyricsTranslation,
    wordLyrics: lyricsWords,
  );

  MusicTrack copyWith({
    bool? favorite,
    String? lyricsRaw,
    String? lyricsTranslation,
    String? lyricsWords,
    String? genre,
  }) {
    return MusicTrack(
      id: id,
      fileNodeId: fileNodeId,
      title: title,
      artistName: artistName,
      albumTitle: albumTitle,
      durationSeconds: durationSeconds,
      format: format,
      bitrate: bitrate,
      sampleRate: sampleRate,
      fileSize: fileSize,
      lyricsRaw: lyricsRaw ?? this.lyricsRaw,
      lyricsTranslation: lyricsTranslation ?? this.lyricsTranslation,
      lyricsWords: lyricsWords ?? this.lyricsWords,
      genre: genre ?? this.genre,
      coverUrl: coverUrl,
      coverThumbUrl: coverThumbUrl,
      favorite: favorite ?? this.favorite,
      updatedAt: updatedAt,
    );
  }
}

/// 词级时间片：相对所在行起始位置的偏移与时长。
///
/// 网易云 `yrc` 的逐字数据用绝对毫秒表达行与词的时间，解析后统一换算成
/// "相对行首"，渲染层只关心行内进度。

class MusicAlbum {
  const MusicAlbum({
    required this.id,
    required this.title,
    required this.artistName,
    required this.trackCount,
    this.coverUrl,
    this.releaseDate,
    this.totalDuration,
    this.updatedAt,
  });

  factory MusicAlbum.fromJson(Map<String, dynamic> json) {
    return MusicAlbum(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Unknown Album',
      artistName: json['artistName']?.toString() ?? 'Unknown Artist',
      coverUrl: json['coverUrl']?.toString(),
      releaseDate: _parseDateTime(json['releaseDate']),
      totalDuration: _nullableInt(json['totalDuration']),
      trackCount: _asInt(json['trackCount']),
      updatedAt: _parseDateTime(json['updatedAt']),
    );
  }

  final String id;
  final String title;
  final String artistName;
  final String? coverUrl;
  final DateTime? releaseDate;
  final int? totalDuration;
  final int trackCount;
  final DateTime? updatedAt;

  /// 专辑格子用的展示地址：本地封面走派生缩略图，外部地址原样返回。
  String? get listCoverUrl => musicCoverThumbnailPath(coverUrl);
}

class MusicArtist {
  const MusicArtist({
    required this.id,
    required this.name,
    required this.trackCount,
    required this.albumCount,
    this.avatarUrl,
    this.updatedAt,
  });

  factory MusicArtist.fromJson(Map<String, dynamic> json) {
    return MusicArtist(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unknown Artist',
      avatarUrl: json['avatarUrl']?.toString(),
      trackCount: _asInt(json['trackCount']),
      albumCount: _asInt(json['albumCount']),
      updatedAt: _parseDateTime(json['updatedAt']),
    );
  }

  final String id;
  final String name;
  final String? avatarUrl;
  final int trackCount;
  final int albumCount;
  final DateTime? updatedAt;

  /// 艺人格子用的展示地址：本地头像走派生缩略图，外部地址原样返回。
  String? get listCoverUrl => musicCoverThumbnailPath(avatarUrl);
}

class MusicPlaylist {
  const MusicPlaylist({
    required this.id,
    required this.name,
    required this.playlistType,
    required this.trackCount,
    this.description,
    this.coverFileId,
    this.coverUrl,
    this.updatedAt,
  });

  factory MusicPlaylist.fromJson(Map<String, dynamic> json) {
    return MusicPlaylist(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Untitled Playlist',
      description: json['description']?.toString(),
      playlistType: json['playlistType']?.toString() ?? 'CUSTOM',
      coverFileId: json['coverFileId']?.toString(),
      coverUrl: json['coverUrl']?.toString(),
      trackCount: _asInt(json['trackCount']),
      updatedAt: _parseDateTime(json['updatedAt']),
    );
  }

  final String id;
  final String name;
  final String? description;
  final String playlistType;
  final String? coverFileId;
  final String? coverUrl;
  final int trackCount;
  final DateTime? updatedAt;

  /// 歌单格子用的展示地址：本地封面走派生缩略图，外部地址原样返回。
  String? get listCoverUrl => musicCoverThumbnailPath(coverUrl);

  MusicPlaylist copyWith({int? trackCount}) {
    return MusicPlaylist(
      id: id,
      name: name,
      description: description,
      playlistType: playlistType,
      coverFileId: coverFileId,
      coverUrl: coverUrl,
      trackCount: trackCount ?? this.trackCount,
      updatedAt: updatedAt,
    );
  }
}

class MusicDashboard {
  const MusicDashboard({
    required this.trackCount,
    required this.albumCount,
    required this.artistCount,
    required this.playHistoryCount,
    required this.recentTracks,
    required this.recentAlbums,
    required this.featuredArtists,
  });

  factory MusicDashboard.empty() {
    return const MusicDashboard(
      trackCount: 0,
      albumCount: 0,
      artistCount: 0,
      playHistoryCount: 0,
      recentTracks: [],
      recentAlbums: [],
      featuredArtists: [],
    );
  }

  factory MusicDashboard.fromJson(Map<String, dynamic> json) {
    return MusicDashboard(
      trackCount: _asInt(json['trackCount']),
      albumCount: _asInt(json['albumCount']),
      artistCount: _asInt(json['artistCount']),
      playHistoryCount: _asInt(json['playHistoryCount']),
      recentTracks:
          _asMapList(json['recentTracks']).map(MusicTrack.fromJson).toList(),
      recentAlbums:
          _asMapList(json['recentAlbums']).map(MusicAlbum.fromJson).toList(),
      featuredArtists:
          _asMapList(
            json['featuredArtists'],
          ).map(MusicArtist.fromJson).toList(),
    );
  }

  final int trackCount;
  final int albumCount;
  final int artistCount;
  final int playHistoryCount;
  final List<MusicTrack> recentTracks;
  final List<MusicAlbum> recentAlbums;
  final List<MusicArtist> featuredArtists;
}

class MusicSearchResult {
  const MusicSearchResult({
    required this.tracks,
    required this.albums,
    required this.artists,
  });

  factory MusicSearchResult.fromJson(Map<String, dynamic> json) {
    return MusicSearchResult(
      tracks: _asMapList(json['tracks']).map(MusicTrack.fromJson).toList(),
      albums: _asMapList(json['albums']).map(MusicAlbum.fromJson).toList(),
      artists: _asMapList(json['artists']).map(MusicArtist.fromJson).toList(),
    );
  }

  final List<MusicTrack> tracks;
  final List<MusicAlbum> albums;
  final List<MusicArtist> artists;
}

class MusicScanJob {
  const MusicScanJob({
    required this.id,
    required this.status,
    required this.progress,
    required this.scannedFiles,
    this.message,
    this.details,
    this.createdAt,
  });

  factory MusicScanJob.fromJson(Map<String, dynamic> json) {
    return MusicScanJob(
      id: json['id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'PENDING',
      progress: _asInt(json['progress']),
      scannedFiles: _asInt(json['scannedFiles']),
      message: json['message']?.toString(),
      details: json['details']?.toString(),
      createdAt: _parseDateTime(json['createdAt']),
    );
  }

  final String id;
  final String status;
  final int progress;
  final int scannedFiles;
  final String? message;
  final String? details;
  final DateTime? createdAt;
}

/// 外部数据源标识（MusicBrainz 等）。
class MusicExternalIds {
  const MusicExternalIds({
    this.musicbrainzRecordingId,
    this.musicbrainzArtistId,
    this.musicbrainzReleaseId,
    this.musicbrainzReleaseGroupId,
    this.additional = const {},
  });

  factory MusicExternalIds.fromJson(Map<String, dynamic> json) {
    return MusicExternalIds(
      musicbrainzRecordingId: json['musicbrainzRecordingId']?.toString(),
      musicbrainzArtistId: json['musicbrainzArtistId']?.toString(),
      musicbrainzReleaseId: json['musicbrainzReleaseId']?.toString(),
      musicbrainzReleaseGroupId: json['musicbrainzReleaseGroupId']?.toString(),
      additional: _stringMap(json)..removeWhere(
        (key, _) =>
            key == 'musicbrainzRecordingId' ||
            key == 'musicbrainzArtistId' ||
            key == 'musicbrainzReleaseId' ||
            key == 'musicbrainzReleaseGroupId',
      ),
    );
  }

  final String? musicbrainzRecordingId;
  final String? musicbrainzArtistId;
  final String? musicbrainzReleaseId;
  final String? musicbrainzReleaseGroupId;

  /// 其余未建模的外部标识键值。
  final Map<String, String> additional;

  Map<String, Object?> toJson() {
    return {
      if (musicbrainzRecordingId != null)
        'musicbrainzRecordingId': musicbrainzRecordingId,
      if (musicbrainzArtistId != null)
        'musicbrainzArtistId': musicbrainzArtistId,
      if (musicbrainzReleaseId != null)
        'musicbrainzReleaseId': musicbrainzReleaseId,
      if (musicbrainzReleaseGroupId != null)
        'musicbrainzReleaseGroupId': musicbrainzReleaseGroupId,
      ...additional,
    };
  }
}

/// 刮削来源附带的提供方元数据。
class MusicProviderMetadata {
  const MusicProviderMetadata({
    this.provider,
    this.coverUrl,
    this.score,
    this.additional = const {},
  });

  factory MusicProviderMetadata.fromJson(Map<String, dynamic> json) {
    return MusicProviderMetadata(
      provider: json['provider']?.toString(),
      coverUrl: json['coverUrl']?.toString(),
      score: _nullableInt(json['score']),
      additional: _stringMap(json)..removeWhere(
        (key, _) => key == 'provider' || key == 'coverUrl' || key == 'score',
      ),
    );
  }

  final String? provider;
  final String? coverUrl;
  final int? score;

  /// 其余未建模的提供方元数据键值。
  final Map<String, String> additional;

  Map<String, Object?> toJson() {
    return {
      if (provider != null) 'provider': provider,
      if (coverUrl != null) 'coverUrl': coverUrl,
      if (score != null) 'score': score,
      ...additional,
    };
  }
}

class MusicScrapeCandidate {
  const MusicScrapeCandidate({
    required this.provider,
    required this.externalId,
    required this.title,
    required this.artistName,
    required this.albumTitle,
    this.releaseDate,
    this.durationSeconds,
    this.trackNumber,
    this.discNumber,
    this.coverUrl,
    this.score,
    this.externalIds = const MusicExternalIds(),
    this.providerMetadata = const MusicProviderMetadata(),
  });

  factory MusicScrapeCandidate.fromJson(Map<String, dynamic> json) {
    return MusicScrapeCandidate(
      provider: json['provider']?.toString() ?? '',
      externalId: json['externalId']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Untitled Track',
      artistName: json['artistName']?.toString() ?? 'Unknown Artist',
      albumTitle: json['albumTitle']?.toString() ?? 'Unknown Album',
      releaseDate: _parseDateTime(json['releaseDate']),
      durationSeconds: _nullableInt(json['durationSeconds']),
      trackNumber: _nullableInt(json['trackNumber']),
      discNumber: _nullableInt(json['discNumber']),
      coverUrl: json['coverUrl']?.toString(),
      score: _nullableInt(json['score']),
      externalIds: MusicExternalIds.fromJson(_asMap(json['externalIds'])),
      providerMetadata: MusicProviderMetadata.fromJson(
        _asMap(json['providerMetadata']),
      ),
    );
  }

  final String provider;
  final String externalId;
  final String title;
  final String artistName;
  final String albumTitle;
  final DateTime? releaseDate;
  final int? durationSeconds;
  final int? trackNumber;
  final int? discNumber;
  final String? coverUrl;
  final int? score;
  final MusicExternalIds externalIds;
  final MusicProviderMetadata providerMetadata;

  /// 发行日期可读格式；无日期时返回 null，由展示层用 ARB 填充。
  String? get releaseText {
    final date = releaseDate;
    if (date == null) return null;
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String get scoreText => score == null ? '--' : '$score';

  Map<String, dynamic> toApplyJson() {
    return {
      'provider': provider,
      'externalId': externalId,
      'title': title,
      'artistName': artistName,
      'albumTitle': albumTitle,
      'releaseDate': releaseDate?.toIso8601String().split('T').first,
      'durationSeconds': durationSeconds,
      'trackNumber': trackNumber,
      'discNumber': discNumber,
      'coverUrl': coverUrl,
      'score': score,
      'externalIds': externalIds.toJson(),
      'providerMetadata': providerMetadata.toJson(),
    };
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _nullableInt(dynamic value) {
  if (value == null || value.toString().isEmpty) return null;
  return _asInt(value);
}

bool _asBool(dynamic value) {
  if (value is bool) return value;
  return value?.toString().toLowerCase() == 'true';
}

DateTime? _parseDateTime(dynamic value) {
  if (value == null || value.toString().isEmpty) return null;
  return DateTime.tryParse(value.toString().replaceFirst(' ', 'T'))?.toLocal();
}

List<Map<String, dynamic>> _asMapList(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is! Map) return const {};
  return Map<String, dynamic>.from(value);
}

Map<String, String> _stringMap(Map<String, dynamic> json) {
  return json.map((key, value) => MapEntry(key, value?.toString() ?? ''));
}

class MusicPagedResult<T> {
  const MusicPagedResult({
    required this.items,
    this.page = 0,
    this.size = 0,
    this.totalElements = 0,
  });

  final List<T> items;
  final int page;
  final int size;
  final int totalElements;

  bool get hasMore => (page + 1) * size < totalElements;
}

/// 在线平台歌词：原文、独立译文与逐字载荷。
