import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/files/application/file_browser_controller.dart';

/// 会话内复用 presigned download URL 的内存缓存。
/// Provider 保持 autoDispose（页面退出即释放），URL 在缓存 TTL 内可被重建复用，
/// 避免列表滚动反复签名，同时不违背 Family Provider 生命周期测试约定。
final Map<String, String?> _downloadUrlCache = {};
final Map<String, DateTime> _downloadUrlCacheAt = {};
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
      final repository = ref.read(fileRepositoryProvider);
      try {
        final url = await repository.downloadUrl(fileId);
        _downloadUrlCache[fileId] = url;
        _downloadUrlCacheAt[fileId] = DateTime.now();
        return url;
      } catch (_) {
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
