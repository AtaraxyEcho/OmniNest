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
    this.coverUrl,
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
  final String? coverUrl;
  final bool favorite;
  final DateTime? updatedAt;

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

  List<MusicLyricLine> get lyricLines => parseMusicLyrics(lyricsRaw);

  MusicTrack copyWith({bool? favorite, String? lyricsRaw}) {
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
      coverUrl: coverUrl,
      favorite: favorite ?? this.favorite,
      updatedAt: updatedAt,
    );
  }
}

class MusicLyricLine {
  const MusicLyricLine({required this.position, required this.text});

  final Duration position;
  final String text;
}

List<MusicLyricLine> parseMusicLyrics(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return const [];
  }
  final lines = <MusicLyricLine>[];
  final timestampPattern = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');
  for (final rawLine in raw.split(RegExp(r'\r?\n'))) {
    final matches = timestampPattern.allMatches(rawLine).toList();
    if (matches.isEmpty) {
      continue;
    }
    final text = rawLine.replaceAll(timestampPattern, '').trim();
    if (text.isEmpty) {
      continue;
    }
    for (final match in matches) {
      final minutes = int.tryParse(match.group(1) ?? '') ?? 0;
      final seconds = int.tryParse(match.group(2) ?? '') ?? 0;
      final fraction = match.group(3) ?? '0';
      final millis = _lyricFractionToMilliseconds(fraction);
      lines.add(
        MusicLyricLine(
          position: Duration(
            minutes: minutes,
            seconds: seconds,
            milliseconds: millis,
          ),
          text: text,
        ),
      );
    }
  }
  lines.sort((left, right) => left.position.compareTo(right.position));
  return lines;
}

int _lyricFractionToMilliseconds(String fraction) {
  if (fraction.isEmpty) {
    return 0;
  }
  final digits = fraction.length >= 3 ? fraction.substring(0, 3) : fraction;
  final value = int.tryParse(digits) ?? 0;
  if (digits.length == 1) {
    return value * 100;
  }
  if (digits.length == 2) {
    return value * 10;
  }
  return value;
}

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

class MusicPlaybackPlan {
  const MusicPlaybackPlan({
    required this.trackId,
    required this.url,
    this.expiresAt,
    this.durationSeconds,
    this.format,
  });

  factory MusicPlaybackPlan.fromJson(Map<String, dynamic> json) {
    return MusicPlaybackPlan(
      trackId: json['trackId']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      expiresAt: _parseDateTime(json['expiresAt']),
      durationSeconds: _nullableInt(json['durationSeconds']),
      format: json['format']?.toString(),
    );
  }

  final String trackId;
  final String url;
  final DateTime? expiresAt;
  final int? durationSeconds;
  final String? format;

  MusicPlaybackPlan copyWith({
    String? trackId,
    String? url,
    DateTime? expiresAt,
    int? durationSeconds,
    String? format,
  }) {
    return MusicPlaybackPlan(
      trackId: trackId ?? this.trackId,
      url: url ?? this.url,
      expiresAt: expiresAt ?? this.expiresAt,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      format: format ?? this.format,
    );
  }
}

class MusicPlaybackPosition {
  const MusicPlaybackPosition({
    required this.trackId,
    required this.positionSeconds,
  });

  factory MusicPlaybackPosition.fromJson(Map<String, dynamic> json) {
    return MusicPlaybackPosition(
      trackId: json['trackId']?.toString() ?? '',
      positionSeconds: _asInt(json['positionSeconds']),
    );
  }

  final String trackId;
  final int positionSeconds;
}

/// 本地与服务端共享的音乐播放进度快照。
class MusicPlaybackProgress {
  const MusicPlaybackProgress({
    required this.playableKey,
    required this.positionSeconds,
    required this.durationSeconds,
    required this.completed,
    required this.updatedAt,
    this.version = 0,
  });

  factory MusicPlaybackProgress.fromJson(Map<String, dynamic> json) {
    return MusicPlaybackProgress(
      playableKey: json['playableKey']?.toString() ?? '',
      positionSeconds: _asInt(json['positionSeconds']),
      durationSeconds: _asInt(json['durationSeconds']),
      completed: _asBool(json['completed']),
      updatedAt:
          _parseDateTime(json['updatedAt'] ?? json['clientUpdatedAt']) ??
          DateTime.now(),
      version: _asInt(json['version']),
    );
  }

  final String playableKey;
  final int positionSeconds;
  final int durationSeconds;
  final bool completed;
  final DateTime updatedAt;
  final int version;

  double get progressPercent {
    if (durationSeconds <= 0) {
      return 0;
    }
    return (positionSeconds * 100 / durationSeconds)
        .clamp(0.0, 100.0)
        .toDouble();
  }

  Map<String, dynamic> toSaveJson() {
    return {
      'playableKey': playableKey,
      'positionSeconds': positionSeconds,
      'durationSeconds': durationSeconds,
      'completed': completed,
      'clientUpdatedAt': updatedAt.toUtc().toIso8601String(),
    };
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
    this.externalIds = const {},
    this.providerMetadata = const {},
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
      externalIds: _asMap(json['externalIds']),
      providerMetadata: _asMap(json['providerMetadata']),
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
  final Map<String, dynamic> externalIds;
  final Map<String, dynamic> providerMetadata;

  String get releaseText {
    final date = releaseDate;
    if (date == null) return 'Unknown date';
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
      'externalIds': externalIds,
      'providerMetadata': providerMetadata,
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

/// 在线搜索曲目（来自网易云/QQ音乐）
class OnlineTrack {
  const OnlineTrack({
    required this.platform,
    required this.songId,
    required this.title,
    required this.artistName,
    this.albumTitle = '',
    this.coverUrl = '',
    this.durationSeconds,
    this.quality,
    this.mediaMid,
    this.extra = const {},
  });

  final String platform;
  final String songId;
  final String title;
  final String artistName;
  final String albumTitle;
  final String coverUrl;
  final int? durationSeconds;
  final String? quality;
  final String? mediaMid;
  final Map<String, dynamic> extra;

  String get durationText {
    if (durationSeconds == null || durationSeconds! <= 0) return '';
    final m = durationSeconds! ~/ 60;
    final s = durationSeconds! % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  factory OnlineTrack.fromJson(Map<String, dynamic> json) {
    final extra =
        json['extra'] is Map
            ? Map<String, dynamic>.from(json['extra'] as Map)
            : const <String, dynamic>{};
    return OnlineTrack(
      platform: json['platform']?.toString() ?? '',
      songId: json['songId']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      artistName: json['artistName']?.toString() ?? '',
      albumTitle: json['albumTitle']?.toString() ?? '',
      coverUrl: json['coverUrl']?.toString() ?? '',
      durationSeconds: _nullableInt(json['durationSeconds']),
      quality: json['quality']?.toString(),
      mediaMid: json['mediaMid']?.toString() ?? extra['mediaMid']?.toString(),
      extra: extra,
    );
  }
}

/// 外部平台每日推荐歌曲。
class DailyRecommendedTracks {
  const DailyRecommendedTracks({
    required this.platform,
    required this.recommendationDate,
    required this.tracks,
  });

  final String platform;
  final DateTime recommendationDate;
  final List<OnlineTrack> tracks;

  String get coverUrl => tracks
      .map((track) => track.coverUrl.trim())
      .firstWhere((url) => url.isNotEmpty, orElse: () => '');

  factory DailyRecommendedTracks.fromJson(Map<String, dynamic> json) {
    return DailyRecommendedTracks(
      platform: json['platform']?.toString() ?? '',
      recommendationDate:
          DateTime.tryParse(json['recommendationDate']?.toString() ?? '') ??
          DateTime.now(),
      tracks: _asMapList(
        json['tracks'],
      ).map(OnlineTrack.fromJson).toList(growable: false),
    );
  }
}

/// 在线平台歌单
class OnlinePlaylist {
  const OnlinePlaylist({
    required this.platform,
    required this.playlistId,
    required this.name,
    this.description = '',
    this.coverUrl = '',
    this.trackCount,
    this.ownerName = '',
    this.subscribed = false,
    this.extra = const {},
  });

  final String platform;
  final String playlistId;
  final String name;
  final String description;
  final String coverUrl;
  final int? trackCount;
  final String ownerName;
  final bool subscribed;
  final Map<String, dynamic> extra;

  factory OnlinePlaylist.fromJson(Map<String, dynamic> json) => OnlinePlaylist(
    platform: json['platform']?.toString() ?? '',
    playlistId: json['playlistId']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    description: json['description']?.toString() ?? '',
    coverUrl: json['coverUrl']?.toString() ?? '',
    trackCount: _nullableInt(json['trackCount']),
    ownerName: json['ownerName']?.toString() ?? '',
    subscribed: _asBool(json['subscribed']),
    extra: _asMap(json['extra']),
  );
}

/// 本地和在线音乐统一最近播放记录。
class MusicRecentEntry {
  const MusicRecentEntry({
    required this.playableKey,
    required this.playedAt,
    this.localTrack,
    this.onlineTrack,
  });

  final String playableKey;
  final MusicTrack? localTrack;
  final OnlineTrack? onlineTrack;
  final DateTime playedAt;

  factory MusicRecentEntry.fromJson(Map<String, dynamic> json) {
    final localTrack = json['localTrack'];
    final onlineTrack = json['onlineTrack'];
    return MusicRecentEntry(
      playableKey: json['playableKey']?.toString() ?? '',
      localTrack:
          localTrack is Map
              ? MusicTrack.fromJson(Map<String, dynamic>.from(localTrack))
              : null,
      onlineTrack:
          onlineTrack is Map
              ? OnlineTrack.fromJson(Map<String, dynamic>.from(onlineTrack))
              : null,
      playedAt: _parseDateTime(json['playedAt']) ?? DateTime.now(),
    );
  }
}

/// 播放历史条目，覆盖本地与在线播放来源。
class MusicPlayHistoryEntry {
  const MusicPlayHistoryEntry({
    required this.playableKey,
    required this.title,
    required this.artistName,
    required this.playedAt,
    this.albumTitle,
    this.coverUrl,
    this.durationSeconds,
    this.platform,
  });

  final String playableKey;
  final String title;
  final String artistName;
  final String? albumTitle;
  final String? coverUrl;
  final int? durationSeconds;
  final String? platform;
  final DateTime playedAt;

  factory MusicPlayHistoryEntry.fromJson(Map<String, dynamic> json) {
    return MusicPlayHistoryEntry(
      playableKey: json['playableKey']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      artistName: json['artistName']?.toString() ?? '',
      albumTitle: json['albumTitle']?.toString(),
      coverUrl: json['coverUrl']?.toString(),
      durationSeconds:
          json['durationSeconds'] is num
              ? (json['durationSeconds'] as num).toInt()
              : null,
      platform: json['platform']?.toString(),
      playedAt: _parseDateTime(json['playedAt']) ?? DateTime.now(),
    );
  }
}

/// 在线平台能力
class MusicPlatformCapabilities {
  const MusicPlatformCapabilities({
    this.search = false,
    this.playlists = false,
    this.likedTracks = false,
    this.lyrics = false,
    this.dailyRecommendations = false,
    this.qualityLevels = const [],
  });

  final bool search;
  final bool playlists;
  final bool likedTracks;
  final bool lyrics;
  final bool dailyRecommendations;
  final List<String> qualityLevels;

  factory MusicPlatformCapabilities.fromJson(Map<String, dynamic> json) =>
      MusicPlatformCapabilities(
        search: _asBool(json['search']),
        playlists: _asBool(json['playlists']),
        likedTracks: _asBool(json['likedTracks']),
        lyrics: _asBool(json['lyrics']),
        dailyRecommendations: _asBool(json['dailyRecommendations']),
        qualityLevels:
            json['qualityLevels'] is List
                ? (json['qualityLevels'] as List)
                    .map((item) => item.toString())
                    .toList()
                : const [],
      );
}

/// QR 登录会话
class QrLoginSession {
  const QrLoginSession({
    required this.loginKey,
    this.qrUrl,
    this.qrImageBase64,
  });

  final String loginKey;
  final String? qrUrl;
  final String? qrImageBase64;

  factory QrLoginSession.fromJson(Map<String, dynamic> json) => QrLoginSession(
    loginKey: json['loginKey']?.toString() ?? '',
    qrUrl: json['qrUrl']?.toString(),
    qrImageBase64: json['qrImageBase64']?.toString(),
  );
}

/// QR 登录状态
class QrLoginStatus {
  const QrLoginStatus({required this.status, this.userInfo});

  final String status;
  final PlatformUserInfo? userInfo;

  factory QrLoginStatus.fromJson(Map<String, dynamic> json) {
    final raw = json['userInfo'];
    return QrLoginStatus(
      status: json['status']?.toString() ?? '',
      userInfo:
          raw is Map
              ? PlatformUserInfo.fromJson(Map<String, dynamic>.from(raw))
              : null,
    );
  }
}

/// 平台用户信息
class PlatformUserInfo {
  const PlatformUserInfo({
    required this.platform,
    this.userId = '',
    this.nickname = '',
    this.avatarUrl = '',
    this.vip = false,
  });

  final String platform;
  final String userId;
  final String nickname;
  final String avatarUrl;
  final bool vip;

  factory PlatformUserInfo.fromJson(Map<String, dynamic> json) =>
      PlatformUserInfo(
        platform: json['platform']?.toString() ?? '',
        userId: json['userId']?.toString() ?? '',
        nickname: json['nickname']?.toString() ?? '',
        avatarUrl: json['avatarUrl']?.toString() ?? '',
        vip: json['vip'] == true,
      );
}

/// 在线平台连接状态
class MusicPlatformStatus {
  const MusicPlatformStatus({
    required this.platform,
    required this.displayName,
    required this.enabled,
    required this.connected,
    required this.capabilities,
    this.userInfo,
    this.lastVerifiedAt,
    this.recoverableErrors = const [],
  });

  final String platform;
  final String displayName;
  final bool enabled;
  final bool connected;
  final PlatformUserInfo? userInfo;
  final MusicPlatformCapabilities capabilities;
  final DateTime? lastVerifiedAt;
  final List<String> recoverableErrors;

  factory MusicPlatformStatus.fromJson(Map<String, dynamic> json) {
    final rawUserInfo = json['userInfo'];
    return MusicPlatformStatus(
      platform: json['platform']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
      enabled: _asBool(json['enabled']),
      connected: _asBool(json['connected']),
      userInfo:
          rawUserInfo is Map
              ? PlatformUserInfo.fromJson(
                Map<String, dynamic>.from(rawUserInfo),
              )
              : null,
      capabilities: MusicPlatformCapabilities.fromJson(
        _asMap(json['capabilities']),
      ),
      lastVerifiedAt: _parseDateTime(json['lastVerifiedAt']),
      recoverableErrors:
          json['recoverableErrors'] is List
              ? (json['recoverableErrors'] as List)
                  .map((item) => item.toString())
                  .toList()
              : const [],
    );
  }
}

/// 音乐曲库分页结果，与后端 PageResponse 对齐。
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
