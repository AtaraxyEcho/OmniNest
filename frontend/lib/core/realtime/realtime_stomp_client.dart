import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:omninest/core/realtime/realtime_models.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';
import 'package:omninest/core/log/dev_log.dart';

/// STOMP 传输层连接状态。
enum RealtimeTransportState { disconnected, connecting, connected }

/// 同步协调器依赖的实时传输接口。
abstract interface class RealtimeTransport {
  Stream<RealtimeSyncEvent> get syncEvents;

  Stream<Map<String, dynamic>> get notifications;

  Stream<RealtimeTransportState> get states;

  RealtimeTransportState get state;

  void connect();

  void pause();

  Future<void> dispose();
}

/// 同步和通知共用的原生 STOMP WebSocket 客户端。
class RealtimeStompClient implements RealtimeTransport {
  RealtimeStompClient({
    required this.url,
    required this.accessTokenResolver,
    Random? random,
  }) : _random = random ?? Random();

  static const _reconnectDelays = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 30),
  ];

  /// 握手超时：连接发出 CONNECT 后迟迟收不到 CONNECTED 时必须自行拆链重连，
  /// 否则状态永远停在 connecting，后续 connect() 被短路条件挡回。
  static const _handshakeTimeout = Duration(seconds: 15);

  final String url;

  /// 每次建立连接时实时解析访问令牌；令牌在会话内轮换后重连仍可用。
  final String Function() accessTokenResolver;
  final Random _random;
  final StreamController<RealtimeSyncEvent> _syncEvents =
      StreamController<RealtimeSyncEvent>.broadcast();
  final StreamController<Map<String, dynamic>> _notifications =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<RealtimeTransportState> _states =
      StreamController<RealtimeTransportState>.broadcast();

  StompClient? _client;
  Timer? _reconnectTimer;
  Timer? _connectTimeoutTimer;
  int _reconnectAttempt = 0;
  bool _desired = false;
  bool _disposed = false;
  RealtimeTransportState _state = RealtimeTransportState.disconnected;

  /// 实时同步事件流。
  @override
  Stream<RealtimeSyncEvent> get syncEvents => _syncEvents.stream;

  /// 原始通知 JSON 流。
  @override
  Stream<Map<String, dynamic>> get notifications => _notifications.stream;

  /// STOMP 传输层状态流。
  @override
  Stream<RealtimeTransportState> get states => _states.stream;

  /// 当前传输层状态。
  @override
  RealtimeTransportState get state => _state;

  /// 建立或恢复连接。
  @override
  void connect() {
    if (_disposed) return;
    _desired = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    if (_state == RealtimeTransportState.connected || _client != null) {
      return;
    }
    _open();
  }

  /// 暂停连接且不自动重连。
  @override
  void pause() {
    _desired = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _connectTimeoutTimer?.cancel();
    _connectTimeoutTimer = null;
    final client = _client;
    _client = null;
    client?.deactivate();
    _setState(RealtimeTransportState.disconnected);
  }

  void _open() {
    if (_disposed || !_desired || _client != null) return;
    _setState(RealtimeTransportState.connecting);
    final accessToken = accessTokenResolver();
    final client = StompClient(
      config: StompConfig(
        url: url,
        onConnect: _onConnect,
        onDisconnect: _onDisconnect,
        onStompError: _onStompError,
        onWebSocketError: _onWebSocketError,
        // 反向代理空闲超时、服务端重启或网络切换都会「正常关闭」底层 WebSocket，
        // 走的是 onDone 而不是 onError。不接这个回调时 _client 保持非空、状态停在
        // connected，后续 connect() 被短路，本次会话的推送与通知流永久失效。
        onWebSocketDone: _onWebSocketDone,
        stompConnectHeaders: {'Authorization': 'Bearer $accessToken'},
        reconnectDelay: const Duration(days: 365),
        heartbeatIncoming: const Duration(seconds: 10),
        heartbeatOutgoing: const Duration(seconds: 10),
      ),
    );
    _client = client;
    _connectTimeoutTimer?.cancel();
    _connectTimeoutTimer = Timer(_handshakeTimeout, () {
      if (_disposed || _client == null) return;
      if (_state != RealtimeTransportState.connecting) return;
      _handleConnectionLoss('STOMP 握手超时');
    });
    client.activate();
  }

  void _onWebSocketDone() {
    _handleConnectionLoss('WebSocket 连接已关闭');
  }

  void _onConnect(StompFrame frame) {
    _connectTimeoutTimer?.cancel();
    _connectTimeoutTimer = null;
    if (_disposed || !_desired) {
      pause();
      return;
    }
    _reconnectAttempt = 0;
    _setState(RealtimeTransportState.connected);
    _client?.subscribe(destination: '/user/queue/sync', callback: _onSyncFrame);
    _client?.subscribe(
      destination: '/user/queue/notifications',
      callback: _onNotificationFrame,
    );
  }

  void _onSyncFrame(StompFrame frame) {
    if (_disposed) return;
    final json = _decodeFrame(frame);
    if (json == null) return;
    try {
      _syncEvents.add(RealtimeSyncEvent.fromJson(json));
    } on FormatException catch (error) {
      if (kDebugMode) {
        devLog('实时同步事件格式无效: $error');
      }
    }
  }

  void _onNotificationFrame(StompFrame frame) {
    if (_disposed) return;
    final json = _decodeFrame(frame);
    if (json != null) {
      _notifications.add(json);
    }
  }

  Map<String, dynamic>? _decodeFrame(StompFrame frame) {
    final body = frame.body;
    if (body == null || body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } on FormatException catch (error) {
      if (kDebugMode) {
        devLog('实时消息 JSON 无效: $error');
      }
      return null;
    }
  }

  void _onDisconnect(StompFrame frame) {
    _handleConnectionLoss('STOMP 连接断开');
  }

  void _onStompError(StompFrame frame) {
    _handleConnectionLoss('STOMP 协议错误');
  }

  void _onWebSocketError(dynamic error) {
    _handleConnectionLoss('WebSocket 连接失败');
  }

  void _handleConnectionLoss(String message) {
    if (_disposed) return;
    _connectTimeoutTimer?.cancel();
    _connectTimeoutTimer = null;
    final client = _client;
    _client = null;
    client?.deactivate();
    _setState(RealtimeTransportState.disconnected);
    if (kDebugMode) {
      devLog(message);
    }
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_desired || _disposed || _reconnectTimer?.isActive == true) return;
    final index = min(_reconnectAttempt, _reconnectDelays.length - 1);
    final base = _reconnectDelays[index];
    _reconnectAttempt++;
    final jitter = Duration(
      milliseconds: _random.nextInt(max(1, base.inMilliseconds ~/ 5)),
    );
    _reconnectTimer = Timer(base + jitter, () {
      _reconnectTimer = null;
      _open();
    });
  }

  void _setState(RealtimeTransportState value) {
    if (_state == value) return;
    _state = value;
    if (!_states.isClosed) {
      _states.add(value);
    }
  }

  /// 永久释放连接和消息流。
  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    pause();
    await Future.wait([
      _syncEvents.close(),
      _notifications.close(),
      _states.close(),
    ]);
  }
}
