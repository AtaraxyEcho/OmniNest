import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/realtime/realtime_invalidation_dispatcher.dart';
import 'package:omninest/core/realtime/realtime_models.dart';
import 'package:omninest/core/realtime/realtime_scope_handler.dart';

void main() {
  test('同一作用域只刷新一次并逐条确认观察到的 revision', () async {
    final dirtyScopes = StreamController<Set<RealtimeScope>>.broadcast();
    final handler = _FakeHandler(RealtimeScope.files);
    final secondaryHandler = _FakeHandler(RealtimeScope.files);
    final first = _invalidation('first', revision: 2);
    final second = _invalidation('second', revision: 4);
    final acknowledged = <RealtimeInvalidation>[];
    final dispatcher = RealtimeInvalidationDispatcher(
      dirtyScopes: dirtyScopes.stream,
      pendingInvalidations: () async => [first, second],
      acknowledge: (invalidation) async {
        acknowledged.add(invalidation);
        return 1;
      },
      handlers: [handler, secondaryHandler],
      retryDelay: null,
    );

    await dispatcher.start();

    expect(handler.calls, 1);
    expect(secondaryHandler.calls, 1);
    expect(handler.received.single, [first, second]);
    expect(acknowledged, [first, second]);
    await dispatcher.dispose();
    await dirtyScopes.close();
  });

  test('无订阅 handler 的作用域直接确认消费', () async {
    final dirtyScopes = StreamController<Set<RealtimeScope>>.broadcast();
    final handler = _FakeHandler(RealtimeScope.files);
    final musicInvalidation = _invalidation(
      'music',
      scope: RealtimeScope.music,
    );
    final acknowledged = <RealtimeInvalidation>[];
    final dispatcher = RealtimeInvalidationDispatcher(
      dirtyScopes: dirtyScopes.stream,
      pendingInvalidations: () async => [musicInvalidation],
      acknowledge: (invalidation) async {
        acknowledged.add(invalidation);
        return 1;
      },
      handlers: [handler],
      retryDelay: null,
    );

    await dispatcher.start();

    expect(handler.calls, 0);
    expect(acknowledged, [musicInvalidation]);
    await dispatcher.dispose();
    await dirtyScopes.close();
  });

  test('刷新失败时不确认失效记录', () async {
    final dirtyScopes = StreamController<Set<RealtimeScope>>.broadcast();
    final handler = _FakeHandler(RealtimeScope.photos, shouldFail: true);
    var acknowledgeCount = 0;
    final dispatcher = RealtimeInvalidationDispatcher(
      dirtyScopes: dirtyScopes.stream,
      pendingInvalidations: () async => [_invalidation('photo')],
      acknowledge: (_) async {
        acknowledgeCount++;
        return 1;
      },
      handlers: [handler],
      retryDelay: null,
    );

    await dispatcher.start();

    expect(handler.calls, 1);
    expect(acknowledgeCount, 0);
    await dispatcher.dispose();
    await dirtyScopes.close();
  });

  test('旧 revision 未能确认时会读取并处理刷新期间的新 revision', () async {
    final dirtyScopes = StreamController<Set<RealtimeScope>>.broadcast();
    final handler = _FakeHandler(RealtimeScope.files);
    final oldRevision = _invalidation('file', revision: 8);
    final newRevision = _invalidation('file', revision: 9);
    var readCount = 0;
    final acknowledgedRevisions = <int>[];
    final dispatcher = RealtimeInvalidationDispatcher(
      dirtyScopes: dirtyScopes.stream,
      pendingInvalidations: () async {
        readCount++;
        return readCount == 1 ? [oldRevision] : [newRevision];
      },
      acknowledge: (invalidation) async {
        acknowledgedRevisions.add(invalidation.revision);
        return invalidation.revision == 8 ? 0 : 1;
      },
      handlers: [handler],
      retryDelay: null,
    );

    await dispatcher.start();

    expect(handler.calls, 2);
    expect(acknowledgedRevisions, [8, 9]);
    await dispatcher.dispose();
    await dirtyScopes.close();
  });

  test('延迟消费者不会确认 dirty 且已完成消费者不会重复刷新', () async {
    final dirtyScopes = StreamController<Set<RealtimeScope>>.broadcast();
    final completed = _FakeHandler(RealtimeScope.files);
    final deferred = _FakeHandler(RealtimeScope.files, shouldDefer: true);
    final invalidation = _invalidation('deferred');
    var acknowledgeCount = 0;
    final dispatcher = RealtimeInvalidationDispatcher(
      dirtyScopes: dirtyScopes.stream,
      pendingInvalidations: () async => [invalidation],
      acknowledge: (_) async {
        acknowledgeCount++;
        return 1;
      },
      handlers: [completed, deferred],
      retryDelay: null,
    );

    await dispatcher.start();
    expect(acknowledgeCount, 0);

    deferred.shouldDefer = false;
    await dispatcher.dispatchPending();

    expect(completed.calls, 1);
    expect(deferred.calls, 2);
    expect(acknowledgeCount, 1);
    await dispatcher.dispose();
    await dirtyScopes.close();
  });

  test('快速重试耗尽后进入低频恢复并最终确认记录', () async {
    final dirtyScopes = StreamController<Set<RealtimeScope>>.broadcast();
    final handler = _RecoveringHandler(
      RealtimeScope.files,
      failuresBeforeSuccess: 2,
    );
    final acknowledged = Completer<void>();
    final dispatcher = RealtimeInvalidationDispatcher(
      dirtyScopes: dirtyScopes.stream,
      pendingInvalidations: () async => [_invalidation('recovering-file')],
      acknowledge: (_) async {
        if (!acknowledged.isCompleted) {
          acknowledged.complete();
        }
        return 1;
      },
      handlers: [handler],
      retryDelay: Duration.zero,
      maxRetries: 1,
      retryWindow: const Duration(seconds: 1),
      exhaustedRetryDelay: const Duration(milliseconds: 1),
    );

    await dispatcher.start();
    await acknowledged.future.timeout(const Duration(seconds: 1));

    expect(handler.calls, 3);
    await dispatcher.dispose();
    await dirtyScopes.close();
  });
}

RealtimeInvalidation _invalidation(
  String key, {
  int revision = 1,
  RealtimeScope? scope,
}) {
  return RealtimeInvalidation(
    key: key,
    scope: scope ?? (key == 'photo' ? RealtimeScope.photos : RealtimeScope.files),
    resourceType: 'RESOURCE',
    revision: revision,
    createdAt: DateTime.utc(2026, 7, 17),
  );
}

class _FakeHandler implements RealtimeScopeHandler {
  _FakeHandler(this.scope, {this.shouldFail = false, this.shouldDefer = false});

  @override
  final RealtimeScope scope;
  final bool shouldFail;
  bool shouldDefer;
  final List<List<RealtimeInvalidation>> received = [];
  int calls = 0;

  @override
  bool appliesTo(RealtimeInvalidation invalidation) => true;

  @override
  Future<bool> refresh(List<RealtimeInvalidation> invalidations) async {
    calls++;
    received.add(invalidations);
    if (shouldFail) {
      throw StateError('refresh failed');
    }
    return !shouldDefer;
  }
}

class _RecoveringHandler implements RealtimeScopeHandler {
  _RecoveringHandler(this.scope, {required this.failuresBeforeSuccess});

  @override
  final RealtimeScope scope;
  int failuresBeforeSuccess;
  int calls = 0;

  @override
  bool appliesTo(RealtimeInvalidation invalidation) => true;

  @override
  Future<bool> refresh(List<RealtimeInvalidation> invalidations) async {
    calls++;
    if (failuresBeforeSuccess > 0) {
      failuresBeforeSuccess--;
      throw StateError('temporary refresh failure');
    }
    return true;
  }
}
