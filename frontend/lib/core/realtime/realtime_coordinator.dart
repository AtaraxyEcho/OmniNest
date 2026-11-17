import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:omninest/core/realtime/realtime_api.dart';
import 'package:omninest/core/realtime/realtime_models.dart';
import 'package:omninest/core/realtime/realtime_stomp_client.dart';
import 'package:omninest/core/realtime/realtime_store.dart';

typedef RealtimeSessionRefresher = Future<bool> Function();

/// 协调 STOMP、REST 补偿、本地游标和应用生命周期。
class RealtimeCoordinator {
  RealtimeCoordinator({
    required RealtimeRemoteDataSource api,
    required RealtimeStore store,
    required RealtimeTransport stompClient,
    required Stream<bool> connectivity,
    required RealtimeSessionRefresher refreshSession,
    required bool suspendInBackground,
    required Duration headInterval,
  }) : _api = api,
       _store = store,
       _stompClient = stompClient,
       _connectivity = connectivity,
       _refreshSession = refreshSession,
       _suspendInBackground = suspendInBackground,
       _headInterval = headInterval;

  static const _degradedPollDelays = <Duration>[
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(seconds: 60),
  ];

  final RealtimeRemoteDataSource _api;
  final RealtimeStore _store;
  final RealtimeTransport _stompClient;
  final Stream<bool> _connectivity;
  final RealtimeSessionRefresher _refreshSession;
  final bool _suspendInBackground;
  final Duration _headInterval;
  final StreamController<RealtimePhase> _phases =
      StreamController<RealtimePhase>.broadcast();
  final StreamController<Set<RealtimeScope>> _dirtyScopes =
      StreamController<Set<RealtimeScope>>.broadcast();

  StreamSubscription<RealtimeSyncEvent>? _syncSubscription;
  StreamSubscription<RealtimeTransportState>? _transportSubscription;
  StreamSubscription<bool>? _connectivitySubscription;
  AppLifecycleListener? _lifecycleListener;
  Timer? _catchUpDebounce;
  Timer? _headTimer;
  Timer? _degradedTimer;
  RealtimePhase _phase = RealtimePhase.signedOut;
  int _degradedPollAttempt = 0;
  bool _started = false;
  bool _disposed = false;
  bool _foreground = true;
  bool _catchingUp = false;
  bool _catchUpRequested = false;

  /// 协调器状态流。
  Stream<RealtimePhase> get phases => _phases.stream;

  /// 本地脏作用域变化流。
  Stream<Set<RealtimeScope>> get dirtyScopes => _dirtyScopes.stream;

  /// 复用 STOMP 连接收到的通知 JSON 流。
  Stream<Map<String, dynamic>> get notificationMessages =>
      _stompClient.notifications;

  /// 访问令牌刷新完成：让传输层重置退避并立即恢复连接。
  void notifyAccessTokenRefreshed() {
    if (_disposed) return;
    _stompClient.notifyAccessTokenRefreshed();
  }

  /// 当前协调器状态。
  RealtimePhase get phase => _phase;

  /// 启动实时连接、网络监听和低频高水位检查。
  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    _syncSubscription = _stompClient.syncEvents.listen(_onLiveEvent);
    _transportSubscription = _stompClient.states.listen(_onTransportState);
    _connectivitySubscription = _connectivity.listen(_onConnectivityChanged);
    _lifecycleListener = AppLifecycleListener(
      onStateChange: _onLifecycleStateChanged,
    );
    _startHeadTimer();
    _setPhase(RealtimePhase.connecting);
    _stompClient.connect();
  }

  void _onLiveEvent(RealtimeSyncEvent event) {
    unawaited(_ingestLive(event));
  }

  Future<void> _ingestLive(RealtimeSyncEvent event) async {
    try {
      _requireSchema(event.schemaVersion);
      if (await _store.ingestLive(event)) {
        _emitDirty({event.scope});
      }
      _catchUpDebounce?.cancel();
      _catchUpDebounce = Timer(
        const Duration(milliseconds: 300),
        () => unawaited(synchronize()),
      );
    } catch (_) {
      _setPhase(RealtimePhase.degraded);
      _scheduleDegradedPoll();
    }
  }

  void _onTransportState(RealtimeTransportState state) {
    if (_disposed) return;
    switch (state) {
      case RealtimeTransportState.connecting:
        _setPhase(RealtimePhase.reconnecting);
      case RealtimeTransportState.connected:
        _degradedPollAttempt = 0;
        _degradedTimer?.cancel();
        _setPhase(RealtimePhase.subscribed);
        unawaited(synchronize());
      case RealtimeTransportState.disconnected:
        if (_foreground) {
          _setPhase(RealtimePhase.degraded);
          unawaited(synchronize());
          _scheduleDegradedPoll();
        }
    }
  }

  void _onConnectivityChanged(bool online) {
    if (_disposed || !online || !_foreground) return;
    _stompClient.connect();
    unawaited(synchronize());
  }

  void _onLifecycleStateChanged(AppLifecycleState state) {
    if (!_suspendInBackground) return;
    if (state == AppLifecycleState.resumed) {
      if (_foreground) return;
      _foreground = true;
      unawaited(_resumeFromBackground());
      return;
    }
    // 只认真正进入后台的状态。inactive 是下拉通知栏、系统权限弹窗、分享面板和
    // 切窗预览，几百毫秒后就会回到 resumed；在这里挂起等于每次失焦都断链、
    // 回焦就轮换一次刷新令牌。
    if (state != AppLifecycleState.paused &&
        state != AppLifecycleState.hidden) {
      return;
    }
    if (!_foreground) return;
    _foreground = false;
    _headTimer?.cancel();
    _degradedTimer?.cancel();
    _catchUpDebounce?.cancel();
    _stompClient.pause();
  }

  Future<void> _resumeFromBackground() async {
    // 回到前台先无条件重启高水位轮询：预刷新遇到瞬时网络抖动只会返回 false，
    // 把它当成「别再连接」会让 headTimer 永不启动、STOMP 停在 pause 且再无入口恢复。
    _startHeadTimer();
    await _refreshSession();
    if (_disposed || !_foreground) return;
    _stompClient.connect();
    await synchronize();
  }

  /// 执行唯一能够推进本地 cursor 的 REST 有序补偿。
  Future<void> synchronize() async {
    if (_disposed || !_foreground) return;
    if (_catchingUp) {
      _catchUpRequested = true;
      return;
    }
    _catchingUp = true;
    try {
      do {
        _catchUpRequested = false;
        _setPhase(RealtimePhase.catchingUp);
        await _synchronizeOnce();
      } while (_catchUpRequested && !_disposed && _foreground);
      _setPhase(
        _stompClient.state == RealtimeTransportState.connected
            ? RealtimePhase.healthy
            : RealtimePhase.degraded,
      );
    } catch (_) {
      _setPhase(RealtimePhase.degraded);
      _scheduleDegradedPoll();
    } finally {
      _catchingUp = false;
    }
  }

  Future<void> _synchronizeOnce() async {
    var state = await _store.readState();
    if (state == null) {
      final bootstrap = await _api.bootstrap();
      _requireSchema(bootstrap.schemaVersion);
      await _store.initializeCursor(
        cursor: bootstrap.latestCursor,
        schemaVersion: bootstrap.schemaVersion,
      );
      state = await _store.readState();
    }
    var cursor = state?.cursor ?? 0;
    while (!_disposed && _foreground) {
      final page = await _api.events(after: cursor);
      if (page.resetRequired) {
        await _store.resetToCursor(
          latestCursor: page.latestCursor,
          schemaVersion: 1,
        );
        _emitDirty(RealtimeScope.values.toSet());
        break;
      }
      for (final event in page.items) {
        _requireSchema(event.schemaVersion);
      }
      final changed = await _store.ingestRestPage(
        page.items,
        nextCursor: page.nextCursor,
        schemaVersion: 1,
      );
      _emitDirty(changed);
      cursor = page.nextCursor;
      if (!page.hasMore) break;
    }
    await _store.cleanupProcessedEvents();
  }

  void _requireSchema(int schemaVersion) {
    if (schemaVersion != 1) {
      throw StateError('不支持的同步契约版本: $schemaVersion');
    }
  }

  void _startHeadTimer() {
    _headTimer?.cancel();
    _headTimer = Timer.periodic(_headInterval, (_) {
      unawaited(_checkHead());
    });
  }

  Future<void> _checkHead() async {
    if (_disposed || !_foreground) return;
    try {
      final head = await _api.head();
      _requireSchema(head.schemaVersion);
      final state = await _store.readState();
      final cursor = state?.cursor;
      if (cursor == null ||
          cursor < head.retentionFloor ||
          cursor != head.latestCursor) {
        await synchronize();
      }
    } catch (_) {
      if (_stompClient.state != RealtimeTransportState.connected) {
        _setPhase(RealtimePhase.degraded);
        _scheduleDegradedPoll();
      }
    }
  }

  void _scheduleDegradedPoll() {
    if (_disposed || !_foreground || _degradedTimer?.isActive == true) return;
    final index = _degradedPollAttempt.clamp(0, _degradedPollDelays.length - 1);
    final delay = _degradedPollDelays[index];
    _degradedPollAttempt++;
    _degradedTimer = Timer(delay, () async {
      _degradedTimer = null;
      await synchronize();
      if (_stompClient.state != RealtimeTransportState.connected) {
        _scheduleDegradedPoll();
      }
    });
  }

  void _emitDirty(Set<RealtimeScope> scopes) {
    if (scopes.isNotEmpty && !_dirtyScopes.isClosed) {
      _dirtyScopes.add(Set.unmodifiable(scopes));
    }
  }

  void _setPhase(RealtimePhase value) {
    if (_phase == value) return;
    _phase = value;
    if (!_phases.isClosed) {
      _phases.add(value);
    }
  }

  /// 返回当前待处理失效记录。
  Future<List<RealtimeInvalidation>> pendingInvalidations() {
    return _store.pendingInvalidations();
  }

  /// 在业务刷新成功后按 revision 确认失效记录。
  Future<int> acknowledge(RealtimeInvalidation invalidation) {
    return _store.acknowledge(invalidation);
  }

  /// 停止所有连接、定时器和本地流。
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _catchUpDebounce?.cancel();
    _headTimer?.cancel();
    _degradedTimer?.cancel();
    _lifecycleListener?.dispose();
    await _syncSubscription?.cancel();
    await _transportSubscription?.cancel();
    await _connectivitySubscription?.cancel();
    await _stompClient.dispose();
    await Future.wait([_phases.close(), _dirtyScopes.close()]);
  }
}
