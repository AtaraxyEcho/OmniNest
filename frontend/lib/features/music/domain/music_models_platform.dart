part of 'music_models.dart';

/// 在线搜索曲目（来自网易云）
class OnlineTrack {
  const OnlineTrack({
    required this.platform,
    required this.songId,
    required this.title,
    required this.artistName,
    this.albumTitle = '',
    this.coverUrl = '',
    this.thumbUrl = '',
    this.durationSeconds,
    this.quality,

    this.extra = const {},
  });

  final String platform;
  final String songId;
  final String title;
  final String artistName;
  final String albumTitle;
  final String coverUrl;

  /// 图片来源平台提供的缩略位地址，缺失时展示层回退 `coverUrl`。
  final String thumbUrl;
  final int? durationSeconds;
  final String? quality;

  final Map<String, dynamic> extra;

  /// 列表与封面格子用的展示地址：优先平台缩放图，缺省回退原图。
  String get listCoverUrl {
    final thumb = thumbUrl.trim();
    return thumb.isEmpty ? coverUrl : thumb;
  }

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
      thumbUrl: json['thumbUrl']?.toString() ?? '',
      durationSeconds: _nullableInt(json['durationSeconds']),
      quality: json['quality']?.toString(),

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

  /// 格子用的展示地址：取首曲目的缩放封面，缺省回退原图。
  String get listCoverUrl => tracks
      .map((track) => track.listCoverUrl.trim())
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
    this.thumbUrl = '',
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

  /// 图片来源平台提供的缩略位地址，缺失时展示层回退 `coverUrl`。
  final String thumbUrl;
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
    thumbUrl: json['thumbUrl']?.toString() ?? '',
    trackCount: _nullableInt(json['trackCount']),
    ownerName: json['ownerName']?.toString() ?? '',
    subscribed: _asBool(json['subscribed']),
    extra: _asMap(json['extra']),
  );
}

/// 本地和在线音乐统一最近播放记录。

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
