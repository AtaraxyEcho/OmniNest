part of 'music_controller.dart';

extension MusicQueuePersistenceActions on MusicCenterController {
  Future<void> flushPlaybackQueue() {
    return _queuePersistence.flush();
  }
}

extension _MusicQueueRestore on MusicCenterController {
  List<MusicPlayableItem> _restorePlaybackQueue(
    MusicPlaybackQueueSnapshot snapshot,
    List<MusicTrack> tracks,
  ) {
    final restored = <MusicPlayableItem>[];
    final keys = <String>{};
    for (final item in snapshot.items) {
      MusicPlayableItem? resolved;
      switch (item.ref) {
        case LocalMusicRef(:final trackId):
          final track = _findTrack(tracks, trackId);
          if (track != null) {
            resolved = MusicPlayableItem.local(track);
          }
        case OnlineMusicRef():
          resolved = item;
      }
      if (resolved != null && keys.add(resolved.playableKey)) {
        restored.add(resolved);
      }
    }
    return restored;
  }
}

class _MusicQueuePersistenceCoordinator {
  _MusicQueuePersistenceCoordinator({
    required this.api,
    required this.store,
    required this.ownerId,
    required this.onRemoteFailure,
    required this.onRemoteSuccess,
  });

  static const int _cacheLimit = 100;
  static const List<Duration> _retryDelays = <Duration>[
    Duration(milliseconds: 120),
    Duration(milliseconds: 360),
  ];

  final MusicApi api;
  final MusicPlaybackQueueStore store;
  final String? ownerId;
  final ValueChanged<Object> onRemoteFailure;
  final VoidCallback onRemoteSuccess;

  Timer? _timer;
  MusicPlaybackQueueSnapshot? _pendingSnapshot;
  MusicPlaybackQueueSnapshot? _latestSnapshot;
  Future<void>? _persistFuture;
  bool _disposed = false;
  bool restoreRequiresRemoteSync = false;

  Future<MusicPlaybackQueueSnapshot> load() async {
    restoreRequiresRemoteSync = false;
    final currentOwnerId = ownerId;
    if (currentOwnerId == null) {
      return const MusicPlaybackQueueSnapshot();
    }
    MusicPlaybackQueueSnapshot? remote;
    try {
      remote = await api.playbackQueue();
    } on Exception catch (error) {
      _logFailure('读取远端播放队列失败', error);
    }
    MusicPlaybackQueueSnapshot? local;
    try {
      local = await store.load(currentOwnerId);
    } on Exception catch (error) {
      _logFailure('读取本地播放队列失败', error);
    }
    if (local == null) {
      final resolved = remote ?? const MusicPlaybackQueueSnapshot();
      if (remote != null) {
        unawaited(_saveLocal(currentOwnerId, remote));
      }
      return resolved;
    }
    if (remote == null || _isLocalNewer(local, remote)) {
      restoreRequiresRemoteSync = true;
      return local;
    }
    unawaited(_saveLocal(currentOwnerId, remote));
    return remote;
  }

  void schedule(
    MusicCenterState current, {
    Duration delay = const Duration(milliseconds: 160),
  }) {
    _timer?.cancel();
    final queue = current.playbackItems;
    final limit = min(_cacheLimit, queue.length);
    final preferredStart = current.playbackIndex - limit ~/ 2;
    final maxStart = max(0, queue.length - limit);
    final start = preferredStart.clamp(0, maxStart).toInt();
    final items = queue.sublist(start, start + limit);
    final currentIndex =
        current.playbackIndex < 0 || items.isEmpty
            ? -1
            : (current.playbackIndex - start)
                .clamp(0, items.length - 1)
                .toInt();
    final snapshot = MusicPlaybackQueueSnapshot(
      items: List<MusicPlayableItem>.unmodifiable(items),
      currentIndex: currentIndex,
      repeatMode: current.repeatMode.name,
      shuffleEnabled: current.shuffleEnabled,
      updatedAt: DateTime.now().toUtc(),
    );
    _latestSnapshot = snapshot;
    _pendingSnapshot = snapshot;
    final currentOwnerId = ownerId;
    if (currentOwnerId == null) {
      _pendingSnapshot = null;
      return;
    }
    unawaited(_saveLocal(currentOwnerId, snapshot));
    _timer = Timer(delay, () {
      unawaited(_flushPending());
    });
  }

  Future<void> flush() async {
    _timer?.cancel();
    final snapshot = _latestSnapshot;
    final currentOwnerId = ownerId;
    if (currentOwnerId == null) {
      _pendingSnapshot = null;
      return;
    }
    if (snapshot != null) {
      _pendingSnapshot = snapshot;
      await _saveLocal(currentOwnerId, snapshot);
    }
    await _flushPending();
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _timer?.cancel();
    final snapshot = _latestSnapshot;
    if (snapshot == null) {
      return;
    }
    final currentOwnerId = ownerId;
    if (currentOwnerId == null) {
      return;
    }
    unawaited(_saveLocal(currentOwnerId, snapshot));
    unawaited(_persistOnDispose(snapshot));
  }

  Future<void> _flushPending() async {
    while (!_disposed) {
      final active = _persistFuture;
      if (active != null) {
        await active;
        continue;
      }
      final snapshot = _pendingSnapshot;
      if (snapshot == null) {
        return;
      }
      _pendingSnapshot = null;
      final operation = _persist(snapshot);
      _persistFuture = operation;
      try {
        await operation;
      } finally {
        if (identical(_persistFuture, operation)) {
          _persistFuture = null;
        }
      }
    }
  }

  Future<void> _persist(MusicPlaybackQueueSnapshot snapshot) async {
    final error = await _saveRemoteWithRetry(snapshot);
    if (_disposed) {
      return;
    }
    if (error == null) {
      onRemoteSuccess();
    } else {
      onRemoteFailure(error);
    }
  }

  Future<void> _persistOnDispose(MusicPlaybackQueueSnapshot snapshot) async {
    final error = await _saveRemoteWithRetry(snapshot);
    if (error != null) {
      _logFailure('退出前同步播放队列失败', error);
    }
  }

  Future<Object?> _saveRemoteWithRetry(
    MusicPlaybackQueueSnapshot snapshot,
  ) async {
    Object? lastError;
    for (var attempt = 0; attempt <= _retryDelays.length; attempt++) {
      try {
        await api.savePlaybackQueue(snapshot);
        return null;
      } on Exception catch (error) {
        lastError = error;
        if (attempt < _retryDelays.length) {
          await Future<void>.delayed(_retryDelays[attempt]);
        }
      }
    }
    return lastError;
  }

  Future<void> _saveLocal(
    String currentOwnerId,
    MusicPlaybackQueueSnapshot snapshot,
  ) async {
    try {
      await store.save(currentOwnerId, snapshot);
    } on Exception catch (error) {
      _logFailure('写入本地播放队列失败', error);
    }
  }

  bool _isLocalNewer(
    MusicPlaybackQueueSnapshot local,
    MusicPlaybackQueueSnapshot remote,
  ) {
    final localUpdatedAt = local.updatedAt;
    final remoteUpdatedAt = remote.updatedAt;
    if (localUpdatedAt == null) {
      return remote.items.isEmpty && local.items.isNotEmpty;
    }
    if (remoteUpdatedAt == null) {
      return true;
    }
    return localUpdatedAt.isAfter(remoteUpdatedAt);
  }

  void _logFailure(String message, Object error) {
    if (kDebugMode) {
      devLog('[MusicQueue] $message: $error');
    }
  }
}
