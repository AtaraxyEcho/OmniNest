import 'package:omninest/features/video/domain/movie_model_json.dart';

class PlaybackSubtitle {
  const PlaybackSubtitle({
    required this.id,
    required this.language,
    required this.label,
    required this.kind,
    this.url,
    this.streamIndex,
  });

  final String id;
  final String language;
  final String label;
  final String kind;
  final String? url;
  final int? streamIndex;

  factory PlaybackSubtitle.fromJson(Map<String, dynamic> json) {
    return PlaybackSubtitle(
      id: json['id']?.toString() ?? '',
      language: json['language']?.toString() ?? '',
      label: json['label']?.toString() ?? '字幕',
      kind: json['kind']?.toString() ?? 'SUBTITLE',
      url: json['url']?.toString(),
      streamIndex:
          json['streamIndex'] == null
              ? null
              : (json['streamIndex'] is int
                  ? json['streamIndex'] as int
                  : int.tryParse(json['streamIndex'].toString())),
    );
  }

  /// 是否为外挂字幕：kind 为 EXTERNAL（用户上传 或 已从内嵌提取到 MinIO）
  bool get isExternal => kind == 'EXTERNAL';

  /// 是否为内嵌字幕：有流索引且尚未提取（kind 不是 EXTERNAL）
  bool get isEmbedded => streamIndex != null && kind != 'EXTERNAL';
}

class SubtitleTrack {
  const SubtitleTrack({
    required this.id,
    required this.language,
    required this.label,
    required this.kind,
    required this.embedded,
    this.url,
    this.streamIndex,
    this.createdAt,
  });

  final String id;
  final String language;
  final String label;
  final String kind;
  final String? url;
  final bool embedded;
  final int? streamIndex;
  final DateTime? createdAt;

  factory SubtitleTrack.fromJson(Map<String, dynamic> json) {
    return SubtitleTrack(
      id: json['id']?.toString() ?? '',
      language: json['language']?.toString() ?? 'und',
      label: json['label']?.toString() ?? '字幕',
      kind: json['kind']?.toString() ?? 'SUBTITLE',
      url: json['url']?.toString(),
      embedded: json['embedded'] == true,
      streamIndex:
          json['streamIndex'] == null
              ? null
              : (json['streamIndex'] is int
                  ? json['streamIndex'] as int
                  : int.tryParse(json['streamIndex'].toString())),
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toLocal(),
    );
  }
}

class PlaybackPlan {
  const PlaybackPlan({
    required this.videoItemId,
    required this.mode,
    required this.url,
    required this.positionSeconds,
    required this.durationSeconds,
    required this.subtitles,
    this.expiresAt,
    this.container,
    this.videoCodec,
    this.audioCodec,
    this.streamUrl,
    this.hasAudioCache = false,
  });

  final String videoItemId;
  final String mode;
  final String url;
  final DateTime? expiresAt;
  final int positionSeconds;
  final int durationSeconds;
  final String? container;
  final String? videoCodec;
  final String? audioCodec;
  final List<PlaybackSubtitle> subtitles;
  final String? streamUrl;
  final bool hasAudioCache;

  factory PlaybackPlan.fromJson(Map<String, dynamic> json) {
    return PlaybackPlan(
      videoItemId: json['videoItemId']?.toString() ?? '',
      mode: json['mode']?.toString() ?? 'DIRECT_PLAY',
      url: json['url']?.toString() ?? '',
      expiresAt:
          DateTime.tryParse(json['expiresAt']?.toString() ?? '')?.toLocal(),
      positionSeconds: MovieJson.asInt(json['positionSeconds']),
      durationSeconds: MovieJson.asInt(json['durationSeconds']),
      container: json['container']?.toString(),
      videoCodec: json['videoCodec']?.toString(),
      audioCodec: json['audioCodec']?.toString(),
      subtitles:
          MovieJson.asList(
            json['subtitles'],
          ).map(PlaybackSubtitle.fromJson).toList(),
      streamUrl: json['streamUrl']?.toString(),
      hasAudioCache: json['hasAudioCache'] == true,
    );
  }
}
