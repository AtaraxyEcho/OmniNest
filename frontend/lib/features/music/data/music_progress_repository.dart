import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:omninest/core/storage/local_database.dart';
import 'package:omninest/core/storage/sync_queue.dart';
import 'package:omninest/features/music/data/music_api.dart';
import 'package:omninest/features/music/domain/music_models.dart';

/// 统一管理音乐进度的本地缓存、离线队列和服务端同步。
class MusicProgressRepository {
  MusicProgressRepository({
    required LocalDatabase database,
    required SyncQueue syncQueue,
    required MusicApi api,
    String? userId,
  }) : _database = database,
       _syncQueue = syncQueue,
       _api = api,
       _userId = userId ?? '';

  static const String operationPrefix = 'music.playback_progress:';
  static const String mediaType = 'music';

  final LocalDatabase _database;
  final SyncQueue _syncQueue;
  final MusicApi _api;
  final String _userId;

  /// 读取本地进度；没有待同步修改时会与服务端刷新一次。
  Future<MusicPlaybackProgress?> loadForRestore(String playableKey) async {
    final local = await loadLocal(playableKey);
    final hasPending = await _syncQueue.hasPending(operationType(playableKey));
    if (local != null) {
      if (!hasPending) {
        unawaited(_refreshRemote(playableKey));
      }
      return local;
    }
    if (hasPending) {
      return null;
    }
    try {
      final remote = await _api.playbackProgress(playableKey);
      if (remote == null) {
        return local;
      }
      await _cache(remote);
      return remote;
    } on Exception {
      return local;
    }
  }

  Future<void> _refreshRemote(String playableKey) async {
    try {
      final remote = await _api.playbackProgress(playableKey);
      if (remote != null &&
          !await _syncQueue.hasPending(operationType(playableKey))) {
        await _cache(remote);
      }
    } on Exception {
      return;
    }
  }

  /// 读取本地音乐进度。
  Future<MusicPlaybackProgress?> loadLocal(String playableKey) async {
    final row =
        await (_database.select(_database.cachedMediaProgress)..where(
          (table) =>
              table.userId.equals(_userId) &
              table.mediaId.equals(playableKey) &
              table.mediaType.equals(mediaType),
        )).getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  /// 保存本地进度并合并同曲目的待同步操作。
  Future<MusicPlaybackProgress> saveLocal({
    required String playableKey,
    required Duration position,
    required Duration duration,
    required bool completed,
  }) async {
    final durationSeconds = duration.inSeconds.clamp(0, 2147483647).toInt();
    final positionSeconds =
        completed && durationSeconds > 0
            ? durationSeconds
            : position.inSeconds
                .clamp(0, durationSeconds > 0 ? durationSeconds : 2147483647)
                .toInt();
    final progress = MusicPlaybackProgress(
      playableKey: playableKey,
      positionSeconds: positionSeconds,
      durationSeconds: durationSeconds,
      completed: completed,
      updatedAt: DateTime.now(),
    );
    await _cache(progress);
    await _syncQueue.enqueueLatest(
      type: operationType(playableKey),
      payload: jsonEncode(progress.toSaveJson()),
    );
    return progress;
  }

  /// 重放一条离线音乐进度操作。
  Future<MusicPlaybackProgress> syncPayload(
    Map<String, dynamic> payload,
  ) async {
    final local = MusicPlaybackProgress.fromJson({
      ...payload,
      'updatedAt':
          payload['clientUpdatedAt'] ??
          payload['updatedAt'] ??
          DateTime.now().toUtc().toIso8601String(),
    });
    final remote = await _api.savePlaybackProgress(local);
    final current = await loadLocal(local.playableKey);
    if (_samePosition(current, local)) {
      await _cache(remote);
    }
    return remote;
  }

  /// 生成同曲目可合并的同步操作类型。
  static String operationType(String playableKey) {
    return '$operationPrefix$playableKey';
  }

  Future<void> _cache(MusicPlaybackProgress progress) {
    return _database
        .into(_database.cachedMediaProgress)
        .insertOnConflictUpdate(
          CachedMediaProgressCompanion.insert(
            userId: Value(_userId),
            mediaId: progress.playableKey,
            mediaType: mediaType,
            progressPercent: progress.progressPercent,
            positionSeconds: progress.positionSeconds,
            durationSeconds: progress.durationSeconds,
            updatedAt: progress.updatedAt,
          ),
        );
  }

  MusicPlaybackProgress _fromRow(CachedMediaProgressData row) {
    final completed =
        row.durationSeconds > 0 && row.positionSeconds >= row.durationSeconds;
    return MusicPlaybackProgress(
      playableKey: row.mediaId,
      positionSeconds: row.positionSeconds,
      durationSeconds: row.durationSeconds,
      completed: completed,
      updatedAt: row.updatedAt,
    );
  }

  bool _samePosition(MusicPlaybackProgress? left, MusicPlaybackProgress right) {
    return left != null &&
        left.playableKey == right.playableKey &&
        left.positionSeconds == right.positionSeconds &&
        left.durationSeconds == right.durationSeconds &&
        left.completed == right.completed;
  }
}
