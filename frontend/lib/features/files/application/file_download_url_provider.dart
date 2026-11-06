import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/session/session_epoch.dart';
import 'package:omninest/features/files/application/file_browser_controller.dart';
import 'package:omninest/features/files/data/file_providers.dart';
import 'package:omninest/features/files/domain/file_node.dart';

/// 会话内复用 presigned download URL 的内存缓存。
/// Provider 保持 autoDispose（页面退出即释放），URL 在缓存 TTL 内可被重建复用，
/// 避免列表滚动反复签名，同时不违背 Family Provider 生命周期测试约定。
final Map<String, String?> _downloadUrlCache = {};
final Map<String, DateTime> _downloadUrlCacheAt = {};

/// 下载地址签名失败登记（负缓存时间戳），30 秒内抑制重试。
final Map<String, DateTime> _downloadUrlFailedAt = {};

/// 进程级缓存上限：长会话翻阅数十万文件时，无上限 Map 会把每个
/// 文件 ID 与其签名 URL 一直留在内存里，直到进程退出。
const int _downloadUrlCacheLimit = 256;
const int _textPreviewCacheLimit = 64;
const int _downloadUrlFailureLimit = 128;

/// 写入并淘汰最旧条目（Dart Map 保持插入顺序，首个键即最久未使用）。
void _putCapped(
  Map<String, String?> values,
  Map<String, DateTime> timestamps,
  String key,
  String? value,
  DateTime at,
  int limit,
) {
  values.remove(key);
  timestamps.remove(key);
  values[key] = value;
  timestamps[key] = at;
  while (values.length > limit) {
    final oldest = values.keys.first;
    values.remove(oldest);
    timestamps.remove(oldest);
  }
}

void _rememberFailure(String fileId, DateTime at) {
  _downloadUrlFailedAt.remove(fileId);
  _downloadUrlFailedAt[fileId] = at;
  while (_downloadUrlFailedAt.length > _downloadUrlFailureLimit) {
    _downloadUrlFailedAt.remove(_downloadUrlFailedAt.keys.first);
  }
}

/// 会话级 URL 缓存写入口（批量预热回填）；同时清除该 ID 的失败登记。
void prewarmDownloadUrl(String fileId, String url, DateTime at) {
  _putCapped(
    _downloadUrlCache,
    _downloadUrlCacheAt,
    fileId,
    url,
    at,
    _downloadUrlCacheLimit,
  );
  _downloadUrlFailedAt.remove(fileId);
}

/// 清空下载地址、失败登记与文本预览的进程级缓存。
///
/// 这些缓存都以文件 ID 为键、不含账号归属：登出或换号后必须显式清空，
/// 否则上一个账号的签名下载地址与纯文本预览仍会命中同一个 ID。
void clearFileDownloadUrlCaches() {
  _downloadUrlCache.clear();
  _downloadUrlCacheAt.clear();
  _downloadUrlFailedAt.clear();
  _textPreviewCache.clear();
  _textPreviewCacheAt.clear();
}

/// 测试用：某个文件 ID 是否仍持有未过期的下载地址缓存。
@visibleForTesting
bool debugHasCachedDownloadUrl(String fileId) =>
    _cachedDownloadUrl(fileId) != null;

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
  final value = _downloadUrlCache.remove(fileId);
  _downloadUrlCache[fileId] = value;
  final stamp = _downloadUrlCacheAt.remove(fileId);
  if (stamp != null) {
    _downloadUrlCacheAt[fileId] = stamp;
  }
  return value;
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
  _textPreviewCache.remove(fileId);
  _textPreviewCache[fileId] = value;
  final stamp = _textPreviewCacheAt.remove(fileId);
  if (stamp != null) {
    _textPreviewCacheAt[fileId] = stamp;
  }
  return value;
}

/// 缓存 presigned download URL，按文件 ID 在会话内复用。
/// 文件夹或获取失败时返回 null。
final fileDownloadUrlProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, fileId) async {
      // 换号必须让签名地址重新求值：进程级缓存由会话协调器清空，
      // 但未销毁的 Provider 实例不会主动重跑。
      ref.watch(sessionEpochProvider);
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
        _putCapped(
          _downloadUrlCache,
          _downloadUrlCacheAt,
          fileId,
          url,
          DateTime.now(),
          _downloadUrlCacheLimit,
        );
        _downloadUrlFailedAt.remove(fileId);
        return url;
      } catch (_) {
        _rememberFailure(fileId, DateTime.now());
        return null;
      }
    });

/// 预览页专用的下载地址：共享端点同时覆盖所有者、共享空间成员和定向分享接收者。
final filePreviewDownloadUrlProvider = FutureProvider.autoDispose
    .family<String?, FileNode>((ref, file) async {
      ref.watch(sessionEpochProvider);
      try {
        return await ref.read(fileApiProvider).downloadSharedUrl(file.id);
      } catch (_) {
        return null;
      }
    });

/// 预览页专用文本内容：使用与共享下载相同的授权端点签名。
final filePreviewTextProvider = FutureProvider.autoDispose
    .family<String, FileNode>((ref, file) {
      ref.watch(sessionEpochProvider);
      return ref.read(fileApiProvider).loadSharedTextPreview(file.id);
    });

/// 按文件 ID 加载有界文本预览。
final fileTextPreviewProvider = FutureProvider.autoDispose
    .family<String, String>((ref, fileId) async {
      ref.watch(sessionEpochProvider);
      final cached = _cachedTextPreview(fileId);
      if (cached != null) {
        return cached;
      }
      final preview = await ref
          .read(fileRepositoryProvider)
          .loadTextPreview(fileId);
      _putCapped(
        _textPreviewCache,
        _textPreviewCacheAt,
        fileId,
        preview,
        DateTime.now(),
        _textPreviewCacheLimit,
      );
      return preview;
    });
