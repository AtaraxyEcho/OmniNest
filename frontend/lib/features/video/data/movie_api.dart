import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:omninest/core/config/file_size_thresholds.dart';
import 'package:omninest/core/device/playback_device_identity.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/errors/envelope_guard.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/core/network/api_url_resolver.dart';
import 'package:omninest/core/network/capability_gate_interceptor.dart';
import 'package:omninest/core/utils/text_file_decoder.dart';
import 'package:omninest/features/files/domain/file_upload_complete_result.dart';
import 'package:omninest/features/video/domain/movie_models.dart';
import 'package:omninest/features/tasks/domain/task_record.dart';

part 'movie_api_catalog.dart';
part 'movie_api_library.dart';
part 'movie_api_playback.dart';
part 'movie_api_upload.dart';

/// 影视数据访问的公共基类：响应解析与相对资源 URL 解析。
abstract class MovieApiBase {
  const MovieApiBase();

  ApiClient get apiClient;

  Map<String, dynamic> parseData(Map<String, dynamic>? body) {
    final envelope = parseEnvelope(body);
    final data = envelope['data'];
    if (data is! Map<String, dynamic>) {
      throw const AppException(code: 'INVALID_RESPONSE', message: '影视响应格式不正确');
    }
    return data;
  }

  List<Map<String, dynamic>> parseList(Map<String, dynamic>? body) {
    final data = parseEnvelope(body)['data'];
    if (data is! List) {
      throw const AppException(code: 'INVALID_RESPONSE', message: '影视列表格式不正确');
    }
    return data.whereType<Map<String, dynamic>>().toList();
  }

  Map<String, dynamic> parseEnvelope(Map<String, dynamic>? body) {
    if (body == null) {
      throw const AppException(code: 'EMPTY_RESPONSE', message: '服务端没有返回影视结果');
    }
    final code = body['code'];
    if (code != 200) {
      final errorName = body['errorName']?.toString();
      throw AppException(
        code: errorName ?? code?.toString() ?? 'MOVIE_ERROR',
        message: body['message']?.toString() ?? '影视操作失败',
        details: {
          if (errorName != null) 'errorName': errorName,
          if (code != null) 'code': code.toString(),
        },
      );
    }
    return body;
  }

  // ---- 相对资源 URL 解析 ----
  // 后端对本地媒体库等场景返回相对路径（/api/v1/...），Flutter 的 Image.network /
  // CachedNetworkImage 需要绝对地址，这里在 data 层统一解析为 API origin。

  String? _resolveApiUrl(String? url) {
    if (url == null || url.isEmpty) return url;
    return resolveServerApiUrl(apiClient.dio.options.baseUrl, url);
  }

  /// 演员头像：MinIO 绝对地址直接使用；TMDB 相对头像路径降级拼接 TMDB 图床。
  String? _resolveProfileImageUrl(String? url) {
    if (url == null || url.isEmpty) return url;
    final parsed = Uri.tryParse(url);
    if (parsed != null && parsed.hasScheme) return url;
    if (url.startsWith('/')) {
      return 'https://image.tmdb.org/t/p/w185$url';
    }
    return url;
  }

  /// 影片/剧集条目的媒体字段（poster/backdrop/assets/演员/职员）统一解析。
  Map<String, dynamic> _resolveMediaJson(Map<String, dynamic> json) {
    final resolved = Map<String, dynamic>.from(json);
    resolved['posterUrl'] = _resolveApiUrl(json['posterUrl']?.toString());
    resolved['backdropUrl'] = _resolveApiUrl(json['backdropUrl']?.toString());
    final rawAssets = json['assets'];
    if (rawAssets is Map) {
      resolved['assets'] = rawAssets.map((key, value) {
        if (value is Map) {
          final asset = Map<String, dynamic>.from(value);
          asset['url'] = _resolveApiUrl(asset['url']?.toString());
          return MapEntry(key, asset);
        }
        return MapEntry(key, value);
      });
    }
    resolved['castMembers'] = _resolveMembers(json['castMembers']);
    resolved['crewMembers'] = _resolveMembers(json['crewMembers']);
    return resolved;
  }

  List<dynamic>? _resolveMembers(Object? raw) {
    if (raw is! List) return null;
    return raw.map((member) {
      if (member is Map) {
        final resolved = Map<String, dynamic>.from(member);
        resolved['profilePath'] = _resolveProfileImageUrl(
          resolved['profilePath']?.toString(),
        );
        return resolved;
      }
      return member;
    }).toList();
  }

  /// 仅含 posterUrl 的条目（继续观看、观看历史、季）。
  Map<String, dynamic> _resolvePosterJson(Map<String, dynamic> json) {
    final resolved = Map<String, dynamic>.from(json);
    resolved['posterUrl'] = _resolveApiUrl(json['posterUrl']?.toString());
    return resolved;
  }

  Map<String, dynamic> _resolveAssetJson(Map<String, dynamic> json) {
    final resolved = Map<String, dynamic>.from(json);
    resolved['url'] = _resolveApiUrl(json['url']?.toString());
    return resolved;
  }

  Map<String, dynamic> _resolveSeriesDetailJson(Map<String, dynamic> json) {
    final resolved = Map<String, dynamic>.from(json);
    final series = json['series'];
    if (series is Map) {
      resolved['series'] = _resolveMediaJson(Map<String, dynamic>.from(series));
    }
    resolved['cast'] = _resolveMembers(json['cast']);
    resolved['crew'] = _resolveMembers(json['crew']);
    final seasons = json['seasons'];
    if (seasons is List) {
      resolved['seasons'] =
          seasons.map((season) {
            if (season is Map) {
              return _resolvePosterJson(Map<String, dynamic>.from(season));
            }
            return season;
          }).toList();
    }
    return resolved;
  }

  Map<String, dynamic> _resolveSeasonDetailJson(Map<String, dynamic> json) {
    final resolved = Map<String, dynamic>.from(json);
    final season = json['season'];
    if (season is Map) {
      resolved['season'] = _resolvePosterJson(
        Map<String, dynamic>.from(season),
      );
    }
    final episodes = json['episodes'];
    if (episodes is List) {
      resolved['episodes'] =
          episodes.map((episode) {
            if (episode is Map) {
              return _resolveMediaJson(Map<String, dynamic>.from(episode));
            }
            return episode;
          }).toList();
    }
    return resolved;
  }

  MovieVideoItem _videoItemFromJson(Map<String, dynamic> json) =>
      MovieVideoItem.fromJson(_resolveMediaJson(json));

  MovieSeries _seriesFromJson(Map<String, dynamic> json) =>
      MovieSeries.fromJson(_resolveMediaJson(json));

  /// 首页摘要内部嵌有影片、继续观看与系列列表，需要一并解析媒体 URL。
  Map<String, dynamic> _resolveDashboardJson(Map<String, dynamic> json) {
    final resolved = Map<String, dynamic>.from(json);
    final recentlyAdded = json['recentlyAdded'];
    if (recentlyAdded is List) {
      resolved['recentlyAdded'] =
          recentlyAdded.map((item) {
            if (item is Map) {
              return _resolveMediaJson(Map<String, dynamic>.from(item));
            }
            return item;
          }).toList();
    }
    final continueWatching = json['continueWatching'];
    if (continueWatching is List) {
      resolved['continueWatching'] =
          continueWatching.map((item) {
            if (item is Map) {
              return _resolvePosterJson(Map<String, dynamic>.from(item));
            }
            return item;
          }).toList();
    }
    final series = json['series'];
    if (series is List) {
      resolved['series'] =
          series.map((item) {
            if (item is Map) {
              return _resolveMediaJson(Map<String, dynamic>.from(item));
            }
            return item;
          }).toList();
    }
    return resolved;
  }
}

/// 影视数据访问入口。各资源域方法按 part 拆分，调用方仍只依赖本类。
class MovieApi extends MovieApiBase
    with MovieApiCatalog, MovieApiLibrary, MovieApiPlayback, MovieApiUpload {
  const MovieApi(this.apiClient);

  @override
  final ApiClient apiClient;
}
