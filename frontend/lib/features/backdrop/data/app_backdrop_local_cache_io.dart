import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 桌面/移动：把服务端视频壁纸缓存到本机后播放，降低网络抖动。
///
/// 不改分辨率，仅落盘原片；Web 不实现（无稳定文件系统）。
class AppBackdropLocalVideoCache {
  AppBackdropLocalVideoCache({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  final Map<String, String> _readyById = <String, String>{};
  final Map<String, Future<String?>> _inFlight = <String, Future<String?>>{};
  Directory? _root;

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
    try {
      if (remoteUrl.isEmpty) {
        return null;
      }
      final root = await _ensureRoot();
      final target = File(
        '${root.path}${Platform.pathSeparator}$assetId.mp4',
      );
      if (await target.exists() && await target.length() > 0) {
        _readyById[assetId] = target.path;
        return target.path;
      }
      await _dio.download(
        remoteUrl,
        target.path,
        options: Options(responseType: ResponseType.stream),
      );
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
        debugPrint('背景视频本地缓存失败: assetId=$assetId $error');
      }
      return null;
    }
  }

  /// 删除素材对应的本地缓存。
  Future<void> evict(String assetId) async {
    _readyById.remove(assetId);
    try {
      final root = await _ensureRoot();
      final file = File(
        '${root.path}${Platform.pathSeparator}$assetId.mp4',
      );
      if (await file.exists()) {
        await file.delete();
      }
    } on Object catch (error) {
      if (kDebugMode) {
        debugPrint('背景视频本地缓存清理失败: assetId=$assetId $error');
      }
    }
  }

  /// 清空全部服务端视频壁纸本地缓存;返回删除的文件数。
  Future<int> evictAll() async {
    _readyById.clear();
    try {
      final root = await _ensureRoot();
      if (!await root.exists()) {
        return 0;
      }
      var removed = 0;
      await for (final entity in root.list(followLinks: false)) {
        if (entity is File && entity.path.endsWith('.mp4')) {
          await entity.delete();
          removed++;
        }
      }
      return removed;
    } on Object catch (error) {
      if (kDebugMode) {
        debugPrint('背景视频本地缓存批量清理失败: $error');
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
