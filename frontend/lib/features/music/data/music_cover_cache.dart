import 'package:dio/dio.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// 音乐封面稳定 API 路径前缀（后端 GET /api/v1/music/covers/{fileId}）。
const String _coverApiPathPrefix = '/api/v1/music/covers/';

/// 判断地址是否为本地音乐封面的稳定鉴权 API 路径。
///
/// 后端 DTO 返回相对路径；网易云、QQ 等外部 CDN 封面为绝对地址，
/// 天然不匹配本前缀，Authorization 头不会外发给第三方域名。
bool isMusicCoverApiPath(String url) => url.startsWith(_coverApiPathPrefix);

/// 音乐封面专域缓存管理器。
///
/// 独立于 DefaultCacheManager 默认库（200 对象）：本地曲库、专辑、
/// 歌单封面共用 400 对象预算，避免被相册与文件缩略图挤出磁盘缓存。
/// 下载经共享 Dio 实例完成，Bearer 头与 401 刷新链全部复用现有
/// 拦截器；Web 端缓存信息库为 NonStoringObjectProvider，字节只在
/// 会话内存与浏览器 HTTP 缓存中存活，由响应的 immutable 缓存指令兜底。
abstract final class MusicCoverCache {
  static CacheManager? _instance;
  static Dio? _dio;

  /// 返回封面缓存管理器；首次访问时以当前 [configure] 注入的下载
  /// 客户端惰性构造——避免在应用启动路径上触碰文件系统，测试环境
  /// 未渲染封面 API 路径时也不会触发平台插件调用。未注入时返回
  /// null，调用方回退默认缓存路径（与历史行为一致，不阻塞渲染）。
  static CacheManager? get maybeInstance {
    final dio = _dio;
    if (dio == null) {
      return null;
    }
    return _instance ??= CacheManager(
      Config(
        'omninestMusicCovers',
        maxNrOfCacheObjects: 400,
        stalePeriod: const Duration(days: 30),
        fileService: MusicCoverFileService(dio),
      ),
    );
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
      url,
      options: Options(responseType: ResponseType.stream, headers: headers),
    );
    return DioCoverFileResponse(response.data!);
  }
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
