import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:omninest/core/log/dev_log.dart';

/// 桌面/移动：把服务端视频壁纸缓存到本机后播放，降低网络抖动。
///
/// 不改分辨率，仅落盘原片；Web 不实现（无稳定文件系统）。
class AppBackdropLocalVideoCache {
  AppBackdropLocalVideoCache({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  final Map<String, String> _readyById = <String, String>{};
  final Map<String, Future<String?>> _inFlight = <String, Future<String?>>{};
  Directory? _root;

  /// 清空后递增，作废仍在途的下载完成回调。
  int _cacheEpoch = 0;

  Future<Directory> _ensureRoot() async {
    final existing = _root;
    if (existing != null) {
      return existing;
    }
    final support = await getApplicationSupportDirectory();
    final dir = Directory(
      '${support.path}${Platform.pathSeparator}backdrops${Platform.pathSeparator}server',
    );
    await dir.create(recursive: true);
    _root = dir;
    return dir;
  }

  /// 已缓存的本地路径；未就绪或非 IO 时返回 null。
  String? cachedPathFor(String assetId) => _readyById[assetId];

  /// 确保 [assetId] 的视频落在本机；成功返回本地路径，失败返回 null。
  ///
  /// 同一 asset 并发调用会复用同一下载任务。
  Future<String?> ensureCached({
    required String assetId,
    required String remoteUrl,
  }) {
    final ready = _readyById[assetId];
    if (ready != null && File(ready).existsSync()) {
      return Future<String?>.value(ready);
    }
    final pending = _inFlight[assetId];
    if (pending != null) {
      return pending;
    }
    final task = _download(assetId: assetId, remoteUrl: remoteUrl).whenComplete(
      () {
        _inFlight.remove(assetId);
      },
    );
    _inFlight[assetId] = task;
    return task;
  }

  Future<String?> _download({
    required String assetId,
    required String remoteUrl,
  }) async {
    final epoch = _cacheEpoch;
    try {
      if (remoteUrl.isEmpty) {
        return null;
      }
      final root = await _ensureRoot();
      final target = File('${root.path}${Platform.pathSeparator}$assetId.mp4');
      if (await target.exists() && await target.length() > 0) {
        if (epoch == _cacheEpoch) {
          _readyById[assetId] = target.path;
        }
        return target.path;
      }
      await _dio.download(
        remoteUrl,
        target.path,
        options: Options(responseType: ResponseType.stream),
      );
      if (epoch != _cacheEpoch) {
        // 清空期间完成的下载：删除落盘文件，避免清空后又占用磁盘。
        if (await target.exists()) {
          await target.delete();
        }
        return null;
      }
      if (!await target.exists() || await target.length() <= 0) {
        if (await target.exists()) {
          await target.delete();
        }
        return null;
      }
      _readyById[assetId] = target.path;
      return target.path;
    } on Object catch (error) {
      if (kDebugMode) {
        devLog('背景视频本地缓存失败: assetId=$assetId $error');
      }
      return null;
    }
  }

  /// 删除素材对应的本地缓存。
  ///
  /// Windows 上 media_kit 可能仍持有文件句柄导致直接删除失败:先改名断开
  /// 后续重开路径再尝试删除,仍失败的改名残留由 [evictAll] 兜底清理。
  Future<void> evict(String assetId) async {
    _readyById.remove(assetId);
    try {
      final root = await _ensureRoot();
      final file = File('${root.path}${Platform.pathSeparator}$assetId.mp4');
      if (await file.exists()) {
        await _deleteWithRenameFallback(file);
      }
    } on Object catch (error) {
      if (kDebugMode) {
        devLog('背景视频本地缓存清理失败: assetId=$assetId $error');
      }
    }
  }

  Future<void> _deleteWithRenameFallback(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      final trash = File('${file.path}.trash');
      await file.rename(trash.path);
      try {
        await trash.delete();
      } on FileSystemException {
        // 句柄仍被占用:保留改名残留,由 evictAll 兜底。
      }
    }
  }

  /// 清空全部服务端视频壁纸本地缓存;返回删除的文件数。
  ///
  /// 同时清理 evict 改名失败留下的 `.trash` 残留。
  Future<int> evictAll() async {
    _cacheEpoch++;
    _readyById.clear();
    try {
      final root = await _ensureRoot();
      if (!await root.exists()) {
        return 0;
      }
      var removed = 0;
      await for (final entity in root.list(followLinks: false)) {
        if (entity is File &&
            (entity.path.endsWith('.mp4') || entity.path.endsWith('.trash'))) {
          try {
            await entity.delete();
            removed++;
          } on FileSystemException {
            // 个别文件仍被占用:跳过,下次清空再试。
          }
        }
      }
      return removed;
    } on Object catch (error) {
      if (kDebugMode) {
        devLog('背景视频本地缓存批量清理失败: $error');
      }
      return 0;
    }
  }

  /// 当前已缓存的素材数量。
  int get cachedCount => _readyById.length;

  void dispose() {
    _dio.close(force: true);
  }
}
