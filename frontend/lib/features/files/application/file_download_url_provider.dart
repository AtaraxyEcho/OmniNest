import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/files/application/file_browser_controller.dart';

/// 会话内复用 presigned download URL 的内存缓存。
/// Provider 保持 autoDispose（页面退出即释放），URL 在缓存 TTL 内可被重建复用，
/// 避免列表滚动反复签名，同时不违背 Family Provider 生命周期测试约定。
final Map<String, String?> _downloadUrlCache = {};
final Map<String, DateTime> _downloadUrlCacheAt = {};

/// 下载地址签名失败登记（负缓存时间戳），30 秒内抑制重试。
final Map<String, DateTime> _downloadUrlFailedAt = {};

/// 会话级 URL 缓存写入口（批量预热回填）；同时清除该 ID 的失败登记。
void prewarmDownloadUrl(String fileId, String url, DateTime at) {
  _downloadUrlCache[fileId] = url;
  _downloadUrlCacheAt[fileId] = at;
  _downloadUrlFailedAt.remove(fileId);
}

final Map<String, String> _textPreviewCache = {};
final Map<String, DateTime> _textPreviewCacheAt = {};

const Duration _downloadUrlTtl = Duration(minutes: 10);
const Duration _textPreviewTtl = Duration(minutes: 5);

String? _cachedDownloadUrl(String fileId) {
  final at = _downloadUrlCacheAt[fileId];
  if (!_downloadUrlCache.containsKey(fileId) || at == null) {
    return null;
  }
  if (DateTime.now().isAfter(at.add(_downloadUrlTtl))) {
    _downloadUrlCache.remove(fileId);
    _downloadUrlCacheAt.remove(fileId);
    return null;
  }
  return _downloadUrlCache[fileId];
}

String? _cachedTextPreview(String fileId) {
  final at = _textPreviewCacheAt[fileId];
  final value = _textPreviewCache[fileId];
  if (value == null || at == null) {
    return null;
  }
  if (DateTime.now().isAfter(at.add(_textPreviewTtl))) {
    _textPreviewCache.remove(fileId);
    _textPreviewCacheAt.remove(fileId);
    return null;
  }
  return value;
}

/// 缓存 presigned download URL，按文件 ID 在会话内复用。
/// 文件夹或获取失败时返回 null。
final fileDownloadUrlProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, fileId) async {
      final cached = _cachedDownloadUrl(fileId);
      if (cached != null) {
        return cached;
      }
      // 负缓存：签名失败（如共享空间非属主封面）30 秒内不再重试，
      // 避免列表页反复发出注定失败的签名请求。
      final failedAt = _downloadUrlFailedAt[fileId];
      if (failedAt != null &&
          DateTime.now().difference(failedAt) < const Duration(seconds: 30)) {
        return null;
      }
      final repository = ref.read(fileRepositoryProvider);
      try {
        final url = await repository.downloadUrl(fileId);
        _downloadUrlCache[fileId] = url;
        _downloadUrlCacheAt[fileId] = DateTime.now();
        _downloadUrlFailedAt.remove(fileId);
        return url;
      } catch (_) {
        _downloadUrlFailedAt[fileId] = DateTime.now();
        return null;
      }
    });

/// 按文件 ID 加载有界文本预览。
final fileTextPreviewProvider = FutureProvider.autoDispose
    .family<String, String>((ref, fileId) async {
      final cached = _cachedTextPreview(fileId);
      if (cached != null) {
        return cached;
      }
      final preview = await ref
          .read(fileRepositoryProvider)
          .loadTextPreview(fileId);
      _textPreviewCache[fileId] = preview;
      _textPreviewCacheAt[fileId] = DateTime.now();
      return preview;
    });
