part of 'music_models.dart';

class MusicPlaybackPlan {
  const MusicPlaybackPlan({
    required this.trackId,
    required this.url,
    this.expiresAt,
    this.durationSeconds,
    this.format,
    this.quality,
  });

  factory MusicPlaybackPlan.fromJson(Map<String, dynamic> json) {
    return MusicPlaybackPlan(
      trackId: json['trackId']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      expiresAt: _parseDateTime(json['expiresAt']),
      durationSeconds: _nullableInt(json['durationSeconds']),
      format: json['format']?.toString(),
      quality: json['quality']?.toString(),
    );
  }

  final String trackId;
  final String url;
  final DateTime? expiresAt;
  final int? durationSeconds;
  final String? format;

  /// 在线曲目由平台实际签发的音质档位（如 lossless / exhigh）；
  /// 本地曲目为 null（真实采样率/码率在曲目元数据上）。
  final String? quality;

  MusicPlaybackPlan copyWith({
    String? trackId,
    String? url,
    DateTime? expiresAt,
    int? durationSeconds,
    String? format,
    String? quality,
  }) {
    return MusicPlaybackPlan(
      trackId: trackId ?? this.trackId,
      url: url ?? this.url,
      expiresAt: expiresAt ?? this.expiresAt,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      format: format ?? this.format,
      quality: quality ?? this.quality,
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

  /// 历史列表行用的展示地址：本地封面走派生缩略图，外部地址原样返回。
  String? get listCoverUrl => musicCoverThumbnailPath(coverUrl);
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
