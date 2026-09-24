import 'package:dio/dio.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// 音乐封面专域缓存管理器。
///
/// 独立于 DefaultCacheManager 默认库（200 对象）：本地曲库、专辑、
/// 歌单封面共用 400 对象预算，避免被相册与文件缩略图挤出磁盘缓存。
/// 下载经共享 Dio 实例完成，Bearer 头与 401 刷新链全部复用现有
/// 拦截器；Web 端缓存信息库为 NonStoringObjectProvider，字节只在
/// 会话内存与浏览器 HTTP 缓存中存活，由响应的 immutable 缓存指令兜底。
abstract final class MusicCoverCache {
  static CacheManager? _instance;
  static Dio? _instanceDio;
  static Dio? _dio;

  /// 返回封面缓存管理器；首次访问时以当前 [configure] 注入的下载
  /// 客户端惰性构造——避免在应用启动路径上触碰文件系统，测试环境
  /// 未渲染封面 API 路径时也不会触发平台插件调用。注入的 dio 引用
  /// 变化（如运行时切换服务器地址）时重建实例，磁盘缓存按同一
  /// cacheKey 保留。未注入时返回 null，调用方回退默认缓存路径
  /// （与历史行为一致，不阻塞渲染）。
  static CacheManager? get maybeInstance {
    final dio = _dio;
    if (dio == null) {
      return null;
    }
    if (_instance == null || !identical(_instanceDio, dio)) {
      _instanceDio = dio;
      _instance = CacheManager(
        Config(
          'omninestMusicCovers',
          maxNrOfCacheObjects: 400,
          stalePeriod: const Duration(days: 30),
          fileService: MusicCoverFileService(dio),
        ),
      );
    }
    return _instance;
  }

  /// 记录封面缓存的下载客户端；[apiClientProvider] 重建时刷新引用。
  static void configure(Dio dio) {
    _dio = dio;
  }
}

/// 经共享 Dio 拉取封面的 [FileService] 实现。
///
/// 相对路径由 Dio baseUrl 统一拼接（三端一致）；流式响应直接交给
/// 缓存管理器落盘，不整段读入内存。
class MusicCoverFileService extends FileService {
  MusicCoverFileService(this._dio);

  Dio _dio;

  void updateDio(Dio dio) {
    _dio = dio;
  }

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    final response = await _dio.get<ResponseBody>(
      resolveApiAbsoluteUrl(_dio, url),
      options: Options(responseType: ResponseType.stream, headers: headers),
    );
    return DioCoverFileResponse(response.data!);
  }
}

/// 把后端下发的根相对 API 路径（`/api/v1/...`）换算成绝对请求地址。
///
/// Dio 的 baseUrl 已带 `/api/v1` 前缀，直接把 `/api/v1/music/covers/x` 交给它会被
/// 拼成 `/api/v1/api/v1/...` 并返回"接口不存在"；绝对地址绕过 baseUrl 合并，
/// 鉴权拦截器照常生效。其它形态（CDN 直链、无 prefixes 的相对资源路径）原样交给 Dio。
String resolveApiAbsoluteUrl(Dio dio, String url) {
  if (!url.startsWith('/api/v1/')) {
    return url;
  }
  final base = Uri.tryParse(dio.options.baseUrl);
  if (base == null || !base.hasScheme || base.authority.isEmpty) {
    return url;
  }
  return '${base.scheme}://${base.authority}$url';
}

/// [ResponseBody] 到 [FileServiceResponse] 的适配。
class DioCoverFileResponse implements FileServiceResponse {
  DioCoverFileResponse(this._response) : _receivedTime = DateTime.now();

  final ResponseBody _response;
  final DateTime _receivedTime;

  @override
  Stream<List<int>> get content =>
      _response.stream.map((chunk) => chunk.toList());

  @override
  int? get contentLength {
    // dio 缺 Content-Length 头时解析为 -1，归一为 null。
    final length = _response.contentLength;
    return length > 0 ? length : null;
  }

  @override
  int get statusCode => _response.statusCode;

  /// 后端响应带 `Cache-Control: private, max-age=2592000, immutable`，
  /// 缺头时退回一周，与默认 HttpFileService 的保守策略一致。
  @override
  DateTime get validTill {
    var ageDuration = const Duration(days: 7);
    final firstValue = _response.headers['cache-control']?.firstOrNull;
    if (firstValue != null) {
      for (final setting in firstValue.split(',')) {
        final sanitized = setting.trim().toLowerCase();
        if (sanitized == 'no-cache') {
          ageDuration = Duration.zero;
        }
        if (sanitized.startsWith('max-age=')) {
          final seconds = int.tryParse(sanitized.split('=')[1]) ?? 0;
          if (seconds > 0) {
            ageDuration = Duration(seconds: seconds);
          }
        }
      }
    }
    return _receivedTime.add(ageDuration);
  }

  @override
  String? get eTag => (_response.headers['etag']?.firstOrNull);

  @override
  String get fileExtension {
    final contentType = _response.headers['content-type']?.firstOrNull;
    if (contentType == null) {
      return '';
    }
    final mime = contentType.split(';').first.trim();
    return switch (mime) {
      'image/jpeg' => '.jpg',
      'image/png' => '.png',
      'image/gif' => '.gif',
      'image/webp' => '.webp',
      _ => '',
    };
  }
}
