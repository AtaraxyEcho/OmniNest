import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/realtime/realtime_api.dart';
import 'package:omninest/core/realtime/realtime_coordinator.dart';
import 'package:omninest/core/realtime/realtime_models.dart';
import 'package:omninest/core/realtime/realtime_stomp_client.dart';
import 'package:omninest/core/realtime/realtime_store.dart';
import 'package:omninest/core/storage/local_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalDatabase database;
  late RealtimeStore store;
  late FakeRealtimeRemote remote;
  late FakeRealtimeTransport transport;
  late StreamController<bool> connectivity;
  late RealtimeCoordinator coordinator;

  setUp(() {
    database = LocalDatabase(NativeDatabase.memory());
    store = RealtimeStore(
      database: database,
      serverKey: 'http://server/api/v1',
      userId: 'user-1',
    );
    remote = FakeRealtimeRemote();
    transport = FakeRealtimeTransport();
    connectivity = StreamController<bool>.broadcast();
    coordinator = RealtimeCoordinator(
      api: remote,
      store: store,
      stompClient: transport,
      connectivity: connectivity.stream,
      refreshSession: () async => true,
      suspendInBackground: false,
      headInterval: const Duration(days: 1),
    );
  });

  tearDown(() async {
    await coordinator.dispose();
    await connectivity.close();
    await database.close();
  });

  test(
    'first connection starts from bootstrap cursor instead of replaying history',
    () async {
      await coordinator.start();

      expect(transport.connectCalls, 1);
      transport.emitState(RealtimeTransportState.connected);
      await waitFor(() async => (await store.readState())?.cursor == 50);

      expect(remote.bootstrapCalls, 1);
      expect(remote.requestedCursors, [50]);
      expect(coordinator.phase, RealtimePhase.healthy);
    },
  );

  test(
    'expired cursor marks all scopes dirty and advances to latest cursor',
    () async {
      await store.initializeCursor(cursor: 2, schemaVersion: 1);
      remote.pages.add(
        const RealtimeEventPage(
          items: [],
          nextCursor: 80,
          latestCursor: 80,
          hasMore: false,
          resetRequired: true,
        ),
      );
      await coordinator.start();
      transport.emitState(RealtimeTransportState.connected);
      await waitFor(() async => (await store.readState())?.cursor == 80);

      expect(
        (await store.pendingInvalidations()).length,
        RealtimeScope.values.length,
      );
    },
  );

  test(
    'transport disconnect immediately verifies the session through catch-up',
    () async {
      await store.initializeCursor(cursor: 12, schemaVersion: 1);
      await coordinator.start();

      transport.emitState(RealtimeTransportState.disconnected);
      await waitFor(() async => remote.requestedCursors.contains(12));

      expect(coordinator.phase, RealtimePhase.degraded);
    },
  );

  test('后台挂起只认 paused/hidden，回前台即使预刷新失败也必须重连', () async {
    final binding = TestWidgetsFlutterBinding.instance;
    var refreshOk = true;
    coordinator = RealtimeCoordinator(
      api: remote,
      store: store,
      stompClient: transport,
      connectivity: connectivity.stream,
      refreshSession: () async => refreshOk,
      suspendInBackground: true,
      headInterval: const Duration(days: 1),
    );
    await coordinator.start();
    expect(transport.connectCalls, 1);

    // 下拉通知栏、系统权限弹窗与切窗预览都是 inactive，
    // 在这里掐链等于每次失焦断一次、回焦又轮换一次刷新令牌。
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(transport.pauseCalls, 0);
    expect(transport.connectCalls, 1);

    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    expect(transport.pauseCalls, 1);

    // 刚解锁时网络未就绪，预刷新返回 false；恢复流程不得因此跳过重连，
    // 否则 head 定时器与 STOMP 永久停摆，且没有任何入口能自愈。
    refreshOk = false;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(transport.pauseCalls, 1);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await waitFor(() async => transport.connectCalls >= 2);

    expect(transport.pauseCalls, 1);
  });
}

Future<void> waitFor(Future<bool> Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!await predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('等待异步条件超时');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class FakeRealtimeRemote implements RealtimeRemoteDataSource {
  int bootstrapCalls = 0;
  final List<int> requestedCursors = [];
  final List<RealtimeEventPage> pages = [];

  @override
  Future<RealtimeBootstrap> bootstrap() async {
    bootstrapCalls++;
    return RealtimeBootstrap(
      schemaVersion: 1,
      latestCursor: 50,
      retentionFloor: 0,
      serverTime: DateTime.utc(2026, 7, 17),
    );
  }

  @override
  Future<RealtimeEventPage> events({
    required int after,
    int limit = 200,
  }) async {
    requestedCursors.add(after);
    if (pages.isNotEmpty) return pages.removeAt(0);
    return RealtimeEventPage(
      items: const [],
      nextCursor: after,
      latestCursor: after,
      hasMore: false,
      resetRequired: false,
    );
  }

  @override
  Future<RealtimeHead> head() async {
    return const RealtimeHead(
      schemaVersion: 1,
      latestCursor: 50,
      retentionFloor: 0,
    );
  }
}

class FakeRealtimeTransport implements RealtimeTransport {
  var tokenRefreshNotifications = 0;

  @override
  void notifyAccessTokenRefreshed() {
    tokenRefreshNotifications++;
  }

  final StreamController<RealtimeSyncEvent> _events =
      StreamController<RealtimeSyncEvent>.broadcast();
  final StreamController<Map<String, dynamic>> _notifications =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<RealtimeTransportState> _states =
      StreamController<RealtimeTransportState>.broadcast();
  int connectCalls = 0;
  int pauseCalls = 0;
  RealtimeTransportState _state = RealtimeTransportState.disconnected;

  @override
  Stream<Map<String, dynamic>> get notifications => _notifications.stream;

  @override
  RealtimeTransportState get state => _state;

  @override
  Stream<RealtimeTransportState> get states => _states.stream;

  @override
  Stream<RealtimeSyncEvent> get syncEvents => _events.stream;

  @override
  void connect() {
    connectCalls++;
  }

  void emitState(RealtimeTransportState state) {
    _state = state;
    _states.add(state);
  }

  @override
  void pause() {
    pauseCalls++;
    _state = RealtimeTransportState.disconnected;
  }

  @override
  Future<void> dispose() async {
    await Future.wait([
      _events.close(),
      _notifications.close(),
      _states.close(),
    ]);
  }
}
