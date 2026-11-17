import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/data/reader_api.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';

/// 漫画清单与来源操作的应用服务。
class ReaderComicService {
  const ReaderComicService(this._api);

  final ReaderApi _api;

  /// 加载漫画清单。
  Future<ComicManifest> loadManifest(String itemId) {
    return _api.getComicManifest(itemId);
  }

  /// 加载阅读条目详情。
  Future<ReaderItemDetail> loadDetail(String itemId) {
    return _api.detail(itemId);
  }

  /// 重试漫画来源解析。
  Future<bool> retrySource(String itemId, String sourceId) {
    return _api.retryComicSource(itemId, sourceId);
  }

  /// 删除漫画来源。
  Future<void> deleteSource(String itemId, String sourceId) {
    return _api.deleteComicSource(itemId, sourceId);
  }
}

/// 漫画应用服务 Provider。
final readerComicServiceProvider = Provider<ReaderComicService>((ref) {
  return ReaderComicService(ref.read(readerApiProvider));
});

class ComicManifestMonitorState {
  const ComicManifestMonitorState({this.manifest, this.refreshError});

  final ComicManifest? manifest;
  final Object? refreshError;
}

/// 串行监控漫画解析清单；终态自动停止，临时失败按上限退避。
final comicManifestMonitorProvider = StreamProvider.autoDispose
    .family<ComicManifestMonitorState, String>((ref, itemId) async* {
      const maximumDuration = Duration(minutes: 30);
      const maximumConsecutiveFailures = 8;
      final service = ref.watch(readerComicServiceProvider);
      ComicManifest? lastManifest;
      var consecutiveFailures = 0;
      final startedAt = DateTime.now();
      while (ref.mounted) {
        if (DateTime.now().difference(startedAt) >= maximumDuration) {
          yield ComicManifestMonitorState(
            manifest: lastManifest,
            refreshError: TimeoutException(
              'Comic manifest monitoring timed out',
            ),
          );
          return;
        }
        try {
          final manifest = await service.loadManifest(itemId);
          if (!ref.mounted) {
            return;
          }
          lastManifest = manifest;
          consecutiveFailures = 0;
          yield ComicManifestMonitorState(manifest: manifest);
          final status = manifest.importStatus.toUpperCase();
          if (status != 'PENDING' && status != 'PARSING') {
            return;
          }
        } on Object catch (error) {
          if (!ref.mounted) {
            return;
          }
          consecutiveFailures++;
          yield ComicManifestMonitorState(
            manifest: lastManifest,
            refreshError: error,
          );
          if (_isComicTaskNotFound(error) ||
              consecutiveFailures >= maximumConsecutiveFailures) {
            return;
          }
        }
        final seconds = switch (consecutiveFailures) {
          0 => 3,
          1 => 3,
          2 => 6,
          _ => 12,
        };
        await Future<void>.delayed(Duration(seconds: seconds));
      }
    });

bool _isComicTaskNotFound(Object error) {
  if (error is! AppException) {
    return false;
  }
  final code = error.code.toUpperCase();
  return code == 'NOT_FOUND' || code == 'TASK_NOT_FOUND' || code == '404';
}
