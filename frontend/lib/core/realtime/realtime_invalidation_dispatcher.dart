import 'dart:async';

import 'package:omninest/core/realtime/realtime_models.dart';
import 'package:omninest/core/realtime/realtime_scope_handler.dart';

typedef PendingInvalidationReader =
    Future<List<RealtimeInvalidation>> Function();
typedef InvalidationAcknowledger =
    Future<int> Function(RealtimeInvalidation invalidation);
typedef RealtimeDispatchErrorListener =
    void Function(Object error, StackTrace stackTrace);

/// 串行分发持久失效记录，并按观察到的 revision 确认刷新结果。
class RealtimeInvalidationDispatcher {
  RealtimeInvalidationDispatcher({
    required Stream<Set<RealtimeScope>> dirtyScopes,
    required PendingInvalidationReader pendingInvalidations,
    required InvalidationAcknowledger acknowledge,
    required Iterable<RealtimeScopeHandler> handlers,
    Duration? retryDelay = const Duration(seconds: 15),
    int maxRetries = 20,
    Duration retryWindow = const Duration(hours: 1),
    Duration exhaustedRetryDelay = const Duration(minutes: 5),
    RealtimeDispatchErrorListener? onError,
  }) : _dirtyScopes = dirtyScopes,
       _pendingInvalidations = pendingInvalidations,
       _acknowledge = acknowledge,
       _handlers = _groupHandlers(handlers),
       _retryDelay = retryDelay,
       _maxRetries = maxRetries,
       _retryWindow = retryWindow,
       _exhaustedRetryDelay = exhaustedRetryDelay,
       _onError = onError;

  final Stream<Set<RealtimeScope>> _dirtyScopes;
  final PendingInvalidationReader _pendingInvalidations;
  final InvalidationAcknowledger _acknowledge;
  final Map<RealtimeScope, List<RealtimeScopeHandler>> _handlers;
  final Duration? _retryDelay;
  final int _maxRetries;
  final Duration _retryWindow;
  final Duration _exhaustedRetryDelay;
  final RealtimeDispatchErrorListener? _onError;

  static const List<Duration> _backoffSteps = [
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(seconds: 60),
    Duration(seconds: 120),
    Duration(seconds: 300),
  ];

  StreamSubscription<Set<RealtimeScope>>? _dirtySubscription;
  Timer? _retryTimer;
  bool _started = false;
  bool _disposed = false;
  bool _dispatching = false;
  bool _dispatchRequested = false;
  int _retryCount = 0;
  DateTime? _retryFirstAt;
  final Map<RealtimeScopeHandler, Map<String, int>> _completedRevisions =
      Map.identity();

  /// 订阅脏作用域变化，并处理应用上次退出前遗留的失效记录。
  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    _dirtySubscription = _dirtyScopes.listen((_) {
      unawaited(dispatchPending());
    });
    await dispatchPending();
  }

  /// 合并并串行处理当前全部待确认失效记录。
  Future<void> dispatchPending() async {
    if (_disposed) return;
    if (_dispatching) {
      _dispatchRequested = true;
      return;
    }
    _dispatching = true;
    var shouldRetry = false;
    try {
      do {
        _dispatchRequested = false;
        final pending = await _pendingInvalidations();
        final grouped = <RealtimeScope, List<RealtimeInvalidation>>{};
        for (final invalidation in pending) {
          grouped.putIfAbsent(invalidation.scope, () => []).add(invalidation);
        }
        for (final entry in grouped.entries) {
          final handlers = _handlers[entry.key];
          if (handlers == null || handlers.isEmpty) {
            // 该作用域没有任何订阅 handler：没有本地状态需要刷新，
            // 直接确认消费，避免持久失效记录无限重试。
            for (final invalidation in entry.value) {
              final acknowledged = await _acknowledge(invalidation);
              if (acknowledged == 0) {
                _dispatchRequested = true;
              }
            }
            continue;
          }
          try {
            final observed = List<RealtimeInvalidation>.unmodifiable(
              entry.value,
            );
            for (final handler in handlers) {
              final completed = _completedRevisions.putIfAbsent(
                handler,
                () => <String, int>{},
              );
              final applicable = observed
                  .where(handler.appliesTo)
                  .where(
                    (invalidation) =>
                        (completed[invalidation.key] ?? 0) <
                        invalidation.revision,
                  )
                  .toList(growable: false);
              if (applicable.isEmpty) {
                continue;
              }
              final refreshed = await handler.refresh(applicable);
              if (!refreshed) {
                shouldRetry = true;
                continue;
              }
              for (final invalidation in applicable) {
                completed[invalidation.key] = invalidation.revision;
              }
            }
            for (final invalidation in observed) {
              final relevantHandlers = handlers.where(
                (handler) => handler.appliesTo(invalidation),
              );
              final allCompleted = relevantHandlers.every(
                (handler) =>
                    (_completedRevisions[handler]?[invalidation.key] ?? 0) >=
                    invalidation.revision,
              );
              if (!allCompleted) {
                shouldRetry = true;
                continue;
              }
              final acknowledged = await _acknowledge(invalidation);
              if (acknowledged == 0) {
                _dispatchRequested = true;
              } else {
                for (final completed in _completedRevisions.values) {
                  completed.remove(invalidation.key);
                }
              }
            }
          } on Object catch (error, stackTrace) {
            shouldRetry = true;
            _onError?.call(error, stackTrace);
          }
        }
      } while (_dispatchRequested && !_disposed);
    } on Object catch (error, stackTrace) {
      shouldRetry = true;
      _onError?.call(error, stackTrace);
    } finally {
      _dispatching = false;
    }
    if (_dispatchRequested && !_disposed) {
      unawaited(dispatchPending());
      return;
    }
    if (shouldRetry) {
      _scheduleRetry();
    } else {
      _retryTimer?.cancel();
      _retryTimer = null;
      _retryCount = 0;
      _retryFirstAt = null;
    }
  }

  static Map<RealtimeScope, List<RealtimeScopeHandler>> _groupHandlers(
    Iterable<RealtimeScopeHandler> handlers,
  ) {
    final grouped = <RealtimeScope, List<RealtimeScopeHandler>>{};
    for (final handler in handlers) {
      grouped.putIfAbsent(handler.scope, () => []).add(handler);
    }
    return grouped;
  }

  void _scheduleRetry() {
    if (_disposed || _retryTimer?.isActive == true) return;

    // 快速重试耗尽后降为低频恢复，持久失效记录仍保留等待最终确认。
    final firstAt = _retryFirstAt ??= DateTime.now();
    _retryCount++;
    if (_retryCount > _maxRetries ||
        DateTime.now().difference(firstAt) > _retryWindow) {
      _retryCount = 0;
      _retryFirstAt = null;
      _onError?.call(StateError('实时失效刷新快速重试已耗尽，切换为低频恢复'), StackTrace.current);
      _retryTimer = Timer(_exhaustedRetryDelay, () {
        _retryTimer = null;
        unawaited(dispatchPending());
      });
      return;
    }

    final baseDelay = _retryDelay ?? _backoffSteps.first;
    final stepIndex = (_retryCount - 1).clamp(0, _backoffSteps.length - 1);
    final delay = stepIndex == 0 ? baseDelay : _backoffSteps[stepIndex];
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      unawaited(dispatchPending());
    });
  }

  /// 停止业务刷新订阅和失败重试。
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _retryTimer?.cancel();
    await _dirtySubscription?.cancel();
  }
}
