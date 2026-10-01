import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:omninest/core/storage/local_database.dart';
import 'package:omninest/core/storage/sync_queue.dart';
import 'package:omninest/features/files/data/file_api.dart';
import 'package:omninest/features/music/data/music_api.dart';
import 'package:omninest/features/music/data/music_progress_repository.dart';
import 'package:omninest/features/reader/data/reader_api.dart';
import 'package:omninest/features/reader/data/reader_sync_queue.dart';
import 'package:omninest/core/log/dev_log.dart';

/// 网络状态监听器：网络恢复时触发同步队列重放。
class ConnectivityListener {
  ConnectivityListener({
    required SyncQueue syncQueue,
    required FileApi fileApi,
    required MusicApi musicApi,
    required MusicProgressRepository musicProgressRepository,
    ReaderApi? readerApi,
  }) : _syncQueue = syncQueue,
       _fileApi = fileApi,
       _musicApi = musicApi,
       _musicProgressRepository = musicProgressRepository,
       _readerApi = readerApi;

  final SyncQueue _syncQueue;
  final FileApi _fileApi;
  final MusicApi _musicApi;
  final MusicProgressRepository _musicProgressRepository;
  final ReaderApi? _readerApi;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _replayTimer;
  bool _hasConnection = false;
  bool _connectivityInitialized = false;
  bool _replaying = false;
  int _lastReportedFailures = 0;
  final StreamController<bool> _onlineController =
      StreamController<bool>.broadcast();
  final StreamController<int> _replayFailureController =
      StreamController<int>.broadcast();

  /// 当前是否在线，初始化完成前返回 null。
  bool? get isOnline => _connectivityInitialized ? _hasConnection : null;

  /// 网络可用性变化流。
  Stream<bool> get onlineStream => _onlineController.stream;

  /// 重放失败事件流：仅在出现「新增」失败时上报一次数量，避免周期
  /// 重放对同一批失败反复打扰；全部重试成功后计数归零。
  Stream<int> get replayFailureStream => _replayFailureController.stream;

  /// 开始监听网络状态变化。
  void start() {
    _subscription = Connectivity().onConnectivityChanged.listen(
      _onConnectivityChanged,
    );
    _replayTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_hasConnection) {
        unawaited(replaySyncQueue());
      }
    });
    unawaited(_initializeConnectivity());
  }

  /// 停止监听。
  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _replayTimer?.cancel();
    _replayTimer = null;
    if (!_onlineController.isClosed) {
      unawaited(_onlineController.close());
    }
    if (!_replayFailureController.isClosed) {
      unawaited(_replayFailureController.close());
    }
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final connected = results.any(
      (r) =>
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.ethernet ||
          r == ConnectivityResult.vpn,
    );
    final changed = !_connectivityInitialized || connected != _hasConnection;
    _connectivityInitialized = true;
    _hasConnection = connected;
    if (changed && !_onlineController.isClosed) {
      _onlineController.add(connected);
    }
    if (_hasConnection) {
      unawaited(replaySyncQueue());
    }
  }

  Future<void> _initializeConnectivity() async {
    try {
      _onConnectivityChanged(await Connectivity().checkConnectivity());
    } on Exception catch (error) {
      if (kDebugMode) {
        devLog('网络状态初始化失败: $error');
      }
    }
  }

  /// 重放同步队列中的待处理操作。
  @visibleForTesting
  Future<void> replaySyncQueue() async {
    if (_replaying) {
      return;
    }
    _replaying = true;
    var failures = 0;
    try {
      await _replayReaderSyncQueue();
      await _syncQueue.retryFailed();
      final pending = await _syncQueue.dequeue(limit: 50);
      for (final op in pending) {
        try {
          await _dispatch(op);
          await _syncQueue.markCompleted(op.id);
        } on Exception catch (e) {
          if (kDebugMode) {
            devLog('同步操作失败: id=${op.id}, type=${op.type}, error=$e');
          }
          failures++;
          await _syncQueue.markFailed(op.id);
        }
      }
    } finally {
      _replaying = false;
      if (failures == 0) {
        _lastReportedFailures = 0;
      } else if (failures > _lastReportedFailures) {
        _lastReportedFailures = failures;
        if (!_replayFailureController.isClosed) {
          _replayFailureController.add(failures);
        }
      }
    }
  }

  Future<void> _replayReaderSyncQueue() async {
    final api = _readerApi;
    if (api == null) return;
    try {
      await ReaderSyncQueue.retryFailed();
      await ReaderSyncQueue.flush(api: api);
    } on Exception catch (e) {
      if (kDebugMode) {
        devLog('阅读同步队列重放失败: $e');
      }
    }
  }

  /// 根据操作类型分发到对应的 API 调用。
  Future<void> _dispatch(SyncOperation op) async {
    final payload = jsonDecode(op.payload) as Map<String, dynamic>;
    if (op.type.startsWith(MusicProgressRepository.operationPrefix)) {
      await _musicProgressRepository.syncPayload(payload);
      return;
    }
    switch (op.type) {
      case 'file.favorite':
        final fileId = payload['fileId'] as String? ?? '';
        if (fileId.isEmpty) return;
        await _fileApi.addFavorite(fileId);
      case 'file.unfavorite':
        final fileId = payload['fileId'] as String? ?? '';
        if (fileId.isEmpty) return;
        await _fileApi.removeFavorite(fileId);
      case 'music.play_history':
        final trackId = payload['trackId'] as String? ?? '';
        if (trackId.isEmpty) return;
        await _musicApi.recordPlayHistory(trackId);
      default:
        break;
    }
  }
}
